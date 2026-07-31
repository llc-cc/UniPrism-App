"""社区试点编排在单个平台受阻时继续处理其他平台。"""

import unittest
from datetime import datetime, timezone

from university_crawler.community_discovery import DiscoveryNotConfigured
from university_crawler.community_models import (
    CommunityAgentTaskResult,
    CommunityEvidenceCandidate,
    DiscoveredLink,
)
from university_crawler.community_crawler import CommunityCrawlResult
from university_crawler.community_runner import run_community_pilot
from university_crawler.community_agent_skill import CommunityAgentSkill
from university_crawler.config import Settings


class CommunityRunnerTest(unittest.IsolatedAsyncioTestCase):
    async def test_discovery_not_configured_returns_code_four(self) -> None:
        async def discoverer(*_args, **_kwargs):
            raise DiscoveryNotConfigured("DISCOVERY_NOT_CONFIGURED")

        result = await run_community_pilot(
            Settings(),
            platform="all",
            discovery_mode="search_api",
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
            discovery_mode="search_api",
            discoverer=discoverer,
            crawler=crawler,
            uploader=uploader,
        )

        self.assertEqual(result.exit_code, 0)
        self.assertEqual(result.counts["blocked"], 1)
        self.assertEqual(result.counts["uploaded"], 1)
        self.assertEqual(uploaded_platforms, ["tieba"])

    async def test_agent_runs_seven_dimension_tasks_and_deduplicates_upload(self) -> None:
        tasks = []
        uploads = []

        async def agent_task_runner(task, _skill, _settings):
            tasks.append(task)
            candidate = CommunityEvidenceCandidate(
                external_id="shared-evidence",
                platform="zhihu",
                dimension=task.dimension,
                url="https://www.zhihu.com/question/123",
                title="北京大学公开体验",
                text="这是实际打开公开页面后提交的北京大学学习与校园体验内容。",
                discovered_at=datetime.now(timezone.utc),
            )
            return CommunityAgentTaskResult(
                task=task,
                status="completed",
                candidates=[candidate],
                steps=3,
                pages_visited=2,
            )

        async def uploader(candidates, **kwargs):
            uploads.append((candidates, kwargs))
            return [{
                "createdCount": len(candidates),
                "updatedCount": 0,
                "unchangedCount": 0,
                "rejectedCount": 0,
                "failedCount": 0,
            }]

        async def no_delay(_seconds):
            return None

        result = await run_community_pilot(
            Settings(
                community_agent_enabled=True,
                deepseek_api_key="test-key",
                crawler_community_ingest_url="http://backend.test/community",
                crawler_backend_token="token",
            ),
            platform="zhihu",
            discovery_mode="agent",
            agent_task_runner=agent_task_runner,
            skill_loader=lambda _path: CommunityAgentSkill(
                name="uniprism-university-community-crawler",
                version="test",
                body="仅访问公开内容。",
            ),
            uploader=uploader,
            task_delay=no_delay,
        )

        self.assertEqual(len(tasks), 7)
        self.assertEqual(result.counts["planned_tasks"], 7)
        self.assertEqual(result.counts["completed_tasks"], 7)
        self.assertEqual(result.counts["duplicates_removed"], 6)
        self.assertEqual(result.counts["uploaded"], 1)
        self.assertEqual(len(uploads), 1)
        self.assertEqual(
            uploads[0][1]["agent_metadata"]["skillVersion"],
            "test",
        )
