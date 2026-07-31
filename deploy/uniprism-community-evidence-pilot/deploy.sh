#!/usr/bin/env bash
set -Eeuo pipefail

BACKEND_ROOT="/root/zjy/UniPrism_New"
CRAWLER_ROOT="/opt/uniprism-crawler"
CRAWLER_APP="${CRAWLER_ROOT}/app"
BUNDLE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="/root/uniprism-deploy-backups/community-evidence-$(date +%Y%m%d-%H%M%S)"
SERVICE_NAME="uniprism-community-evidence.service"
TIMER_NAME="uniprism-community-evidence.timer"
WORKER_NAME="UniPrism_Community_Evidence"

for required in \
  "${BACKEND_ROOT}/package.json" \
  "${CRAWLER_APP}/pyproject.toml" \
  "${CRAWLER_APP}/.env" \
  "${BUNDLE_ROOT}/backend.tar.gz" \
  "${BUNDLE_ROOT}/crawler.tar.gz" \
  "${BUNDLE_ROOT}/systemd/${SERVICE_NAME}" \
  "${BUNDLE_ROOT}/systemd/${TIMER_NAME}"; do
  [[ -e "${required}" ]] || {
    echo "缺少部署前置文件：${required}" >&2
    exit 1
  }
done

echo "[1/7] 创建可恢复备份"
install -d -m 0700 "${BACKUP_ROOT}"
backend_candidates=(
  "prisma/schema.prisma"
  "prisma/content-ingestion-schema.prisma"
  "app/admin/content-ingestion"
  "app/api/admin/content-ingestion"
  "app/api/internal/content-ingestion"
  "lib/content-ingestion"
  "lib/community-analysis"
  "lib/adminCommunityEvidence.ts"
  "scripts/workers/community-evidence-analysis-worker.ts"
)
crawler_candidates=("src" ".env.example" "README.md")
backend_paths=()
crawler_paths=()
for path in "${backend_candidates[@]}"; do
  [[ -e "${BACKEND_ROOT}/${path}" ]] && backend_paths+=("${path}")
done
for path in "${crawler_candidates[@]}"; do
  [[ -e "${CRAWLER_APP}/${path}" ]] && crawler_paths+=("${path}")
done
((${#backend_paths[@]} == 0)) || tar -czf "${BACKUP_ROOT}/backend-before.tar.gz" \
  -C "${BACKEND_ROOT}" "${backend_paths[@]}"
((${#crawler_paths[@]} == 0)) || tar -czf "${BACKUP_ROOT}/crawler-before.tar.gz" \
  -C "${CRAWLER_APP}" "${crawler_paths[@]}"

echo "[2/7] 叠加本次社区试点代码"
tar -xzf "${BUNDLE_ROOT}/backend.tar.gz" -C "${BACKEND_ROOT}"
tar -xzf "${BUNDLE_ROOT}/crawler.tar.gz" -C "${CRAWLER_APP}"
chown -R uniprism-crawler:uniprism-crawler "${CRAWLER_APP}"

echo "[3/7] 补充非敏感环境配置"
if ! grep -q '^CRAWLER_COMMUNITY_INGEST_URL=' "${CRAWLER_APP}/.env"; then
  printf '\nCRAWLER_COMMUNITY_INGEST_URL="http://127.0.0.1:3000/api/internal/content-ingestion/community"\n' \
    >> "${CRAWLER_APP}/.env"
fi
if ! grep -q '^CRAWLER_CONTACT=' "${CRAWLER_APP}/.env"; then
  printf 'CRAWLER_CONTACT="crawler-contact-not-configured"\n' >> "${CRAWLER_APP}/.env"
fi
chown uniprism-crawler:uniprism-crawler "${CRAWLER_APP}/.env"
chmod 0600 "${CRAWLER_APP}/.env"

echo "[4/7] 迁移数据库、生成 Prisma Client 并构建后端"
cd "${BACKEND_ROOT}"
npx prisma migrate deploy
npm run db:generate
npm run build

echo "[5/7] 重启后端并启动独立 AI 分析 worker"
pm2 restart UniPrism_New --update-env
if pm2 describe "${WORKER_NAME}" >/dev/null 2>&1; then
  pm2 restart "${WORKER_NAME}" --update-env
else
  pm2 start node_modules/.bin/tsx \
    --name "${WORKER_NAME}" \
    -- scripts/workers/community-evidence-analysis-worker.ts
fi
pm2 save

echo "[6/7] 安装但保持关闭社区定时器"
install -o root -g root -m 0644 \
  "${BUNDLE_ROOT}/systemd/${SERVICE_NAME}" \
  "/etc/systemd/system/${SERVICE_NAME}"
install -o root -g root -m 0644 \
  "${BUNDLE_ROOT}/systemd/${TIMER_NAME}" \
  "/etc/systemd/system/${TIMER_NAME}"
systemctl daemon-reload
# 首批内容必须由管理员审核，部署不能自动开始社区采集。
systemctl disable --now "${TIMER_NAME}" >/dev/null 2>&1 || true

echo "[7/7] 只读健康检查"
backend_ready=false
for _attempt in {1..30}; do
  if curl -fsS -o /dev/null "http://127.0.0.1:3000/api/health"; then
    backend_ready=true
    break
  fi
  sleep 1
done
[[ "${backend_ready}" == "true" ]] || {
  echo "后端 30 秒内未就绪，请执行 pm2 logs UniPrism_New。" >&2
  exit 1
}
systemctl is-enabled "${TIMER_NAME}" || true
systemctl list-timers --all "${TIMER_NAME}" --no-pager || true

if grep -q '^BRAVE_SEARCH_API_KEY=.\+' "${CRAWLER_APP}/.env"; then
  echo "搜索发现配置：已配置。可以手动执行首批采集。"
else
  echo "搜索发现配置：DISCOVERY_NOT_CONFIGURED。请先在 ${CRAWLER_APP}/.env 写入 BRAVE_SEARCH_API_KEY。"
fi

echo "部署完成，社区定时器保持关闭。"
echo "备份目录：${BACKUP_ROOT}"
echo "手动首批：systemctl start ${SERVICE_NAME}"
echo "查看日志：journalctl -u ${SERVICE_NAME} -n 200 --no-pager"
echo "回滚代码：分别将 ${BACKUP_ROOT} 下备份包解压回对应目录，再重建并重启。"
