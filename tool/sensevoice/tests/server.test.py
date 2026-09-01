import importlib.util
import os
import pathlib
import tempfile
import threading
import unittest
import wave
from concurrent.futures import CancelledError
from io import BytesIO
from unittest import mock

import funasr
from fastapi.testclient import TestClient


SERVER_PATH = pathlib.Path(__file__).parents[1] / "server.py"


def load_server_module():
    spec = importlib.util.spec_from_file_location("sensevoice_server", SERVER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeAutoModel:
    """Avoid model I/O while keeping FunASR's real application and routes."""

    constructions = []
    events = []
    generate_calls = []

    def __init__(self, **kwargs):
        self.constructions.append(kwargs)
        self.events.append("create")

    def generate(self, **kwargs):
        input_path = pathlib.Path(kwargs["input"])
        audio_metadata = None
        try:
            with wave.open(str(input_path), "rb") as audio_file:
                audio_metadata = {
                    "channels": audio_file.getnchannels(),
                    "sample_width": audio_file.getsampwidth(),
                    "frame_rate": audio_file.getframerate(),
                    "frame_count": audio_file.getnframes(),
                    "compression": audio_file.getcomptype(),
                }
        except (EOFError, wave.Error):
            pass
        self.events.append("generate")
        self.generate_calls.append(
            {
                "kwargs": kwargs,
                "input_path": input_path,
                "input_existed": input_path.is_file(),
                "audio_metadata": audio_metadata,
            }
        )
        return [{"text": "<|zh|><|NEUTRAL|><|Speech|><|woitn|>负二的平方"}]


class FailingWarmupAutoModel(FakeAutoModel):
    """Expose startup warmup failures without loading the real model."""

    def generate(self, **kwargs):
        super().generate(**kwargs)
        raise RuntimeError("warmup failed")


class EmptyWarmupAutoModel(FakeAutoModel):
    """Mirror FunASR's successful empty result when VAD finds no speech."""

    def generate(self, **kwargs):
        super().generate(**kwargs)
        return [{"key": "warmup", "text": "", "timestamp": []}]


class TagsOnlyWarmupAutoModel(FakeAutoModel):
    """Return SenseVoice control tags without transcribed speech."""

    def generate(self, **kwargs):
        super().generate(**kwargs)
        return [
            {
                "key": "warmup",
                "text": "<|zh|><|NEUTRAL|><|Speech|><|woitn|>",
                "timestamp": [],
            }
        ]


class LaterTextWarmupAutoModel(FakeAutoModel):
    """Return usable speech only in a later batch result item."""

    def generate(self, **kwargs):
        super().generate(**kwargs)
        return [
            {"key": "empty", "text": "", "timestamp": []},
            {"key": "speech", "text": "<|zh|>预热成功", "timestamp": []},
        ]


class MalformedFirstWarmupAutoModel(FakeAutoModel):
    """Return a malformed first item followed by usable speech."""

    def generate(self, **kwargs):
        super().generate(**kwargs)
        return [
            {"key": "malformed", "timestamp": []},
            {"key": "speech", "text": "<|zh|>预热成功", "timestamp": []},
        ]


class SenseVoiceApplicationTests(unittest.TestCase):
    def setUp(self):
        FakeAutoModel.constructions.clear()
        FakeAutoModel.events.clear()
        FakeAutoModel.generate_calls.clear()
        self.server = load_server_module()

    def create_client(self):
        patcher = mock.patch.object(funasr, "AutoModel", FakeAutoModel)
        patcher.start()
        self.addCleanup(patcher.stop)
        application = self.create_application()
        return TestClient(application)

    def create_application(self, model_path=None):
        return self.server.create_application(
            host="127.0.0.1",
            device="cpu",
            cors_origin="http://localhost:5174",
            model_path=model_path,
        )

    def create_local_model_directory(self):
        model_directory = tempfile.TemporaryDirectory()
        self.addCleanup(model_directory.cleanup)
        example_path = pathlib.Path(model_directory.name) / "example" / "zh.mp3"
        example_path.parent.mkdir()
        example_path.write_bytes(b"fake local example audio")
        return model_directory.name

    def test_transcription_removes_outer_silence_before_model_inference(self):
        audio_bytes = BytesIO()
        with wave.open(audio_bytes, "wb") as audio_file:
            audio_file.setnchannels(1)
            audio_file.setsampwidth(2)
            audio_file.setframerate(16000)
            # 录音常见的首尾静音不携带公式信息，不应交给 CPU ASR 继续计算。
            audio_file.writeframes(b"\x00\x00" * 16000)
            audio_file.writeframes(b"\x10\x27" * 8000)
            audio_file.writeframes(b"\x00\x00" * 16000)

        with self.create_client() as client:
            response = client.post(
                "/v1/audio/transcriptions",
                files={"file": ("formula.wav", audio_bytes.getvalue(), "audio/wav")},
                data={"model": "sensevoice", "response_format": "json"},
            )

        self.assertEqual(200, response.status_code)
        inference_audio = FakeAutoModel.generate_calls[1]["audio_metadata"]
        self.assertEqual(16000, inference_audio["frame_rate"])
        self.assertLess(inference_audio["frame_count"], 16000)
        self.assertGreater(inference_audio["frame_count"], 8000)

    def test_audio_preparation_keeps_a_quiet_tail_after_loud_speech(self):
        audio_bytes = BytesIO()
        with wave.open(audio_bytes, "wb") as audio_file:
            audio_file.setnchannels(1)
            audio_file.setsampwidth(2)
            audio_file.setframerate(16000)
            audio_file.writeframes(b"\x00\x00" * 16000)
            audio_file.writeframes(b"\x10\x27" * 3200)
            audio_file.writeframes(b"\xf4\x01" * 8000)
            audio_file.writeframes(b"\x00\x00" * 16000)

        prepared = self.server.prepare_audio_for_inference(
            audio_bytes.getvalue(),
            filename="formula.wav",
        )

        self.assertGreaterEqual(prepared.inference_duration_seconds, 0.9)
        self.assertLess(prepared.inference_duration_seconds, 1.0)

    def test_audio_preparation_preserves_quiet_tail_when_silence_is_brief(self):
        audio_bytes = BytesIO()
        with wave.open(audio_bytes, "wb") as audio_file:
            audio_file.setnchannels(1)
            audio_file.setsampwidth(2)
            audio_file.setframerate(16000)
            audio_file.writeframes(b"\x00\x00" * 1600)
            audio_file.writeframes(b"\x10\x27" * 8000)
            audio_file.writeframes(b"\xf4\x01" * 8000)
            audio_file.writeframes(b"\x00\x00" * 1600)

        with mock.patch.object(self.server, "_SILENCE_PADDING_SECONDS", 0.02):
            prepared = self.server.prepare_audio_for_inference(
                audio_bytes.getvalue(),
                filename="formula.wav",
            )

        self.assertGreaterEqual(prepared.inference_duration_seconds, 1.0)
        self.assertLess(prepared.inference_duration_seconds, 1.1)

    def test_latest_inference_replaces_an_obsolete_queued_request(self):
        started = threading.Event()
        release = threading.Event()
        generated_inputs = []

        class BlockingModel:
            def generate(self, **kwargs):
                generated_inputs.append(kwargs["input"])
                if kwargs["input"] == "first.wav":
                    started.set()
                    release.wait(timeout=2)
                return [{"text": kwargs["input"]}]

        scheduler_class = getattr(self.server, "LatestInferenceScheduler", None)
        self.assertIsNotNone(
            scheduler_class,
            "the server needs a latest-only inference scheduler",
        )
        scheduler = scheduler_class(BlockingModel())
        self.addCleanup(scheduler.close)
        first = scheduler.submit("first.wav", {"batch_size": 1})
        self.assertTrue(started.wait(timeout=1))
        obsolete = scheduler.submit("obsolete.wav", {"batch_size": 1})
        newest = scheduler.submit("newest.wav", {"batch_size": 1})

        with self.assertRaises(CancelledError):
            obsolete.result(timeout=1)
        release.set()

        self.assertEqual("first.wav", first.result(timeout=1)[0]["text"])
        self.assertEqual("newest.wav", newest.result(timeout=1)[0]["text"])
        self.assertEqual(["first.wav", "newest.wav"], generated_inputs)

    def test_running_inference_keeps_its_input_file_until_model_returns(self):
        started = threading.Event()
        release = threading.Event()

        class BlockingModel:
            def generate(self, **kwargs):
                started.set()
                release.wait(timeout=2)
                return [{"text": "done"}]

        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as audio_file:
            audio_path = audio_file.name
        self.addCleanup(lambda: os.path.isfile(audio_path) and os.unlink(audio_path))
        scheduler = self.server.LatestInferenceScheduler(BlockingModel())
        self.addCleanup(scheduler.close)
        inference = scheduler.submit(audio_path, {"batch_size": 1})
        cleaned_up = threading.Event()

        def clean_up_input(_: object) -> None:
            os.unlink(audio_path)
            cleaned_up.set()

        inference.add_done_callback(clean_up_input)
        self.assertTrue(started.wait(timeout=1))

        self.assertFalse(inference.cancel())
        self.assertTrue(os.path.isfile(audio_path))
        release.set()
        self.assertEqual("done", inference.result(timeout=1)[0]["text"])
        self.assertTrue(cleaned_up.wait(timeout=1))
        self.assertFalse(os.path.exists(audio_path))

    def test_application_creation_defers_inference_worker_until_a_request(self):
        worker_count_before = sum(
            worker.name == "sensevoice-inference" for worker in threading.enumerate()
        )
        with mock.patch.object(funasr, "AutoModel", FakeAutoModel):
            application = self.create_application()
        self.addCleanup(application.state.sensevoice_scheduler.close)

        worker_count_after = sum(
            worker.name == "sensevoice-inference" for worker in threading.enumerate()
        )
        self.assertEqual(worker_count_before, worker_count_after)

    def test_close_waits_for_running_inference_and_stops_its_worker(self):
        started = threading.Event()
        release = threading.Event()
        closed = threading.Event()

        class BlockingModel:
            def generate(self, **kwargs):
                started.set()
                release.wait(timeout=3)
                return [{"text": "done"}]

        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as audio_file:
            audio_path = audio_file.name
        self.addCleanup(lambda: os.path.isfile(audio_path) and os.unlink(audio_path))
        scheduler = self.server.LatestInferenceScheduler(BlockingModel())
        self.addCleanup(scheduler.close)
        inference = scheduler.submit(audio_path, {"batch_size": 1})
        inference.add_done_callback(lambda _: os.unlink(audio_path))
        self.assertTrue(started.wait(timeout=1))

        closer = threading.Thread(target=lambda: (scheduler.close(), closed.set()))
        closer.start()
        self.assertFalse(closed.wait(timeout=1.2))
        release.set()
        self.assertTrue(closed.wait(timeout=1))
        closer.join(timeout=1)

        self.assertFalse(closer.is_alive())
        self.assertFalse(os.path.exists(audio_path))
        self.assertFalse(
            any(worker.name == "sensevoice-inference" for worker in threading.enumerate())
        )
        rejected = scheduler.submit("after-close.wav", {"batch_size": 1})
        with self.assertRaisesRegex(RuntimeError, "closed"):
            rejected.result(timeout=1)

    def test_close_before_running_transition_prevents_model_generate(self):
        set_running_entered = threading.Event()
        release_running_transition = threading.Event()
        closed = threading.Event()
        generated = []

        class Model:
            def generate(self, **kwargs):
                generated.append(kwargs)
                return [{"text": "unexpected"}]

        scheduler = self.server.LatestInferenceScheduler(Model())
        self.addCleanup(scheduler.close)
        original_set_running = self.server.Future.set_running_or_notify_cancel

        def block_running_transition(future):
            set_running_entered.set()
            release_running_transition.wait(timeout=3)
            return original_set_running(future)

        with mock.patch.object(
            self.server.Future,
            "set_running_or_notify_cancel",
            new=block_running_transition,
        ):
            scheduler.submit("queued.wav", {"batch_size": 1})
            self.assertTrue(set_running_entered.wait(timeout=1))
            closer = threading.Thread(target=lambda: (scheduler.close(), closed.set()))
            closer.start()
            release_running_transition.set()
            self.assertTrue(closed.wait(timeout=1))
            closer.join(timeout=1)

        self.assertFalse(closer.is_alive())
        self.assertEqual([], generated)

    def test_replaced_pending_request_returns_stable_json_response(self):
        first_request_started = threading.Event()
        release_first_request = threading.Event()
        obsolete_submitted = threading.Event()
        model_calls = 0

        class BlockingRequestAutoModel:
            def __init__(self, **kwargs):
                del kwargs

            def generate(self, **kwargs):
                nonlocal model_calls
                del kwargs
                model_calls += 1
                if model_calls == 2:
                    first_request_started.set()
                    release_first_request.wait(timeout=3)
                return [{"text": "<|zh|>done"}]

        with mock.patch.object(funasr, "AutoModel", BlockingRequestAutoModel):
            application = self.create_application()
        scheduler = application.state.sensevoice_scheduler
        original_submit = scheduler.submit
        submitted_count = 0

        def record_submit(*args, **kwargs):
            nonlocal submitted_count
            submitted_count += 1
            result = original_submit(*args, **kwargs)
            if submitted_count == 2:
                obsolete_submitted.set()
            return result

        scheduler.submit = record_submit
        audio = b"not-a-real-wave"
        outcomes = {}

        def post(name):
            try:
                outcomes[name] = client.post(
                    "/v1/audio/transcriptions",
                    files={"file": ("formula.wav", audio, "audio/wav")},
                    data={"model": "sensevoice", "response_format": "json"},
                )
            except BaseException as error:
                outcomes[name] = error

        with TestClient(application) as client:
            first = threading.Thread(target=post, args=("first",))
            first.start()
            self.assertTrue(first_request_started.wait(timeout=1))
            obsolete = threading.Thread(target=post, args=("obsolete",))
            obsolete.start()
            self.assertTrue(obsolete_submitted.wait(timeout=1))
            newest = threading.Thread(target=post, args=("newest",))
            newest.start()
            obsolete.join(timeout=1)
            release_first_request.set()
            first.join(timeout=1)
            newest.join(timeout=1)

        self.assertFalse(obsolete.is_alive())
        self.assertEqual(409, outcomes["obsolete"].status_code)
        self.assertEqual({"error": {"code": "request_replaced"}}, outcomes["obsolete"].json())
        self.assertIn("queue;dur=", outcomes["obsolete"].headers["server-timing"])
        self.assertIn("inference;dur=0.0", outcomes["obsolete"].headers["server-timing"])

    def test_route_removes_temp_audio_when_scheduler_submit_fails(self):
        with mock.patch.object(funasr, "AutoModel", FakeAutoModel):
            application = self.create_application()
        created_paths = []
        original_named_temporary_file = self.server.tempfile.NamedTemporaryFile

        def record_named_temporary_file(*args, **kwargs):
            temporary_file = original_named_temporary_file(*args, **kwargs)
            created_paths.append(temporary_file.name)
            return temporary_file

        with mock.patch.object(
            self.server.tempfile,
            "NamedTemporaryFile",
            side_effect=record_named_temporary_file,
        ), mock.patch.object(
            application.state.sensevoice_scheduler,
            "submit",
            side_effect=RuntimeError("scheduler unavailable"),
        ), TestClient(application, raise_server_exceptions=False) as client:
            response = client.post(
                "/v1/audio/transcriptions",
                files={"file": ("formula.wav", b"not-a-real-wave", "audio/wav")},
                data={"model": "sensevoice", "response_format": "json"},
            )

        self.assertEqual(500, response.status_code)
        self.assertEqual(1, len(created_paths))
        self.assertFalse(os.path.exists(created_paths[0]))

    def test_route_removes_temp_audio_when_file_write_fails(self):
        with mock.patch.object(funasr, "AutoModel", FakeAutoModel):
            application = self.create_application()
        created_paths = []
        original_named_temporary_file = self.server.tempfile.NamedTemporaryFile

        class FailingWriteTemporaryFile:
            def __init__(self, temporary_file):
                self._temporary_file = temporary_file
                self.name = temporary_file.name

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return self._temporary_file.__exit__(*args)

            def write(self, content):
                del content
                raise OSError("disk write failed")

        def create_failing_temporary_file(*args, **kwargs):
            temporary_file = original_named_temporary_file(*args, **kwargs)
            created_paths.append(temporary_file.name)
            return FailingWriteTemporaryFile(temporary_file)

        with mock.patch.object(
            self.server.tempfile,
            "NamedTemporaryFile",
            side_effect=create_failing_temporary_file,
        ), TestClient(application, raise_server_exceptions=False) as client:
            response = client.post(
                "/v1/audio/transcriptions",
                files={"file": ("formula.wav", b"not-a-real-wave", "audio/wav")},
                data={"model": "sensevoice", "response_format": "json"},
            )

        self.assertEqual(500, response.status_code)
        self.assertEqual(1, len(created_paths))
        self.assertFalse(os.path.exists(created_paths[0]))

    def test_route_retries_temp_audio_cleanup_after_permission_error(self):
        with self.create_client() as client:
            original_unlink = self.server.os.unlink
            unlink_attempts = []

            def fail_once(path):
                unlink_attempts.append(path)
                if len(unlink_attempts) == 1:
                    raise PermissionError("temporary lock")
                return original_unlink(path)

            with mock.patch.object(self.server.os, "unlink", side_effect=fail_once):
                response = client.post(
                    "/v1/audio/transcriptions",
                    files={"file": ("formula.wav", b"not-a-real-wave", "audio/wav")},
                    data={"model": "sensevoice", "response_format": "json"},
                )
                input_path = FakeAutoModel.generate_calls[1]["input_path"]
                removed = False
                for _ in range(20):
                    if not input_path.exists():
                        removed = True
                        break
                    threading.Event().wait(timeout=0.05)

        self.assertEqual(200, response.status_code)
        self.assertTrue(removed)
        self.assertGreaterEqual(len(unlink_attempts), 2)

    def test_transcription_response_exposes_non_sensitive_phase_timings(self):
        audio_bytes = BytesIO()
        with wave.open(audio_bytes, "wb") as audio_file:
            audio_file.setnchannels(1)
            audio_file.setsampwidth(2)
            audio_file.setframerate(16000)
            audio_file.writeframes(b"\x10\x27" * 8000)

        with self.create_client() as client:
            response = client.post(
                "/v1/audio/transcriptions",
                files={"file": ("formula.wav", audio_bytes.getvalue(), "audio/wav")},
                data={"model": "sensevoice", "response_format": "json"},
            )

        self.assertEqual(200, response.status_code)
        timings = response.headers.get("server-timing", "")
        for stage in ("read", "prepare", "queue", "inference", "total"):
            self.assertIn(f"{stage};dur=", timings)

    def test_verbose_transcription_keeps_openai_compatible_segment(self):
        audio_bytes = BytesIO()
        with wave.open(audio_bytes, "wb") as audio_file:
            audio_file.setnchannels(1)
            audio_file.setsampwidth(2)
            audio_file.setframerate(16000)
            audio_file.writeframes(b"\x00\x00" * 16000)
            audio_file.writeframes(b"\x10\x27" * 8000)

        with self.create_client() as client:
            response = client.post(
                "/v1/audio/transcriptions",
                files={"file": ("formula.wav", audio_bytes.getvalue(), "audio/wav")},
                data={
                    "model": "sensevoice",
                    "language": "auto",
                    "response_format": "verbose_json",
                },
            )

        self.assertEqual(200, response.status_code)
        self.assertEqual("transcribe", response.json()["task"])
        self.assertEqual("zh", response.json()["language"])
        self.assertEqual(1.5, response.json()["duration"])
        self.assertEqual(1, len(response.json()["segments"]))
        self.assertEqual(0, response.json()["segments"][0]["id"])
        self.assertEqual(0.88, response.json()["segments"][0]["start"])
        self.assertEqual(1.5, response.json()["segments"][0]["end"])
        self.assertEqual(
            "\u8d1f\u4e8c\u7684\u5e73\u65b9",
            response.json()["segments"][0]["text"],
        )
        self.assertEqual([], response.json()["segments"][0]["words"])

    def test_health_reports_loaded_cpu_sensevoice_runtime(self):
        with self.create_client() as client:
            response = client.get("/health")

        self.assertEqual(200, response.status_code)
        self.assertEqual(
            {
                "status": "healthy",
                "runtime": "funasr-1.3.29",
                "device": "cpu",
                "model": "sensevoice",
                "modelsLoaded": ["sensevoice"],
            },
            response.json(),
        )
        self.assertEqual("iic/SenseVoiceSmall", FakeAutoModel.constructions[0]["model"])
        self.assertEqual("cpu", FakeAutoModel.constructions[0]["device"])

    def test_model_is_warmed_exactly_once_before_application_returns(self):
        with mock.patch.object(funasr, "AutoModel", FakeAutoModel):
            application = self.create_application()

        self.assertIsNotNone(application)
        self.assertEqual(["create", "generate"], FakeAutoModel.events)
        self.assertEqual(1, len(FakeAutoModel.generate_calls))
        self.assertEqual(
            {"input", "batch_size"},
            set(FakeAutoModel.generate_calls[0]["kwargs"]),
        )
        self.assertEqual(1, FakeAutoModel.generate_calls[0]["kwargs"]["batch_size"])

    def test_warmup_uses_short_pcm16_16khz_mono_wave(self):
        with mock.patch.object(funasr, "AutoModel", FakeAutoModel):
            self.create_application()

        self.assertEqual(1, len(FakeAutoModel.generate_calls))
        warmup_call = FakeAutoModel.generate_calls[0]
        self.assertTrue(warmup_call["input_existed"])
        self.assertEqual(
            {
                "channels": 1,
                "sample_width": 2,
                "frame_rate": 16000,
                "compression": "NONE",
            },
            {
                key: warmup_call["audio_metadata"][key]
                for key in ("channels", "sample_width", "frame_rate", "compression")
            },
        )
        self.assertGreater(warmup_call["audio_metadata"]["frame_count"], 0)
        self.assertLessEqual(warmup_call["audio_metadata"]["frame_count"], 16000)

    def test_warmup_temporary_wave_is_removed_before_application_returns(self):
        with mock.patch.object(funasr, "AutoModel", FakeAutoModel):
            self.create_application()

        self.assertEqual(1, len(FakeAutoModel.generate_calls))
        self.assertFalse(FakeAutoModel.generate_calls[0]["input_path"].exists())

    def test_warmup_failure_stops_application_creation_and_removes_audio(self):
        with mock.patch.object(funasr, "AutoModel", FailingWarmupAutoModel):
            with self.assertRaisesRegex(RuntimeError, "warmup failed"):
                self.create_application()

        self.assertEqual(["create", "generate"], FakeAutoModel.events)
        self.assertEqual(1, len(FakeAutoModel.generate_calls))
        self.assertFalse(FakeAutoModel.generate_calls[0]["input_path"].exists())

    def test_synthetic_warmup_accepts_empty_transcript_after_inference(self):
        with mock.patch.object(funasr, "AutoModel", EmptyWarmupAutoModel):
            application = self.create_application()

        self.assertIsNotNone(application)
        self.assertEqual(["create", "generate"], FakeAutoModel.events)
        self.assertEqual(1, len(FakeAutoModel.generate_calls))
        self.assertFalse(FakeAutoModel.generate_calls[0]["input_path"].exists())

    def test_synthetic_warmup_rejects_malformed_route_result(self):
        with mock.patch.object(funasr, "AutoModel", MalformedFirstWarmupAutoModel):
            with self.assertRaisesRegex(RuntimeError, "no usable text"):
                self.create_application()

        self.assertEqual(["create", "generate"], FakeAutoModel.events)
        self.assertEqual(1, len(FakeAutoModel.generate_calls))
        self.assertFalse(FakeAutoModel.generate_calls[0]["input_path"].exists())

    def test_empty_real_speech_warmup_stops_application_creation_before_health(self):
        with mock.patch.object(funasr, "AutoModel", EmptyWarmupAutoModel):
            with self.assertRaisesRegex(RuntimeError, "no usable text"):
                self.create_application(self.create_local_model_directory())

        self.assertEqual(["create", "generate"], FakeAutoModel.events)
        self.assertEqual(1, len(FakeAutoModel.generate_calls))
        self.assertTrue(FakeAutoModel.generate_calls[0]["input_path"].exists())

    def test_tags_only_real_speech_warmup_stops_application_creation_before_health(self):
        with mock.patch.object(funasr, "AutoModel", TagsOnlyWarmupAutoModel):
            with self.assertRaisesRegex(RuntimeError, "no usable text"):
                self.create_application(self.create_local_model_directory())

        self.assertEqual(["create", "generate"], FakeAutoModel.events)
        self.assertEqual(1, len(FakeAutoModel.generate_calls))
        self.assertTrue(FakeAutoModel.generate_calls[0]["input_path"].exists())

    def test_later_text_does_not_hide_empty_first_warmup_result(self):
        with mock.patch.object(funasr, "AutoModel", LaterTextWarmupAutoModel):
            with self.assertRaisesRegex(RuntimeError, "no usable text"):
                self.create_application(self.create_local_model_directory())

        self.assertEqual(["create", "generate"], FakeAutoModel.events)
        self.assertEqual(1, len(FakeAutoModel.generate_calls))
        self.assertTrue(FakeAutoModel.generate_calls[0]["input_path"].exists())

    def test_later_text_does_not_hide_malformed_first_warmup_result(self):
        with mock.patch.object(funasr, "AutoModel", MalformedFirstWarmupAutoModel):
            with self.assertRaisesRegex(RuntimeError, "no usable text"):
                self.create_application(self.create_local_model_directory())

        self.assertEqual(["create", "generate"], FakeAutoModel.events)
        self.assertEqual(1, len(FakeAutoModel.generate_calls))
        self.assertTrue(FakeAutoModel.generate_calls[0]["input_path"].exists())

    def test_local_snapshot_example_audio_is_used_and_preserved(self):
        with tempfile.TemporaryDirectory() as model_directory:
            example_path = pathlib.Path(model_directory) / "example" / "zh.mp3"
            example_path.parent.mkdir()
            example_path.write_bytes(b"fake local example audio")

            with mock.patch.object(funasr, "AutoModel", FakeAutoModel):
                application = self.server.create_application(
                    host="127.0.0.1",
                    device="cpu",
                    cors_origin="http://localhost:5174",
                    model_path=model_directory,
                )

            self.assertIsNotNone(application)
            self.assertEqual(example_path, FakeAutoModel.generate_calls[0]["input_path"])
            self.assertTrue(example_path.is_file())

    def test_local_snapshot_example_audio_is_preserved_when_warmup_fails(self):
        with tempfile.TemporaryDirectory() as model_directory:
            example_path = pathlib.Path(model_directory) / "example" / "zh.mp3"
            example_path.parent.mkdir()
            example_path.write_bytes(b"fake local example audio")

            with mock.patch.object(funasr, "AutoModel", FailingWarmupAutoModel):
                with self.assertRaisesRegex(RuntimeError, "warmup failed"):
                    self.server.create_application(
                        host="127.0.0.1",
                        device="cpu",
                        cors_origin="http://localhost:5174",
                        model_path=model_directory,
                    )

            self.assertEqual(example_path, FakeAutoModel.generate_calls[0]["input_path"])
            self.assertTrue(example_path.is_file())

    def test_local_model_snapshot_is_forwarded_without_network_lookup(self):
        patcher = mock.patch.object(funasr, "AutoModel", FakeAutoModel)
        patcher.start()
        self.addCleanup(patcher.stop)

        application = self.server.create_application(
            host="127.0.0.1",
            device="cpu",
            cors_origin="http://localhost:5174",
            model_path=r"D:\dev\local-ai\sensevoice\cache\modelscope\models\iic--SenseVoiceSmall\snapshots\master",
        )

        with TestClient(application) as client:
            response = client.get("/health")

        self.assertEqual(200, response.status_code)
        self.assertEqual(["sensevoice"], response.json()["modelsLoaded"])
        self.assertEqual(
            r"D:\dev\local-ai\sensevoice\cache\modelscope\models\iic--SenseVoiceSmall\snapshots\master",
            FakeAutoModel.constructions[0]["model"],
        )

    def test_cors_preflight_allows_only_configured_local_origin(self):
        with self.create_client() as client:
            allowed = client.options(
                "/v1/audio/transcriptions",
                headers={
                    "Origin": "http://localhost:5174",
                    "Access-Control-Request-Method": "POST",
                },
            )
            denied = client.options(
                "/v1/audio/transcriptions",
                headers={
                    "Origin": "http://example.invalid",
                    "Access-Control-Request-Method": "POST",
                },
            )

        self.assertEqual(200, allowed.status_code)
        self.assertEqual(
            "http://localhost:5174", allowed.headers["access-control-allow-origin"]
        )
        self.assertEqual(400, denied.status_code)
        self.assertNotIn("access-control-allow-origin", denied.headers)

    def test_official_multipart_route_transcribes_with_fake_model(self):
        with self.create_client() as client:
            response = client.post(
                "/v1/audio/transcriptions",
                files={"file": ("formula.wav", b"not-a-real-wave", "audio/wav")},
                data={"model": "sensevoice", "response_format": "json"},
            )

        self.assertEqual(200, response.status_code)
        self.assertEqual({"text": "负二的平方"}, response.json())

    def test_public_host_is_rejected_before_funasr_app_creation(self):
        with mock.patch("funasr.bin._server_app.create_app") as create_app:
            with self.assertRaisesRegex(ValueError, "127.0.0.1"):
                self.server.create_application(
                    host="0.0.0.0",
                    device="cpu",
                    cors_origin="http://localhost:5174",
                )

        create_app.assert_not_called()


if __name__ == "__main__":
    unittest.main()
