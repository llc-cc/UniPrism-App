"""平台提取器只输出正文证据，不输出账号身份字段。"""

from pathlib import Path

from university_crawler.community_extractors import extract_public_evidence

FIXTURES = Path(__file__).parent / "fixtures"


def test_extracts_visible_zhihu_text_without_identity() -> None:
    candidates = extract_public_evidence(
        "zhihu",
        (FIXTURES / "zhihu_public_page.html").read_text(encoding="utf-8"),
        "https://www.zhihu.com/question/123",
        dimension="course",
    )

    assert len(candidates) == 2
    payload = [candidate.model_dump(mode="json") for candidate in candidates]
    assert all("username" not in item for item in payload)
    assert all("avatar" not in item for item in payload)
    assert "测试用户" not in " ".join(item["text"] for item in payload)


def test_extracts_visible_tieba_posts() -> None:
    candidates = extract_public_evidence(
        "tieba",
        (FIXTURES / "tieba_public_page.html").read_text(encoding="utf-8"),
        "https://tieba.baidu.com/p/123",
        dimension="dormitory",
    )

    assert len(candidates) == 2
    assert all(candidate.dimension == "dormitory" for candidate in candidates)
