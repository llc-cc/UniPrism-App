"""北京大学社区证据试点的发现、抓取和直传编排。"""

from collections.abc import Awaitable, Callable
from typing import Any, Literal
from uuid import uuid4

from pydantic import BaseModel

from university_crawler.community_crawler import (
    CommunityCrawlResult,
    crawl_discovered_link,
)
from university_crawler.community_discovery import (
    DiscoveryNotConfigured,
    discover_public_links,
)
from university_crawler.community_ingestion import upload_community_evidence
from university_crawler.community_models import (
    CommunityDiscoveryPlan,
    CommunityEvidenceCandidate,
    CommunityPlatform,
    DiscoveredLink,
)
from university_crawler.config import Settings

PlatformArgument = Literal["all", "zhihu", "tieba"]
Discoverer = Callable[..., Awaitable[list[DiscoveredLink]]]
Crawler = Callable[[DiscoveredLink, Settings], Awaitable[CommunityCrawlResult]]
Uploader = Callable[..., Awaitable[list[dict[str, Any]]]]

ALL_DIMENSIONS = [
    "school",
    "major",
    "course",
    "employment",
    "dormitory",
    "cafeteria",
    "student_club",
]


class CommunityRunResult(BaseModel):
    exit_code: int
    state: str
    counts: dict[str, int]


def _empty_counts() -> dict[str, int]:
    return {
        "discovered": 0,
        "allowed": 0,
        "blocked": 0,
        "pages_fetched": 0,
        "candidates_extracted": 0,
        "uploaded": 0,
        "rejected": 0,
        "failed": 0,
    }


async def run_community_pilot(
    settings: Settings,
    *,
    platform: PlatformArgument,
    discoverer: Discoverer = discover_public_links,
    crawler: Crawler = crawl_discovered_link,
    uploader: Uploader = upload_community_evidence,
) -> CommunityRunResult:
    """单个平台受阻只计数，另一平台仍继续，避免整批任务误判失败。"""

    counts = _empty_counts()
    platforms: list[CommunityPlatform] = (
        ["zhihu", "tieba"] if platform == "all" else [platform]
    )
    plan = CommunityDiscoveryPlan(
        institution_code="peking-university",
        institution_name="北京大学",
        platforms=platforms,
        dimensions=ALL_DIMENSIONS,
    )
    try:
        links = await discoverer(plan, settings)
    except DiscoveryNotConfigured:
        return CommunityRunResult(
            exit_code=4,
            state="DISCOVERY_NOT_CONFIGURED",
            counts=counts,
        )

    counts["discovered"] = len(links)
    counts["allowed"] = len(links)
    candidates_by_platform: dict[CommunityPlatform, list[CommunityEvidenceCandidate]] = {
        "zhihu": [],
        "tieba": [],
    }
    query_by_platform: dict[CommunityPlatform, str] = {}

    for link in links:
        result = await crawler(link, settings)
        if result.status.startswith("blocked_"):
            counts["blocked"] += 1
            continue
        if result.status == "failed":
            counts["failed"] += 1
            continue
        counts["pages_fetched"] += 1
        counts["candidates_extracted"] += len(result.candidates)
        candidates_by_platform[link.platform].extend(result.candidates)
        query_by_platform.setdefault(link.platform, link.query)

    run_id = f"community-{uuid4().hex}"
    for current_platform in platforms:
        candidates = candidates_by_platform[current_platform]
        if not candidates:
            continue
        try:
            upload_results = await uploader(
                candidates,
                platform=current_platform,
                run_id=run_id,
                query=query_by_platform.get(current_platform, "北京大学社区公开内容"),
                settings=settings,
            )
        except Exception:
            counts["failed"] += len(candidates)
            continue
        counts["uploaded"] += sum(
            int(result.get("createdCount", 0))
            + int(result.get("updatedCount", 0))
            + int(result.get("unchangedCount", 0))
            for result in upload_results
        )
        counts["rejected"] += sum(
            int(result.get("rejectedCount", 0)) for result in upload_results
        )
        counts["failed"] += sum(
            int(result.get("failedCount", 0)) for result in upload_results
        )

    return CommunityRunResult(exit_code=0, state="COMPLETED", counts=counts)
