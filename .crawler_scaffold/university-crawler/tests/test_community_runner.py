"""社区试点编排在单个平台受阻时继续处理其他平台。"""

import unittest
from datetime import datetime, timezone

from university_crawler.community_discovery import DiscoveryNotConfigured
from university_crawler.community_models import (
    CommunityEvidenceCandidate,
    DiscoveredLink,
)
from university_crawler.community_crawler import CommunityCrawlResult
from university_crawler.community_runner import run_community_pilot
from university_crawler.config import Settings


class CommunityRunnerTest(unittest.IsolatedAsyncioTestCase):
    async def test_discovery_not_configured_returns_code_four(self) -> None:
        async def discoverer(*_args, **_kwargs):
            raise DiscoveryNotConfigured("DISCOVERY_NOT_CONFIGURED")

        result = await run_community_pilot(
            Settings(),
            platform="all",
            discoverer=discoverer,
        )

        self.assertEqual(result.exit_code, 4)
        self.assertEqual(result.state, "DISCOVERY_NOT_CONFIGURED")

    async def test_platform_block_does_not_stop_other_platform(self) -> None:
        links = [
            DiscoveredLink(
                platform="zhihu",
                dimension="course",
                url="https://www.zhihu.com/question/1",
                title="课程",
                query="query",
            ),
            DiscoveredLink(
                platform="tieba",
                dimension="dormitory",
                url="https://tieba.baidu.com/p/1",
                title="宿舍",
                query="query",
            ),
        ]

        async def discoverer(*_args, **_kwargs):
            return links

        async def crawler(link, _settings):
            if link.platform == "zhihu":
                return CommunityCrawlResult(
                    status="blocked_login",
                    candidates=[],
                    block_reason="login_wall",
                    final_url=link.url,
                    elapsed_ms=1,
                )
            return CommunityCrawlResult(
                status="completed",
                candidates=[
                    CommunityEvidenceCandidate(
                        external_id="tieba-1",
                        platform="tieba",
                        dimension="dormitory",
                        url=link.url,
                        title="北京大学宿舍",
                        text="宿舍安排会因校区和年级变化，应以学校当年通知为准。",
                        discovered_at=datetime.now(timezone.utc),
                    )
                ],
                final_url=link.url,
                elapsed_ms=1,
            )

        uploaded_platforms: list[str] = []

        async def uploader(candidates, *, platform, **_kwargs):
            uploaded_platforms.append(platform)
            return [{
                "createdCount": len(candidates),
                "updatedCount": 0,
                "unchangedCount": 0,
                "rejectedCount": 0,
                "failedCount": 0,
            }]

        result = await run_community_pilot(
            Settings(
                brave_search_api_key="key",
                crawler_community_ingest_url="http://backend.test/community",
                crawler_backend_token="token",
            ),
            platform="all",
            discoverer=discoverer,
            crawler=crawler,
            uploader=uploader,
        )

        self.assertEqual(result.exit_code, 0)
        self.assertEqual(result.counts["blocked"], 1)
        self.assertEqual(result.counts["uploaded"], 1)
        self.assertEqual(uploaded_platforms, ["tieba"])
