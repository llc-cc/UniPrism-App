# 北京大学社区证据试点部署

范围固定为北京大学、知乎、贴吧以及学校、专业、课程、就业、宿舍、食堂、社团七个维度。

部署前，在服务器 `/opt/uniprism-crawler/app/.env` 中配置：

```text
BRAVE_SEARCH_API_KEY="搜索服务控制台提供的 Key"
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
systemctl start uniprism-community-evidence.service
journalctl -u uniprism-community-evidence.service -n 200 --no-pager
```

然后登录 `/admin/content-ingestion/community-evidence` 审核首批数据。定时器默认关闭；在首批质量确认前不要运行：

```bash
systemctl enable --now uniprism-community-evidence.timer
```

查看是否关闭：

```bash
systemctl is-enabled uniprism-community-evidence.timer
systemctl list-timers --all uniprism-community-evidence.timer --no-pager
```
