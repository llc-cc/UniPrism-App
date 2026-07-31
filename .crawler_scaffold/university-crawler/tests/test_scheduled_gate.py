"""定时模式必须先通过总开关检查，手动测试则保持独立。"""

import unittest
from unittest.mock import AsyncMock, patch

from university_crawler.config import Settings
from university_crawler.main import run, run_community


class ScheduledGateTest(unittest.IsolatedAsyncioTestCase):
    async def test_disabled_schedule_exits_without_loading_or_crawling_sources(self) -> None:
        with (
            patch(
                "university_crawler.main.fetch_university_automation_enabled",
                new=AsyncMock(return_value=False),
            ),
            patch("university_crawler.main.load_sources") as load_sources,
            patch("university_crawler.main.crawl_source", new=AsyncMock()) as crawl_source,
        ):
            exit_code = await run(source_code=None, scheduled=True)

        self.assertEqual(exit_code, 0)
        load_sources.assert_not_called()
        crawl_source.assert_not_awaited()

    async def test_control_api_failure_fails_closed_before_crawling(self) -> None:
        with (
            patch(
                "university_crawler.main.fetch_university_automation_enabled",
                new=AsyncMock(side_effect=RuntimeError("backend unavailable")),
            ),
            patch("university_crawler.main.load_sources") as load_sources,
            patch("university_crawler.main.crawl_source", new=AsyncMock()) as crawl_source,
        ):
            exit_code = await run(source_code=None, scheduled=True)

        self.assertNotEqual(exit_code, 0)
        load_sources.assert_not_called()
        crawl_source.assert_not_awaited()

    async def test_manual_run_bypasses_schedule_gate(self) -> None:
        with (
            patch(
                "university_crawler.main.fetch_university_automation_enabled",
                new=AsyncMock(),
            ) as fetch_control,
            patch("university_crawler.main.load_sources", return_value=[]),
        ):
            exit_code = await run(source_code="peking-university-public-pages")

        self.assertEqual(exit_code, 0)
        fetch_control.assert_not_awaited()

    async def test_scheduled_community_agent_obeys_same_master_switch(self) -> None:
        with (
            patch(
                "university_crawler.main.fetch_university_automation_enabled",
                new=AsyncMock(return_value=False),
            ),
            patch(
                "university_crawler.main.run_community_pilot",
                new=AsyncMock(),
            ) as pilot,
        ):
            result = await run_community(
                Settings(),
                platform="all",
                discovery_mode="agent",
                dimension="all",
                scheduled=True,
            )

        self.assertEqual(result.exit_code, 0)
        self.assertEqual(result.state, "AUTOMATION_DISABLED")
        pilot.assert_not_awaited()
