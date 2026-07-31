"""通过有授权的搜索 API 发现公开链接，搜索响应本身不落盘。"""

import asyncio

import httpx

from university_crawler.community_models import (
    CommunityDiscoveryPlan,
    DiscoveredLink,
)
from university_crawler.community_policies import (
    PLATFORM_HOSTS,
    evaluate_public_url,
)
from university_crawler.config import Settings

BRAVE_SEARCH_ENDPOINT = "https://api.search.brave.com/res/v1/web/search"

DIMENSION_TERMS = {
    "school": "学校 校园体验",
    "major": "专业 选择",
    "course": "课程 选课",
    "employment": "就业 实习",
    "dormitory": "宿舍 住宿",
    "cafeteria": "食堂 餐饮",
    "student_club": "社团 学生活动",
}


class DiscoveryNotConfigured(RuntimeError):
    """搜索凭据缺失时使用明确状态，禁止伪装为零结果成功。"""


async def discover_public_links(
    plan: CommunityDiscoveryPlan,
    settings: Settings,
    *,
    transport: httpx.AsyncBaseTransport | None = None,
) -> list[DiscoveredLink]:
    api_key = settings.brave_search_api_key.strip()
    if not api_key:
        raise DiscoveryNotConfigured("DISCOVERY_NOT_CONFIGURED")

    links_by_url: dict[str, DiscoveredLink] = {}
    headers = {
        "Accept": "application/json",
        "X-Subscription-Token": api_key,
    }
    async with httpx.AsyncClient(
        transport=transport,
        timeout=httpx.Timeout(20.0, connect=10.0),
        headers=headers,
    ) as client:
        requests_sent = 0
        for platform in plan.platforms:
            search_host = PLATFORM_HOSTS[platform][0]
            for dimension in plan.dimensions:
                if len(links_by_url) >= settings.community_discovery_max_results:
                    return list(links_by_url.values())
                if requests_sent and transport is None:
                    # 真实搜索调用限速；测试 transport 不等待。
                    await asyncio.sleep(settings.community_request_delay_seconds)
                query = (
                    f"site:{search_host} {plan.institution_name} "
                    f"{DIMENSION_TERMS[dimension]}"
                )
                response = await client.get(
                    BRAVE_SEARCH_ENDPOINT,
                    params={"q": query, "count": 10},
                )
                response.raise_for_status()
                requests_sent += 1
                results = response.json().get("web", {}).get("results", [])
                for result in results:
                    raw_url = str(result.get("url", "")).strip()
                    if evaluate_public_url(raw_url, platform).status != "allowed":
                        continue
                    link = DiscoveredLink(
                        platform=platform,
                        dimension=dimension,
                        url=raw_url,
                        title=str(result.get("title", ""))[:500],
                        query=query,
                    )
                    links_by_url.setdefault(str(link.url), link)
                    if len(links_by_url) >= settings.community_discovery_max_results:
                        break

    return list(links_by_url.values())
