"""社区公开链接必须先经过平台域名和路径白名单检查。"""

from university_crawler.community_policies import evaluate_public_url


def test_allows_only_https_public_platform_pages() -> None:
    assert evaluate_public_url(
        "https://www.zhihu.com/question/123", "zhihu"
    ).status == "allowed"
    assert evaluate_public_url(
        "https://tieba.baidu.com/p/123", "tieba"
    ).status == "allowed"
    assert evaluate_public_url(
        "http://www.zhihu.com/question/123", "zhihu"
    ).status == "blocked_path"


def test_rejects_foreign_hosts_login_and_unsupported_platforms() -> None:
    assert evaluate_public_url(
        "https://example.com/question/123", "zhihu"
    ).status == "blocked_host"
    assert evaluate_public_url(
        "https://www.zhihu.com/signin", "zhihu"
    ).status == "blocked_path"
    assert evaluate_public_url(
        "https://www.zhihu.com/question/123", "xiaohongshu"
    ).status == "unsupported_platform"
