"""北京大学社区证据试点的发现、抓取和直传编排。"""

import asyncio
from collections.abc import Awaitable, Callable
from pathlib import Path
from typing import Any, Literal
from uuid import uuid4

from pydantic import BaseModel

from university_crawler.community_agent import (
    CommunityAgentNotConfigured,
    run_community_agent_task,
)
from university_crawler.community_agent_skill import (
    CommunityAgentSkill,
    CommunityAgentSkillNotConfigured,
    build_community_agent_tasks,
    load_community_agent_skill,
)
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
    CommunityAgentTask,
    CommunityAgentTaskResult,
    CommunityDimension,
    CommunityEvidenceCandidate,
    CommunityPlatform,
    DiscoveredLink,
)
from university_crawler.config import Settings

PlatformArgument = Literal["all", "zhihu", "tieba"]
DimensionArgument = Literal[
    "all",
    "school",
    "major",
    "course",
    "employment",
    "dormitory",
    "cafeteria",
    "student_club",
]
DiscoveryMode = Literal["agent", "search_api"]
ExecutionTrigger = Literal["manual", "scheduled"]
Discoverer = Callable[..., Awaitable[list[DiscoveredLink]]]
Crawler = Callable[[DiscoveredLink, Settings], Awaitable[CommunityCrawlResult]]
Uploader = Callable[..., Awaitable[list[dict[str, Any]]]]
AgentTaskRunner = Callable[
    [CommunityAgentTask, CommunityAgentSkill, Settings],
    Awaitable[CommunityAgentTaskResult],
]
SkillLoader = Callable[[Path], CommunityAgentSkill]
TaskDelay = Callable[[float], Awaitable[None]]

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
        "planned_tasks": 0,
        "completed_tasks": 0,
        "blocked_tasks": 0,
        "failed_tasks": 0,
        "agent_steps": 0,
        "pages_visited": 0,
        "candidates_submitted": 0,
        "duplicates_removed": 0,
    }


async def run_community_pilot(
    settings: Settings,
    *,
    platform: PlatformArgument,
    discovery_mode: DiscoveryMode = "agent",
    dimension: DimensionArgument = "all",
    execution_trigger: ExecutionTrigger = "manual",
    discoverer: Discoverer = discover_public_links,
    crawler: Crawler = crawl_discovered_link,
    uploader: Uploader = upload_community_evidence,
    agent_task_runner: AgentTaskRunner = run_community_agent_task,
    skill_loader: SkillLoader = load_community_agent_skill,
    task_delay: TaskDelay = asyncio.sleep,
) -> CommunityRunResult:
    """单个平台受阻只计数，另一平台仍继续，避免整批任务误判失败。"""

    platforms: list[CommunityPlatform] = (
        ["zhihu", "tieba"] if platform == "all" else [platform]
    )
    dimensions: list[CommunityDimension] = (
        list(ALL_DIMENSIONS) if dimension == "all" else [dimension]
    )
    plan = CommunityDiscoveryPlan(
        institution_code="peking-university",
        institution_name="北京大学",
        platforms=platforms,
        dimensions=dimensions,
    )

    if discovery_mode == "agent":
        return await _run_agent_pilot(
            plan,
            settings,
            uploader=uploader,
            agent_task_runner=agent_task_runner,
            skill_loader=skill_loader,
            task_delay=task_delay,
            execution_trigger=execution_trigger,
        )
    return await _run_search_api_pilot(
        plan,
        settings,
        discoverer=discoverer,
        crawler=crawler,
        uploader=uploader,
        execution_trigger=execution_trigger,
    )


async def _run_agent_pilot(
    plan: CommunityDiscoveryPlan,
    settings: Settings,
    *,
    uploader: Uploader,
    agent_task_runner: AgentTaskRunner,
    skill_loader: SkillLoader,
    task_delay: TaskDelay,
    execution_trigger: ExecutionTrigger,
) -> CommunityRunResult:
    """串行执行受控 Agent，限制并发可降低平台压力和服务器内存峰值。"""

    counts = _empty_counts()
    if not settings.community_agent_enabled:
        return CommunityRunResult(
            exit_code=5,
            state="AGENT_DISABLED",
            counts=counts,
        )
    try:
        skill = skill_loader(Path(settings.community_agent_skill_path))
    except CommunityAgentSkillNotConfigured:
        return CommunityRunResult(
            exit_code=5,
            state="AGENT_SKILL_NOT_CONFIGURED",
            counts=counts,
        )

    tasks = build_community_agent_tasks(plan)
    counts["planned_tasks"] = len(tasks)
    candidates_by_platform: dict[
        CommunityPlatform,
        list[CommunityEvidenceCandidate],
    ] = {"zhihu": [], "tieba": []}
    seen_external_ids: set[str] = set()

    for index, task in enumerate(tasks):
        try:
            result = await agent_task_runner(task, skill, settings)
        except CommunityAgentNotConfigured:
            return CommunityRunResult(
                exit_code=5,
                state="AGENT_NOT_CONFIGURED",
                counts=counts,
            )
        except Exception:
            counts["failed_tasks"] += 1
            counts["failed"] += 1
        else:
            counts["agent_steps"] += result.steps
            counts["pages_visited"] += result.pages_visited
            counts["candidates_extracted"] += len(result.candidates)
            if result.status == "completed":
                counts["completed_tasks"] += 1
            elif result.status.startswith("blocked_"):
                counts["blocked_tasks"] += 1
                counts["blocked"] += 1
            else:
                counts["failed_tasks"] += 1
                counts["failed"] += 1

            for candidate in result.candidates:
                if candidate.external_id in seen_external_ids:
                    counts["duplicates_removed"] += 1
                    continue
                seen_external_ids.add(candidate.external_id)
                candidates_by_platform[candidate.platform].append(candidate)

        if index < len(tasks) - 1 and settings.community_agent_task_delay_seconds:
            await task_delay(settings.community_agent_task_delay_seconds)

    counts["candidates_submitted"] = sum(
        len(items) for items in candidates_by_platform.values()
    )
    run_id = f"community-agent-{uuid4().hex}"
    for current_platform in plan.platforms:
        candidates = candidates_by_platform[current_platform]
        if not candidates:
            continue
        try:
            upload_results = await uploader(
                candidates,
                platform=current_platform,
                run_id=run_id,
                query=f"北京大学 {current_platform} 七维度公开社区证据",
                trigger=execution_trigger,
                agent_metadata={
                    "mode": "agent",
                    "skillName": skill.name,
                    "skillVersion": skill.version,
                    "plannedTasks": counts["planned_tasks"],
                    "completedTasks": counts["completed_tasks"],
                    "blockedTasks": counts["blocked_tasks"],
                    "failedTasks": counts["failed_tasks"],
                    "steps": counts["agent_steps"],
                    "pagesVisited": counts["pages_visited"],
                    "duplicatesRemoved": counts["duplicates_removed"],
                    "triggerSource": execution_trigger,
                },
                settings=settings,
            )
        except Exception:
            counts["failed"] += len(candidates)
            continue
        _merge_upload_counts(counts, upload_results)

    state = "COMPLETED" if counts["failed_tasks"] == 0 else "COMPLETED_WITH_ERRORS"
    return CommunityRunResult(exit_code=0, state=state, counts=counts)


async def _run_search_api_pilot(
    plan: CommunityDiscoveryPlan,
    settings: Settings,
    *,
    discoverer: Discoverer,
    crawler: Crawler,
    uploader: Uploader,
    execution_trigger: ExecutionTrigger,
) -> CommunityRunResult:
    """保留已有搜索 API 模式，便于 Agent 故障时人工诊断。"""

    counts = _empty_counts()
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
    for current_platform in plan.platforms:
        candidates = candidates_by_platform[current_platform]
        if not candidates:
            continue
        try:
            upload_results = await uploader(
                candidates,
                platform=current_platform,
                run_id=run_id,
                query=query_by_platform.get(current_platform, "北京大学社区公开内容"),
                trigger=execution_trigger,
                settings=settings,
            )
        except Exception:
            counts["failed"] += len(candidates)
            continue
        _merge_upload_counts(counts, upload_results)

    return CommunityRunResult(exit_code=0, state="COMPLETED", counts=counts)


def _merge_upload_counts(
    counts: dict[str, int],
    upload_results: list[dict[str, Any]],
) -> None:
    """统一汇总后端批次结果，避免两种发现模式产生不同统计口径。"""

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
