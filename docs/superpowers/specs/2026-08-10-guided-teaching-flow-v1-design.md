# 教案引导教学闭环 V1 设计

## 1. 目标

在现有预习探索模块上增加可恢复、可验证的教案引导模式，同时完整保留自由探索模式。第一阶段使用 Mock 教案和 Mock 教学素材，但学生操作必须经过后端形成结构化证据，并由后端决定下一步教学动作，为以后接入正式知识库和 MCP 教学资产保留稳定边界。

## 2. 范围

### 2.1 本阶段实现

- 复用现有 `LearningSession`、模型对话、分支、回溯、账号历史和会话恢复。
- 创建会话时增加 `OPEN_EXPLORATION` 与 `GUIDED_LESSON` 两种模式；未传模式时保持现有自由探索行为。
- 为引导模式增加版本化的 `TeachingFlowV1`、`TeacherActionV1`、`AssetEventV1` 和 `EvidenceStateV1` 协议。
- 使用现有 `LearningMaterialUsage.interactionEvents` 持久化素材事件。
- 使用现有练习尝试和掌握证据能力完成无提示微测。
- 后端根据教学阶段和证据状态确定下一步动作。
- Flutter 在现有会话控制器和页面上展示目标、教学动作、素材互动、验证与反思流程。
- Mock 素材不可用、模型失败和重复事件均有确定性处理。

### 2.2 本阶段不实现

- 飞书或其他平台的真实 MCP 素材搜索。
- 正式知识库、稳定知识原子图和正式教案管理后台。
- 素材审核、版权、效果统计和复杂设备适配。
- 由大模型自主生成或修改证据规则。
- 替代现有自由探索模式。

## 3. 方案选择

采用“扩展现有会话聚合”方案。引导模式与自由探索模式共用会话、权限、幂等、持久化、模型调用和历史恢复能力，不建立第二套教学会话服务。

未采用以下方案：

- 独立引导课堂模块：会重复会话、权限、节点树和恢复逻辑。
- 仅 Flutter 本地 Mock：无法证明素材事件可以恢复，也无法让事件可靠地影响下一步教学。

## 4. 后端架构

### 4.1 会话扩展

`createLearningSessionSchema` 增加可选字段：

```ts
flowMode?: 'OPEN_EXPLORATION' | 'GUIDED_LESSON'
```

未提供时使用 `OPEN_EXPLORATION`，保证旧客户端和已有测试兼容。通过章节知识节点进入时，Flutter 显式请求 `GUIDED_LESSON`；从自由问题入口进入时显式请求 `OPEN_EXPLORATION`。

`LearningSession` 增加可空 JSON 字段 `teachingFlow`。它只保存当前可恢复的引导流程快照，不保存模型思维链。已有会话的字段为空，按自由探索处理。

### 4.2 核心协议

所有协议均带 `schemaVersion: 1`，后续只能通过新增版本演进。

```ts
type TeachingStageV1 =
  | 'DIALOGUE'
  | 'ASSET'
  | 'FOCUS'
  | 'REFLECT';

type TeacherActionTypeV1 =
  | 'ASK_QUESTION'
  | 'SHOW_ASSET'
  | 'REQUEST_MICRO_CHECK'
  | 'REQUEST_REFLECTION';

type EvidenceStrengthV1 =
  | 'OBSERVED'
  | 'ASSISTED'
  | 'INDEPENDENT';
```

`TeacherActionV1` 包含动作类型、面向学生的提示语、教学意图、可选素材使用记录 ID、可选练习 ID和可审计的 `reasonCode`。

`AssetEventV1` 包含事件 ID、素材使用记录 ID、事件类型、发生时间和经过白名单校验的 payload。客户端不能直接声明证据强度；后端依据当前提示等级、事件类型和完成条件推导证据。

`EvidenceStateV1` 包含已记录的证据项、必需证据代码、仍缺少的证据代码，以及是否允许进入无提示微测。每个证据项记录来源类型、来源 ID、强度和记录时间。

`TeachingFlowV1` 包含流程模式、当前阶段、教案标识、当前目标、当前动作、证据状态、提示等级和最后更新时间。

### 4.3 教学流程协调器

新增 `TeachingFlowCoordinator`，只负责确定性流程编排，不负责模型生成和数据库读写：

1. 创建引导会话后进入 `DIALOGUE`，当前动作为诊断提问。
2. 学生通过现有 `submitTurn` 回答诊断问题后，协调器选择当前节点允许的 Mock 素材，进入 `ASSET`。
3. 完成素材事件后记录 `OBSERVED`；如果使用过提示则记录 `ASSISTED`，否则在满足互动完成条件时记录 `OBSERVED`。
4. 必需的操作证据满足后进入 `FOCUS`，要求学生完成现有章节微测。
5. 无提示微测判定为 `MASTERED` 时记录 `INDEPENDENT` 并进入 `REFLECT`。
6. 微测为 `PARTIAL` 或 `RETRY` 时回到 `DIALOGUE`，当前动作说明缺失证据；不会把模型置信度当作掌握证据。
7. 学生提交反思后调用现有完成接口，并由 `LearningSession.status` 表示最终完成状态。

协调器输入为当前 `TeachingFlowV1`、最近一次学生动作及可用素材，输出为新的 `TeachingFlowV1`。相同输入必须得到相同流程决定。

### 4.4 素材事件接口

新增：

```text
POST /api/learning-sessions/{sessionId}/materials/{materialUsageId}/events
```

请求包含 `exploreSessionId`、`schemaVersion`、`eventId`、`eventType`、`occurredAt` 和 `payload`。接口沿用现有会话鉴权、限流、revision 与幂等包装。

Repository 在同一事务中：

1. 校验素材属于当前会话；
2. 按 `eventId` 去重；
3. 追加到 `interactionEvents`；
4. 更新 `teachingFlow` 和会话 revision；
5. 返回完整会话快照。

重复提交同一 `eventId` 返回当前快照，不重复追加事件或推进流程。

### 4.5 Mock Provider

第一阶段不改变现有 `KnowledgeProvider` 的知识事实职责。新增窄接口 `GuidedLessonProvider`，只提供当前知识节点的教学目标、必需证据、允许素材和微测 ID。

`MockGuidedLessonProvider` 使用现有 Mock 知识节点和组件键返回确定性数据。未来 MCP 接入时新增 Provider 实现，不修改 Controller、页面、事件协议和证据协调器。

## 5. Flutter 架构

### 5.1 DTO 与 API

- 创建会话请求增加 `flowMode`。
- 会话快照增加可空 `teachingFlow`。
- 素材 DTO 保留现有字段，并读取后端返回的互动契约和已提交事件。
- `RemoteExplorationApi` 增加 `submitMaterialEvent`。

所有新增字段均可空或有默认值，旧后端响应仍能进入自由探索模式。

### 5.2 Controller

在现有 `RemoteExplorationSessionController` 中增加：

- 当前 `TeachingFlowV1` 只读状态；
- `submitMaterialEvent` 异步动作；
- 引导模式下对重复点击的本地提交保护；
- 通过现有 `submitPracticeAttempt` 提交 `FOCUS` 阶段微测；
- 每次后端返回快照后统一替换流程状态，不在客户端自行推导证据。

Controller 只编排接口调用和页面状态，不解释素材 payload，也不自行决定学生是否掌握。

### 5.3 页面

继续使用现有 `RemoteLearningSessionPage`：

- 自由探索模式保持当前页面和交互。
- 引导模式显示当前教学目标、阶段和缺失证据的学生友好描述。
- `SHOW_ASSET` 时将目标素材提升为当前主要工作区。
- 互动组件通过统一回调产生 `AssetEventV1`，不再只调用本地 `setState`。
- `REQUEST_MICRO_CHECK` 复用现有练习提交能力。
- `REQUEST_REFLECTION` 复用现有完成会话入口。
- 技术字段、reason code 和内部证据代码不直接展示给学生。

第一阶段不重写五套独立页面，只根据后端阶段调整现有页面的主要区域；未来可在协议不变的前提下拆分布局。

## 6. 失败与边界

- 引导 Provider 无对应教案：创建会话失败并返回可识别业务错误，不伪装成引导模式。
- 素材不可用：协调器使用同一教案声明的公式卡或文字素材降级；降级结果仍返回正式 `TeacherActionV1`。
- 模型失败：继续使用现有 `SAFE_FALLBACK`，教学阶段不丢失。
- 非当前会话素材、未知事件类型、超长 payload 或错误阶段提交：返回校验错误，不修改会话。
- 网络重试：客户端复用同一个 `eventId`，由后端保证幂等。
- 老会话与老响应：`teachingFlow == null` 时完全沿用自由探索逻辑。

## 7. 测试与验收

### 7.1 后端测试

- 旧创建请求默认创建自由探索会话。
- 引导会话创建后返回 `DIALOGUE/ASK_QUESTION`。
- 诊断回答推进到 `ASSET/SHOW_ASSET`。
- 有效素材事件追加一次并推进到 `FOCUS`。
- 重复 `eventId` 不重复追加或推进。
- 使用提示的结果不会产生 `INDEPENDENT` 证据。
- 微测 `MASTERED` 进入 `REFLECT`；`PARTIAL/RETRY` 回到 `DIALOGUE`。
- 会话重新读取后恢复相同 `TeachingFlowV1`。
- 非法素材、非法事件和错误归属不会修改数据。

### 7.2 Flutter 测试

- 自由探索页面保持现有行为。
- 章节节点入口以 `GUIDED_LESSON` 创建会话。
- 引导会话显示目标和当前动作。
- 互动组件提交结构化事件，并使用稳定 `eventId` 重试。
- 后端快照推进后切换到微测和反思状态。
- 提交期间禁止重复操作，失败后可以重试。
- 旧快照没有 `teachingFlow` 时仍正常渲染。

### 7.3 完成标准

用户能够完成以下真实前后端链路，并在重新打开后恢复：

```text
创建引导会话
→ AI 诊断提问
→ 学生回答
→ 展示 Mock 互动素材
→ 素材事件上传并持久化
→ 后端更新证据和下一步动作
→ 学生完成无提示微测
→ 进入反思并结束会话
```

## 8. 数据与安全

- 不在 Flutter 中保存后端密钥、知识库凭证或 MCP 凭证。
- 客户端 payload 经过严格 schema、长度和事件类型白名单校验。
- 证据强度只由后端推导，客户端不能直接写入掌握结论。
- 不记录或返回模型思维链；只返回可审计的动作类型和 reason code。
- 本阶段新增一个可空会话 JSON 字段，不新增业务表；素材事件和练习证据继续使用已有数据结构。

## 9. 本地运行与当前限制

本次实现直接扩展现有探索页，没有建立第二套课堂页面。章节知识节点和原子入口创建 `GUIDED_LESSON`，独立自由提问仍创建 `OPEN_EXPLORATION`。引导模式需要后端启用 Mock 知识与教案提供器：

```env
LEARNING_KNOWLEDGE_PROVIDER="mock"
```

数据库模式还需要先应用 `20260810120000_guided_teaching_flow_v1` 迁移。`none` 与尚未提供教案的正式 Provider 会明确拒绝创建引导会话，避免把无教案内容伪装成已编排课堂。当前 V1 只覆盖已登记的 Mock 知识原子与组件事件；搜索、正式知识内容、MCP 教学资产和提示等级仍作为后续 Provider 能力接入。
