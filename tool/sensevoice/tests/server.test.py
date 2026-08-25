import importlib.util
import pathlib
import unittest


SERVER_PATH = pathlib.Path(__file__).parents[1] / "server.py"


def load_server_module():
    spec = importlib.util.spec_from_file_location("sensevoice_server", SERVER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class HealthPayloadTests(unittest.TestCase):
    def test_builds_healthy_runtime_payload_after_official_app_load(self):
        server = load_server_module()

        payload = server.build_health_payload("cpu", "1.3.29", ["sensevoice"])

        self.assertEqual(
            {
                "status": "healthy",
                "runtime": "funasr-1.3.29",
                "device": "cpu",
                "model": "sensevoice",
                "modelsLoaded": ["sensevoice"],
            },
            payload,
        )


if __name__ == "__main__":
    unittest.main()
