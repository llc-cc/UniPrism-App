# 练习评分后端接入与底层判断 V1 设计

状态：已确认方向，待书面审阅
日期：2026-08-12

## 1. 目标

把 Flutter 中现有的练习评分实验室接入真实 Next.js 后端，形成一个可恢复、可追溯、可自动产生训练候选数据的最小正式闭环：

1. 从后端读取版本化的 19 题演示卷；
2. 匿名或登录用户创建、恢复练习会话；
3. 服务端保存草稿、过程事件和不可变提交；
4. 题目难度与人的能力证据由两个独立引擎判断；
5. 规则事实、结构化模型判断、冲突校验和能力画像均可版本化重放；
6. Flutter 页面展示连接状态、会话状态、单题结果和能力证据；
7. 只把去标识化、高置信度、无冲突且获得训练授权的样本投影为小模型训练候选。

本期继续使用项目自造的 19 题演示内容，不宣称为 2026 新高考 I 卷官方试题。

## 2. 本期不包含

- 购买、抓取或导入未经授权的正式高考试题；
- 训练、部署或灰度真实小模型权重；
- 人工审核队列；
- 基于单次作答给出确定的长期能力结论；
- 手写识别、图片答题、语音答题和数学 OCR；
- 将练习数据写回预习模块的内部状态或数据表。

## 3. 工程与分支

- Flutter 学生端：`D:\dev\Uniprism\uniprism_app`，当前分支 `feat/practice-assessment-v1`。
- Next.js 后端：`D:\ywkeji\Uniprism\UniPrism_New-main`。
- 后端实施时从 `feature/dialogue-exploration-1-2-backend` 新建 `feat/practice-assessment-v1-backend`。
- Flutter 练习模块保留 `PracticeRepository` 端口；远程实现和 Mock 实现可替换，但远程模式失败时不得静默回退 Mock。
- 后端新建独立 `lib/practice-assessment/` 领域目录，不复用 `lib/learning-session/` 的预习/教学状态机。

## 4. 核心原则

### 4.1 题目与人严格分离

`QuestionDifficultyEngine` 只读取题目、知识点、标准解法和 rubric，不读取学生数据。`AttemptEvidenceEngine` 读取一道题的一次作答及其过程事实，输出单次证据，不直接宣称学生长期能力。

### 4.2 先事实、后判断

系统先形成可重复计算的确定事实，例如答案是否匹配、命中了哪些 rubric 步骤、是否请求提示、是否自主修正、服务器观察到的用时范围，再由评估器引用这些事实形成能力观察。

### 4.3 证据不足不等于能力低

能力维度必须先返回以下状态之一：

- `OBSERVED`：证据足够，必须给出 `0..4` 档位；
- `INSUFFICIENT_EVIDENCE`：题目可能涉及该维度，但本次过程不足，不允许给档位；
- `NOT_APPLICABLE`：该题不能观察这个维度，不允许给档位。

### 4.4 全链路版本化

题目内容、rubric、难度规则、事实提取器、模型提示词、评估器、画像更新算法和训练投影格式分别保存版本。历史提交只引用提交当时的版本；算法升级通过离线重算产生新派生结果，不覆盖原始作答和事件。

### 4.5 服务端是真实来源

标准答案、完整 rubric、模型提示词、内部置信度和训练标签只存在于后端。Flutter 只接收学生可见题目和经过裁剪的结果。

## 5. 总体架构

```text
Flutter Practice UI
        |
RemotePracticeRepository
        |
Practice HTTP API
        |
PracticeSessionService
   |          |             |                 |
Prisma   QuestionDifficulty  AttemptEvidence   AbilityProfile
Store         Engine            Engine            Updater
                                  |
                         Rule Facts + Optional
                         Structured Model Pair
                                  |
                         TrainingDatasetProjector
```

模块职责：

- `PracticeSessionService`：身份、会话归属、状态迁移、幂等、事务和业务编排；
- `QuestionDifficultyEngine`：题目六维内容难度和综合档位；
- `AttemptFactExtractor`：确定性判题、rubric 命中和过程事实；
- `AttemptEvidenceEngine`：七维单次能力证据与置信度；
- `AbilityProfileUpdater`：结合题目难度更新长期画像；
- `TrainingDatasetProjector`：授权、去标识化、冲突过滤和数据集契约输出；
- Repository：只负责 Prisma 读写，不承载评分决策；
- Flutter Repository：只负责 HTTP、DTO 转换、超时和错误映射，不承载 UI。

## 6. 题目难度判断

### 6.1 六维定义

所有维度使用 `0..4` 有序量表：

| 维度 | 主要可计算特征 |
| --- | --- |
| 知识负荷 | 知识点数量、前置层级、跨知识组合、概念抽象度 |
| 阅读负荷 | 题干长度、有效条件数、隐含条件、图文/符号转换 |
| 推理负荷 | 必要推理跳数、分类讨论、构造、反证、充要关系 |
| 计算负荷 | 运算步数、表达式复杂度、数值规模、易错变形 |
| 技巧依赖 | 非常规转换、特殊构造、模式识别、替代解法依赖 |
| 步骤深度 | rubric 必要步骤依赖图的最长路径 |

每道题必须保存一份 `QuestionDifficultyFeaturesV1`，其中的计数来自版本化 rubric 依赖图和题目结构，不在请求时临时猜测。`difficulty-rule-v1` 使用以下确定性规则：

```text
knowledgeRaw = min(max(knowledgePointCount - 1, 0), 3)
             + min(maxPrerequisiteDepth, 4)
             + min(crossTopicLinkCount, 2)
             + (hasAbstractConcept ? 2 : 0)

readingRaw = min(floor(effectiveChineseCharCount / 80), 3)
           + min(explicitConditionCount, 4)
           + min(implicitConditionCount * 2, 4)
           + min(representationTransformCount, 2)

reasoningRaw = min(requiredInferenceEdgeCount, 6)
             + min(caseBranchCount * 2, 4)
             + (requiresConstruction ? 2 : 0)
             + (requiresBidirectionalProof ? 1 : 0)

calculationRaw = min(symbolicOperationCount, 6)
               + min(errorProneTransformCount * 2, 4)
               + min(numericScaleLevel, 2)

techniqueRaw = min(nonRoutinePatternCount * 2, 6)
             + (requiresSpecialConstruction ? 2 : 0)
             + (routineMethodExceedsTimeBudget ? 2 : 0)
```

前五项 raw score 统一映射为：`0..1 -> 0`、`2..3 -> 1`、`4..5 -> 2`、`6..8 -> 3`、`>=9 -> 4`。步骤深度按 rubric 必要依赖图最长路径映射：`<=1 -> 0`、`2 -> 1`、`3 -> 2`、`4..5 -> 3`、`>=6 -> 4`。所有计数必须是非负整数；依赖图有环、必要字段缺失或题目/选项哈希不一致时，该题版本不能发布。

这些规则是可复现的内容先验，不宣称是最终统计难度。题目内容变更后生成新的 `PracticeQuestionVersion`，不得原地改变历史难度。

### 6.2 综合档位

综合内容难度由六维稳定派生：

```text
overall = round((2K + R + 2G + C + 2T + S) / 9)
```

其中 `K` 为知识负荷、`R` 为阅读负荷、`G` 为推理负荷、`C` 为计算负荷、`T` 为技巧依赖、`S` 为步骤深度。结果限制在 `0..4`。

### 6.3 自动双评与冲突处理

规则先验生成后，混合模式执行两个职责分离的结构化步骤：

1. `difficulty-assessor` 根据题目、标准解法和 rubric 独立输出六维档位、证据代码和置信度；
2. `difficulty-verifier` 在看不到第一份模型结果的条件下独立输出六维档位，并检查它们是否与可计算事实、rubric 深度和知识点层级冲突。

每个维度仅在模型档位与规则档位相差不超过 1、验证器未发现硬冲突时进入自动共识；最终取规则与模型结果的加权中位数。冲突维度保留规则先验，标记 `RULE_FALLBACK` 并降低置信度。冲突记录不进入训练候选，也不创建人工任务。

### 6.4 内容难度与实证难度

内容难度 `contentDifficulty` 和真实作答校准值 `empiricalDifficulty` 分开保存。实证难度按学生当时的对应能力值进行在线 IRT 风格更新，不能直接使用全体正确率。

默认发布门槛：至少 200 次有效首答、100 个独立参与者，并覆盖至少 3 个能力展示档位。门槛未满足时，产品只显示“内容估计难度”；满足后才显示“数据校准难度”。门槛和算法版本写入校准记录。

## 7. 单次作答事实与能力证据

### 7.1 七个能力维度

核心画像：阅读、理解、计算、技巧。
辅助画像：推理、自我纠错、表达。

七项都保存原始证据状态和档位；产品可以突出四项核心画像，但不得丢弃三个辅助维度。

### 7.2 确定事实

`AttemptFactExtractor` 至少输出：

- `ANSWER_CORRECT`、`ANSWER_PARTIALLY_CORRECT`、`ANSWER_INCORRECT`；
- 命中的 rubric 步骤 ID、缺失的必要步骤 ID；
- 可确定的矛盾、计算错误和错误标签；
- 首次提交、重复提交、自主修正、提示后修正；
- 服务端观察到的阅读和作答时长区间；
- 答案修改次数、过程修改次数、提示次数和题目返回次数；
- 客户端事件是否缺失、乱序或与服务器时间明显冲突。

行为事件和耗时属于弱证据。客户端上传的时间不得单独产生能力低分；异常数据只降低置信度。

rubric 的每个步骤必须声明：所属能力维度、是否必要、依赖步骤、可接受表达和可确定错误。rubric 还必须声明 `answerObservableDimensions`；只有被明确列入的维度，才能在学生只提交最终答案时由确定性答案产生观察，其余适用维度一律为 `INSUFFICIENT_EVIDENCE`。

### 7.3 `0..4` 证据档位

| 档位 | 单次证据含义 |
| --- | --- |
| 0 | 已产生明确相关行为，但出现基础性矛盾或完全错误 |
| 1 | 能启动相关步骤，但核心方法或计算持续错误 |
| 2 | 部分正确，依赖提示/修正，或缺少关键闭环 |
| 3 | 独立完成主要步骤，过程与结论一致 |
| 4 | 在足够难度下完成迁移、构造、替代解法或高质量自证 |

最终答案正确不能自动产生理解、推理、技巧或表达高分。没有过程时，这些维度保持 `INSUFFICIENT_EVIDENCE`。提示后完成通常最高为 2–3 档；自主修正可以产生自我纠错证据，但不删除原始错误事实。

每个维度按该维度的必要 rubric 步骤计算 `coverage`，再执行以下固定顺序：

1. 本题没有该维度步骤且不在 `answerObservableDimensions`：`NOT_APPLICABLE`；
2. 本题适用但学生没有提交可观察过程或答案事实：`INSUFFICIENT_EVIDENCE`；
3. 出现该维度的基础性矛盾且没有有效步骤：`OBSERVED/0`；
4. `coverage < 0.5`：`OBSERVED/1`；
5. `0.5 <= coverage < 1`，或缺少必要闭环：`OBSERVED/2`；
6. 必要步骤全部成立、无未解决矛盾且独立完成：`OBSERVED/3`；
7. 在对应难度至少为 3 的题目上满足第 6 条，并存在 rubric 标记的迁移、替代解法或自证扩展：`OBSERVED/4`。

提示事件分为 `NUDGE`、`STRATEGY` 和 `SOLUTION`。使用 `SOLUTION` 后相关维度最高为 2，使用 `STRATEGY` 后最高为 3，`NUDGE` 只降低置信度而不直接封顶。系统未实际提供提示内容时，不得仅凭一个按钮事件推断提示等级。

自我纠错维度只有在存在可追溯的原错误和后续修改时适用：未发生可纠正错误为 `NOT_APPLICABLE`；发生错误但没有后续有效修改为 `OBSERVED/0..1`；在不使用 `SOLUTION` 提示的情况下定位并修正为 `2..3`；还能解释错误原因并给出防错验证时为 `4`。

### 7.4 证据优先级与置信度

```text
确定性答案/计算事实
> rubric 关键步骤
> 结构化语义判断
> 修改、提示、自主纠错事件
> 耗时和页面行为
```

每个 `OBSERVED` 结果必须包含：

- `band: 0..4`；
- `confidence: 0..1`；
- `evidenceStepIds`；
- `factCodes`；
- `errorTags`；
- `assessorVersion` 和 `rubricVersion`。

状态为 `INSUFFICIENT_EVIDENCE` 或 `NOT_APPLICABLE` 时，`band` 必须为 `null`。

### 7.5 开放过程的自动双评

规则无法覆盖的解答题过程进入两个结构化步骤：

1. `evidence-assessor` 只依据题目版本、rubric 和确定事实输出候选观察；
2. `evidence-verifier` 在看不到第一份模型结果的条件下独立输出观察，再检查证据引用、事实冲突、档位越界和过度推断。

任一维度出现状态冲突、档位差超过 1、引用不存在步骤或违反确定事实时，该维度回退规则结果；规则也无足够证据时返回 `INSUFFICIENT_EVIDENCE`。模型失败不得阻止提交。

## 8. 长期能力画像

### 8.1 更新输入

`AbilityProfileUpdater` 只接收已经校验的 `OBSERVED` 证据、对应题目难度、置信度和重复权重，不读取原始答案或自由文本。

七个能力维度对应的题目挑战难度固定映射如下，避免实现者任意挑选综合难度：

| 能力维度 | 用于画像更新的题目难度 |
| --- | --- |
| 阅读 | `readingLoad` |
| 理解 | `round((2 * knowledgeLoad + reasoningLoad) / 3)` |
| 计算 | `calculationLoad` |
| 推理 | `reasoningLoad` |
| 技巧 | `techniqueDependency` |
| 自我纠错 | `overallBand` |
| 表达 | `round((reasoningLoad + stepDepth) / 2)` |

证据档位转换为表现概率：

```text
0 -> 0.05
1 -> 0.25
2 -> 0.50
3 -> 0.75
4 -> 0.95
```

题目维度档位转换为难度参数：

```text
0 -> -2
1 -> -1
2 ->  0
3 ->  1
4 ->  2
```

### 8.2 在线更新

每个参与者的每个能力维度维护 `theta`、`information`、`evidenceCount` 和算法版本：

```text
expected = sigmoid(theta - difficulty)
weight = confidence × evidenceQuality × repeatPenalty
thetaNext = clamp(theta + 0.35 × weight × (performance - expected), -3, 3)
informationNext = information + weight × expected × (1 - expected)
uncertainty = 1 / sqrt(1 + informationNext)
```

同一会话、同一题目版本的首次提交可以完整更新核心能力；后续提交只完整更新自我纠错，其他维度的 `repeatPenalty` 为 `0.25`。这样既保留纠错证据，也避免重复提交刷高画像。

`evidenceQuality` 只能取以下版本化值：确定性答案或可验证计算事实 `1.0`，完整 rubric 步骤事实 `0.95`，通过 verifier 的结构化语义证据 `0.85`，只由行为事件支持的弱证据 `0.50`。存在未解决冲突的数据不更新画像。首次提交的 `repeatPenalty` 为 `1.0`；后续提交除自我纠错外为 `0.25`，自我纠错为 `1.0`。

展示档位按 `theta` 映射：

```text
theta < -1.5       -> 0
-1.5 <= theta < -.5 -> 1
-.5 <= theta < .5   -> 2
.5 <= theta < 1.5   -> 3
theta >= 1.5        -> 4
```

### 8.3 画像成熟度

- 少于 3 条有效证据：`INSUFFICIENT`；
- 至少 3 条且覆盖 2 个题目结构族：`PROVISIONAL`；
- 至少 10 条且覆盖多个题型和难度：`STABLE`。

未达到 `PROVISIONAL` 时，UI 只显示“样本不足”和已收集证据数，不展示确定档位。

## 9. 匿名身份与账号绑定

匿名用户可以开始、保存和恢复练习。后端生成至少 256 bit 随机参与者令牌，只保存令牌哈希，不能接受客户端自定义 `userId`。

令牌按平台处理：

- Flutter 原生端通过 `Authorization: PracticeParticipant <token>` 发送，并保存在平台安全存储中；明文只在创建和轮换时返回一次；
- Flutter Web 使用后端签发的 `HttpOnly`、`SameSite=Lax` Cookie，生产环境必须带 `Secure`；前端 JavaScript 和响应正文都不能读取令牌；
- Web 跨源联调必须使用受信任 Origin、显式 credentials 和精确的 `Access-Control-Allow-Origin`，不能使用通配 Origin；
- 认证日志、错误详情和监控事件不得包含令牌或令牌哈希。

登录后，客户端携带匿名令牌调用绑定接口。后端在事务中验证当前认证用户、匿名参与者状态和目标账号状态：

- 未绑定时一次性绑定到当前账号；
- 已绑定当前账号时幂等返回成功；
- 已绑定其他账号时返回 `409 CONFLICT`；
- 绑定后原匿名令牌轮换，旧令牌失效；
- 长期画像只在账号绑定后支持跨设备聚合；匿名阶段只在当前参与者范围内更新。

生产环境不得提供通过请求头伪造用户或参与者 ID 的测试后门。

## 10. Prisma 数据模型

### `PracticeParticipant`

保存可空 `userId`、唯一 `anonymousTokenHash`、状态、绑定时间、训练授权版本和时间。`trainingConsentVersion` 默认 `null`，不能因开始练习或登录而自动授权训练。用户删除时关联练习数据按产品删除策略级联清理；账号解绑不能把数据转移给其他用户。

### `PracticePaperVersion`

保存 `paperCode`、内容版本、标题、来源类型、来源说明、发布状态、题目数、难度引擎版本和发布时间。`(paperCode, contentVersion)` 唯一。

### `PracticeQuestionVersion`

保存试卷版本、稳定题目代码、题号、题型、题干、选项 JSON、知识点 JSON、内容难度 JSON、标准答案 JSON、rubric JSON 和内容哈希。`(paperVersionId, questionCode)` 与 `(paperVersionId, number)` 唯一。

### `PracticeSession`

保存参与者、试卷版本、状态、当前题号、开始/最后活动/完成/过期时间和乐观锁版本。对 `(participantId, lastActiveAt)`、`(paperVersionId, status)` 建索引。

### `PracticeQuestionProgress`

保存会话、题目版本、当前答案、当前过程、草稿版本、首次查看时间和最近修改时间。`(sessionId, questionVersionId)` 唯一。草稿更新使用版本号避免多端覆盖。

### `PracticeEvent`

保存会话、题目版本、客户端事件 ID、事件类型、受限 payload、客户端时间和服务器接收时间。`(sessionId, clientEventId)` 唯一，按 `(sessionId, questionVersionId, receivedAt)` 查询。

### `PracticeAttempt`

保存会话、题目版本、提交序号、草稿快照、确定事实 JSON、判题结果、评分器版本、rubric 版本、授权快照和提交时间。`(sessionId, questionVersionId, attemptNumber)` 唯一，提交后不可修改。

### `PracticeAbilityObservation`

保存 attempt、能力维度、证据状态、可空档位、置信度、证据引用 JSON、事实代码 JSON、错误标签 JSON、评估器版本。`(attemptId, dimension)` 唯一。

### `PracticeAbilityProfile`

保存 participant、维度、`theta`、`information`、`uncertainty`、展示档位、成熟度、有效样本数、覆盖结构族 JSON、算法版本和更新时间。`(participantId, dimension)` 唯一。

### `PracticeDifficultyCalibration`

保存题目版本、难度维度、连续难度参数、展示档位、有效提交数、独立参与者数、能力覆盖、置信度、状态和算法版本。`(questionVersionId, dimension, algorithmVersion)` 唯一。

所有外键、删除行为、唯一约束和查询索引必须通过 Prisma migration 提交，不依赖人工修改数据库。

## 11. API 契约

### 11.1 题目与会话

- `GET /api/practice/papers/{paperCode}`：返回已发布题目、选项、知识点和学生可见的内容难度；不返回答案和 rubric。
- `POST /api/practice/sessions`：按 `paperCode` 创建或恢复活动会话。匿名创建时返回一次性参与者令牌。
- `GET /api/practice/sessions/{sessionId}`：返回会话归属范围内的进度、草稿、历史学生可见结果和画像成熟度。

### 11.2 草稿、事件和提交

- `PUT /api/practice/sessions/{sessionId}/drafts/{questionId}`：使用 `draftVersion` 乐观更新最终答案和当前过程；答案最长 4,000 字符，过程最长 20,000 字符。
- `POST /api/practice/sessions/{sessionId}/events`：单批最多 50 个事件，单事件 payload 序列化后最多 2 KB；按 `clientEventId` 去重。
- `POST /api/practice/sessions/{sessionId}/attempts`：引用服务端草稿版本创建不可变提交，返回学生可见判题和七维证据。重复 `Idempotency-Key` 返回同一结果。
- `POST /api/practice/sessions/{sessionId}/complete`：至少每题存在一次提交后完成整卷，重复调用幂等。

### 11.3 身份与画像

- `POST /api/practice/sessions/{sessionId}/bind`：将匿名参与者绑定到当前登录账号并轮换令牌。
- `GET /api/practice/ability-profile`：登录用户返回跨会话画像；匿名调用只返回当前参与者范围画像。

所有写接口使用 Zod 校验、JSON Content-Type、Origin/CORS 防护、限流、会话归属检查和 `Idempotency-Key`。错误沿用现有 `{ ok: false, error: { code, message, requestId } }` 格式。

## 12. 会话与提交状态

会话状态：`ACTIVE -> COMPLETED` 或 `ACTIVE -> EXPIRED`。完成和过期状态不再接受草稿、事件或提交；恢复接口仍可读取历史结果。

一道题允许最多 3 次正式提交。每次提交不可变，下一次提交必须基于更高的草稿版本。整卷完成要求 19 道题都至少有一次正式提交，不要求全部正确。

并发提交在数据库事务中锁定会话和题目进度；相同幂等键返回原结果，不同幂等键但相同草稿版本只有一个可以成功，另一个返回 `409 CONFLICT`。

## 13. 过程事件与可信度

允许的 V1 事件：

- `QUESTION_VIEWED`；
- `ANSWER_STARTED`；
- `ANSWER_CHANGED`；
- `REASONING_STARTED`；
- `REASONING_CHANGED`；
- `HINT_REQUESTED`；
- `QUESTION_REVISITED`；
- `ATTEMPT_SUBMITTED`。

修改事件只记录次数、长度区间和时间，不保存每次按键文本。Flutter 在内存中聚合高频修改，最多每 5 秒刷新一次，并在提交、切题和应用进入后台前尽力发送。

服务器使用接收时间建立可信时间线。客户端时间只用于排序辅助；出现未来时间、倒序、超长停留或缺失事件时标记数据质量代码并降低置信度，不直接判低分。

## 14. 评分器运行模式

后端统一接口：

```ts
interface AttemptAssessor {
  assess(input: AttemptAssessmentInput): Promise<AttemptAssessment>;
}
```

支持以下显式配置：

- `PRACTICE_ASSESSOR_MODE=rules`：只运行确定性事实和规则证据；测试环境默认；
- `PRACTICE_ASSESSOR_MODE=hybrid`：规则事实加结构化模型双评；模型不可用时回退规则；
- 后续新增 `small-model` 实现时保持同一契约。

模式、模型、提示词和规则版本写入每次提交。远程模型超时、限流、JSON 无效或冲突时，提交仍以规则结果成功落库，并返回可重放的降级代码。

## 15. 训练候选数据

`TrainingDatasetProjector` 只选择：

- 提交时存在有效训练授权；
- 题目和 rubric 版本完整；
- 确定事实无冲突；
- 双评状态一致且档位差不超过 1；
- 维度置信度达到数据集版本设定门槛；
- 自由文本经过个人信息和无关内容清洗。

训练授权必须来自当前隐私同意体系中明确包含“练习数据用于模型改进”的独立同意版本，并在提交时固化快照。本期不新增同意 UI，因此生产数据默认不具备训练授权；只有产品上线相应同意流程后的新提交才可成为训练候选。测试环境可以使用固定测试参与者验证投影逻辑，但该开关不得在生产构建中生效。

训练样本包含题目版本内容、题型、知识点、六维难度、学生最终答案和过程、受限行为事实、七维证据标签、证据引用以及所有算法版本。模型输入不包含用户 ID、参与者 ID、会话 ID、设备标识、IP、Token 或 Cookie。

为了按参与者隔离训练/验证/测试集，投影阶段使用数据集专用 HMAC 生成 `subjectGroupHash`；它只参与分组切分，不进入模型输入，且不同数据集版本使用不同密钥域。按题目结构族再次分组，防止同题改写泄漏到不同集合。

不一致样本自动进入 `REJECTED_CONFLICT`，证据不足样本可用于训练证据状态分类，但不能伪造成 `0` 档能力样本。V1 只生成候选契约和统计，不启动真实训练任务。

## 16. 数据安全与保留

- 匿名参与者令牌只保存哈希，明文只返回一次；
- 标准答案、rubric、模型提示词和内部标签不返回 Flutter；
- API 对答案、过程、事件数量和 payload 长度设置硬限制；
- 未绑定匿名会话在最后活动 30 天后删除；
- 原始过程事件保留 180 天，派生事实和画像按账号数据生命周期保存；
- 用户删除账号时，未进入冻结去标识化数据集的练习记录随账号删除；
- V1 不创建冻结训练数据集，因此本期所有训练候选都可以随授权撤回或账号删除而清除；
- 日志不记录答案全文、过程全文、匿名令牌或认证 Token；
- 数据库迁移先在测试数据库验证，不在首次部署时直接试跑生产数据。

## 17. Flutter 接入

新增：

- `RemotePracticeRepository`：实现现有 `PracticeRepository`；
- `PracticeApiClient`：统一超时、请求头、错误解码和 request ID；
- `PracticeEventRecorder`：聚合并批量刷新受限过程事件；
- `PracticeParticipantTokenStore`：按平台保存匿名参与者令牌；
- 远程 DTO 映射和学生可见结果模型。

远程模式由明确配置开启。测试/离线演示可以显式使用 Mock；远程连接失败时页面显示错误、request ID 和重试，不得自动切回 Mock，以免把本地结果误认为已保存。

练习实验室顶部显示后端连接状态、试卷版本、评分器模式和当前会话状态。内部标准答案、完整 rubric 和训练置信度不显示。

## 18. 错误与降级

- 后端不可达或超时：Flutter 保留草稿和未发送事件，显示可重试状态；
- 草稿版本冲突：先拉取服务端版本，再让当前设备显式重试，不静默覆盖；
- 重复提交：相同幂等键返回原结果；不同请求竞争同一草稿版本时返回冲突；
- 模型失败：规则结果正常落库，记录降级代码，不把失败暴露为整次提交失败；
- 数据库失败：不向客户端假报成功，客户端保留本地草稿；
- 事件缺失或异常：降低证据置信度，不阻断判题；
- 会话过期：历史可读，新提交返回 `GONE`，用户可创建新会话；
- 匿名令牌失效：返回 `UNAUTHORIZED`，不能自动创建新身份覆盖旧进度。

## 19. 测试策略

### 19.1 后端 Vitest

覆盖：

- 六维难度规则和综合公式；
- 三种证据状态与 `band` 不变量；
- 客观题规范化、rubric 步骤、提示和自主纠错；
- 模型双评一致、冲突、超时和规则回退；
- 能力更新的难题奖励、简单题错误、低置信度降权和重复题降权；
- 匿名令牌哈希、归属、轮换和账号绑定冲突；
- 草稿乐观锁、事件幂等、提交幂等、最多 3 次提交和整卷完成约束；
- API Zod 校验、Origin/CORS、限流和统一错误响应；
- 训练投影授权、去标识化、分组哈希和冲突过滤；
- Prisma migration 包含索引、唯一约束和外键策略。

### 19.2 Flutter 测试

覆盖：

- 题目、会话、结果和画像 DTO 映射；
- 匿名令牌注入与绑定后的轮换；
- 草稿防抖保存、事件批量发送和提交前刷新；
- 超时、断网、统一错误、request ID 和重试；
- 页面恢复服务端会话和 19 题进度；
- Mock/远程显式切换且远程失败不静默降级；
- 小屏、宽屏、长解答过程和加载/失败/空状态无溢出。

### 19.3 手工联调

1. 启动测试 MySQL，并应用练习 migration；
2. 启动 Next.js，使用 `rules` 模式；
3. 启动 Flutter，并配置真实 `API_BASE_URL` 和远程练习模式；
4. 匿名完成部分题目，关闭并重开页面验证恢复；
5. 提交客观题最终答案但不写过程，验证相关维度为“证据不足”；
6. 提交包含关键步骤的解答题，验证步骤引用和能力证据；
7. 制造断网后提交，验证草稿保留和恢复后重试；
8. 登录并绑定匿名会话，验证跨设备画像读取；
9. 完成 19 题，验证整卷状态和数据库记录；
10. 切换 `hybrid` 模式，验证模型成功和强制失败时的规则降级。

## 20. 实施顺序

1. 在后端先实现纯函数契约、难度引擎、事实提取器、证据引擎和能力更新器；
2. 增加 Prisma 模型、migration 和 Repository；
3. 实现身份、会话、草稿、事件、提交、完成和画像 API；
4. 接入可选结构化模型双评和规则回退；
5. 实现训练候选投影与自动过滤；
6. 在 Flutter 实现远程 Repository、事件记录器和令牌存储；
7. 接入实验室连接状态、恢复、失败重试和测试说明；
8. 运行后端单元测试、类型检查、构建、Flutter 静态检查和全量测试；
9. 提供本地启动、迁移、联调和重置测试数据的明确命令。

## 21. 验收标准

- 题目难度和人的能力证据使用独立输入、实现和数据库结果；
- 19 题内容由后端返回，响应不泄露标准答案和完整 rubric；
- 匿名用户可以创建、恢复、提交和完成练习，且身份不可伪造；
- 登录后能把匿名会话安全绑定到当前账号；
- 草稿、事件和提交持久化，重启 Flutter 后可以恢复；
- 单次证据明确区分低档、证据不足和不适用；
- 能力画像考虑题目难度、证据置信度和重复提交降权；
- 模型不可用或冲突时规则降级仍可完成提交；
- 训练候选不包含直接身份字段，冲突样本自动排除；
- 页面明确显示后端连接、会话和评分模式，可完成手工联调；
- 后端相关 Vitest、类型检查和构建通过，Flutter 相关测试和全量测试通过；
- 交付说明列出启动命令、数据库迁移、测试步骤和仍未实现的小模型训练阶段。

## 22. 已知限制

- 演示题和 rubric 仍是自造内容，只用于验证工程与评分闭环；
- 规则引擎不能证明任意数学表达式等价，也不能替代正式数学阅卷；
- 自动双评产生的是高质量银标签，不等于教师金标签；
- 实证难度在数据门槛满足前不会发布；
- 单次作答只形成证据，稳定能力画像需要跨题型、跨难度积累；
- V1 准备训练数据，不训练或部署实际小模型。
