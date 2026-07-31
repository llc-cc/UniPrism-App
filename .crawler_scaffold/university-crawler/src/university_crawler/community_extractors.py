"""从已渲染公开 HTML 中提取正文，不读取隐藏接口或账号身份。"""

from datetime import datetime, timezone
from hashlib import sha256

from bs4 import BeautifulSoup

from university_crawler.community_models import (
    CommunityDimension,
    CommunityEvidenceCandidate,
    CommunityPlatform,
)

PLATFORM_SELECTORS: dict[CommunityPlatform, tuple[str, ...]] = {
    "zhihu": (
        "article .RichContent-inner",
        ".CommentItem .RichText",
        ".AnswerItem .RichContent-inner",
    ),
    "tieba": (".d_post_content",),
}


def _visible_text(node: object) -> str:
    get_text = getattr(node, "get_text")
    return " ".join(get_text(" ", strip=True).split())


def extract_public_evidence(
    platform: CommunityPlatform,
    html: str,
    page_url: str,
    *,
    dimension: CommunityDimension,
    limit: int = 100,
) -> list[CommunityEvidenceCandidate]:
    """只取平台公开页面已渲染的正文节点，作者区不会进入输出模型。"""

    soup = BeautifulSoup(html, "lxml")
    title = " ".join((soup.title.get_text(" ", strip=True) if soup.title else "").split())
    title = title or "公开社区内容"
    seen: set[str] = set()
    candidates: list[CommunityEvidenceCandidate] = []

    for selector in PLATFORM_SELECTORS[platform]:
        for node in soup.select(selector):
            text = _visible_text(node)
            if not text or text in seen:
                continue
            seen.add(text)
            external_id = sha256(
                f"{platform}\0{page_url}\0{text}".encode("utf-8")
            ).hexdigest()[:40]
            candidates.append(
                CommunityEvidenceCandidate(
                    external_id=external_id,
                    platform=platform,
                    dimension=dimension,
                    url=page_url,
                    title=title[:2_000],
                    text=text[:100_000],
                    discovered_at=datetime.now(timezone.utc),
                )
            )
            if len(candidates) >= limit:
                return candidates

    return candidates
