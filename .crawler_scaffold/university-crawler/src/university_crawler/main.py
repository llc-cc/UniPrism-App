"""CLI entry point for streaming direct-to-cloud university source crawling."""

import argparse
import asyncio
from pathlib import Path
from typing import Any

from university_crawler.automation import fetch_university_automation_enabled
from university_crawler.config import Settings, load_sources
from university_crawler.community_runner import run_community_pilot
from university_crawler.crawler import crawl_source
from university_crawler.ingestion import upload_documents
from university_crawler.models import CrawledDocument


async def run(source_code: str | None, scheduled: bool = False) -> int:
    """Crawls enabled sources and uploads each bounded batch without disk output."""

    settings = Settings()
    if scheduled:
        try:
            automation_enabled = await fetch_university_automation_enabled(settings)
        except Exception:
            # 定时任务无法确认开关状态时必须保持关闭，避免后台失联却继续采集。
            print("无法确认高校自动采集开关，本次定时任务已安全跳过。", flush=True)
            return 3
        if not automation_enabled:
            print("高校自动采集总开关已关闭，本次定时任务已跳过。", flush=True)
            return 0

    sources = [source for source in load_sources(Path("sources.yaml")) if source.enabled]
    if source_code:
        sources = [source for source in sources if source.code == source_code]
    if not sources:
        print("没有启用的来源。请先在 sources.yaml 配置并确认公开访问策略。")
        return 0
    if not settings.crawler_backend_ingest_url.strip() or not settings.crawler_backend_token.strip():
        print("缺少云端入库配置：请设置 CRAWLER_BACKEND_INGEST_URL 和 CRAWLER_BACKEND_TOKEN。")
        return 2

    for source in sources:
        pending: list[CrawledDocument] = []
        uploaded_results: list[dict[str, Any]] = []
        crawled_count = 0

        async def flush() -> None:
            """Uploads only the current in-memory batch, then releases it."""

            nonlocal pending
            if not pending:
                return
            result = await upload_documents(source, pending, settings)
            uploaded_results.extend(result)
            uploaded_count = sum(
                entry.get("createdCount", 0)
                + entry.get("updatedCount", 0)
                + entry.get("unchangedCount", 0)
                for entry in result
            )
            print(f"{source.code}: 已直传云数据库 {uploaded_count} 条。", flush=True)
            pending = []

        async def on_document(document: CrawledDocument) -> None:
            """Accumulates no more than one configured cloud-upload batch."""

            nonlocal crawled_count
            crawled_count += 1
            pending.append(document)
            if len(pending) >= settings.crawler_upload_batch_size:
                await flush()

        await crawl_source(source, settings, on_document=on_document)
        await flush()
        created = sum(result.get("createdCount", 0) for result in uploaded_results)
        updated = sum(result.get("updatedCount", 0) for result in uploaded_results)
        unchanged = sum(result.get("unchangedCount", 0) for result in uploaded_results)
        failed = sum(result.get("failedCount", 0) for result in uploaded_results)
        print(
            f"{source.code}: 完成抓取 {crawled_count} 条；"
            f"新增 {created}，更新 {updated}，未变化 {unchanged}，失败 {failed}。",
            flush=True,
        )
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description="UniPrism university public-content crawler")
    parser.add_argument("--source", help="只运行一个已启用的来源 code")
    parser.add_argument(
        "--community",
        action="store_true",
        help="运行北京大学知乎/贴吧公开社区证据试点",
    )
    parser.add_argument(
        "--institution",
        choices=["peking-university"],
        default="peking-university",
        help="社区试点学校；首期仅允许北京大学",
    )
    parser.add_argument(
        "--platform",
        choices=["all", "zhihu", "tieba"],
        default="all",
        help="社区试点平台",
    )
    parser.add_argument(
        "--scheduled",
        action="store_true",
        help="定时模式：先检查管理端高校自动采集总开关",
    )
    args = parser.parse_args()
    if args.community:
        result = asyncio.run(
            run_community_pilot(Settings(), platform=args.platform)
        )
        print(
            f"社区采集状态：{result.state}；阶段统计：{result.counts}",
            flush=True,
        )
        raise SystemExit(result.exit_code)
    raise SystemExit(asyncio.run(run(args.source, scheduled=args.scheduled)))


if __name__ == "__main__":
    main()
