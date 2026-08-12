# 练习评分模块 V1 交接说明

最后更新：2026-08-12

## 1. 交付结果

练习评分模块已经与预习模块分离，并在 Flutter 开发者工具中提供独立入口。V1 使用一套自造的 19 题结构演示卷跑通：

- 8 道单项选择、3 道多项选择、3 道填空和 5 道解答题；
- 分题草稿、题号切换、提交失败重试和整卷完成约束；
- 客观答案规范化、填空文本规范化和 rubric 关键步骤匹配；
- 阅读、理解、计算、推理、技巧、自我纠错、表达七类单次作答证据；
- 明确区分“能力较低”“过程证据不足”和“本题不适用”；
- 去标识化的 `TrainingExampleV1` 小模型训练数据结构。

V1 是本地技术闭环，不包含正式题库、服务器持久化、远程大模型评分或已训练的小模型权重。

## 2. 访问方式

开发环境运行应用后进入：

`首页 → 开发者工具 → 练习评分实验室`

开发者工具由 `ENABLE_DEVELOPER_TOOLS=true` 控制，生产环境不会显示入口。

## 3. 内容边界

当前 `cn-gaokao-2026-new-i-math-v1` 只复刻 2026 新高考 I 卷数学的 19 题题型结构。全部题干均为项目自造的流程演示内容，页面顶部明确显示：

> 19 道自造演示题，仅用于验证练习评分流程，不是官方试题。

正式接入试卷时必须从获得使用权限的内容源导入，并保存内容版本、来源标识、摘要哈希和授权状态。不得用第三方回忆版替换当前演示题并标记为官方内容。

## 4. 代码边界

模块入口：`lib/features/practice_assessment/practice_assessment.dart`

- `core/practice_models.dart`：试卷、题目、rubric、草稿、事实、判题、能力证据和训练样本；
- `core/practice_ports.dart`：数据存储与评分器的可替换端口；
- `core/rule_based_attempt_assessor.dart`：V1 确定性判题与保守能力证据；
- `core/ability_profile_aggregator.dart`：只聚合已经观察到的证据；
- `adapters/mock_gaokao_math_repository.dart`：19 题自造目录与内存提交；
- `application/practice_session_controller.dart`：异步加载、草稿、导航、提交、重试和完成；
- `presentation/practice_assessment_lab_page.dart`：练习评分实验室页面。

练习目录没有引用 `features/dialogue_exploration`。预习结果后续只能通过公开、版本化的 DTO 传入；练习模块不能读取或修改预习 Controller、Widget、Redis 快照或 Repository 内部类型。

## 5. 正式后端替换点

### `PracticeRepository`

当前实现：`MockGaokaoMathRepository`

正式实现需要负责：

- 根据认证身份创建和恢复练习会话；
- 读取获得授权的试卷和题目版本；
- 幂等保存草稿、事实事件和不可变提交；
- 调用服务端判题与评估流水线；
- 返回不包含标准答案、完整 rubric 和内部置信度的学生可见结果。

Flutter Controller 只依赖 `PracticeRepository`。正式 API 可以扩充仓储契约，但不要把 HTTP JSON 解析放入页面或 Controller。

### `AttemptAssessor`

当前实现：`RuleBasedAttemptAssessor`

后续可以在服务端替换为结构化大模型评分器、离线验证过的小模型评分器，或“规则优先、小模型处理高置信度样本、低置信度回退大模型”的组合评分器。所有实现必须返回同一 `AttemptAssessment` 契约，并校验证据步骤引用、等级范围、错误标签和确定事实之间的冲突。

## 6. V1 规则评分边界

V1 可以确定：

- 单选和多选答案，忽略大小写、分隔符和多选顺序；
- 填空文本的首尾/内部空白和部分全角标点规范化；
- 学生过程是否命中题目 rubric 中配置的关键步骤；
- 提示后完成、自主修改后答对等事实标签。

V1 不会宣称：

- 两个任意数学表达式在代数意义上等价；
- 关键词命中等价于完整数学证明正确；
- 单次作答能够决定学生长期能力；
- 自动银标签等价于人工教师金标签。

因此，只有最终答案而没有过程时，系统会正常判题，但理解、推理和技巧保持“过程证据不足”。

## 7. 小模型训练路径

`TrainingExampleV1` 包含题目与题型、学生答案和分步推理、提示/提交/用时/修改事实、七个维度的证据状态与等级，以及 assessor/rubric 版本；它明确排除用户身份、会话 ID、设备标识、IP、Token、Cookie 和无关自由对话。

在正式训练前，建议依次完成：

1. 服务端个人信息清洗和敏感文本拦截；
2. 删除规则事实互相冲突的样本；
3. 使用两次独立强模型评分，仅保留一致的高置信度银标签；
4. 按学生和题目结构族隔离训练集、验证集和测试集，避免泄漏；
5. 在冻结测试集上评估有序分类、证据状态识别和置信度校准；
6. 使用中文数学能力较好的 1B–4B 基座，以 QLoRA 做监督微调；
7. 小模型只接管高置信度样本，低置信度输出“证据不足”或回退远程评分器。

第一版不追求让小模型直接从整段答案生成一个总分，而是训练两个结构化任务：先判断每个能力维度是否有足够证据，再对“已观察”维度预测 `0..4` 的有序等级。题目难度继续作为独立输入和独立模型，避免把“题难”错误归因为“人弱”。

## 8. 数据与安全

V1 没有新增数据库、缓存、远程接口或密钥。所有作答只保存在当前页面 Controller 和内存 Repository 中，退出页面即丢失。

客户端当前能看到演示题 rubric，是因为 V1 完全离线。正式接入后，完整标准答案、rubric、模型配置、训练标签和内部置信度必须只保存在服务端。

## 9. 验证命令

```powershell
dart analyze lib/main.dart lib/developer_tools.dart lib/features/practice_assessment test/features/practice_assessment test/widget_test.dart
flutter test test/features/practice_assessment test/widget_test.dart test/developer_tools_web_test.dart
rg -n "dialogue_exploration" lib/features/practice_assessment test/features/practice_assessment
git diff --check HEAD
```

## 10. 下一阶段建议

1. 在正式后端仓库创建练习评分领域模块和数据库迁移；
2. 接入具有明确授权的 19 题内容与分问 rubric；
3. 把 Flutter Mock Repository 替换为具有超时、错误映射和身份边界的 HTTP Repository；
4. 上线结构化大模型银标任务与自动质检；
5. 积累真实过程作答后训练第一个小模型；
6. 增加同结构变式题、能力画像驱动选题和复习调度。
