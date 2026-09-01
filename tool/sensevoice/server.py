"""Add local CORS and health metadata to FunASR's official HTTP server."""

from __future__ import annotations

import argparse
import asyncio
from concurrent.futures import CancelledError, Future
from contextlib import asynccontextmanager
from io import BytesIO
import logging
import math
import os
import re
import struct
import tempfile
import threading
import time
import wave
from typing import Any, Optional

from fastapi import File, Form, HTTPException, Request, UploadFile
from fastapi.responses import JSONResponse


_WARMUP_SAMPLE_RATE = 16000
_WARMUP_FRAME_COUNT = _WARMUP_SAMPLE_RATE // 2
_SENSEVOICE_CONTROL_TAG = re.compile(r"<\|[^|]*\|>")
_SENSEVOICE_LANGUAGE_TAG = re.compile(r"<\|(zh|en|yue|ja|ko)\|>")
_AUDIO_SUFFIX_FALLBACK = ".wav"
_SILENCE_FRAME_SECONDS = 0.02
_SILENCE_PADDING_SECONDS = 0.12
_TEMP_FILE_CLEANUP_RETRIES = 5
_TEMP_FILE_CLEANUP_DELAY_SECONDS = 0.05
_LOGGER = logging.getLogger("sensevoice.adapter")


class PreparedAudio:
    """传给模型的短音频窗口及其可审计时长。"""

    def __init__(
        self,
        audio_bytes: bytes,
        suffix: str,
        original_duration_seconds: Optional[float],
        inference_duration_seconds: Optional[float],
        trim_start_seconds: float = 0.0,
    ) -> None:
        self.audio_bytes = audio_bytes
        self.suffix = suffix
        self.original_duration_seconds = original_duration_seconds
        self.inference_duration_seconds = inference_duration_seconds
        self.trim_start_seconds = trim_start_seconds


class _InferenceJob:
    """单个模型推理的内部所有权，避免请求方直接管理线程资源。"""

    def __init__(
        self,
        input_path: str,
        generate_kwargs: dict[str, Any],
        future: Future,
    ) -> None:
        self.input_path = input_path
        self.generate_kwargs = generate_kwargs
        self.future = future


class LatestInferenceScheduler:
    """串行执行模型推理，并在排队时让较新的录音替换较旧录音。"""

    def __init__(self, model: Any):
        self._model = model
        self._condition = threading.Condition()
        self._pending: Optional[_InferenceJob] = None
        self._is_closed = False
        self._close_requested = threading.Event()
        self._model_call_lock = threading.Lock()
        self._worker: Optional[threading.Thread] = None

    def submit(self, input_path: str, generate_kwargs: dict[str, Any]) -> Future:
        future: Future = Future()
        future.sensevoice_submitted_at = time.perf_counter()
        job = _InferenceJob(input_path, generate_kwargs, future)
        with self._condition:
            if self._is_closed:
                future.set_exception(RuntimeError("SenseVoice inference scheduler is closed"))
                return future
            if self._worker is None:
                # 仅构造 app 的健康检查测试不应遗留 daemon；首次真实推理才需要 worker。
                self._worker = threading.Thread(
                    target=self._run,
                    name="sensevoice-inference",
                    daemon=True,
                )
                self._worker.start()
            if self._pending is not None:
                # 只保留用户最后一次可见的尝试，断连/重试不会形成无限 CPU 队列。
                self._pending.future.cancel()
            self._pending = job
            self._condition.notify()
        return future

    def close(self) -> None:
        # 先发布关闭意图，覆盖 worker 已取出 job 但尚未进入 model.generate 的窗口。
        self._close_requested.set()
        with self._condition:
            self._is_closed = True
            if self._pending is not None:
                self._pending.future.cancel()
                self._pending = None
            self._condition.notify_all()
            worker = self._worker
        # 与 model.generate 共用启动闸门：close 已开始后，尚未取得闸门的 job 不能再启动。
        with self._model_call_lock:
            pass
        if worker is not None:
            # 无法中断的 CPU 推理仍在持有模型/临时文件；shutdown 必须等它自然收尾。
            worker.join()

    def _run(self) -> None:
        while True:
            with self._condition:
                while self._pending is None and not self._is_closed:
                    self._condition.wait()
                if self._is_closed:
                    return
                job = self._pending
                self._pending = None

            if job is None or not job.future.set_running_or_notify_cancel():
                continue
            with self._model_call_lock:
                if self._close_requested.is_set():
                    job.future.set_exception(
                        RuntimeError("SenseVoice inference scheduler is closed")
                    )
                    continue
                job.future.sensevoice_started_at = time.perf_counter()
                try:
                    result = self._model.generate(
                        input=job.input_path,
                        **job.generate_kwargs,
                    )
                except Exception as error:
                    if not job.future.cancelled():
                        job.future.set_exception(error)
                else:
                    if not job.future.cancelled():
                        job.future.set_result(result)
                finally:
                    job.future.sensevoice_finished_at = time.perf_counter()


def prepare_audio_for_inference(content: bytes, *, filename: Optional[str]) -> PreparedAudio:
    """裁掉无声首尾，减少短口述录音送入 CPU 模型的有效长度。"""
    suffix = os.path.splitext(filename or "")[1].lower() or _AUDIO_SUFFIX_FALLBACK
    try:
        import numpy as np
        import soundfile as sound_file

        audio_data, sample_rate = sound_file.read(
            BytesIO(content),
            dtype="float32",
            always_2d=True,
        )
    except (RuntimeError, ValueError, OSError):
        # 非 WAV/解码失败仍交由 FunASR 保持原有格式兼容；不能因优化改变既有错误语义。
        return PreparedAudio(content, suffix, None, None)

    mono_audio = np.mean(audio_data, axis=1, dtype=np.float32)
    original_duration = len(mono_audio) / sample_rate if sample_rate else 0.0
    frame_size = max(1, round(sample_rate * _SILENCE_FRAME_SECONDS))
    usable_length = len(mono_audio) - (len(mono_audio) % frame_size)
    if usable_length == 0:
        return PreparedAudio(content, suffix, original_duration, original_duration)

    frames = mono_audio[:usable_length].reshape(-1, frame_size)
    frame_rms = np.sqrt(np.mean(np.square(frames), axis=1))
    if float(np.max(frame_rms)) == 0:
        return PreparedAudio(content, suffix, original_duration, original_duration)
    # 固定极低门限只裁绝对静音；环境底噪会降低裁剪率而不会吞掉轻声有效尾音。
    threshold = 0.0005
    speech_frames = np.flatnonzero(frame_rms >= threshold)
    if len(speech_frames) == 0:
        return PreparedAudio(content, suffix, original_duration, original_duration)

    padding = round(sample_rate * _SILENCE_PADDING_SECONDS)
    start = max(0, int(speech_frames[0]) * frame_size - padding)
    end = min(len(mono_audio), (int(speech_frames[-1]) + 1) * frame_size + padding)
    trimmed_audio = mono_audio[start:end]
    output = BytesIO()
    sound_file.write(output, trimmed_audio, sample_rate, format="WAV", subtype="PCM_16")
    inference_duration = len(trimmed_audio) / sample_rate
    return PreparedAudio(
        output.getvalue(),
        ".wav",
        original_duration,
        inference_duration,
        start / sample_rate,
    )


def _format_server_timing(timings: dict[str, float]) -> str:
    return ", ".join(f"{name};dur={duration * 1000:.1f}" for name, duration in timings.items())


def _resolve_transcription_language(requested_language: Optional[str], raw_text: str) -> str:
    if requested_language and requested_language.strip().lower() != "auto":
        return requested_language
    match = _SENSEVOICE_LANGUAGE_TAG.search(raw_text)
    return match.group(1) if match else "unknown"


def _clean_up_temp_audio(input_path: str, retries: int = _TEMP_FILE_CLEANUP_RETRIES) -> None:
    """回收请求临时音频；Windows 文件锁短暂滞后时延迟重试。"""
    try:
        os.unlink(input_path)
    except FileNotFoundError:
        return
    except PermissionError:
        if retries <= 0:
            _LOGGER.warning("sensevoice temporary audio cleanup remained locked")
            return
        retry = threading.Timer(
            _TEMP_FILE_CLEANUP_DELAY_SECONDS,
            _clean_up_temp_audio,
            args=(input_path, retries - 1),
        )
        retry.daemon = True
        retry.start()


def _build_warmup_pcm16() -> bytes:
    """Build a deterministic short voiced signal without external fixtures."""
    samples = []
    for index in range(_WARMUP_FRAME_COUNT):
        seconds = index / _WARMUP_SAMPLE_RATE
        envelope = math.sin(math.pi * index / (_WARMUP_FRAME_COUNT - 1)) ** 2
        carrier = (
            0.7 * math.sin(2 * math.pi * 220 * seconds)
            + 0.3 * math.sin(2 * math.pi * 440 * seconds)
        )
        samples.append(int(9000 * envelope * carrier))
    return struct.pack(f"<{len(samples)}h", *samples)


def _has_usable_warmup_result(result: Any, *, require_text: bool) -> bool:
    if not isinstance(result, list) or not result:
        return False
    # 官方 HTTP route 只读取首个批次项，预热必须遵守同一契约，避免健康检查误报就绪。
    first_item = result[0]
    if not isinstance(first_item, dict):
        return False
    raw_text = first_item.get("text")
    if not isinstance(raw_text, str):
        return False
    if not require_text:
        # 合成音只负责触发模型图与算子初始化；它不是语音，空转写不代表模型不可用。
        return True
    # 控制标签本身不能证明 ASR 已完成，必须包含真实转写文本。
    return bool(_SENSEVOICE_CONTROL_TAG.sub("", raw_text).strip())


def _warm_up_sensevoice_model(
    funasr_app: Any, model_path: str | None = None
) -> None:
    """Run one real inference before health can report the service as ready."""
    model = funasr_app.state.fallback_models.get("sensevoice")
    if model is None:
        raise RuntimeError("SenseVoice warmup requires a loaded sensevoice model")

    snapshot_example = (
        os.path.join(model_path, "example", "zh.mp3") if model_path else None
    )
    owns_warmup_path = not snapshot_example or not os.path.isfile(snapshot_example)
    if owns_warmup_path:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
            warmup_path = temp_file.name
    else:
        # Snapshot 自带语音已经过真实 VAD 验证，且其生命周期不归适配器管理。
        warmup_path = snapshot_example
    try:
        if owns_warmup_path:
            with wave.open(warmup_path, "wb") as audio_file:
                audio_file.setnchannels(1)
                audio_file.setsampwidth(2)
                audio_file.setframerate(_WARMUP_SAMPLE_RATE)
                audio_file.writeframes(_build_warmup_pcm16())

        # 参数与官方 fallback route 保持一致，确保预热覆盖真实首请求的执行路径。
        result = model.generate(input=warmup_path, batch_size=1)
        if not _has_usable_warmup_result(
            result,
            require_text=not owns_warmup_path,
        ):
            raise RuntimeError(
                "SenseVoice warmup returned no usable text; "
                "the warmup audio produced no transcribed speech"
            )
    finally:
        if owns_warmup_path:
            # Windows 下模型会重新打开文件，因此必须先关闭 WAV，再在推理结束后统一清理。
            try:
                os.unlink(warmup_path)
            except FileNotFoundError:
                pass


def build_health_payload(
    device: str, runtime_version: str, models_loaded: list[str]
) -> dict[str, Any]:
    """Build the stable health contract consumed by local tooling."""
    return {
        "status": "healthy",
        "runtime": f"funasr-{runtime_version}",
        "device": device,
        "model": "sensevoice",
        "modelsLoaded": models_loaded,
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Local SenseVoice HTTP adapter")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--device", choices=("cpu",), required=True)
    parser.add_argument("--model", choices=("sensevoice",), required=True)
    parser.add_argument("--cors-origin", required=True)
    return parser.parse_args()


def create_application(
    host: str,
    device: str,
    cors_origin: str,
    model_path: str | None = None,
):
    # 在导入/创建 FunASR 应用前拒绝公网地址，避免错误配置触发模型加载后才失败.
    if host != "127.0.0.1":
        raise ValueError("Local SenseVoice may bind only to 127.0.0.1")

    import funasr
    from fastapi import FastAPI
    from fastapi.middleware.cors import CORSMiddleware
    from funasr.bin._server_app import create_app as create_funasr_app

    # 1.3.29 已提供 OpenAI 转写端点和模型预加载；这里只补项目需要的 CORS 与稳定 health 字段.
    # 优先使用 setup 已落盘的模型快照，避免每次启动都依赖模型站连通性。
    funasr_app = create_funasr_app(
        device=device,
        preload_model="sensevoice",
        model_path=model_path,
        hub="ms",
    )
    if model_path and "custom" in funasr_app.state.fallback_models:
        # 对外仍保持 model=sensevoice；内部复用已加载的本地实例，避免短公式请求再次构造联网 VAD。
        funasr_app.state.fallback_models["sensevoice"] = (
            funasr_app.state.fallback_models.pop("custom")
        )
    _warm_up_sensevoice_model(funasr_app, model_path)
    scheduler = LatestInferenceScheduler(
        funasr_app.state.fallback_models["sensevoice"]
    )

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        try:
            yield
        finally:
            scheduler.close()

    app = FastAPI(
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan,
    )
    app.state.sensevoice_scheduler = scheduler
    app.add_middleware(
        CORSMiddleware,
        allow_origins=[cors_origin],
        allow_credentials=False,
        allow_methods=["GET", "POST"],
        allow_headers=["*"],
    )

    @app.get("/health")
    async def health() -> dict[str, Any]:
        loaded = list(funasr_app.state.fallback_models.keys())
        return build_health_payload(device, funasr.__version__, loaded)

    # 自定义 health 必须先注册；其余路径原样交给 FunASR 官方应用处理.
    @app.post("/v1/audio/transcriptions")
    async def transcribe(
        request: Request,
        file: UploadFile = File(...),
        model: str = Form(default="sensevoice"),
        language: Optional[str] = Form(default=None),
        response_format: Optional[str] = Form(default="json"),
    ) -> JSONResponse:
        started_at = time.perf_counter()
        content = await file.read()
        read_finished_at = time.perf_counter()
        if model != "sensevoice":
            raise HTTPException(status_code=400, detail="Only sensevoice is available")

        # 解码和能量扫描会消耗 CPU，移到线程后事件循环仍可接收断连信号。
        prepared = await asyncio.to_thread(
            prepare_audio_for_inference,
            content,
            filename=file.filename,
        )
        prepare_finished_at = time.perf_counter()
        input_path: Optional[str] = None
        try:
            with tempfile.NamedTemporaryFile(
                delete=False,
                suffix=prepared.suffix,
            ) as temp_file:
                input_path = temp_file.name
                temp_file.write(prepared.audio_bytes)

            generate_kwargs: dict[str, Any] = {"batch_size": 1}
            if language:
                generate_kwargs["language"] = language
            inference_future = scheduler.submit(input_path, generate_kwargs)
        except Exception:
            if input_path is not None:
                _clean_up_temp_audio(input_path)
            raise

        def clean_up_input(_: Future) -> None:
            # 推理线程结束前不能删除 Windows 临时文件；排队任务被替换时则可立即回收。
            _clean_up_temp_audio(input_path)

        try:
            inference_future.add_done_callback(clean_up_input)
        except Exception:
            inference_future.cancel()

            def wait_then_clean_up() -> None:
                try:
                    inference_future.result()
                except Exception:
                    pass
                finally:
                    _clean_up_temp_audio(input_path)

            threading.Thread(target=wait_then_clean_up, daemon=True).start()
            raise
        try:
            while not inference_future.done():
                if await request.is_disconnected():
                    inference_future.cancel()
                    raise HTTPException(status_code=499, detail="Client disconnected")
                await asyncio.sleep(0.025)
            result = await asyncio.wrap_future(inference_future)
        except (asyncio.CancelledError, CancelledError):
            if inference_future.cancelled():
                cancelled_at = time.perf_counter()
                queue_started_at = getattr(
                    inference_future,
                    "sensevoice_started_at",
                    None,
                )
                submitted_at = getattr(
                    inference_future,
                    "sensevoice_submitted_at",
                    prepare_finished_at,
                )
                queue_duration = (
                    cancelled_at - submitted_at
                    if queue_started_at is None
                    else queue_started_at - submitted_at
                )
                inference_duration = (
                    0.0
                    if queue_started_at is None
                    else cancelled_at - queue_started_at
                )
                timings = {
                    "read": read_finished_at - started_at,
                    "prepare": prepare_finished_at - read_finished_at,
                    "queue": queue_duration,
                    "inference": inference_duration,
                    "total": cancelled_at - started_at,
                }
                _LOGGER.info(
                    "sensevoice transcription timing outcome=request_replaced %s",
                    _format_server_timing(timings),
                )
                return JSONResponse(
                    {"error": {"code": "request_replaced"}},
                    status_code=409,
                    headers={"Server-Timing": _format_server_timing(timings)},
                )
            inference_future.cancel()
            raise
        finally:
            completed_at = time.perf_counter()

        if not isinstance(result, list) or not result or not isinstance(result[0], dict):
            raise HTTPException(status_code=502, detail="SenseVoice returned an invalid result")
        raw_text = result[0].get("text")
        if not isinstance(raw_text, str):
            raise HTTPException(status_code=502, detail="SenseVoice returned no text")
        text = _SENSEVOICE_CONTROL_TAG.sub("", raw_text).strip()
        queue_started_at = getattr(
            inference_future,
            "sensevoice_started_at",
            prepare_finished_at,
        )
        submitted_at = getattr(
            inference_future,
            "sensevoice_submitted_at",
            prepare_finished_at,
        )
        inference_finished_at = getattr(
            inference_future,
            "sensevoice_finished_at",
            completed_at,
        )
        timings = {
            "read": read_finished_at - started_at,
            "prepare": prepare_finished_at - read_finished_at,
            "queue": queue_started_at - submitted_at,
            "inference": inference_finished_at - queue_started_at,
            "total": completed_at - started_at,
        }
        # 只记录阶段耗时和输入时长，不记录原始音频、文件名或转写文本。
        _LOGGER.info(
            "sensevoice transcription timing original_seconds=%s inference_seconds=%s %s",
            prepared.original_duration_seconds,
            prepared.inference_duration_seconds,
            _format_server_timing(timings),
        )
        headers = {"Server-Timing": _format_server_timing(timings)}
        if response_format == "text":
            return JSONResponse(text, headers=headers)
        if response_format == "verbose_json":
            inference_duration = prepared.inference_duration_seconds or 0
            duration = prepared.original_duration_seconds or inference_duration
            offset = prepared.trim_start_seconds
            segments = []
            for index, sentence in enumerate(result[0].get("sentence_info", [])):
                if not isinstance(sentence, dict):
                    continue
                sentence_text = sentence.get("text", "")
                if not isinstance(sentence_text, str):
                    continue
                segments.append(
                    {
                        "id": index,
                        "start": offset + sentence.get("start", 0) / 1000,
                        "end": offset + sentence.get("end", 0) / 1000,
                        "text": _SENSEVOICE_CONTROL_TAG.sub("", sentence_text).strip(),
                        "words": [],
                    }
                )
            if not segments and text:
                segments.append(
                    {
                        "id": 0,
                        "start": offset,
                        "end": min(duration, offset + inference_duration),
                        "text": text,
                        "words": [],
                    }
                )
            return JSONResponse(
                {
                    "task": "transcribe",
                    "language": _resolve_transcription_language(language, raw_text),
                    "duration": duration,
                    "text": text,
                    "segments": segments,
                },
                headers=headers,
            )
        return JSONResponse({"text": text}, headers=headers)

    app.mount("/", funasr_app)
    return app


def main() -> None:
    arguments = parse_arguments()

    import uvicorn

    application = create_application(
        arguments.host,
        arguments.device,
        arguments.cors_origin,
        os.environ.get("SENSEVOICE_MODEL_PATH"),
    )
    uvicorn.run(application, host=arguments.host, port=arguments.port)


if __name__ == "__main__":
    main()
