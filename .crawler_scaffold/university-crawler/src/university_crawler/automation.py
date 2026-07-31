"""Reads the backend-owned university crawler automation control."""

from typing import Any

import httpx

from university_crawler.config import Settings


async def fetch_university_automation_enabled(
    settings: Settings,
    *,
    transport: httpx.AsyncBaseTransport | None = None,
) -> bool:
    """Returns the persisted switch and rejects missing or malformed responses."""

    control_url = settings.crawler_backend_control_url.strip()
    token = settings.crawler_backend_token.strip()
    if not control_url or not token:
        raise RuntimeError("automation control is not configured")

    async with httpx.AsyncClient(
        timeout=10,
        transport=transport,
        follow_redirects=False,
    ) as client:
        response = await client.get(
            control_url,
            headers={"Authorization": f"Bearer {token}"},
        )
        response.raise_for_status()

    try:
        body: Any = response.json()
        enabled = body["data"]["enabled"]
    except (KeyError, TypeError, ValueError) as error:
        raise RuntimeError("invalid automation response") from error

    # bool 是唯一可接受类型，避免字符串 "false" 被 Python 当成真值而误启动采集。
    if type(enabled) is not bool:
        raise RuntimeError("invalid automation response")
    return enabled

