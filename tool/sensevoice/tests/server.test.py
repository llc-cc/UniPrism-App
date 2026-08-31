import importlib.util
import pathlib
import tempfile
import unittest
import wave
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
