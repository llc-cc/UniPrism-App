"""将内存中的社区候选分批直传后端，不提供本地文件降级。"""

import asyncio
from collections.abc import Awaitable, Callable
from typing import Any, Literal

import httpx

from university_crawler.community_models import (
    CommunityEvidenceCandidate,
    CommunityPlatform,
)
from university_crawler.config import Settings

RetryDelay = Callable[[float], Awaitable[None]]


def _document_payload(candidate: CommunityEvidenceCandidate) -> dict[str, Any]:
    return {
        "externalId": candidate.external_id,
        "url": str(candidate.url),
        "title": candidate.title,
        "text": candidate.text,
        "dimension": candidate.dimension,
        "discoveredAt": candidate.discovered_at.isoformat().replace("+00:00", "Z"),
        "publishedAt": (
            candidate.published_at.isoformat().replace("+00:00", "Z")
            if candidate.published_at
            else None
        ),
        "engagement": candidate.engagement,
    }


async def upload_community_evidence(
    candidates: list[CommunityEvidenceCandidate],
    *,
    platform: CommunityPlatform,
    run_id: str,
    query: str,
    trigger: Literal["manual", "scheduled"] = "manual",
    agent_metadata: dict[str, Any] | None = None,
    settings: Settings,
    transport: httpx.AsyncBaseTransport | None = None,
    retry_delay: RetryDelay = asyncio.sleep,
) -> list[dict[str, Any]]:
    """网络故障和 5xx 最多重试三次；鉴权/契约错误立即失败。"""

    endpoint = settings.crawler_community_ingest_url.strip()
    token = settings.crawler_backend_token.strip()
    if not endpoint or not token:
        raise RuntimeError(
            "CRAWLER_COMMUNITY_INGEST_URL and CRAWLER_BACKEND_TOKEN "
            "must be configured; local fallback is disabled."
        )

    results: list[dict[str, Any]] = []
    async with httpx.AsyncClient(
        transport=transport,
        timeout=httpx.Timeout(60.0, connect=15.0),
        headers={"Authorization": f"Bearer {token}"},
    ) as client:
        for offset in range(0, len(candidates), 50):
            batch = candidates[offset:offset + 50]
            payload = {
                "runId": f"{run_id}-{offset // 50:03d}",
                "institutionCode": "peking-university",
                "institutionName": "北京大学",
                "platform": platform,
                "query": query,
                "trigger": trigger,
                "documents": [_document_payload(item) for item in batch],
            }
            if agent_metadata is not None:
                # 只上传可审计统计，不上传模型思维链或浏览器会话数据。
                payload["agentMetadata"] = agent_metadata
            for attempt in range(3):
                try:
                    response = await client.post(endpoint, json=payload)
                except httpx.TransportError as error:
                    if attempt == 2:
                        raise RuntimeError("Community upload network failure.") from error
                    await retry_delay(2 ** attempt)
                    continue

                if response.status_code >= 500:
                    if attempt == 2:
                        raise RuntimeError(
                            f"Community backend unavailable: {response.status_code}"
                        )
                    await retry_delay(2 ** attempt)
                    continue
                if response.status_code >= 400:
                    # 401/403 和其他 4xx 都不是暂时故障，重试只会重复错误请求。
                    raise RuntimeError(
                        f"Community upload rejected: {response.status_code} "
                        f"{response.text[:300]}"
                    )

                body = response.json()
                if body.get("ok") is not True or not isinstance(body.get("data"), dict):
                    raise RuntimeError("Invalid community ingestion response.")
                results.append(body["data"])
                break

    return results
