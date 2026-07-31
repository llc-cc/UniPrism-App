# UniPrism 高校公开内容采集器

这是独立于 App 的 Python 服务：它只读取已审批的高校公开页面，并把当前批次直接发送给后端；后端在云数据库中负责清洗、去重、版本、来源归属和入库。

## 安全边界

- 仅访问 `sources.yaml` 显式允许的域名和页面，并在启用前确认页面公开可访问、robots 规则和保存策略。
- 不登录、不绕过验证码或付费墙、不采集私人页面，也不自动扩展到未配置链接。
- 每个 `seed_pages` 项必须写明业务类别，例如 `major`、`campus_activity` 或 `student_community`。详情页需要同时配置路径白名单 `follow_path_prefixes` 与上限 `max_pages`。
- 不写 `var/crawler-out` 或任何网页正文文件到本机。未配置云端接口或令牌时，命令会直接失败，不会降级写入 D 盘。

## 在 PyCharm 中运行

```powershell
python -m pip install -e .
python -m playwright install chromium
Copy-Item .env.example .env
```

在后端 `.env` 设置高强度随机令牌：

```text
CONTENT_CRAWLER_INGEST_TOKEN="请替换为随机长令牌"
```

再在本项目 `.env` 设置后端地址和同一令牌：

```text
CRAWLER_BACKEND_INGEST_URL="https://你的后端域名/api/internal/content-ingestion/browser"
CRAWLER_BACKEND_CONTROL_URL="https://你的后端域名/api/internal/content-ingestion/automation"
CRAWLER_BACKEND_TOKEN="同一份随机长令牌"
CRAWLER_UPLOAD_BATCH_SIZE="25"
```

开发联调可使用 `http://127.0.0.1:3000/api/internal/content-ingestion/browser`。审核并启用 `sources.yaml` 中的来源后，可以只执行一所学校：

```powershell
python -m university_crawler.main --source peking-university-public-pages
```

也可以顺序执行全部已启用学校：

```powershell
python -m university_crawler.main
```

服务器定时器应使用定时模式；它会先读取管理端保存的高校自动采集总开关。开关关闭或状态无法确认时，本轮不会打开浏览器、抓取页面或写入数据库：

```bash
python -m university_crawler.main --scheduled
```

管理端总开关只控制带 `--scheduled` 的自动任务，因此管理员仍可使用 `--source` 手动验证单所学校。

当前试点包含北京大学、清华大学、中国人民大学和中南大学。新增学校时，Python 的 `sources.yaml` 与后端的高校来源白名单必须同时登记；后端会再次校验学校编码、内容类型和官方域名，不能只修改爬虫端绕过限制。

命令会按 25 条一批直传后端，不会把网页正文保存在本机。高校试点默认只允许清洗入库；来源的发布、推荐和 AI 使用仍需完成来源政策审核后才能开放给 App 用户。

## 北京大学社区证据试点

首期由 DeepSeek 驱动 Browser Use，在知乎和百度贴吧的公开页面内完成
搜索、打开候选页、相关性判断、翻页和结构化提交，覆盖学校、专业、课程、
就业、宿舍、食堂、社团七个维度。它不会登录账号、绕过验证码、使用代理
隐藏 IP 或保存用户身份；遇到登录墙、验证码和访问限制会记录阻断数量后跳过。

在服务器 `.env` 配置模型、后端地址和独立运行目录。部署脚本可以复用同一台
服务器主后端已有的 DeepSeek 配置：

```text
COMMUNITY_AGENT_ENABLED="true"
DEEPSEEK_API_KEY="DeepSeek Key"
DEEPSEEK_BASE_URL="可选；为空时使用官方地址"
DEEPSEEK_DIALOGUE_MODEL="deepseek-chat"
COMMUNITY_AGENT_RUNTIME_DIR="/opt/uniprism-crawler/runtime/browser-use"
CRAWLER_COMMUNITY_INGEST_URL="http://127.0.0.1:3000/api/internal/content-ingestion/community"
CRAWLER_CONTACT="你的运维联系邮箱或网页"
```

手动执行：

```bash
python -m university_crawler.main \
  --community \
  --institution peking-university \
  --platform all \
  --discovery-mode agent \
  --dimension all
```

定时任务还必须追加 `--scheduled`，这样管理端总开关关闭或控制接口不可用时
会安全跳过。缺少 Agent 开关、Skill 或 DeepSeek Key 时命令返回明确的
`AGENT_*` 状态和非零退出码，不会伪造“没有结果”的成功状态。所有非垃圾
候选进入人工审核，审核前不能参与 App 推荐或问答。
