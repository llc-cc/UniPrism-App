"""Add local CORS and health metadata to FunASR's official HTTP server."""

from __future__ import annotations

import argparse
import math
import os
import re
import struct
import tempfile
import wave
from typing import Any


_WARMUP_SAMPLE_RATE = 16000
_WARMUP_FRAME_COUNT = _WARMUP_SAMPLE_RATE // 2
_SENSEVOICE_CONTROL_TAG = re.compile(r"<\|[^|]*\|>")


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
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
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
