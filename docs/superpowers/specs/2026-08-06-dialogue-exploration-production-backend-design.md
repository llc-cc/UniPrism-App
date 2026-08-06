# 1.2 对话式发散提问正式链路设计

状态：已确认，进入实施前审阅  
日期：2026-08-06

## 1. 目标

把现有 Flutter Mock 原型升级为可真实联调的 10 分钟 AI 学习 Session。学生从一个问题出发，系统自动选择教学策略、生成回答与原理型反问、调度素材、记录思维树，并在结束时形成理解报告、错误模型、兴趣证据与记忆候选。

本阶段唯一保留的 Mock 是 1.1 知识库及其素材目录。知识边界、关系边、种子问题和素材元数据由 `MockKnowledgeProvider` 提供；其接口与未来正式 1.1 Provider 一致。会话、AI、评估、缓存、数据库、保存、恢复、导出和学习产出全部走正式链路。

## 2. 工程与分支

- Flutter 学生端：`D:\dev\Uniprism\uniprism_app`，分支 `feature/student-dialogue-exploration-1-2`。
- Next.js 后端：`D:\ywkeji\Uniprism\UniPrism_New-main`，从 `feature/app-support` 新建 `feature/dialogue-exploration-1-2-backend`。
- Android App 与 Flutter Web 共用同一套页面、领域模型和远程 Gateway；不在 Next.js 中复制学生端页面。
- Next.js 负责 API、认证、AI 编排、Redis、MySQL 与服务端学习产出。

## 3. 总体架构

```text
Flutter App / Flutter Web
          |
Learning Session API
          |
Session Manager
   |          |          |
 Redis       MySQL    Teaching Engine
                         |
              Dialogue Model Provider
                         |
                     DeepSeek
                         |
                Question Evaluator
                         |
                MockKnowledgeProvider
```

模块边界：

- `Session Manager`：验证会话归属、10 分钟时限、节点限制、幂等与状态迁移。
- `Teaching Engine`：只决定如何教，不生成知识事实。
- `Dialogue Model Provider`：调用现有 DeepSeek 能力并返回结构化结果。
- `Question Evaluator`：评价反问质量，控制重生成与安全降级。
- `KnowledgeProvider`：提供知识边界、关系边、素材白名单和种子问题；本阶段为 Mock。
- Repository：只负责 Prisma 持久化，不承载教学决策。
- Redis Store：只保存运行态、锁和幂等结果；MySQL 是最终事实来源。

## 4. 用户流程

1. 学生打开 1.2，看到问题输入框与来自 Mock 知识 Provider 的种子问题。
2. 客户端创建 `LearningSession`，后端读取学生历史证据；没有历史时返回 `UNKNOWN`，不伪造掌握档位。
3. 每次学生提问或提出假设时，后端读取当前根到活动叶节点的最多 5 层路径、掌握证据和允许素材集合。
4. Teaching Engine 选择本轮策略，DeepSeek 返回结构化回答、原理型反问、边界判断和候选素材 ID。
5. Evaluator 按 5 个维度评分。通过后在同一事务中写入节点、素材记录、评价记录和运行态；失败则重生成或降级。
6. 学生可以继续深挖、从任一有效节点开支线、保留错误路径并回退。
7. 达到结束条件后进入自我解释，服务端根据整棵树生成学习总结并保存证据。
8. 学生可恢复会话、导出 JSON、将选中节点转为记忆候选。App 和 Web 登录同一账号时读取同一数据。

## 5. 教学策略

本阶段正式实现一个 Teaching Engine 和五种自动策略，不创建五个 Agent：

1. `QUESTION_CHAIN`：新会话梳理主干、前置概念与可探索支线。
2. `SOCRATIC`：追问结论依据、适用条件和反例。
3. `ERROR_TRACKING`：保留错误思路，制造或引用反例，定位首个矛盾点并回退。
4. `ANALOGY_TRANSFER`：学生表达抽象、不会或不知道时，建立结构同构的熟悉类比。
5. `SELF_EXPLANATION`：收口阶段要求学生用自己的话解释并验证理解。

优先级为：已确认错误 > 收口 > 明确卡住 > 首轮问题链 > 苏格拉底追问。策略决策必须保存版本、原因、目标和深度，便于审计与后续 A/B。

## 6. AI 请求与结构化输出

每轮输入包含：主题、当前学生问题、活动路径、掌握证据、误解标签、当前策略、Session 进度、知识边界和素材白名单。只传活动路径最多 5 层，不把整场聊天无限塞入模型。

模型输出通过 Zod 校验：

```json
{
  "answer": "解释正文",
  "nextQuestion": "指向原理或成立条件的反问",
  "strategy": "SOCRATIC",
  "boundary": "IN_SCOPE",
  "materialIds": ["number_line_001"],
  "sideBranchSuggested": false,
  "reasoningTags": ["operation_consistency"]
}
```

模型不得直接决定数据库 ID、用户归属、节点深度或最终掌握程度。服务端会再次裁剪不在 Provider 白名单中的素材 ID。

## 7. 反问质量评估

Evaluator 对以下维度各评 0–5 分：

- 是否指向底层原理或成立条件；
- 是否关联当前知识与活动路径；
- 是否推动下一步探索；
- 难度是否匹配学生证据；
- 问题是否明确、可回答。

总分不低于 18 才通过。低分时最多重生成 2 次；仍未通过、模型超时或 JSON 无效时，使用服务端经过测试的策略模板生成反问。独立的“你觉得呢”“还有吗”以及只要求态度、不要求依据的问题永远不通过。

每次尝试都写入 `QuestionEvaluation`，保存各维度分数、总分、是否通过、模型版本和失败原因。

## 8. 节点与会话限制

- 会话有效学习时长：10 分钟。
- 单会话最多 20 个节点。
- 根到叶最大深度：5。
- 单节点最多 3 个直接分支。
- 单轮最多引用 2 个素材。
- 输入长度、输出长度和单用户请求频率由 API 层限制。

达到任一结构限制后不再扩树，系统转入 `SELF_EXPLANATION`；仍允许总结、保存、导出和创建记忆候选。

错误分支不能删除。回退时把错误路径标记为 `CONTRADICTED/BACKTRACKED`，新增回退节点记录恢复点，再从恢复点建立新分支。

## 9. Redis 运行态

Redis Key：

- `learning-session:{sessionId}`：活动节点、策略、节点数、深度、最近节点 ID 和硬截止时间。
- `learning-session:{sessionId}:lock`：单轮写入锁，防止双击生成两个节点。
- `learning-session:{sessionId}:idem:{key}`：创建、回答、回退、完成操作的幂等结果。

课程硬截止时间仍为开始后 10 分钟；Redis 使用 15 分钟滑动 TTL，避免第 9 分钟请求处理中缓存先过期。完成或取消后立即删除运行态。Redis 不可用时从 MySQL 恢复必要状态，不能因缓存故障丢失已确认节点。

## 10. MySQL/Prisma 数据模型

### `LearningSession`

保存用户、主题、入口类型、Mock atom ID、状态、活动节点、策略版本、开始/截止/完成时间和版本号。用户 ID 只从认证会话获得，不接受客户端指定。

### `ThinkingNode`

保存父节点、节点类型、状态、学生问题或假设、AI 回答、反问、策略、深度、知识 ID、理解候选值、支线标记、回退目标与创建时间。对 `(sessionId, parentId)`、`(sessionId, createdAt)` 建索引。

### `MaterialUsage`

记录节点、素材 ID、类型、选择原因、Provider 版本和实际交互事件。素材主数据本阶段不复制入 MySQL，由 `MockKnowledgeProvider` 提供。

### `QuestionEvaluation`

记录每次生成尝试、五维评分、总分、通过状态、模型与失败原因。

### `LearningSummary`

一场会话最多一条，保存理解报告、错误模型、兴趣方向、自我解释、树统计和摘要版本。

### `MemoryCandidate`

保存用户、来源 Session、来源节点、正反面内容和状态；`(userId, sessionId, nodeId)` 唯一，保证重复点击幂等。

### `MasteryEvidence` 与 `InterestEvidence`

只保存可追溯证据。模型猜测不能直接成为正式掌握结论；学生确认、规则验证和完成自我解释后才写入。兴趣证据记录主动提问深度、支线广度和素材交互，不直接给学生贴标签。

## 11. API

- `POST /api/learning-sessions`：创建会话。
- `GET /api/learning-sessions/{id}`：恢复会话与完整树。
- `POST /api/learning-sessions/{id}/turns`：提交问题或假设并返回本轮结构化结果。
- `POST /api/learning-sessions/{id}/branches`：从指定节点新开支线。
- `POST /api/learning-sessions/{id}/backtracks`：确认错误并回退。
- `POST /api/learning-sessions/{id}/complete`：提交自我解释并生成最终产出。
- `POST /api/learning-sessions/{id}/memory-candidates`：幂等创建记忆候选。
- `GET /api/learning-sessions/{id}/export`：导出版本化 JSON。

所有写接口使用 Zod 校验、现有认证、Origin 校验、限流、会话归属检查和 `Idempotency-Key`。错误响应使用现有统一 API error 格式。

## 12. MockKnowledgeProvider

Provider 内置少量可测试数据：负负得正、二次函数顶点、不等式证明、咖啡店商业模型，以及图、可播放演示视频、真实可操作交互和公式卡。Provider 必须返回：

- 学段与知识边界；
- 前置、对比、应用关系边；
- 种子问题；
- 可用素材及类型；
- 每个 atom 的允许素材 ID 集合。

未来 1.1 接入只新增正式 Provider，并通过配置切换；AI、Session Manager、数据库和 Flutter 协议保持不变。

## 13. Flutter App/Web

- 保留现有领域模型、树和响应式页面，新增 `RemoteExplorationGateway`、Session Repository 与 DTO 映射。
- 配置后默认调用正式后端；显式开发开关才使用本地 Mock。
- App 与 Web 共用会话 ID，页面刷新或重启后可恢复。
- 宽屏使用右侧思维树面板，小屏使用抽屉/底部面板。
- 网络请求必须有超时、重试边界、加载、失败、空状态和幂等键。
- 素材组件根据服务端返回的类型注册表渲染；声明为 interactive 的素材必须可操作并上报交互。

## 14. 异常与降级

- DeepSeek 超时、限流或结构化结果无效：最多按策略重试，之后使用服务端确定性反问模板；不丢失学生输入。
- Evaluator 连续失败：记录失败并使用通过规则测试的模板。
- Redis 故障：从 MySQL 恢复；数据库故障时不向客户端假报成功。
- Mock Provider 未命中：标记为超出当前知识范围，可给学段内概览，但不引用未授权素材。
- 不适宜输入：拒绝且不写入思维树；安全事件单独审计。
- 重复提交：返回同一幂等结果，不重复调用模型或创建节点。

## 15. 测试

后端使用 Vitest 覆盖：策略优先级、结构限制、Evaluator 阈值与重试、素材白名单、幂等、并发锁、认证归属、Redis 重建、总结证据规则和 API 契约。Prisma 迁移需要生成检查和关键读写集成测试。

Flutter 使用单元与 Widget 测试覆盖：远程 DTO 映射、错误重试、创建/恢复 Session、树增长、分支/回退、完成总结、记忆候选、App/Web 响应式布局及本地 Mock 开关。最终运行全量 Flutter 测试、后端单元测试、类型检查和构建。

## 16. 验收标准

- 学生无需选择模式即可从问题库或自由问题启动。
- App 与 Web 可使用同一账号恢复同一 Session。
- 一场会话可以真实调用后端模型，也能在模型故障时继续受控测试。
- 每轮成功回答包含通过评估的原理型反问。
- 素材不越出 Mock Provider 关系边白名单，交互素材真实可操作。
- 错误思路可保留、验证、回退并建立新分支。
- 节点、深度、分支和时间限制全部由服务端强制执行。
- 会话可保存、刷新恢复、导出，并把节点转为记忆候选。
- 完成后生成理解报告、错误模型、兴趣证据和复习卡。
- 以后接入 1.1 时只替换 `KnowledgeProvider`，无需重写其他模块。

## 17. 本阶段不包含

- 正式 1.1 知识库数据与检索实现；
- 其余十种教学策略，当前只保留可版本化扩展点；
- John Zheng 的外部协作与 Skill 归属流程；
- 语音识别和手写识别。

这些能力不影响本阶段完整联调和产品验证。
