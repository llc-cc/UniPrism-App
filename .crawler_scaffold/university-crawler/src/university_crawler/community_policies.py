"""公开社区页面的静态策略门禁，不尝试绕过登录或访问控制。"""

from typing import Literal
from urllib.parse import urlparse

from pydantic import BaseModel

from university_crawler.community_models import CommunityPlatform

PolicyStatus = Literal[
    "allowed",
    "blocked_host",
    "blocked_path",
    "unsupported_platform",
]

PLATFORM_HOSTS: dict[CommunityPlatform, tuple[str, ...]] = {
    "zhihu": ("zhihu.com", "www.zhihu.com", "zhuanlan.zhihu.com"),
    "tieba": ("tieba.baidu.com",),
}

BLOCKED_PATH_PARTS = (
    "/signin",
    "/login",
    "/account/",
    "/captcha",
    "/oauth/",
)


class PolicyDecision(BaseModel):
    status: PolicyStatus
    reason: str = ""


def evaluate_public_url(url: str, platform: str) -> PolicyDecision:
    """仅允许 HTTPS 白名单页面；登录和验证码路径直接跳过。"""

    if platform not in PLATFORM_HOSTS:
        return PolicyDecision(
            status="unsupported_platform",
            reason="platform_not_in_pilot",
        )

    parsed = urlparse(url)
    if parsed.scheme.lower() != "https":
        return PolicyDecision(status="blocked_path", reason="https_required")

    hostname = (parsed.hostname or "").lower()
    allowed_hosts = PLATFORM_HOSTS[platform]  # type: ignore[index]
    if not any(
        hostname == allowed or hostname.endswith(f".{allowed}")
        for allowed in allowed_hosts
    ):
        return PolicyDecision(status="blocked_host", reason="host_not_allowed")

    lowered_path = parsed.path.lower()
    if any(part in lowered_path for part in BLOCKED_PATH_PARTS):
        return PolicyDecision(status="blocked_path", reason="access_control_path")

    return PolicyDecision(status="allowed")
