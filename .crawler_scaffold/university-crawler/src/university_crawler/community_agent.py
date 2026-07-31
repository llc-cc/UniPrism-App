"""使用 DeepSeek 驱动 Browser Use，并将其限制在 UniPrism 结构化提交工具内。"""

from collections.abc import Callable
import os
from pathlib import Path
from typing import Protocol

from pydantic import BaseModel, Field

from university_crawler.community_agent_collector import CommunityAgentCollector
from university_crawler.community_agent_skill import (
    CommunityAgentSkill,
    render_community_agent_task,
)
from university_crawler.community_models import (
    CommunityAgentTask,
    CommunityAgentTaskResult,
)
from university_crawler.community_policies import PLATFORM_HOSTS
from university_crawler.config import Settings


class CommunityAgentNotConfigured(RuntimeError):
    """模型或运行开关缺失时阻止浏览器启动。"""


class AgentRuntimeHistory(BaseModel):
    """隔离 Browser Use 历史结构，避免业务编排依赖第三方内部对象。"""

    steps: int = Field(default=0, ge=0)
    urls: list[str] = Field(default_factory=list)
    errors: list[str] = Field(default_factory=list)
    successful: bool = False
    final_result: str = ""


class CommunityAgentRuntime(Protocol):
    async def run(
        self,
        task_text: str,
        *,
        max_steps: int,
    ) -> AgentRuntimeHistory: ...

    async def close(self) -> None: ...


RuntimeFactory = Callable[
    [CommunityAgentTask, CommunityAgentCollector, CommunityAgentSkill, Settings],
    CommunityAgentRuntime,
]


def _classify_status(history: AgentRuntimeHistory) -> tuple[str, str]:
    combined = "\n".join([*history.errors, history.final_result]).lower()
    if any(token in combined for token in ("captcha", "验证码")):
        return "blocked_captcha", "captcha"
    if any(token in combined for token in ("login", "登录", "signin")):
        return "blocked_login", "login_wall"
    if any(token in combined for token in (
        "403",
        "429",
        "access denied",
        "访问拒绝",
    )):
        return "blocked_access", "access_denied"
    if history.successful:
        return "completed", ""
    return "failed", "agent_failed"


def _configure_browser_use_environment(settings: Settings) -> None:
    """把第三方运行文件固定到采集器目录，避免写入系统盘或用户主目录。"""

    runtime_dir = Path(
        settings.community_agent_runtime_dir.strip() or ".runtime/browser-use"
    ).resolve()
    os.environ.setdefault("BROWSER_USE_CONFIG_DIR", str(runtime_dir))


class BrowserUseRuntime:
    """生产运行时延迟导入 Browser Use，单元测试无需启动真实浏览器。"""

    def __init__(
        self,
        task: CommunityAgentTask,
        collector: CommunityAgentCollector,
        skill: CommunityAgentSkill,
        settings: Settings,
    ) -> None:
        _configure_browser_use_environment(settings)
        from browser_use import Agent, Browser, Tools
        from browser_use.llm import ChatDeepSeek

        tools = Tools()

        @tools.action(
            "提交一条已实际访问、符合当前学校和维度的公开社区证据",
            param_model=collector_submission_model(),
        )
        def submit_community_evidence(params):
            return collector.submit(params)

        model_name = (
            settings.community_agent_model.strip()
            or settings.deepseek_dialogue_model.strip()
            or "deepseek-chat"
        )
        llm = ChatDeepSeek(
            model=model_name,
            api_key=settings.deepseek_api_key,
            base_url=(
                settings.deepseek_base_url.strip()
                or "https://api.deepseek.com/v1"
            ),
            temperature=0.0,
        )
        browser_options = {
            "headless": settings.community_agent_browser_headless,
            "allowed_domains": list(PLATFORM_HOSTS[task.platform]),
            "keep_alive": False,
            # 首期遇到验证码即停止并记录阻断，不启用第三方解码或绕过能力。
            "captcha_solver": False,
        }
        if settings.crawler_browser_executable_path.strip():
            browser_options["executable_path"] = (
                settings.crawler_browser_executable_path.strip()
            )
        self._browser = Browser(**browser_options)
        self._agent_class = Agent
        self._llm = llm
        self._tools = tools
        self._skill = skill

    async def run(
        self,
        task_text: str,
        *,
        max_steps: int,
    ) -> AgentRuntimeHistory:
        agent = self._agent_class(
            task=task_text,
            llm=self._llm,
            browser=self._browser,
            tools=self._tools,
            extend_system_message=self._skill.body,
            use_vision=False,
            max_failures=3,
            calculate_cost=True,
        )
        history = await agent.run(max_steps=max_steps)
        return AgentRuntimeHistory(
            steps=history.number_of_steps(),
            urls=[str(url) for url in history.urls() if url],
            errors=[str(error) for error in history.errors() if error],
            successful=history.is_successful() is True,
            final_result=str(history.final_result() or ""),
        )

    async def close(self) -> None:
        # kill 会同时清理 Chromium 子进程，避免 systemd 下次运行残留会话。
        await self._browser.kill()


def collector_submission_model():
    """局部导入避免装配模块产生循环依赖。"""

    from university_crawler.community_agent_collector import (
        CommunityEvidenceSubmission,
    )

    return CommunityEvidenceSubmission


async def run_community_agent_task(
    task: CommunityAgentTask,
    skill: CommunityAgentSkill,
    settings: Settings,
    *,
    runtime_factory: RuntimeFactory = BrowserUseRuntime,
) -> CommunityAgentTaskResult:
    """执行单任务且始终关闭浏览器；状态分类不暴露原始错误正文。"""

    if not settings.community_agent_enabled:
        raise CommunityAgentNotConfigured("AGENT_DISABLED")
    if not settings.deepseek_api_key.strip():
        raise CommunityAgentNotConfigured("DEEPSEEK_API_KEY_NOT_CONFIGURED")

    collector = CommunityAgentCollector(
        task=task,
        limit=settings.community_agent_max_candidates,
    )
    task_text = render_community_agent_task(
        skill,
        task,
        max_candidates=settings.community_agent_max_candidates,
    )
    runtime = runtime_factory(task, collector, skill, settings)
    try:
        history = await runtime.run(
            task_text,
            max_steps=settings.community_agent_max_steps,
        )
    finally:
        await runtime.close()

    status, block_reason = _classify_status(history)
    return CommunityAgentTaskResult(
        task=task,
        status=status,
        candidates=collector.candidates,
        steps=history.steps,
        pages_visited=len({
            url for url in history.urls if url.startswith(("http://", "https://"))
        }),
        block_reason=block_reason,
    )
