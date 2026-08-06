# 1.2 Learning Entry 与实时知识树设计

状态：已确认，等待实现
日期：2026-08-06

## 1. 目标

在现有 1.2 对话式发散提问能力前增加独立的 `Learning Entry`，解决学生面对陌生知识点时不知道如何提问的问题。进入探索课堂后采用已经确认的 A+C 交互：桌面端左侧为 ChatGPT 式连续对话，右侧常驻实时知识树；点击树节点只查看当时上下文，必须明确选择继续、开支线或回溯才改变会话。

本阶段只 Mock 1.1 知识库数据。AI 回答、教学策略调度、反问评估、素材调度、会话保存/恢复、分支/回溯、总结、记忆候选和导出全部使用正式后端链路。

## 2. 三层产品结构

```text
章节/知识点
  ↓
Learning Entry
  - 核心问题
  - 知识地图
  - 三个可选探索方向
  - 自由问题输入
  - 预计探索时间
  ↓
AI 探索课堂
  - 左侧连续对话
  - 右侧常驻知识树
  - 回答、原理型反问和可交互素材
  ↓
学习产出
  - 保存/恢复、总结、记忆候选、思维树导出
```

Learning Entry 只负责认知导航和激发问题，不提前讲解课程。学生从问题库或自由问题入口进入时可以跳过章节卡片，直接创建 Session。

## 3. Learning Entry

入口数据由后端 `KnowledgeProvider` 提供，Flutter 不写死章节内容。当前 `MockKnowledgeProvider` 返回负负得正、二次函数、不等式证明和咖啡店商业模型四套数据；以后接入 1.1 时只替换 Provider。

```text
GET /api/learning-entries?atomId={atomId}
```

返回标题、核心问题、预计时间、推荐方向以及三个可选方向。每个方向包含稳定 ID、标题、说明和钩子问题。

点击开始探索时，根问题优先级为：

1. 学生自由输入的问题；
2. 学生选择方向的钩子问题；
3. 系统推荐方向的钩子问题。

随后调用创建会话接口，并立即由真实 AI 生成第一轮 `QUESTION_CHAIN`。

## 4. 探索课堂布局

### 桌面端

- 左侧为连续对话讲台，显示学生问题、AI 回答、原理型反问与就地素材。
- 右侧知识树始终可见，显示学生提出的真实问题及分支关系。
- 当前节点、错误节点、已回溯节点和支线使用不同但不依赖颜色的状态标记。

### 手机端

- 对话仍为主区域。
- 顶部常驻当前根到叶的节点路径，可横向浏览。
- 点击路径或“完整知识树”后展开全树；知识树不能完全隐藏为仅在菜单中可发现的功能。

## 5. 节点交互

每个知识树主节点以学生问题作为标题，内部关联 AI 回答、反问、策略、素材、理解证据和创建时间。

点击节点时只执行读取操作：左侧对话切换为该节点当时的根到节点路径，并显示四个显式动作：

- `从这里继续`：把该节点设为活动节点，下一问题沿原分支向下生长；
- `新开支线`：下一问题以该节点为父节点创建新分支；
- `回溯到这里`：记录回溯事件并恢复该节点，不删除错误路径；
- `转为记忆候选`：幂等创建 M2 待接收候选。

单击节点不得自动创建空分支或修改服务端当前节点。

## 6. AI 与知识调度

`Teaching Engine` 自动选择 `QUESTION_CHAIN`、`SOCRATIC`、`ERROR_TRACKING`、`ANALOGY_TRANSFER` 或 `SELF_EXPLANATION`。DeepSeek 返回结构化回答、反问、误区和候选素材 ID。

反问按原理指向、上下文关联、探索价值、难度匹配和可回答性五维评分，总分至少 18/25。低分最多重新生成两次，仍不合格时使用服务端确定性模板。独立的“你觉得呢”等空反问不通过。

素材只能从当前 Mock 原子及关系边允许集合中选取，每轮最多两个；交互素材必须真实可操作。AI 只提出素材候选，服务端负责最终白名单过滤。

## 7. Session API

```text
POST /api/learning-sessions
GET  /api/learning-sessions/{id}
POST /api/learning-sessions/{id}/turns
POST /api/learning-sessions/{id}/branches
POST /api/learning-sessions/{id}/backtracks
POST /api/learning-sessions/{id}/complete
POST /api/learning-sessions/{id}/memory-candidates
GET  /api/learning-sessions/{id}/export
```

所有写接口使用现有身份鉴权、归属校验、Zod、限流、短锁与 `Idempotency-Key`。客户端不提交 user ID，也不生成正式节点 ID。单棵树最多 20 个节点、深度 5、单节点三个直接分支，会话学习时长 10 分钟。

由于单树最多 20 个节点，创建、继续、分支、回溯和完成接口统一返回包含 `revision` 的完整服务端树快照。Flutter 原子替换快照，不在本地猜测合并结果；App 与 Web 同账号可恢复同一 Session。

## 8. 数据与产出

MySQL 保存 `LearningSession`、`ThinkingNode`、`MaterialUsage`、`QuestionEvaluation`、`LearningSummary`、`MemoryCandidate`、`MasteryEvidence` 和 `InterestEvidence`。Redis 仅保存 15 分钟运行态、短锁和幂等结果；MySQL 是事实源。

完成时学生必须提交自己的复述。后端生成完整问题树、主/支线路径、错误与回溯、理解证据、未解决问题、兴趣方向、复习建议和版本化 JSON 导出。记忆候选状态为 `PENDING`，页面不得宣称已经进入 2.2 正式复习队列。

## 9. 异常处理

- DeepSeek 超时、无效 JSON 或低质量反问：受控重试后使用安全兜底，不丢失学生输入。
- Redis 不可用：从 MySQL 重建运行态；数据库失败时不得假报成功。
- 网络重试：复用同一个幂等键，不创建重复节点。
- App/Web 并发：使用会话 revision 和服务端短锁，冲突时刷新最新树。
- 未知或越界素材：过滤并记录，不渲染静态“交互”占位。
- 远程服务失败：Flutter 显示重试，不静默切换本地 Mock。

## 10. 验收

- Learning Entry 可展示知识地图、方向和自由问题，并创建真实 Session。
- 桌面端对话与知识树同时可见；手机端当前节点路径始终可见。
- 学生每次提问后，AI 真正回答、反问和调度 Mock 知识素材，树实时增长。
- 点击旧节点只查看；明确操作后才能继续、开支线或回溯。
- 会话刷新后可恢复，错误路径不丢失，App/Web 可读取同一服务端树。
- 会话可完成、生成学习总结、创建记忆候选并导出版本化思维树 JSON。
- 除知识库与首批内容外，无关键链路使用仅存于 Flutter 内存的 Mock。
