"""运行时采集 Skill 必须可校验、可渲染，且任务范围不能被模型自行扩大。"""

from pathlib import Path

import pytest

from university_crawler.community_agent_skill import (
    CommunityAgentSkillNotConfigured,
    build_community_agent_tasks,
    load_community_agent_skill,
    render_community_agent_task,
)
from university_crawler.community_models import (
    CommunityAgentTask,
    CommunityDiscoveryPlan,
)


def _write_skill(path: Path) -> None:
    path.write_text(
        """---
name: uniprism-university-community-crawler
version: uniprism-community-v1
---

只采集实际访问过的公开高校社区内容。
""",
        encoding="utf-8",
    )


def test_builds_platform_dimension_tasks_in_stable_order() -> None:
    """防止任务遗漏维度，或因集合无序导致定时批次难以复现。"""

    plan = CommunityDiscoveryPlan(
        institution_code="peking-university",
        institution_name="北京大学",
        platforms=["zhihu", "tieba"],
        dimensions=[
            "school",
            "major",
            "course",
            "employment",
            "dormitory",
            "cafeteria",
            "student_club",
        ],
    )

    tasks = build_community_agent_tasks(plan)

    assert len(tasks) == 14
    assert (tasks[0].platform, tasks[0].dimension) == ("zhihu", "school")
    assert (tasks[-1].platform, tasks[-1].dimension) == (
        "tieba",
        "student_club",
    )


def test_missing_skill_fails_closed(tmp_path: Path) -> None:
    """Skill 缺失时不得让模型在没有边界的情况下自由浏览。"""

    with pytest.raises(CommunityAgentSkillNotConfigured):
        load_community_agent_skill(tmp_path / "SKILL.md")


def test_rejects_skill_with_wrong_name(tmp_path: Path) -> None:
    skill_path = tmp_path / "SKILL.md"
    skill_path.write_text(
        "---\nname: unrelated-browser-skill\n---\n\n任意浏览。",
        encoding="utf-8",
    )

    with pytest.raises(CommunityAgentSkillNotConfigured):
        load_community_agent_skill(skill_path)


def test_task_rendering_contains_scope_without_secrets(tmp_path: Path) -> None:
    """任务提示只能包含业务边界，不能把环境变量或密钥交给模型。"""

    skill_path = tmp_path / "SKILL.md"
    _write_skill(skill_path)
    skill = load_community_agent_skill(skill_path)

    text = render_community_agent_task(
        skill,
        CommunityAgentTask(
            institution_code="peking-university",
            institution_name="北京大学",
            platform="zhihu",
            dimension="course",
        ),
        max_candidates=30,
    )

    assert "北京大学" in text
    assert "知乎" in text
    assert "课程" in text
    assert "30" in text
    assert "DEEPSEEK_API_KEY" not in text
    assert "CRAWLER_BACKEND_TOKEN" not in text
