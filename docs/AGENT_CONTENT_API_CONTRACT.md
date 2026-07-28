# 万有棱镜 Agent 内容检索与订阅 API 契约

> 版本：v0.1  
> 状态：前后端并行开发基线  
> Base URL：沿用 App `API_BASE_URL`  
> 认证：沿用现有 Bearer Token 和匿名探索会话机制

## 1. 设计原则

- Agent 只返回回答、来源卡片和“待确认动作”；
- 对话接口不能直接创建订阅或发送推送；
- 订阅必须通过独立确认接口创建；
- 所有外部结果携带来源、权利和 AI 标识；
- 服务端按当前用户绑定工具调用，客户端不能指定任意用户 ID；
- 所有写操作支持幂等键；
- 后端在展示、模型分析和推送前分别检查内容权利；
- 第一版采用游标分页，不返回未经授权全文。

## 2. Agent 对话

### `POST /api/app/agent/chat`

请求：

```json
{
  "conversationId": "可空，继续会话时传入",
  "message": "我对人工智能专业感兴趣，每天晚上八点推荐相关内容",
  "useProfile": true,
  "clientContext": {
    "timezone": "Asia/Shanghai",
    "locale": "zh-CN"
  }
}
```

响应：

```json
{
  "conversationId": "conv_123",
  "messageId": "msg_456",
  "text": "我找到了一些相关内容，并可以为你创建每日订阅。",
  "cards": [
    {
      "id": "content_1",
      "source": {
        "id": "zhihu",
        "name": "知乎",
        "type": "community",
        "url": "https://www.zhihu.com/..."
      },
      "title": "人工智能专业的学习体验",
      "excerpt": "由授权接口返回的有限摘要",
      "publishedAt": "2026-07-22T10:00:00+08:00",
      "contentType": "major_experience",
      "recommendationReason": "与你关注的人工智能和计算机专业相关",
      "aiGenerated": false,
      "rights": {
        "display": true,
        "aiSummary": false,
        "push": true
      }
    }
  ],
  "pendingAction": {
    "type": "create_subscription",
    "previewId": "preview_789",
    "requiresConfirmation": true,
    "subscription": {
      "name": "AI 与计算机专业探索",
      "topics": ["人工智能", "计算机专业"],
      "excludedTopics": ["娱乐八卦"],
      "sourceScope": ["zhihu", "own_content"],
      "contentScope": ["major_experience", "learning_guide"],
      "frequency": "daily",
      "pushTime": "20:00",
      "quietHours": ["22:00", "07:30"],
      "maxItems": 3
    }
  },
  "traceId": "trace_abc"
}
```

错误：

- `400 INVALID_MESSAGE`
- `401 AUTH_REQUIRED`
- `403 PROFILE_CONSENT_REQUIRED`
- `429 AGENT_RATE_LIMITED`
- `503 AGENT_UNAVAILABLE`

## 3. 订阅预览与确认

### `POST /api/app/content/subscriptions/preview`

用于用户手动编辑主题或时间后重新计算预览，不创建订阅。

### `POST /api/app/content/subscriptions`

请求：

```json
{
  "previewId": "preview_789",
  "confirmed": true,
  "consentVersion": "agent-subscription-v1",
  "idempotencyKey": "uuid-from-client"
}
```

响应：

```json
{
  "subscription": {
    "id": "sub_123",
    "name": "AI 与计算机专业探索",
    "topics": ["人工智能", "计算机专业"],
    "sourceScope": ["zhihu", "own_content"],
    "contentScope": ["major_experience", "learning_guide"],
    "frequency": "daily",
    "pushTime": "20:00",
    "quietHours": ["22:00", "07:30"],
    "maxItems": 3,
    "status": "active",
    "nextRunAt": "2026-07-23T20:00:00+08:00"
  }
}
```

服务端必须校验 `previewId` 属于当前用户、未过期且内容未被修改。`confirmed=false` 不得创建。

## 4. 订阅管理

```http
GET    /api/app/content/subscriptions
PUT    /api/app/content/subscriptions/{subscriptionId}
POST   /api/app/content/subscriptions/{subscriptionId}/pause
POST   /api/app/content/subscriptions/{subscriptionId}/resume
DELETE /api/app/content/subscriptions/{subscriptionId}
```

修改主题、来源、频率、时间或通知范围时，服务端保存新的确认版本和审计记录。

## 5. 内容流和详情

```http
GET  /api/app/content/feed?cursor=&mode=personalized
GET  /api/app/content/{contentId}
POST /api/app/content/{contentId}/feedback
```

`mode`：

- `personalized`：用户已开启个性化；
- `general`：非个性化公共内容；
- `subscription`：仅订阅内容。

反馈请求：

```json
{
  "action": "not_interested",
  "reason": "topic",
  "clientEventId": "uuid"
}
```

允许动作：`open`、`effective_read`、`favorite`、`share`、`not_interested`、`block_topic`、`report`。

## 6. 设备与消息

```http
POST   /api/app/devices
DELETE /api/app/devices/{deviceId}
GET    /api/app/messages?cursor=
POST   /api/app/messages/{messageId}/read
POST   /api/app/messages/read-all
```

设备注册只提交推送所需最小字段。退出登录、注销、Token 刷新和设备失活时解除旧绑定。

## 7. 内部任务

```http
POST /internal/content/search/run
POST /internal/content/classify
POST /internal/content/deduplicate
POST /internal/recommendations/build
POST /internal/subscriptions/dispatch
POST /internal/push/prepare
POST /internal/push/send
POST /internal/content/retract
```

内部接口必须网络隔离、服务身份认证、幂等、限流并记录 trace ID。

## 8. Provider 接口

```text
search(query, timeRange, cursor, limit)
getById(externalId)
checkRights(action, contentId)
healthCheck()
```

统一结果：

```json
{
  "sourceId": "zhihu",
  "externalId": "answer_123",
  "title": "...",
  "excerpt": "...",
  "url": "https://...",
  "author": "...",
  "publishedAt": "...",
  "fetchedAt": "...",
  "contentHash": "...",
  "rightsSnapshotId": "rights_123"
}
```

## 9. 安全要求

- 限制消息长度、会话轮数和工具调用次数；
- 正文视为不可信输入，防止 Prompt 注入；
- URL 只允许来源白名单并防止 SSRF；
- 模型输出经过 Schema、内容和权利校验；
- 不在响应中返回模型密钥、内部 Prompt 或完整画像；
- 外部搜索词不包含手机号、学校等可识别信息；
- Agent 无 `send_push`、`approve_content`、SQL 或任意 HTTP 工具；
- `traceId` 可追溯会话、工具、内容、审核和推送。

## 10. 内部开发模式

Flutter 客户端允许在非生产构建中使用显式模拟开关：

```text
--dart-define=AGENT_ENABLED=true
--dart-define=AGENT_MOCK_ENABLED=true
```

生产构建必须关闭模拟数据。后端未部署时不得悄悄回退为模拟结果。

### 10.1 独立的 DeepSeek + 知乎内容源测试

首轮真实性验证不接入现有 Agent，不修改登录、测评、报告、小程序或网页接口。正式后端只新增以下隔离模块：

```text
lib/content-sources/zhihu.ts
app/api/dev/content-sources/zhihu/search/route.ts
tests/unit/zhihuContentSource.test.ts
scripts/run-zhihu-content-source-test.ps1
```

测试接口为：

```http
POST /api/dev/content-sources/zhihu/search
```

该路由在 `NODE_ENV=production` 时直接拒绝访问，不读写数据库。它复用后端已有的 `lib/ai/deepseek.ts`，但不修改 DeepSeek 公共封装和其他调用方。

在正式后端目录启动测试服务：

```powershell
cd D:\ywkeji\Uniprism\UniPrism_New-main
powershell -ExecutionPolicy Bypass -File .\scripts\run-zhihu-content-source-test.ps1
```

脚本会依次要求隐藏输入当前 DeepSeek API Key 和知乎 Access Secret，只注入当前后端进程，不写入 `.env`、源码、Flutter、响应或日志。这样可以避免本地旧 Key 与部署环境 Key 不一致。

Android 模拟器访问电脑上的 Next.js 后端：

```powershell
cd D:\dev\Uniprism\uniprism_app
flutter run -d emulator-5554 `
  --dart-define=CONTENT_SOURCE_TEST_API_BASE_URL=http://10.0.2.2:3000
```

App 首页开发工具区域会显示“知乎内容真实性测试”按钮。这个入口与“棱镜 Agent”完全独立，不改变 Agent 的正式接口、模拟开关和页面行为。Android 局域网明文 HTTP 只在 debug manifest 中启用，正式构建不开放。

当前测试流程为：

```text
用户问题 + 手动兴趣标签
→ 复用现有 DeepSeek 封装生成一个结构化知乎检索词
→ 知乎官方 zhihu_search 返回真实内容
→ 后端保留标题、摘要、作者、互动数和原文链接
→ 独立 Flutter 测试页展示来源与检索过程
```

DeepSeek 只接收当前问题和最多 10 个手动兴趣标签，不接收知乎正文、手机号、姓名、学校、登录信息或业务数据库画像。AI 不能生成来源卡片正文；卡片内容只取自知乎接口响应。模型返回的兴趣标签还会与用户输入求交集，避免凭空添加兴趣。

当前知乎接口联调使用秒级 `X-Request-Timestamp`。平台鉴权说明与其 curl 示例曾出现毫秒/秒描述不一致，生产迁移时应以届时官方文档和重新验证结果为准。

### 10.2 多来源统一回答测试

开发接口：

```http
POST /api/dev/content-sources/answer
```

当前已纳入统一适配层的来源：

- 知乎、GitHub、OpenAlex、Crossref、ESCO、O*NET；
- 教育部本科专业目录、Hacker News；
- arXiv、PubMed、Stack Overflow、Hugging Face。

客户端会传入当前阶段推荐专业、人格/兴趣测评线索、最近用户问题和最近几轮对话。后端先按问题类型选择最多四个相关来源，不再对每个问题查询全部平台：

```text
用户问题 + 推荐专业 + 兴趣线索 + 最近对话
→ 来源路由（专业 / 职业 / 科研 / 医学 / 技术项目 / 热点）
→ 2～4 个真实来源并行检索
→ 去重、权威性、相关性、时效与公开热度排序
→ DeepSeek 生成一份中文统一回答
→ 返回实际使用的来源与原文链接
```

新增来源均允许无 Key 基础测试；生产环境建议配置：

```dotenv
ONET_API_KEY=""
NCBI_API_KEY=""
NCBI_CONTACT_EMAIL=""
NCBI_TOOL="uniprism_agent"
STACK_EXCHANGE_KEY=""
HUGGINGFACE_TOKEN=""
```

O*NET 没有 Key 时会返回 `configuration_required`，不会伪造职业数据。arXiv 在部分国内网络环境可能连接超时；单一来源失败会被隔离，其他来源仍继续生成回答。该开发接口仍不写数据库、不创建订阅、不发送推送，也不修改现有登录、测评、报告、小程序和网页接口。
