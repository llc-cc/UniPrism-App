# UniPrism B 类学校体验语料地基设计

## 1. 目标与范围

本阶段建立“低频体验语料”独立闭环，验证学生公开经验能否经过合规采集、
去标识化清洗、质量筛选和多来源聚合，最终作为 App 的补充体验信息。

首期范围固定为：

- 实体：北京大学，仅构建学校体验，不构建北京城市画像；
- 平台：知乎、贴吧；
- 维度：学校、专业、课程、就业、宿舍、食堂、社团；
- 采集方式：本地已登录专用 Chrome，由用户完成登录和验证码；
- 运行方式：首次快照手动触发，验证通过后每 3–6 个月刷新；
- 最终产物：人工审核通过的 `ExperienceSignalAggregate`；
- App 边界：不读取未经审核的原文，不把单条评论当作学校结论。

本阶段不实现 A 类新闻、政策、科研、GitHub、产品和活动每日信息流，也不修改
现有邀请码、用户管理或其他无关页面。

## 2. A/B 分流原则

来源等级与处理类型是两个独立维度：

- `S1–S4` 描述来源权威程度；
- `A/B` 描述内容变化速度、处理流程和最终产物。

B 类社区体验默认属于 S4，只能补充长期生活和学习感受，不能覆盖 S1/S2
官方事实。B 类内容不得进入每日新闻推送，A 类内容也不得直接写入学校长期体验。

两类任务必须分别拥有：

- 调度策略；
- 任务类型和状态；
- 清洗与质量规则；
- 数据表和最终产物；
- 管理端监控指标；
- App 检索入口。

现有高校官网采集继续独立运行；社区体验定时器保持关闭，不参与每日任务。

## 3. 总体架构

```text
专用本地 Chrome（用户手动登录）
  → Local Community Agent（CDP 连接 127.0.0.1）
  → 仅访问允许范围内的公开页面
  → ExperienceRawSample 临时样本
  → 程序基础过滤
  → 去标识化与安全清洗
  → 近重复与跨平台转载去重
  → 实体、时间、属性和情绪识别
  → 内容质量与可信度评分
  → 主题聚类和多来源聚合
  → 人工审核
  → ExperienceSignalAggregate
  → App 安全检索
```

本地 Agent 只负责采集和安全上传，不保存长期业务数据。云端后端负责持久化、
清洗编排、审核和聚合。App 只读取发布状态的聚合结果。

## 4. 来源治理

每个来源必须登记：

- 平台、入口和来源等级；
- 访问方式；
- 允许和禁止采集范围；
- robots.txt、服务条款和复核时间；
- 请求频率、保存期限和解析器版本；
- `active / paused / blocked / retired` 状态。

知乎、贴吧首期只允许：

- 用户已经合法登录后可见的公开页面；
- 与北京大学和当前任务维度直接相关的公开正文或评论；
- 平台允许保存和处理的最小必要字段。

禁止绕过登录、验证码、付费墙或反自动化措施。出现 403、验证码或条款边界不明
时，将任务记为 `blocked`，不自动高频重试。

## 5. 本地登录浏览器模式

本地 Chrome 使用独立目录 `D:\UniPrismBrowserProfile`，并只在
`127.0.0.1:9222` 提供 CDP 连接。Agent 不接收账号密码，也不把 Cookie、
浏览器配置或跨站身份信息上传 ECS。

采集器新增可选配置：

```text
COMMUNITY_AGENT_CDP_URL="http://127.0.0.1:9222"
```

设置该值时：

- 连接已经运行的浏览器，不再启动独立无头浏览器；
- 任务完成后只断开 Agent 会话，不关闭用户 Chrome；
- 不改变用户登录状态；
- CDP 地址必须是回环地址，拒绝公网地址；
- 浏览器不可连接时，任务直接失败并给出可操作提示。

ECS 定时采集不使用本地登录会话。将来如需授权平台接口，应新增
`authorized_export` 或官方 API 访问方式，不上传本地 Cookie 代替授权。

## 6. 数据模型

### 6.1 ExperienceRawSample

临时保存清洗和审核所需的最小样本：

```ts
interface ExperienceRawSample {
  id: string;
  sourceId: string;
  crawlRunId: string;
  entityType: 'school' | 'city';
  entityId: string;
  platformType: string;
  sourceUrl: string;
  sourceContentId?: string;
  capturedAt: string;
  occurredAt?: string;
  encryptedRawText?: string;
  normalizedTextHash: string;
  retentionUntil: string;
  processingStatus:
    | 'pending'
    | 'cleaned'
    | 'rejected'
    | 'aggregated'
    | 'deleted';
}
```

原文如确有复核必要，必须加密、限管理员访问并设置短期保留时间；完成聚合后按
策略删除。普通用户昵称、头像、主页、联系方式和跨平台身份标识不入库。

### 6.2 ExperienceEvidence

清洗后的内部证据，不直接展示给 App：

```ts
interface ExperienceEvidence {
  id: string;
  rawSampleId: string;
  entityType: 'school' | 'city';
  entityId: string;
  primaryAspect: string;
  secondaryAspects: string[];
  sentiment: 'positive' | 'neutral' | 'mixed' | 'negative';
  sentimentIntensity: number;
  safeSummary: string;
  experienceTimeFrom?: string;
  experienceTimeTo?: string;
  qualityStatus:
    | 'high_value'
    | 'usable'
    | 'low_context'
    | 'duplicate'
    | 'spam'
    | 'unsafe';
  qualityScore: number;
  credibilityScore: number;
  clusterKey?: string;
  reviewStatus: 'pending' | 'approved' | 'rejected';
}
```

### 6.3 ExperienceSignalAggregate

App 可使用的稳定体验产物：

```ts
interface ExperienceSignalAggregate {
  id: string;
  entityType: 'school' | 'city';
  entityId: string;
  aspect: string;
  timeWindow: { from?: string; to: string };
  sentimentDistribution: {
    positive: number;
    neutral: number;
    mixed: number;
    negative: number;
  };
  recurringThemes: string[];
  minorityViews: string[];
  representativeSafeSummaries: string[];
  independentSourceCount: number;
  uniqueContentCount: number;
  duplicateSuppressionCount: number;
  qualityDistribution: Record<string, number>;
  sourcePlatformTypes: string[];
  confidence: number;
  reviewStatus: 'pending' | 'approved' | 'rejected';
  refreshedAt: string;
  nextRefreshAt: string;
}
```

聚合数量只描述本次样本，不推断全体学生比例。没有代表性采样依据时，App
不得输出“80% 的学生”等总体统计结论。

## 7. 清洗与聚合流程

每条样本按固定顺序处理：

1. HTML、空白、表情和格式清理；
2. 广告、引流、机器人和无意义短文本过滤；
3. 昵称、联系方式、个人身份和敏感组合去除；
4. 辱骂、攻击、违法和高风险内容标记；
5. 北京大学实体校验与歧义排除；
6. 体验时间窗口识别；
7. URL、平台内容 ID、文本哈希和高相似去重；
8. 主属性和次属性分类；
9. 情绪对象、倾向和强度识别；
10. 事实陈述与主观体验拆分；
11. 质量和可信度评分；
12. 主题聚类、少数观点保留和跨平台聚合。

低质量、重复、广告和不安全内容不参与聚合，也不得进入用户画像或 Agent
回答。未经清洗的原始评论不得直接进入回答 Prompt。

## 8. 七个首期维度

首期使用统一枚举：

- `school_overall`：学校整体体验；
- `major_resources`：专业资源；
- `course_and_workload`：课程与学习强度；
- `career_and_employment`：实习、升学与就业资源；
- `dormitory`：宿舍和校区差异；
- `canteen`：食堂与日常消费；
- `clubs_and_culture`：社团与校园文化。

一条证据可以命中多个维度，但必须指定一个主维度。后续扩展图书馆、行政、
校园交通、周边生活等属性时，不改变首期数据契约。

## 9. 状态与失败处理

`CrawlRun.status` 使用：

- `queued`
- `running`
- `completed`
- `partial`
- `failed`
- `blocked`

当全部任务均因 403、验证码或登录失效停止时，顶层状态必须是 `blocked`，
不能显示 `completed`。部分平台成功、部分阻断时显示 `partial`。

同一学校、平台、维度和快照窗口只允许一个活跃任务。连续失败采用指数退避，
达到阈值后自动暂停来源并进入人工处理，不无限重试。

## 10. 管理端与人工审核

继续使用现有内容采集监控中心，只增加 B 类体验区域，不修改其他管理页面。

首期展示：

- 首次快照和下次刷新时间；
- 平台运行状态和阻断原因；
- 原始样本、有效、重复、广告、不安全和待审核数量；
- 七个维度的证据数量和来源分布；
- 聚合结论、少数观点、时间窗口和置信度；
- 批量审核、单条驳回和来源下线后的重算入口。

首批聚合全部人工审核。只有审核通过的聚合可发布给 App。

## 11. App 使用规则

App 检索北京大学体验问题时：

1. 先读取 S1/S2 官方事实；
2. 再读取审核通过、未过期的 B 类聚合；
3. 明确区分“官方事实”和“学生体验汇总”；
4. 展示体验时间窗口和平台类型，不展示评论者身份；
5. 样本不足或置信度低时明确提示，不生成确定性结论；
6. 用户换到其他学校或其他主题时重新检索，不复用无关聚合。

## 12. 测试与验收

最低验收项：

- 本地 Agent 能连接 `127.0.0.1:9222`，任务结束不关闭 Chrome；
- 非回环 CDP 地址被拒绝；
- 登录失效、403 和验证码正确标记为 `blocked`；
- 同一任务不会重复并发；
- 联系方式和可识别身份不会进入清洗结果；
- 广告、短文本、重复和不安全内容不会参与聚合；
- 一条内容可有多个属性，但只有一个主属性；
- 聚合保留少数观点和时间窗口；
- 全部阻断时顶层状态不是 `completed`；
- 未审核聚合无法被 App 检索；
- 原始文本到期后可删除，并能审计删除结果；
- 现有高校官网采集和其他 App 页面测试不受影响。

## 13. 分阶段实施

1. 来源治理字段、B 类模型和数据库迁移；
2. 本地 CDP 登录浏览器模式与安全校验；
3. 原始样本接收、去标识化、过滤和去重；
4. 七维分类、质量评分和主题聚合；
5. 管理端 B 类监控与人工审核；
6. App 聚合检索和来源说明；
7. 北京大学首批快照验收；
8. 验收通过后配置 3–6 个月刷新，再扩展学校和城市。

