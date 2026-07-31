"""Configuration models for approved university public sources."""

from pathlib import Path

import yaml
from pydantic import BaseModel, Field, HttpUrl
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Environment-owned crawler settings; secrets never live in source files."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    crawler_backend_ingest_url: str = ""
    crawler_backend_control_url: str = ""
    crawler_backend_token: str = ""
    crawler_headless: bool = True
    crawler_browser_executable_path: str = ""
    crawler_request_delay_seconds: float = 1.5
    crawler_upload_batch_size: int = Field(default=25, ge=1, le=100)
    brave_search_api_key: str = ""
    community_discovery_max_results: int = Field(default=140, ge=1, le=500)
    community_request_delay_seconds: float = Field(default=3.0, ge=1.0, le=30.0)
    crawler_community_ingest_url: str = ""
    crawler_contact: str = "crawler-contact-not-configured"
    community_agent_enabled: bool = False
    community_agent_model: str = ""
    community_agent_max_steps: int = Field(default=40, ge=5, le=80)
    community_agent_max_candidates: int = Field(default=30, ge=1, le=100)
    community_agent_task_delay_seconds: float = Field(
        default=5.0,
        ge=0.0,
        le=60.0,
    )
    community_agent_browser_headless: bool = True
    community_agent_skill_path: str = (
        "skills/uniprism-university-community-crawler/SKILL.md"
    )
    deepseek_api_key: str = ""
    deepseek_base_url: str = ""
    deepseek_dialogue_model: str = "deepseek-chat"


class SeedPage(BaseModel):
    """One explicitly approved public page and its business category."""

    url: HttpUrl
    category: str = Field(pattern=r"^[a-z_]{3,64}$")
    follow_path_prefixes: list[str] = Field(default_factory=list)
    max_pages: int = Field(default=1, ge=1, le=500)


class SourceConfig(BaseModel):
    """One source is deliberately bounded by hosts, pages and content types."""

    code: str = Field(pattern=r"^[a-z0-9-]{3,64}$")
    display_name: str = Field(min_length=2, max_length=120)
    enabled: bool = False
    allowed_hosts: list[str] = Field(min_length=1)
    seed_pages: list[SeedPage] = Field(min_length=1)
    crawl_interval_hours: int = Field(default=24, ge=1, le=24 * 30)


def load_sources(path: Path) -> list[SourceConfig]:
    """Loads explicit source allowlist; an absent file means crawl nothing."""

    if not path.exists():
        return []
    payload = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    return [SourceConfig.model_validate(item) for item in payload.get("sources", [])]
