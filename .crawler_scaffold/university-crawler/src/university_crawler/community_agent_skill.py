"""加载并渲染 UniPrism 运行时浏览器 Agent 使用的受控 Skill。"""

from pathlib import Path
from urllib.parse import quote_plus

import yaml
from pydantic import BaseModel, Field

from university_crawler.community_models import (
    CommunityAgentTask,
    CommunityDiscoveryPlan,
)

SKILL_NAME = "uniprism-university-community-crawler"

PLATFORM_NAMES = {
    "zhihu": "知乎",
    "tieba": "百度贴吧",
}

DIMENSION_NAMES = {
    "school": "学校整体体验",
    "major": "专业",
    "course": "课程",
    "employment": "就业",
    "dormitory": "宿舍",
    "cafeteria": "食堂",
    "student_club": "社团",
}

DIMENSION_QUERY_TERMS = {
    "school": "校园体验 学习氛围",
    "major": "专业选择 培养方向",
    "course": "课程 选课 学习压力",
    "employment": "就业 实习 升学",
    "dormitory": "宿舍 住宿 校区",
    "cafeteria": "食堂 餐饮",
    "student_club": "社团 学生活动",
}


class CommunityAgentSkillNotConfigured(RuntimeError):
    """Skill 不可用时中止任务，避免模型脱离业务边界自由浏览。"""


class CommunityAgentSkill(BaseModel):
    """已通过前置元数据和正文校验的运行时 Skill。"""

    name: str
    version: str = Field(min_length=1, max_length=120)
    body: str = Field(min_length=1)


def load_community_agent_skill(path: Path) -> CommunityAgentSkill:
    """读取 YAML 前置元数据；任何歧义都按未配置处理。"""

    if not path.is_file():
        raise CommunityAgentSkillNotConfigured("AGENT_SKILL_NOT_CONFIGURED")

    raw_text = path.read_text(encoding="utf-8").strip()
    if not raw_text.startswith("---\n"):
        raise CommunityAgentSkillNotConfigured("AGENT_SKILL_NOT_CONFIGURED")

    try:
        front_matter, body = raw_text[4:].split("\n---\n", maxsplit=1)
        metadata = yaml.safe_load(front_matter) or {}
    except (ValueError, yaml.YAMLError) as error:
        raise CommunityAgentSkillNotConfigured(
            "AGENT_SKILL_NOT_CONFIGURED"
        ) from error

    if metadata.get("name") != SKILL_NAME or not body.strip():
        raise CommunityAgentSkillNotConfigured("AGENT_SKILL_NOT_CONFIGURED")

    try:
        return CommunityAgentSkill(
            name=metadata["name"],
            version=str(metadata.get("version", "")).strip(),
            body=body.strip(),
        )
    except (KeyError, ValueError) as error:
        raise CommunityAgentSkillNotConfigured(
            "AGENT_SKILL_NOT_CONFIGURED"
        ) from error


def build_community_agent_tasks(
    plan: CommunityDiscoveryPlan,
) -> list[CommunityAgentTask]:
    """保持配置顺序生成任务，使定时批次可复现并便于对照日志。"""

    return [
        CommunityAgentTask(
            institution_code=plan.institution_code,
            institution_name=plan.institution_name,
            platform=platform,
            dimension=dimension,
        )
        for platform in plan.platforms
        for dimension in plan.dimensions
    ]


def render_community_agent_task(
    skill: CommunityAgentSkill,
    task: CommunityAgentTask,
    *,
    max_candidates: int,
) -> str:
    """只渲染公开业务参数，不读取或拼接任何环境密钥。"""

    query = f"{task.institution_name} {DIMENSION_QUERY_TERMS[task.dimension]}"
    if task.platform == "zhihu":
        start_url = (
            "https://www.zhihu.com/search?type=content&q="
            f"{quote_plus(query)}"
        )
    else:
        # 贴吧首期从学校吧公开列表进入，再由 Agent 在站内定位当前维度。
        start_url = (
            "https://tieba.baidu.com/f?ie=utf-8&kw="
            f"{quote_plus(task.institution_name)}"
        )

    return "\n".join([
        f"执行 Skill：{skill.name}（{skill.version}）。",
        f"学校：{task.institution_name}（{task.institution_code}）。",
        f"平台：{PLATFORM_NAMES[task.platform]}（{task.platform}）。",
        f"维度：{DIMENSION_NAMES[task.dimension]}（{task.dimension}）。",
        f"起始公开搜索页：{start_url}",
        f"本任务最多提交 {max_candidates} 条真实公开证据。",
        "必须实际打开来源页面后，调用 submit_community_evidence 提交。",
        "达到候选上限或触发 Skill 停止条件时结束任务。",
    ])
