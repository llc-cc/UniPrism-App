"""部署资产必须启用受控 Agent，并继续服从管理端总开关。"""

from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parents[3]
CRAWLER_ROOT = Path(__file__).resolve().parents[1]
DEPLOY_ROOT = WORKSPACE_ROOT / "deploy" / "uniprism-community-evidence-pilot"


def test_environment_example_documents_agent_runtime() -> None:
    env_example = (CRAWLER_ROOT / ".env.example").read_text(encoding="utf-8")

    assert 'COMMUNITY_AGENT_ENABLED="true"' in env_example
    assert 'DEEPSEEK_API_KEY=""' in env_example
    assert 'COMMUNITY_AGENT_RUNTIME_DIR=' in env_example


def test_systemd_agent_obeys_master_switch_and_writable_runtime() -> None:
    service = (
        DEPLOY_ROOT / "systemd" / "uniprism-community-evidence.service"
    ).read_text(encoding="utf-8")

    assert "--discovery-mode agent" in service
    assert "--scheduled" in service
    assert "ReadWritePaths=/opt/uniprism-crawler/runtime" in service


def test_deploy_installs_agent_dependencies_without_printing_key() -> None:
    deploy = (DEPLOY_ROOT / "deploy.sh").read_text(encoding="utf-8")

    assert "pip install --no-cache-dir -e" in deploy
    assert "DEEPSEEK_API_KEY" in deploy
    assert "cat ${CRAWLER_APP}/.env" not in deploy
