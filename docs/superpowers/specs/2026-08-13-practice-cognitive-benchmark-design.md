# 练习认知判断 Benchmark V1 设计

**状态：** 已批准，进入第一版实现
**日期：** 2026-08-13
**实施位置：** UniPrism 后端管理端
**首批内容：** 2026 新高考一卷数学结构演示卷，19 道项目自造题

## 1. 目标

第一版不是普通做题页面，而是一套供开发人员和产品负责人审查底层判断的基准系统。它必须回答四个问题：

1. 系统认为一道题难在哪里，是否与独立人工基准一致？
2. 面对相同题目的不同作答行为，系统提取了哪些事实和能力证据？
3. 连续完成多题后，长期能力画像的方向是否合理？
4. 某个案例失败时，问题发生在判题、事实提取、证据判断还是画像更新？

Gold 是独立的尺子，生产 Engine 是被测对象。禁止从题目种子数据或 Engine 输出复制 Gold，禁止为让测试变绿而修改 Gold。

## 2. 第一版范围与非目标

### 2.1 本期交付

- 定义 `cognition-v2` 七个认知主维和原子能力族。
- 为 19 道演示题建立独立、版本化、只读的题目难度 Gold。
- 建立 19 题 × 10 种行为的 190 个行为基准案例。
- 建立 12 条虚拟学生长期作答轨迹。
- 实现可重复运行的 Benchmark Runner、Comparator 和指标汇总。
- 实现管理员专用 `/admin/practice-benchmark` 调试页面和 API。
- 支持在浏览器中构造一次性自定义行为场景，查看完整流水线结果，但不写数据库、不修改 Gold。
- 保留结果的算法版本、Gold 版本和运行时间，便于后续版本比较。

### 2.2 本期不做

- 不把 `cognition-v2` 自动切换为学生端正式画像算法。
- 不声称 19 道自造题是 2026 官方高考试题。
- 不训练小模型；本期先建立可信标注协议、训练数据契约和评测闭环。
- 不在没有真实学习结果信号时声称课程顺序已经“全局最优”。
- 不允许管理端在线编辑或覆盖 Gold。

## 3. 三轴认知建模

一道题和一次作答必须分别描述，不能把“学生答错”反向解释为“题目很难”。系统采用三条正交轴。

### 3.1 内容与知识轴

- 学科、模块、知识点（KC）和先修关系。
- 题型、结构族、表示形式。
- 必要步骤和步骤依赖图。
- 常见错误类型和边界条件。

### 3.2 七个认知主维

| 代码 | 主维 | 原子能力族 | 局部难度来源 |
|---|---|---|---|
| READ | 审题 | 符号认读、显性条件提取、隐含条件识别、目标识别、干扰排除、多问依赖 | 条件隐蔽、信息密度、干扰强度 |
| COMP | 理解 | 定义理解、概念边界、定理前提、关系辨析、反例识别、等价性理解 | 抽象程度、边界情形、相近误解竞争 |
| REPR | 表征 | 文字转符号、图表读取、数形转换、坐标化、主动构图、多表征一致性 | 转换次数、表征距离、是否自行构造 |
| STRAT | 策略 | 题型辨认、方法选择、模型建立、问题分解、辅助构造、分类规划 | 线索显著度、方法新颖度、策略分支数 |
| CALC | 执行 | 代数变形、方程不等式、函数导数、向量、概率、参数运算、估算 | 运算链长度、参数化、精度、符号复杂度 |
| PROOF | 推理 | 演绎、归纳类比、充分必要性、分类完备性、构造、反证、规范论证 | 推理深度、分支、前提合法性、闭环程度 |
| CHECK | 检验 | 定义域、符号范围、端点、空集、特殊值、回代、数量级、答案格式 | 边界数量和隐蔽程度 |

每个维度的单次判断必须是三态之一：`OBSERVED`、`INSUFFICIENT_EVIDENCE`、`NOT_APPLICABLE`。只有 `OBSERVED` 可以带 `0..4` 档位；另外两种状态的档位必须为 `null`。

### 3.3 可观察行为证据轴

- 最终答案和判题结果。
- 解题过程与命中的必要步骤。
- 答案/过程修改次数和顺序。
- 提示等级、提示发生时间和提示前后的变化。
- 同题重试、跨题迁移和结构族覆盖。
- 时间线质量；时间线缺失或损坏时必须降低置信度，不能编造独立纠错。

动机、自我效能、焦虑等非认知因素不从单题行为中推断。旧 V1 的 `SELF_CORRECTION` 在 V2 中主要进入 CHECK 的行为证据，旧 `EXPRESSION` 作为证据质量或公开反馈，不再作为顶层认知主维；旧 `TECHNIQUE` 映射到 STRAT，新增 REPR。

## 4. 版本与线上隔离

- 新算法版本为 `cognition-rule-v2`，画像版本为 `ability-profile-v2`，Gold 版本为 `gold-v1`。
- V2 类型、规则和 Benchmark 放在独立命名空间，不修改 V1 的公开接口、数据库画像或 Flutter 契约。
- 历史 V1 证据保持不可变，不把旧七维数据直接重解释成 V2。
- 管理端可同时显示 V2 Benchmark 结果和算法版本；未来切换线上评分必须另做数据迁移、灰度和回滚设计。

## 5. Gold 数据设计

Gold 存放于后端代码库：

```text
data/practice-benchmark/gold-v1/
  manifest.json
  question-difficulty-gold.json
  attempt-cases-gold.json
  student-trajectories-gold.json
```

### 5.1 Manifest

记录 Gold 版本、适用卷、内容版本、标注协议版本、案例数量、维度定义和来源声明。Loader 必须校验：

- 题目数恰好为 19。
- 行为案例数恰好为 190，并且每题恰好覆盖 10 个行为类别。
- 案例 ID、题目 ID、轨迹 ID 唯一。
- 所有步骤 ID 都能在题目 rubric 中找到。
- `INSUFFICIENT_EVIDENCE`/`NOT_APPLICABLE` 的期望档位为 `null`。
- Gold 不包含由生产 Engine 生成的 provenance。

### 5.2 题目难度 Gold

题目难度仍使用六维 `0..4`：

- knowledgeLoad
- readingLoad
- reasoningLoad
- calculationLoad
- techniqueDependency
- stepDepth

每个维度同时保存简短人工标注理由。Gold 不读取 `demoCatalog.question.difficulty`；Runner 单独调用生产 `calculateQuestionDifficulty(question.difficultyFeatures)` 得到 Actual 后比较。

第一版因此验证“结构化特征 → 六维难度”的规则和题目特征标注，不宣称已经实现“原始题面文本 → 结构化特征”的小模型。后者是后续独立模型任务。

### 5.3 190 个行为基准案例

每道题覆盖以下 10 类行为：

1. 正确、无过程。
2. 正确、完整过程。
3. 错误、无过程。
4. 部分过程、最终错误。
5. 首次错误后独立改对。
6. 首次错误后经轻提示改对。
7. 首次错误后经答案级提示改对。
8. 完整过程但存在计算失误。
9. 答案正确但过程包含概念矛盾。
10. 同题重复正确，用于验证重复证据衰减。

一个案例包含：

- 静态输入：题目 ID、答案、过程、尝试次数、前次结果、提示、修改和时间线质量。
- 期望判题：`CORRECT`、`PARTIALLY_CORRECT` 或 `INCORRECT`。
- 期望事实：必须包含/不得包含的 fact code、命中/缺失步骤。
- 期望认知证据：七维状态、允许档位范围、是否允许更新画像。
- 期望画像变化：每个维度 `UP`、`DOWN`、`UNCHANGED`，以及 evidenceCount 增量。

Gold 为可读的显式案例数据。允许使用不导入生产 Engine 的离线标注脚本帮助减少重复录入，但被提交的 190 条期望值必须完整展开、可代码审查，运行时不能动态生成 Gold。

## 6. 虚拟学生长期轨迹

第一版包含 12 个虚拟学生原型，每条轨迹使用 5～10 次作答，并跨越多个结构族：

1. 均衡熟练型。
2. 概念强、计算弱。
3. 计算强、概念弱。
4. 审题弱。
5. 表征转换弱。
6. 题型识别强、策略迁移弱。
7. 推理完整、计算粗心。
8. 过程正确、表达证据弱。
9. 检验与独立纠错强。
10. 提示依赖型。
11. 简单题稳定、难题崩溃型。
12. 同题记忆强、跨题迁移弱。

轨迹 Gold 不要求精确浮点 theta，而要求：最终维度状态、允许档位范围、成熟度、证据数范围、变化方向和结构族覆盖。这样可以发现明显错误，同时避免把当前权重常数固化成无法迭代的答案。

## 7. Benchmark 运行管线

```text
Versioned Gold
      │
      ▼
Gold Loader ── schema / invariant validation
      │
      ├── Question Difficulty Engine ── Actual difficulty
      │
      └── Attempt replay
             ├── Judge / Fact Extractor
             ├── Cognition Evidence Engine V2
             └── Ability Profile Updater V2
      │
      ▼
Comparator ── stage-aware deviations
      │
      ▼
Metrics / Admin Debug DTO
```

Runner 是纯内存、确定性的：相同的 Gold、catalog 和算法版本必须得到相同结果，不访问网络，不写数据库。若判题阶段失败，下游证据和画像偏差标记为 `BLOCKED_BY_UPSTREAM`，不能把一个根因重复统计为多层失败。

自定义场景 Runner 使用同一生产 V2 Engine，但只接受受限字段和已存在题目 ID；返回一次性结果，不持久化学生原文。输入长度、枚举和数值范围由 Zod 严格校验。

## 8. 比较规则与质量门槛

### 8.1 硬性不变量（必须 100%）

- 证据不足和不适用永远不显示 0 档，必须为 `null`。
- 正确但无过程不能凭空证明 COMP、REPR、STRAT 或 PROOF。
- 错误但无过程不能把所有能力判为低。
- 独立纠错和提示后改对应产生不同 CHECK 证据。
- Gold 引用的步骤必须存在。
- 同一案例重放结果确定且幂等。
- 同题重复证据不能无限放大画像。

### 8.2 第一版质量目标

- 难度六维 MAE ≤ 0.75。
- 难度六维误差在 ±1 内的比例 ≥ 95%。
- 判题 outcome 一致率 = 100%。
- 七维 evidence status 一致率 ≥ 95%。
- 已观察维度落入 Gold 档位区间的比例 ≥ 90%。
- 长期画像变化方向一致率 ≥ 95%。

质量目标失败时页面明确显示红色基线失败。不能通过运行参数降低门槛，也不能自动修改 Gold。

## 9. 管理端 API 与页面

### 9.1 权限与接口

所有接口使用现有管理员会话校验，非管理员返回 401/403：

- `GET /api/admin/practice-benchmark`：返回 manifest、汇总指标、题目结果、行为案例结果和轨迹结果。
- `POST /api/admin/practice-benchmark/scenarios`：运行一次性自定义场景。

GET 结果可在进程内按 `goldVersion + algorithmVersion + catalog contentVersion` 缓存；代码热更新或键变化后自然失效。POST 不缓存、不落库。

### 9.2 页面结构

管理端新增“能力判断测试台”入口，页面路由 `/admin/practice-benchmark`，包括：

- 总览：硬性不变量、质量门槛、通过率、版本和运行时间。
- 题目难度：19 题表格，展示 Gold、Actual、每维偏差和标注理由。
- 行为案例：可按题号、行为类型、阶段、通过状态过滤 190 个案例；展开后显示输入、判题、事实、七维证据和画像变化。
- 自定义场景：选择题目，填写答案/过程/提示/修改行为，立即查看流水线输出。
- 长期轨迹：查看 12 个虚拟学生的逐题画像变化和最终 Gold 对比。

页面默认只展示安全、可审查的开发数据。自定义输入不进入日志，API 不返回密钥、数据库身份或真实学生数据。

## 10. 错误处理

- Gold 文件缺失、JSON 无效或交叉引用错误：Benchmark 返回配置错误，页面不显示误导性部分通过率。
- 单案例 Engine 异常：记录该案例和阶段，继续运行其他案例。
- 自定义场景输入非法：返回 400 和字段级错误。
- 权限不足：返回 401/403，不执行 Runner。
- 前端请求失败：保留上次成功结果并展示错误；手动重试不产生任何数据写入。

## 11. 测试策略

- Schema/Loader 测试：数量、唯一性、跨引用、三态/null 不变量、Gold 独立性。
- Question Comparator 测试：MAE、±1 命中率、逐维偏差。
- Attempt Runner 测试：10 个行为类别和上游阻断语义。
- V2 Evidence Engine 测试：尤其是无过程、错误无过程、独立纠错、提示纠错、概念矛盾和不适用。
- Profile V2 测试：证据不足零更新、重复衰减、跨结构族成熟度、轨迹方向。
- Admin API 测试：管理员成功、匿名 401、普通用户 403、非法场景 400、无持久化副作用。
- Admin 页面测试：入口、五个工作区、失败状态、过滤器和自定义调试交互。
- 最终验证：定向 Vitest、TypeScript typecheck、Next.js build，以及浏览器手工冒烟。

## 12. 小模型、Autoresearch 与课程学习的后续接口

第一版的 Gold 和 Runner 是后续训练小模型的前提，不是模型本身。后续阶段按以下边界推进：

1. **题目特征模型：** 输入原始题面，输出知识轴、原子能力 Q-matrix 和六维难度；在 Gold 上评测，不能读取答案标签泄漏。
2. **作答证据模型：** 输入匿名化作答与 rubric，输出事实和七维证据；硬性不变量在模型前后都由规则守卫。
3. **Autoresearch：** 允许搜索特征、规则权重、训练数据比例和课程排序策略；固定 Gold、测试切分和门槛不可被实验修改。
4. **课程学习：** 冷启动先用先修 DAG、知识覆盖、认知负荷渐进和间隔重复产生可解释顺序。没有任何学生反馈时只能得到专家先验顺序，不能验证个体最优。
5. **低干扰校准：** 未来使用答题正确性、用时、提示、迁移题和遗忘后的再测作为自然行为信号，不要求学生额外填写主观问卷。

## 13. 研究依据与适用边界

- National Academies 的 *Adding It Up* 将数学能力拆为概念理解、程序流畅、策略能力、适应性推理和积极倾向，为 COMP、CALC、STRAT、PROOF 的区分提供依据：[National Academies](https://nap.nationalacademies.org/catalog/9822/adding-it-up-helping-children-learn-mathematics)。
- OECD PISA 2022 数学框架强调 formulate、employ、interpret/evaluate 以及推理与表征过程，支持 READ/REPR/STRAT/CHECK 的过程化建模：[OECD PISA Mathematics Framework](https://pisa2022-maths.oecd.org/ca/index.html)。
- TIMSS 数学框架使用 knowing、applying、reasoning 认知域，说明内容域与认知过程域应分开表达：[TIMSS 2023 Mathematics Framework](https://timssandpirls.bc.edu/timss2023/frameworks/chapter-1-mathematics-framework/)。
- Q-matrix 的专家标注需要再做经验验证，不能把第一版人工映射视为永久真值：[de la Torre, 2008](https://doi.org/10.1177/0146621607300286)。
- Curriculum Learning 说明由易到难的样本组织可改善机器学习训练，但不能直接证明某个学生课程顺序最优：[Bengio et al., 2009](https://doi.org/10.1145/1553374.1553380)。
- Knowledge Tracing 依赖学习者与课程的交互序列；完全无反馈时无法可靠估计个体知识状态：[Piech et al., 2015](https://arxiv.org/abs/1506.05908)。

## 14. 验收定义

第一版完成的条件是：管理员能打开页面、看到独立 Gold 与真实 V2 Engine 的逐层比较、筛选并展开 190 个行为案例、运行自定义场景、查看 12 条长期轨迹；所有硬性不变量测试通过，定向测试、类型检查和构建通过。若质量目标尚未达到，第一版仍可交付为“可测的红色基线”，但必须如实显示失败，不得宣称判断准确或切换线上算法。
