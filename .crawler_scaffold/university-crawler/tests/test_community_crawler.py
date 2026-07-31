"""遇到访问控制或跨域跳转时必须返回阻断状态。"""

import unittest
from pathlib import Path

from university_crawler.community_crawler import crawl_discovered_link
from university_crawler.community_models import DiscoveredLink
from university_crawler.config import Settings

FIXTURES = Path(__file__).parent / "fixtures"


class CommunityCrawlerTest(unittest.IsolatedAsyncioTestCase):
    async def test_login_wall_is_blocked(self) -> None:
        async def loader(_url: str) -> tuple[str, str]:
            return (
                "https://www.zhihu.com/question/123",
                (FIXTURES / "login_wall.html").read_text(encoding="utf-8"),
            )

        result = await crawl_discovered_link(
            DiscoveredLink(
                platform="zhihu",
                dimension="course",
                url="https://www.zhihu.com/question/123",
                title="课程",
                query="test",
            ),
            Settings(),
            loader=loader,
        )

        self.assertEqual(result.status, "blocked_login")
        self.assertEqual(result.candidates, [])

    async def test_captcha_and_foreign_redirect_are_blocked(self) -> None:
        async def captcha_loader(_url: str) -> tuple[str, str]:
            return (
                "https://tieba.baidu.com/p/123",
                "<html><body>请完成验证码后继续访问</body></html>",
            )

        async def redirect_loader(_url: str) -> tuple[str, str]:
            return ("https://example.com/private", "<html>content</html>")

        link = DiscoveredLink(
            platform="tieba",
            dimension="school",
            url="https://tieba.baidu.com/p/123",
            title="学校",
            query="test",
        )
        captcha = await crawl_discovered_link(link, Settings(), loader=captcha_loader)
        redirect = await crawl_discovered_link(link, Settings(), loader=redirect_loader)

        self.assertEqual(captcha.status, "blocked_captcha")
        self.assertEqual(redirect.status, "blocked_redirect")
