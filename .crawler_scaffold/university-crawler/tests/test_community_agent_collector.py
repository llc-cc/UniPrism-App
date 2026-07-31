"""Agent 提交内容必须经过确定性门禁，不能依赖模型自我声明合规。"""

from university_crawler.community_agent_collector import (
    CommunityAgentCollector,
    CommunityEvidenceSubmission,
)
from university_crawler.community_models import CommunityAgentTask


def _task() -> CommunityAgentTask:
    return CommunityAgentTask(
        institution_code="peking-university",
        institution_name="北京大学",
        platform="zhihu",
        dimension="course",
    )


def _submission(
    *,
    url: str = "https://www.zhihu.com/question/123",
    title: str = "北京大学课程体验",
    text: str = "我在北京大学选课时发现，通识课和专业课需要提前规划。",
) -> CommunityEvidenceSubmission:
    return CommunityEvidenceSubmission(
        url=url,
        title=title,
        text=text,
    )


def test_accepts_matching_public_evidence() -> None:
    """若移除学校与平台校验，这个正常路径仍应生成完整候选。"""

    collector = CommunityAgentCollector(task=_task(), limit=2)

    result = collector.submit(_submission())

    assert result == "accepted"
    assert len(collector.candidates) == 1
    assert collector.candidates[0].platform == "zhihu"
    assert collector.candidates[0].dimension == "course"


def test_rejects_wrong_platform_url() -> None:
    collector = CommunityAgentCollector(task=_task(), limit=2)

    assert collector.submit(_submission(
        url="https://tieba.baidu.com/p/123",
    )) == "rejected_platform"
    assert collector.submit(_submission(
        url="https://example.com/post/123",
    )) == "rejected_platform"


def test_rejects_other_university_and_contact_details() -> None:
    """其他学校或引流信息不得依靠后端二次清洗才被发现。"""

    collector = CommunityAgentCollector(task=_task(), limit=2)

    result = collector.submit(_submission(
        title="其他学校课程咨询",
        text="清华大学课程不错，加微信 abc123 了解详情。",
    ))

    assert result == "rejected_scope"
    assert collector.candidates == []


def test_rejects_after_candidate_limit() -> None:
    collector = CommunityAgentCollector(task=_task(), limit=1)

    assert collector.submit(_submission()) == "accepted"
    assert collector.submit(_submission(
        url="https://www.zhihu.com/question/456",
    )) == "limit_reached"
    assert len(collector.candidates) == 1


def test_deduplicates_canonical_url_and_normalized_text() -> None:
    """同 URL 或仅空白不同的正文只能进入一次，避免浪费后端 AI 分析。"""

    collector = CommunityAgentCollector(task=_task(), limit=5)

    assert collector.submit(_submission()) == "accepted"
    assert collector.submit(_submission(
        url="https://www.zhihu.com/question/123#answer-1",
        text="北京大学另一段课程描述。",
    )) == "duplicate"
    assert collector.submit(_submission(
        url="https://www.zhihu.com/question/789",
        text=" 我在北京大学选课时发现， 通识课和专业课需要提前规划。 ",
    )) == "duplicate"
    assert len(collector.candidates) == 1
