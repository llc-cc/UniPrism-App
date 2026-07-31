# 北京大学社区证据试点部署

范围固定为北京大学、知乎、贴吧以及学校、专业、课程、就业、宿舍、食堂、社团七个维度。

部署脚本会优先复用主后端 `.env` 中已有的 DeepSeek 配置。服务器
`/opt/uniprism-crawler/app/.env` 最终需要包含：

```text
COMMUNITY_AGENT_ENABLED="true"
DEEPSEEK_API_KEY="与主后端相同的 DeepSeek Key"
DEEPSEEK_BASE_URL="主后端使用的地址；未配置时使用官方地址"
DEEPSEEK_DIALOGUE_MODEL="deepseek-chat"
COMMUNITY_AGENT_RUNTIME_DIR="/opt/uniprism-crawler/runtime/browser-use"
CRAWLER_COMMUNITY_INGEST_URL="http://127.0.0.1:3000/api/internal/content-ingestion/community"
CRAWLER_BACKEND_TOKEN="与后端 CONTENT_CRAWLER_INGEST_TOKEN 相同"
CRAWLER_CONTACT="真实运维联系邮箱或网页"
```

部署：

```bash
tar -xzf /tmp/uniprism-community-evidence-pilot.tar.gz -C /tmp
bash /tmp/uniprism-community-evidence-pilot/deploy.sh
```

首次只手动执行：

```bash
cd /opt/uniprism-crawler/app
runuser -u uniprism-crawler -- /opt/uniprism-crawler/venv/bin/python \
  -m university_crawler.main --community --institution peking-university \
  --platform all --discovery-mode agent --dimension all
```

查看手动结果后，登录 `/admin/content-ingestion/community-evidence`
审核首批数据。定时器默认关闭；确认质量后才开启：

```bash
systemctl enable --now uniprism-community-evidence.timer
```

查看是否关闭：

```bash
systemctl is-enabled uniprism-community-evidence.timer
systemctl list-timers --all uniprism-community-evidence.timer --no-pager
journalctl -u uniprism-community-evidence.service -n 200 --no-pager
```

定时服务会带 `--scheduled`，因此管理端“高校自动采集”总开关关闭或
后端控制接口不可用时，本轮会安全跳过。默认执行时间为北京时间 04:00，
与 03:00 的高校官网采集错峰。
