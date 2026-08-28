import importlib.util
import pathlib
import unittest
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

    def __init__(self, **kwargs):
        self.constructions.append(kwargs)

    def generate(self, **_kwargs):
        return [{"text": "<|zh|><|NEUTRAL|><|Speech|><|woitn|>负二的平方"}]


class SenseVoiceApplicationTests(unittest.TestCase):
    def setUp(self):
        FakeAutoModel.constructions.clear()
        self.server = load_server_module()

    def create_client(self):
        patcher = mock.patch.object(funasr, "AutoModel", FakeAutoModel)
        patcher.start()
        self.addCleanup(patcher.stop)
        application = self.server.create_application(
            host="127.0.0.1",
            device="cpu",
            cors_origin="http://localhost:5174",
        )
        return TestClient(application)

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
