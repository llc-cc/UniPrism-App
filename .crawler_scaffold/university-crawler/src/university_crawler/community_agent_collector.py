"""接收 Agent 的结构化提交，并在进入清洗链路前执行确定性门禁。"""

import hashlib
import re
from datetime import datetime, timezone
from urllib.parse import urlsplit, urlunsplit

from pydantic import BaseModel, Field, HttpUrl

from university_crawler.community_models import (
    CommunityAgentTask,
    CommunityEvidenceCandidate,
)
from university_crawler.community_policies import evaluate_public_url

CONTACT_PATTERN = re.compile(
    r"(微信|weixin|wechat|qq|加我|联系我|手机号|电话|邮箱|二维码|公众号)",
    re.IGNORECASE,
)


class CommunityEvidenceSubmission(BaseModel):
    """Agent 工具允许提交的最小公开证据，不接收账号身份字段。"""

    url: HttpUrl
    title: str = Field(min_length=1, max_length=2_000)
    text: str = Field(min_length=1, max_length=100_000)
    published_at: datetime | None = None
    engagement: dict[str, str | int | float | bool] = Field(default_factory=dict)


def _canonical_url(url: str) -> str:
    parts = urlsplit(url)
    return urlunsplit((
        parts.scheme.lower(),
        parts.netloc.lower(),
        parts.path.rstrip("/") or "/",
        parts.query,
        "",
    ))


def _content_fingerprint(text: str) -> str:
    # 社区文本以中文为主，移除空白能覆盖复制时产生的无意义排版差异。
    normalized = re.sub(r"\s+", "", text).lower()
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


class CommunityAgentCollector:
    """将模型提交转换为固定学校、平台和维度的候选，拒绝越界内容。"""

    def __init__(self, *, task: CommunityAgentTask, limit: int) -> None:
        self.task = task
        self.limit = limit
        self.candidates: list[CommunityEvidenceCandidate] = []
        self._urls: set[str] = set()
        self._content_hashes: set[str] = set()

    def submit(self, submission: CommunityEvidenceSubmission) -> str:
        """返回简短状态供 Agent 调整动作，拒绝内容本身不进入日志。"""

        if len(self.candidates) >= self.limit:
            return "limit_reached"

        raw_url = str(submission.url)
        if evaluate_public_url(raw_url, self.task.platform).status != "allowed":
            return "rejected_platform"

        combined_text = f"{submission.title}\n{submission.text}"
        if (
            not any(name in combined_text for name in ("北京大学", "北大"))
            or CONTACT_PATTERN.search(combined_text)
        ):
            return "rejected_scope"

        canonical_url = _canonical_url(raw_url)
        content_hash = _content_fingerprint(submission.text)
        if canonical_url in self._urls or content_hash in self._content_hashes:
            return "duplicate"

        external_id = hashlib.sha256(
            f"{self.task.platform}:{canonical_url}:{content_hash}".encode("utf-8")
        ).hexdigest()[:40]
        self.candidates.append(CommunityEvidenceCandidate(
            external_id=external_id,
            platform=self.task.platform,
            dimension=self.task.dimension,
            url=canonical_url,
            title=submission.title.strip(),
            text=submission.text.strip(),
            discovered_at=datetime.now(timezone.utc),
            published_at=submission.published_at,
            engagement=submission.engagement,
        ))
        self._urls.add(canonical_url)
        self._content_hashes.add(content_hash)
        return "accepted"
