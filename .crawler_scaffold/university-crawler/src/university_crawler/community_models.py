"""北京大学社区证据试点使用的边界模型。"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, HttpUrl

CommunityPlatform = Literal["zhihu", "tieba"]
CommunityDimension = Literal[
    "school",
    "major",
    "course",
    "employment",
    "dormitory",
    "cafeteria",
    "student_club",
]


class CommunityDiscoveryPlan(BaseModel):
    """首期范围写进模型，避免配置错误扩展到其他学校或平台。"""

    institution_code: Literal["peking-university"]
    institution_name: Literal["北京大学"]
    platforms: list[CommunityPlatform] = Field(min_length=1)
    dimensions: list[CommunityDimension] = Field(min_length=1)


class DiscoveredLink(BaseModel):
    platform: CommunityPlatform
    dimension: CommunityDimension
    url: HttpUrl
    title: str = Field(default="", max_length=500)
    query: str = Field(max_length=300)


class CommunityEvidenceCandidate(BaseModel):
    external_id: str = Field(min_length=1, max_length=191)
    platform: CommunityPlatform
    dimension: CommunityDimension
    url: HttpUrl
    title: str = Field(min_length=1, max_length=2_000)
    text: str = Field(min_length=1, max_length=100_000)
    discovered_at: datetime
    published_at: datetime | None = None
    engagement: dict[str, str | int | float | bool] = Field(default_factory=dict)
