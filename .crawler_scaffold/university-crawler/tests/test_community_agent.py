"""Browser Use 属于外部运行时；本测试验证 UniPrism 自己的生命周期和状态契约。"""

from pathlib import Path
import os
import unittest

from university_crawler.community_agent import (
    AgentRuntimeHistory,
    CommunityAgentNotConfigured,
    _configure_browser_use_environment,
    run_community_agent_task,
)
from university_crawler.community_agent_collector import (
    CommunityEvidenceSubmission,
)
from university_crawler.community_agent_skill import (
    load_community_agent_skill,
)
from university_crawler.community_models import CommunityAgentTask
from university_crawler.config import Settings


def _task() -> CommunityAgentTask:
    return CommunityAgentTask(
        institution_code="peking-university",
        institution_name="北京大学",
        platform="zhihu",
        dimension="course",
    )


def _skill(tmp_path: Path):
    path = tmp_path / "SKILL.md"
    path.write_text(
        """---
name: uniprism-university-community-crawler
version: uniprism-community-v1
---

只提交实际访问过的公开内容。
""",
        encoding="utf-8",
    )
    return load_community_agent_skill(path)


class FakeRuntime:
    """只替代外部模型/浏览器，候选门禁仍使用真实生产实现。"""

    def __init__(
        self,
        *,
        collector,
        history: AgentRuntimeHistory,
        submissions: list[CommunityEvidenceSubmission] | None = None,
    ) -> None:
        self.collector = collector
        self.history = history
        self.submissions = submissions or []
        self.closed = False
        self.received_max_steps = 0

    async def run(self, _task_text: str, *, max_steps: int) -> AgentRuntimeHistory:
        self.received_max_steps = max_steps
        for submission in self.submissions:
            self.collector.submit(submission)
        return self.history

    async def close(self) -> None:
        self.closed = True


class CommunityAgentTest(unittest.IsolatedAsyncioTestCase):
    def test_browser_use_runtime_directory_is_configurable(self) -> None:
        runtime_dir = Path(self._tmp_dir.name) / "browser-use"
        previous = os.environ.pop("BROWSER_USE_CONFIG_DIR", None)
        self.addCleanup(self._restore_browser_use_config_dir, previous)

        _configure_browser_use_environment(Settings(
            community_agent_runtime_dir=str(runtime_dir),
        ))

        self.assertEqual(
            os.environ["BROWSER_USE_CONFIG_DIR"],
            str(runtime_dir.resolve()),
        )

    async def test_runs_agent_and_always_closes_browser(self) -> None:
        created: list[FakeRuntime] = []

        def runtime_factory(_task, collector, _skill, _settings):
            runtime = FakeRuntime(
                collector=collector,
                submissions=[CommunityEvidenceSubmission(
                    url="https://www.zhihu.com/question/123",
                    title="北京大学课程体验",
                    text="我在北京大学选课时发现，专业课需要提前做好规划。",
                )],
                history=AgentRuntimeHistory(
                    steps=3,
                    urls=[
                        "https://www.zhihu.com/search?q=北京大学课程",
                        "https://www.zhihu.com/question/123",
                    ],
                    errors=[],
                    successful=True,
                    final_result="completed",
                ),
            )
            created.append(runtime)
            return runtime

        result = await run_community_agent_task(
            _task(),
            _skill(Path(self._tmp_dir.name)),
            Settings(
                community_agent_enabled=True,
                deepseek_api_key="test-key",
                community_agent_max_steps=12,
            ),
            runtime_factory=runtime_factory,
        )

        self.assertEqual(result.status, "completed")
        self.assertEqual(result.steps, 3)
        self.assertEqual(result.pages_visited, 2)
        self.assertEqual(len(result.candidates), 1)
        self.assertEqual(created[0].received_max_steps, 12)
        self.assertTrue(created[0].closed)

    async def test_missing_deepseek_key_does_not_start_runtime(self) -> None:
        called = False

        def runtime_factory(*_args):
            nonlocal called
            called = True
            raise AssertionError("runtime must not start")

        with self.assertRaises(CommunityAgentNotConfigured):
            await run_community_agent_task(
                _task(),
                _skill(Path(self._tmp_dir.name)),
                Settings(
                    community_agent_enabled=True,
                    deepseek_api_key="",
                ),
                runtime_factory=runtime_factory,
            )

        self.assertFalse(called)

    async def test_classifies_blocking_reasons_and_closes_runtime(self) -> None:
        cases = [
            ("页面要求登录后继续", "blocked_login"),
            ("出现 CAPTCHA 验证码", "blocked_captcha"),
            ("HTTP 403 access denied", "blocked_access"),
        ]

        for error_text, expected_status in cases:
            created: list[FakeRuntime] = []

            def runtime_factory(_task, collector, _skill, _settings):
                runtime = FakeRuntime(
                    collector=collector,
                    history=AgentRuntimeHistory(
                        steps=2,
                        urls=["https://www.zhihu.com/search?q=北京大学"],
                        errors=[error_text],
                        successful=False,
                        final_result=error_text,
                    ),
                )
                created.append(runtime)
                return runtime

            result = await run_community_agent_task(
                _task(),
                _skill(Path(self._tmp_dir.name)),
                Settings(
                    community_agent_enabled=True,
                    deepseek_api_key="test-key",
                ),
                runtime_factory=runtime_factory,
            )

            self.assertEqual(result.status, expected_status)
            self.assertTrue(created[0].closed)

    def setUp(self) -> None:
        from tempfile import TemporaryDirectory

        self._tmp_dir = TemporaryDirectory()

    def tearDown(self) -> None:
        self._tmp_dir.cleanup()

    @staticmethod
    def _restore_browser_use_config_dir(previous: str | None) -> None:
        if previous is None:
            os.environ.pop("BROWSER_USE_CONFIG_DIR", None)
            return
        os.environ["BROWSER_USE_CONFIG_DIR"] = previous
