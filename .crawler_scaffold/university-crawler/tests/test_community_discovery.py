"""使用获准的搜索接口发现链接，不保存搜索结果原文。"""

import unittest

import httpx

from university_crawler.community_discovery import (
    DiscoveryNotConfigured,
    discover_public_links,
)
from university_crawler.community_models import CommunityDiscoveryPlan
from university_crawler.config import Settings


class CommunityDiscoveryTest(unittest.IsolatedAsyncioTestCase):
    async def test_discovery_uses_site_queries_and_deduplicates(self) -> None:
        requested_queries: list[str] = []

        async def handler(request: httpx.Request) -> httpx.Response:
            requested_queries.append(request.url.params["q"])
            host = (
                "www.zhihu.com"
                if "zhihu.com" in request.url.params["q"]
                else "tieba.baidu.com"
            )
            return httpx.Response(
                200,
                json={
                    "web": {
                        "results": [
                            {
                                "url": f"https://{host}/question/123"
                                if host == "www.zhihu.com"
                                else f"https://{host}/p/123",
                                "title": "北京大学课程体验",
                            },
                            {
                                "url": f"https://{host}/question/123"
                                if host == "www.zhihu.com"
                                else f"https://{host}/p/123",
                                "title": "重复链接",
                            },
                        ]
                    }
                },
            )

        links = await discover_public_links(
            CommunityDiscoveryPlan(
                institution_code="peking-university",
                institution_name="北京大学",
                platforms=["zhihu", "tieba"],
                dimensions=["course"],
            ),
            Settings(brave_search_api_key="search-key"),
            transport=httpx.MockTransport(handler),
        )

        self.assertEqual({link.platform for link in links}, {"zhihu", "tieba"})
        self.assertEqual(len({str(link.url) for link in links}), len(links))
        self.assertTrue(all(query.startswith("site:") for query in requested_queries))

    async def test_missing_search_key_fails_before_request(self) -> None:
        called = False

        async def handler(_request: httpx.Request) -> httpx.Response:
            nonlocal called
            called = True
            return httpx.Response(500)

        with self.assertRaises(DiscoveryNotConfigured):
            await discover_public_links(
                CommunityDiscoveryPlan(
                    institution_code="peking-university",
                    institution_name="北京大学",
                    platforms=["zhihu"],
                    dimensions=["school"],
                ),
                Settings(brave_search_api_key=""),
                transport=httpx.MockTransport(handler),
            )

        self.assertFalse(called)
