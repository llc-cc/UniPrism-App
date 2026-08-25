"""Add local CORS and health metadata to FunASR's official HTTP server."""

from __future__ import annotations

import argparse
from typing import Any


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


def create_application(device: str, cors_origin: str):
    import funasr
    from fastapi import FastAPI
    from fastapi.middleware.cors import CORSMiddleware
    from funasr.bin._server_app import create_app as create_funasr_app

    # 1.3.29 已提供 OpenAI 转写端点和模型预加载；这里只补项目需要的 CORS 与稳定 health 字段.
    funasr_app = create_funasr_app(device=device, preload_model="sensevoice", hub="ms")
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
    if arguments.host != "127.0.0.1":
        raise SystemExit("Local SenseVoice may bind only to 127.0.0.1")

    import uvicorn

    application = create_application(arguments.device, arguments.cors_origin)
    uvicorn.run(application, host=arguments.host, port=arguments.port)


if __name__ == "__main__":
    main()
