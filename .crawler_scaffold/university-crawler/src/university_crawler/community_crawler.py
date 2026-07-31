"""使用匿名 Playwright 上下文读取公开页面；访问受限时直接停止。"""

from collections.abc import Awaitable, Callable
from time import monotonic
from typing import Literal

from playwright.async_api import async_playwright
from pydantic import BaseModel, HttpUrl

from university_crawler.community_extractors import extract_public_evidence
from university_crawler.community_models import (
    CommunityEvidenceCandidate,
    DiscoveredLink,
)
from university_crawler.community_policies import evaluate_public_url
from university_crawler.config import Settings

CommunityCrawlStatus = Literal[
    "completed",
    "empty",
    "blocked_login",
    "blocked_captcha",
    "blocked_redirect",
    "failed",
]

PageLoader = Callable[[str], Awaitable[tuple[str, str]]]

LOGIN_MARKERS = (
    "登录后继续",
    "请登录后",
    "登录后查看",
    "sign in to continue",
)
CAPTCHA_MARKERS = ("验证码", "安全验证", "captcha")


class CommunityCrawlResult(BaseModel):
    status: CommunityCrawlStatus
    candidates: list[CommunityEvidenceCandidate]
    block_reason: str | None = None
    final_url: HttpUrl
    elapsed_ms: int


async def _load_with_playwright(
    url: str,
    settings: Settings,
) -> tuple[str, str]:
    executable = settings.crawler_browser_executable_path.strip() or None
    contact = settings.crawler_contact.strip()
    user_agent = f"UniPrismPublicCrawler/1.0 (+{contact})"
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(
            headless=settings.crawler_headless,
            executable_path=executable,
        )
        # 每个页面使用无持久化上下文，避免带入账号 Cookie 或本地身份。
        context = await browser.new_context(user_agent=user_agent)
        try:
            page = await context.new_page()
            await page.goto(url, wait_until="domcontentloaded", timeout=20_000)
            await page.wait_for_timeout(5_000)
            return page.url, await page.content()
        finally:
            await context.close()
            await browser.close()


async def crawl_discovered_link(
    link: DiscoveredLink,
    settings: Settings,
    *,
    loader: PageLoader | None = None,
) -> CommunityCrawlResult:
    started = monotonic()
    load_page = loader or (lambda url: _load_with_playwright(url, settings))
    try:
        final_url, html = await load_page(str(link.url))
    except Exception:
        return CommunityCrawlResult(
            status="failed",
            candidates=[],
            block_reason="navigation_failed",
            final_url=link.url,
            elapsed_ms=int((monotonic() - started) * 1_000),
        )

    final_policy = evaluate_public_url(final_url, link.platform)
    if final_policy.status != "allowed":
        return CommunityCrawlResult(
            status="blocked_redirect",
            candidates=[],
            block_reason=final_policy.reason,
            final_url=final_url,
            elapsed_ms=int((monotonic() - started) * 1_000),
        )

    lowered = html.lower()
    if any(marker.lower() in lowered for marker in LOGIN_MARKERS):
        return CommunityCrawlResult(
            status="blocked_login",
            candidates=[],
            block_reason="login_wall",
            final_url=final_url,
            elapsed_ms=int((monotonic() - started) * 1_000),
        )
    if any(marker.lower() in lowered for marker in CAPTCHA_MARKERS):
        return CommunityCrawlResult(
            status="blocked_captcha",
            candidates=[],
            block_reason="captcha",
            final_url=final_url,
            elapsed_ms=int((monotonic() - started) * 1_000),
        )

    candidates = extract_public_evidence(
        link.platform,
        html,
        final_url,
        dimension=link.dimension,
        limit=100,
    )
    return CommunityCrawlResult(
        status="completed" if candidates else "empty",
        candidates=candidates,
        final_url=final_url,
        elapsed_ms=int((monotonic() - started) * 1_000),
    )
