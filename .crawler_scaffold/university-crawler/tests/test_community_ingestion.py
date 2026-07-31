"""社区证据上传按 50 条封顶，并区分可重试与不可重试错误。"""

import json
import unittest
from datetime import datetime, timezone

import httpx

from university_crawler.community_ingestion import upload_community_evidence
from university_crawler.community_models import CommunityEvidenceCandidate
from university_crawler.config import Settings


def candidate(index: int) -> CommunityEvidenceCandidate:
    return CommunityEvidenceCandidate(
        external_id=f"evidence-{index}",
        platform="zhihu",
        dimension="course",
        url=f"https://www.zhihu.com/question/{index}",
        title="北京大学课程",
        text=f"这是用于验证批量上传的公开课程体验内容 {index}",
        discovered_at=datetime.now(timezone.utc),
    )


class CommunityIngestionTest(unittest.IsolatedAsyncioTestCase):
    async def test_batches_at_fifty_and_retries_5xx(self) -> None:
        batch_sizes: list[int] = []
        calls = 0

        async def handler(request: httpx.Request) -> httpx.Response:
            nonlocal calls
            calls += 1
            body = json.loads(request.content)
            batch_sizes.append(len(body["documents"]))
            if calls == 1:
                return httpx.Response(503, text="temporary")
            return httpx.Response(
                200,
                json={
                    "ok": True,
                    "data": {
                        "createdCount": len(body["documents"]),
                        "updatedCount": 0,
                        "unchangedCount": 0,
                        "rejectedCount": 0,
                        "failedCount": 0,
                    },
                },
            )

        results = await upload_community_evidence(
            [candidate(index) for index in range(51)],
            platform="zhihu",
            run_id="pilot-run-0001",
            query="北京大学课程",
            settings=Settings(
                crawler_community_ingest_url="http://backend.test/community",
                crawler_backend_token="token",
            ),
            transport=httpx.MockTransport(handler),
            retry_delay=lambda _seconds: _completed_wait(),
        )

        self.assertEqual(batch_sizes, [50, 50, 1])
        self.assertEqual(sum(item["createdCount"] for item in results), 51)

    async def test_authentication_failure_is_not_retried(self) -> None:
        calls = 0

        async def handler(_request: httpx.Request) -> httpx.Response:
            nonlocal calls
            calls += 1
            return httpx.Response(401, text="unauthorized")

        with self.assertRaises(RuntimeError):
            await upload_community_evidence(
                [candidate(1)],
                platform="zhihu",
                run_id="pilot-run-0002",
                query="北京大学课程",
                settings=Settings(
                    crawler_community_ingest_url="http://backend.test/community",
                    crawler_backend_token="token",
                ),
                transport=httpx.MockTransport(handler),
            )

        self.assertEqual(calls, 1)

    async def test_agent_metadata_is_forwarded_to_backend(self) -> None:
        received_metadata = None

        async def handler(request: httpx.Request) -> httpx.Response:
            nonlocal received_metadata
            received_metadata = json.loads(request.content)["agentMetadata"]
            return httpx.Response(
                200,
                json={
                    "ok": True,
                    "data": {
                        "createdCount": 1,
                        "updatedCount": 0,
                        "unchangedCount": 0,
                        "rejectedCount": 0,
                        "failedCount": 0,
                    },
                },
            )

        await upload_community_evidence(
            [candidate(1)],
            platform="zhihu",
            run_id="agent-run-0001",
            query="北京大学课程",
            agent_metadata={
                "mode": "agent",
                "skillVersion": "uniprism-community-v1",
                "steps": 12,
            },
            settings=Settings(
                crawler_community_ingest_url="http://backend.test/community",
                crawler_backend_token="token",
            ),
            transport=httpx.MockTransport(handler),
        )

        self.assertEqual(received_metadata["mode"], "agent")
        self.assertEqual(received_metadata["steps"], 12)


async def _completed_wait() -> None:
    return None
