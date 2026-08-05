# 1.2 对话探索、2.2 闪卡与 2.3 FSRS Mock 首版设计

状态：用户已确认功能范围与 Mock-first 方向，待书面设计复核

日期：2026-08-05

关联总设计：`docs/superpowers/specs/2026-08-05-teaching-assistant-student-implementation-design.md`

## 1. 目标

在正式教研知识库尚未交付前，用少量、可审计的 Mock 数据完成一条真实可操作的学习闭环：

```text
Mock 原子入口 / 问题库 / 自由输入
→ 1.2 对话式发散与树形分支
→ 勾选对话节点生成记忆项
→ 2.2 多类型闪卡作答
→ 2.3 FSRS 更新记忆状态与到期时间
→ 模拟时间后再次进入复习
```

首版验证的是领域模型、交互、状态机、调度和跨功能数据流，不验证正式知识内容规模、AI 教学质量或生产数据库能力。

## 2. 范围边界

### 2.1 本期实现

- 1.2 的 Mock 原子入口、问题库入口、自由输入、问题脚手架、输入边界、Mock 回答、显式分支、提问树、素材卡、复述收口、保存、导出和转记忆项；
- 1.2 的“二次函数”学习样例和“business model”公开演示样例；
- 2.2 的七类卡片协议、图卡分诊、助记限制、题面、作答、反馈、提示、15 秒时长观测和升降级所需事件；
- 2.3 的真实 FSRS 调度、D/S/R 投影、R0–R5 阶梯、urgency、目标成功率监控、新项引入上限、复习组配方和积压处理；
- 2.3 与 M3 能力事件、M3 选题优先级和 H.1 推荐出口的 Mock 边界；
- 可注入时间、可重复的 Mock 数据和进程内状态；
- 开发者工具中的独立测试入口；
- Flutter 单元测试、Widget 测试和完整闭环测试。

### 2.2 本期预留但不接正式能力

- 1.1 知识库：以 `LearningContentRepository` 替代，Mock 实现提供原子、边、问题和素材；
- 对话模型：以 `LearningDialogueGateway` 替代，Mock 实现按问题意图返回确定性回答；
- 3.3 白板：以 `WhiteboardLauncher` 替代，Mock 实现打开可交互测试面板；
- 正式持久化：以 `LearningStateRepository` 替代，Mock 实现只在当前测试会话内保存；
- 正式音频：以 `AudioPromptPlayer` 替代，Mock 实现模拟播放状态和结束回调；
- 后端事件上传：以 `LearningEventSink` 替代，Mock 实现保存本地事件并提供调试查看。
- M3 能力更新：以 `AbilityEvidenceSink` 替代，只记录符合条件的 R4/R5 证据，不计算正式能力分；
- M3 遗忘优先级：以 `PracticePrioritySink` 替代，只记录低稳定度原子的优先级信号；
- H.1 推荐回流：以 `ReviewRecommendationSink` 替代，只记录下一组建议，不接正式首页。

“预留”必须有明确接口、调用点、失败语义和测试替身，不能只留注释或空按钮。

### 2.3 本期不实现

- 正式 AI 调用、向量检索、问题自动入库和 Skill 服务；
- 正式教研管理后台、内容审核和版权流水线；
- 跨启动、跨设备或多用户数据恢复；
- 真实白板 DSL、语音识别和手写识别；
- M3 能力分、题目难度和段位；
- H 正式首页、推送和教师任务；
- 学生自建卡的班级分享与公共审核；首版只保留 `SharedMemoryCardPublisher` 契约说明，不显示不可用入口。

## 3. 方案选择

采用“领域接口 + 进程内 Mock 实现”。不采用纯硬编码页面，也不在知识库契约缺失时提前建设正式后端。

该方案保证：

1. 页面和业务逻辑不读取 Mock 常量；
2. Mock 与未来 API 实现遵循同一接口；
3. FSRS 和调度行为是真实的，不用固定日期假装算法；
4. 测试可以控制时间、失败、延迟和空数据；
5. 正式接入时只替换 Repository/Gateway，不重写 Widget。

## 4. 现有代码复用与隔离

### 4.1 复用

- 复用现有 Material 3 主题、响应式间距和错误提示风格；
- 参考 `AgentExperiencePage` 的对话布局和来源卡片，但不复用其专业咨询领域状态；
- 参考知识森林的树形模型与 `reactive_mind_map` 适配方式；
- 复用 `DeveloperToolsPage` 作为测试入口容器；
- 延续项目现有 `ChangeNotifier`、构造器注入和 Widget 测试模式。

### 4.2 隔离

- 不把 `MindMapData` 放入学习领域模型；
- 不把正式 Agent 消息直接当作学习对话节点；
- 不复用进程内 `KnowledgeForestStore` 保存正式记忆项；
- 不继续向 `main.dart` 增加大段页面或业务逻辑；
- 不让页面直接依赖 `fsrs` 包类型。

## 5. 建议文件边界

```text
lib/features/learning_lab/
├─ learning_lab.dart
├─ learning_lab_dependencies.dart
├─ models/
│  ├─ learning_atom.dart
│  ├─ learning_material.dart
│  ├─ dialogue_models.dart
│  ├─ memory_item.dart
│  ├─ memory_state.dart
│  ├─ review_models.dart
│  └─ learning_event.dart
├─ repositories/
│  ├─ learning_content_repository.dart
│  ├─ learning_state_repository.dart
│  ├─ mock_learning_content_repository.dart
│  └─ in_memory_learning_state_repository.dart
├─ dialogue/
│  ├─ learning_dialogue_gateway.dart
│  ├─ mock_learning_dialogue_gateway.dart
│  ├─ dialogue_exploration_controller.dart
│  ├─ dialogue_exploration_page.dart
│  ├─ dialogue_tree_adapter.dart
│  └─ widgets/
├─ flashcards/
│  ├─ flashcard_controller.dart
│  ├─ flashcard_page.dart
│  ├─ answer_evaluator.dart
│  └─ widgets/
├─ review/
│  ├─ fsrs_adapter.dart
│  ├─ review_scheduler.dart
│  ├─ review_session_composer.dart
│  ├─ review_landing_page.dart
│  └─ review_session_page.dart
├─ integrations/
│  ├─ whiteboard_launcher.dart
│  ├─ mock_whiteboard_launcher.dart
│  ├─ audio_prompt_player.dart
│  ├─ mock_audio_prompt_player.dart
│  ├─ ability_evidence_sink.dart
│  ├─ practice_priority_sink.dart
│  └─ review_recommendation_sink.dart
└─ mock/
   ├─ quadratic_function_mock_data.dart
   └─ business_model_mock_data.dart

test/features/learning_lab/
├─ mock_repository_test.dart
├─ dialogue_controller_test.dart
├─ dialogue_page_test.dart
├─ memory_conversion_test.dart
├─ flashcard_controller_test.dart
├─ flashcard_widgets_test.dart
├─ fsrs_adapter_test.dart
├─ review_session_composer_test.dart
├─ review_pages_test.dart
└─ learning_loop_test.dart
```

`lib/main.dart` 只新增 import/route；`lib/developer_tools.dart` 只新增一个测试入口卡片。

## 6. 依赖容器

`LearningLabDependencies` 在进入测试实验室时创建一次，并由所有子页面共享：

```dart
final class LearningLabDependencies {
  const LearningLabDependencies({
    required this.contentRepository,
    required this.stateRepository,
    required this.dialogueGateway,
    required this.reviewScheduler,
    required this.eventSink,
    required this.whiteboardLauncher,
    required this.audioPromptPlayer,
    required this.abilityEvidenceSink,
    required this.practicePrioritySink,
    required this.reviewRecommendationSink,
    required this.clock,
  });

  final LearningContentRepository contentRepository;
  final LearningStateRepository stateRepository;
  final LearningDialogueGateway dialogueGateway;
  final ReviewScheduler reviewScheduler;
  final LearningEventSink eventSink;
  final WhiteboardLauncher whiteboardLauncher;
  final AudioPromptPlayer audioPromptPlayer;
  final AbilityEvidenceSink abilityEvidenceSink;
  final PracticePrioritySink practicePrioritySink;
  final ReviewRecommendationSink reviewRecommendationSink;
  final LearningClock clock;
}
```

测试实验室退出后依赖对象释放，Mock 数据清空。页面顶部始终显示“测试数据，退出实验室后清空”。

## 7. 统一领域模型

## 7.1 学习内容

```dart
enum LearningMaterialKind { figure, video, interactive, formula }

final class LearningAtom {
  const LearningAtom({
    required this.id,
    required this.title,
    required this.summary,
    required this.prerequisiteIds,
    required this.applicationWeight,
  });
}

final class LearningMaterial {
  const LearningMaterial({
    required this.id,
    required this.atomId,
    required this.kind,
    required this.title,
    required this.payload,
  });
}
```

`payload` 是受控 Map，只由对应 Material Widget 解析。正式接入时 API Model 先转换成领域对象，Widget 不解析原始 JSON。

## 7.2 对话树

```dart
enum DialogueNodeRole { student, tutor }

final class LearningDialogueSession {
  const LearningDialogueSession({
    required this.id,
    required this.atomId,
    required this.rootNodeId,
    required this.activeLeafId,
    required this.nodes,
    required this.strategyVersion,
  });
}

final class LearningDialogueNode {
  const LearningDialogueNode({
    required this.id,
    required this.parentId,
    required this.role,
    required this.text,
    required this.materialIds,
    required this.memoryCandidates,
    required this.createdAt,
    required this.isSideBranch,
    required this.inputBoundary,
  });
}
```

普通连续提问追加到当前叶节点；只有学生点击“从这里继续探索”才创建新分支。重新查看历史节点不改变活跃分支。

`inputBoundary` 记录 `inScope / aboveStage / unrelated / inappropriate`，让超纲、不相关和不适宜的处理结果可审计。`strategyVersion` 在 Mock 中固定，正式接 Skill 后用于 A/B、回滚和事件重算。

## 7.3 记忆项和呈现

```dart
enum MemoryCardKind {
  questionAnswer,
  cloze,
  discrimination,
  image,
  sequence,
  application,
  listening,
}

enum MemoryLevel { r0, r1, r2, r3, r4, r5 }

enum MemorySourceKind { curated, dialogue }

final class MemoryItem {
  const MemoryItem({
    required this.id,
    required this.atomId,
    required this.sourceKind,
    required this.sourceRef,
    required this.prompt,
    required this.answer,
    required this.answerPoints,
    required this.presentations,
    required this.mnemonicAllowed,
    required this.mnemonic,
    required this.examWeight,
    required this.downstreamImpact,
  });
}

final class MemoryPresentation {
  const MemoryPresentation({
    required this.id,
    required this.kind,
    required this.minimumLevel,
    required this.payload,
  });
}
```

`mnemonicAllowed` 默认 `false`。只有顺序、年代、词形、专名等任意关联内容允许 `mnemonic`；公式推导、定理条件和因果链等可推导内容即使 fixture 错填助记，也必须在校验阶段拒绝。

一个记忆项可以有多个呈现。调度器先决定阶梯，呈现选择器再从满足层级的候选中选择，避免把“卡片类型”和“记忆项”绑定成两套数据。

## 7.4 记忆状态

```dart
final class StudentMemoryState {
  const StudentMemoryState({
    required this.memoryItemId,
    required this.fsrsCard,
    required this.difficulty,
    required this.stability,
    required this.retrievability,
    required this.currentLevel,
    required this.consecutiveSuccesses,
    required this.consecutiveFailures,
    required this.dueAt,
    required this.lastReviewAt,
  });
}

final class FsrsCardSnapshot {
  const FsrsCardSnapshot({
    required this.packageVersion,
    required this.serializedCard,
  });
}
```

`serializedCard` 保存 `fsrs` 包的 `Card.toMap()` 结果；页面和 Repository 不读取内部字段。D/S/R 作为可展示投影，由适配器计算并与序列化卡片一起更新。

## 7.5 作答与事件

```dart
enum ReviewRating { again, hard, good, easy }

final class FlashcardAnswer {
  const FlashcardAnswer({
    required this.itemId,
    required this.presentationId,
    required this.isCorrect,
    required this.usedHint,
    required this.elapsed,
    required this.rating,
    required this.payload,
  });
}
```

每次回答生成唯一 `eventId`。Repository 按 `eventId` 幂等；重复点击、页面恢复和测试重放不能重复更新 FSRS。

## 8. Mock 数据集

学习主题固定为“二次函数”，包含：

- 6 个种子问题：顶点、开口、平移、零点、最值、真实应用；
- 12 个预置记忆项；
- 对话至少可额外生成 4 个记忆项；
- 七种 `MemoryCardKind` 每种至少 1 个呈现；
- 4 类素材各至少 1 个；
- 3 个原子：二次函数定义、图像特征、顶点式；
- 明确的前置和后继权重，用于 urgency 排序；
- 1 个严重过期、2 个薄弱、2 个高 R、其余到期的初始状态，用于稳定构造组卷配方。

另提供一套独立的“business model”公开演示 fixture：

- 根问题为“一家咖啡店怎么赚钱”；
- 可沿收入、成本、定价、渠道、护城河和单位经济模型继续追问；
- 按预设交互路径可长到至少 3 层，并显式产生至少 2 条支线；
- 至少调用对比图、可调参数和公式卡 3 类素材；
- 每条系统反问都指向条件、因果或计算依据，不出现“你觉得呢”式空反问。

Mock 内容全部在 Dart fixture 中定义，不从网络加载。图像使用 `CustomPainter` 绘制抛物线；互动素材使用滑块调整 `a/h/k` 并实时重绘；视频素材使用可操作的 Mock 播放控制器和时间轴，明确标注“模拟视频”；听力卡使用 Mock 音频播放器，测试播放、暂停和结束状态，不冒充真实音频内容。

## 9. 1.2 对话式发散提问

## 9.1 入口

测试页提供三个入口：

1. 从 Mock 原子“二次函数图像特征”进入，由系统给出钩子问题；
2. 从问题库选择 6 个学习问题或 business model Demo；
3. 输入自由问题。

输入框上方提供五个只填入模板、不代替学生作答的脚手架：“是什么”“为什么会这样”“如果……会怎样”“这和 X 有什么关系”“这有什么用”。学生仍需编辑或确认后才能发送。

自由问题由 `MockLearningDialogueGateway` 做确定性关键词路由：

- 命中顶点、开口、平移、零点、最值、应用时返回对应分支；
- 相关但无精确匹配时返回通用函数解释和指向条件/原理的澄清问题；
- 超出当前 Mock 学段时标记“超纲”，只讲大意且不生成超出关系边的素材；
- 明显无关时标记支线并提供返回主干；
- 不适宜测试词明确拒绝并说明边界；
- 空文本、超长文本和不适宜输入都不创建节点。

## 9.2 单轮状态机

```text
idle → submitting → rendered
          └→ failed → retrying
rendered → reflecting → saved
```

实现步骤：

1. 学生提交问题；
2. 控制器先创建本地 pending 节点并生成幂等键；
3. Gateway 根据当前原子、祖先路径和问题生成回答；
4. 回答附带素材、指向原理的反问和记忆候选；
5. 成功后一次性替换 pending 节点；
6. 失败保留问题和重试按钮，不生成空回答；
7. 学生继续当前路径或从历史节点显式开分支；
8. 树形视图增量更新并聚焦活跃叶；
9. 达到收口条件时要求学生用自己的话复述；
10. 学生可保存树、打开导出预览或勾选候选转为记忆项。

树视图必须支持：点击节点回溯、折叠/展开子树、从任意导师节点重开分支、返回活跃叶。导出使用版本化 JSON，包含会话、节点、父子关系、素材引用、边界分类、复述和策略版本；首版提供复制到剪贴板，不申请文件系统权限。

## 9.3 规模和边界

- 单会话最多 40 个节点；
- 主干最多 6 层；
- 单节点最多 8 个直接分支；
- 达到上限时生成本地主干摘要并停止新增，允许保存和转记忆项；
- Mock Gateway 延迟固定为 300 毫秒，可在测试中注入立即完成或失败；
- 每个回答最多插入 2 个素材；
- 素材只能来自当前原子和 Mock 关系边允许的集合。
- 每条成功回答必须包含一个指向底层原理或成立条件的反问；禁止用空泛反问凑节点。
- 每次素材选择都记录候选范围、选中素材和原因；没有合适素材时允许纯文本回答。

## 9.4 素材

- figure：抛物线与顶点标注；
- formula：一般式、顶点式和配方步骤；
- interactive：调节 `a/h/k`；
- video：模拟“参数变化过程”的播放、暂停、进度和结束事件。

互动素材必须真实响应操作；Mock 视频明确标注模拟，不用静态截图伪装成视频。

## 9.5 白板预留

每条导师回答显示“在白板上演示”。调用：

```dart
abstract interface class WhiteboardLauncher {
  Future<void> open(
    BuildContext context, {
    required String dialogueNodeId,
    required String atomId,
    required Map<String, Object?> initialState,
  });
}
```

Mock 白板支持移动一个点、拖动函数参数和关闭返回，返回后对话节点显示“已打开白板演示”。正式 3.3 接入时替换实现。

## 9.6 转为记忆项

1. 导师节点声明 0–2 个 `MemoryCandidateDefinition`；
2. 学生勾选并可编辑标题和答案；
3. 控制器使用 `dialogueNodeId + candidateId` 生成稳定 `memoryItemId`；
4. Repository 进行幂等 upsert；
5. 新项起始层级为 R1，FSRS 卡立即到期；
6. 成功后节点显示“已加入复习”；
7. 重复确认只打开既有项，不产生副本；
8. 取消预览不改变记忆库。

会话结束时计算并保存：节点数、最大深度、最大宽度、主动分支数、素材种类与调用次数、复述文本。它们只作为学习/兴趣行为证据，不直接推断学生明确表达的兴趣结论。

## 10. 2.2 闪卡

## 10.1 七种卡片

| 类型 | Mock 交互 | 判定 |
|---|---|---|
| 问答卡 | 先口述/默想，再显示答案并评级 | 学生四档评级 |
| 挖空卡 | 从候选中填入顶点坐标或系数 | 标准化值相等 |
| 辨析卡 | 选择“顶点/零点”并选择依据 | 结论和依据都正确 |
| 图像卡 | 从四幅抛物线中选匹配图 | 图形 ID 匹配 |
| 序列卡 | 拖动配方步骤排序 | 顺序完全一致 |
| 应用卡 | 输入或选择最值 | 数值及单位匹配 |
| 听力卡 | 模拟播放后选择听到的表达式 | 选项 ID 匹配 |

图卡按内容分诊：空间/结构、易混淆对、流程/时序必须配模板图；纯定义、纯术语和纯结论不得为了装饰配图。fixture 校验器同时检查“该配图却没有图”和“不该配图却带装饰图”。同一学科的 Mock 图统一颜色、线宽和标注位置。

## 10.2 统一作答步骤

1. 卡片进入时开始计时；
2. 正面不展示答案；
3. 学生作答或申请提示；
4. `AnswerEvaluator` 返回正确性和错误原因；
5. 正确时立即记录并进入下一张；
6. 错误时展示解释、关联原子和重学入口；
7. 问答卡由学生选择 Again/Hard/Good/Easy；
8. 可判定卡自动建议评级，学生可以降级但不能把错误改为 Good/Easy；
9. 连续两次失败降低一个记忆阶梯；
10. 生成 `FlashcardAnswer` 和学习事件。

交互优先使用点击、滑动和拖拽；仅挖空和应用题在必须输入时打开键盘。15 秒是产品观测目标而非强制倒计时：超时不判错，但事件记录 `exceededTargetDuration`，用于判断题型或内容是否过重。

## 10.3 评级映射

- 错误：Again；
- 正确但用了提示：Hard；
- 正确、无提示、超过该卡预计时长：Hard；
- 正确、无提示、正常时间：Good；
- 正确、无提示、用时不超过预计时长的 60%：建议 Easy；
- 问答卡以学生选择为准，但展示答案前必须完成“我已经回答”的动作。

## 10.4 阶梯与呈现

- R0：图像选择、基础再认；
- R1：挖空和有锚点问答；
- R2：完整问答；
- R3：辨析和序列；
- R4：单步应用；
- R5：换情境应用。

首期每两次连续成功升一级，上限由现有 presentation 决定；连续两次失败降一级；严重过期由 2.3 直接降到 R1。

助记只作为错误解释后的可选辅助，不遮住标准答案。Mock 提供一个允许助记的任意关联样例和一个禁止助记的公式推导样例，测试后者不能被 Repository 接收。学生自建与班级分享不在当前闭环中展示；未来必须通过 `SharedMemoryCardPublisher` 接审核状态后再开放，不能直接复用本地新增按钮公开发布。

## 11. 2.3 FSRS 调度

## 11.1 依赖选择

固定依赖 `fsrs: 2.0.1`，不使用浮动主版本。该实现由 Open Spaced Repetition 项目列入 Dart 实现列表，支持四档评分、UTC 时间、序列化、指定复习时间和可关闭 fuzzing：

FSRS 的状态使用 Difficulty（难度）、Stability（稳定度）和 Retrievability（当前可提取性）表达；本文简称 D/S/R，不能把三者压成一个不可解释的“掌握度”。

- https://github.com/open-spaced-repetition/dart-fsrs
- https://pub.dev/packages/fsrs

所有包类型封装在 `FsrsReviewScheduler` 内。未来升级先运行兼容快照测试，再更新 `FsrsCardSnapshot.packageVersion`。

## 11.2 调度配置

- desired retention：0.90；
- learning steps：1 分钟、10 分钟；
- relearning step：10 分钟；
- maximum interval：36,500 天；
- 生产/交互演示启用 fuzzing；
- 单元测试关闭 fuzzing；
- 时间统一为 UTC；UI 只在展示时转本地时区。

## 11.3 时间抽象

```dart
abstract interface class LearningClock {
  DateTime nowUtc();
}
```

生产用 `SystemLearningClock`，测试用 `MutableLearningClock`。调度器调用 `reviewCard(..., reviewDateTime: clock.nowUtc())` 和 `getCardRetrievability(..., currentDateTime: clock.nowUtc())`，禁止在领域代码直接调用 `DateTime.now()`。

## 11.4 状态更新

1. 读取 `StudentMemoryState`；
2. 从 `FsrsCardSnapshot` 反序列化 Card；
3. 将 `ReviewRating` 映射到 FSRS Rating；
4. 用注入时间执行 review；
5. 计算当前 retrievability；
6. 投影 difficulty、stability、retrievability、dueAt；
7. 根据连续成功/失败更新 R0–R5；
8. 在单个 Repository 操作中写入新状态、ReviewLog 和事件；
9. 相同 `eventId` 返回既有结果；
10. 任一步失败不写部分状态。

## 11.5 urgency

```text
urgency = (1 - retrievability) * examWeight * downstreamImpact
```

Mock 原子提供 `examWeight` 和 `downstreamImpact`。正式图谱缺失时两者默认 1.0，但事件记录 `usedFallbackImpact = true`。

### 11.5.1 目标成功率

每组统计“无提示正确率”，目标区间为 0.85–0.95。低于 0.70 时生成 `review_session_success_rate_low` 诊断事件，记录组配方、阶梯和卡片类型分布；首版只在调试事件查看器显示，不把选材问题包装成学生失败。

### 11.5.2 新项引入上限

- 限制的是当天首次进入 FSRS 的新记忆项，不限制已经到期的复习；
- Mock 默认每日最多引入 8 项，配置来自可替换策略对象；
- 达到上限后仍可保存对话候选，但状态为 `queuedForIntroduction`，不进入当天组；
- 一组结束后学生可以主动再开一组，系统不自动推动第二组；
- 考前冲刺只能由学生主动开启，允许突破新项上限，并临时放大 `examWeight`；事件必须记录模式和倍率。

## 11.6 复习组配方

每组目标 12–20 项、5–8 分钟：

- 热身 2–3 项：到期项中 retrievability 最高；
- 主体约 55%：urgency 高且 retrievability 在 0.5–0.9；
- 薄弱约 15%：连续两次失败或带 misconception 标记，降一级；
- 探索 5–10%：由注入的随机源确定；
- 收尾 1–2 项：高 retrievability。

不足 12 项时允许生成短组，不复制卡片凑数。一个记忆项在同组只出现一次。测试随机源使用固定 seed。

## 11.7 三种候选组

- 今天该复的：完整配方，约 6 分钟；
- 攻薄弱：至少存在 6 个薄弱项时出现，约 8 分钟；
- 快速过一遍：高 R、低负荷，约 3 分钟。

测试数据不足时至少返回“今天该复的”和“快速过一遍”。页面不显示总待复习数。

## 11.8 积压和断档

- 过期不是债务，每次进入重新计算 R 并采样；
- `R < 0.3` 的项降到 R1；
- 模拟断档 14 天后，只从高 `examWeight * downstreamImpact` 项中取首组；
- 不显示“落后几天”或积压红点；
- Mock 调试面板提供“前进 1 天、7 天、14 天”按钮，只改变 `MutableLearningClock`。

## 11.9 与 M3、H.1 的边界

- R0–R3 作答只更新 FSRS，不发送能力证据；
- R4/R5 无提示正确或错误发送到 `AbilityEvidenceSink`，用了提示则不发送；
- M3 未来可通过同一学习事件入口把原子作答作为一次 FSRS 复习，首版用调试按钮注入一条 Mock M3 事件验证映射；
- 稳定度低的原子通过 `PracticePrioritySink` 输出优先级信号，但首版不做 M3 选题；
- 下一次复习建议通过 `ReviewRecommendationSink` 输出，但首版不做 H.1 首页；
- 能力分与稳定度始终是两个字段，不计算“综合掌握度”。

## 11.10 可追溯与重算

状态更新依赖追加式学习事件。调试页提供“从事件重算”动作：清空派生状态后按 `occurredAt + eventId` 的稳定顺序重放，结果必须与当前 D/S/R、阶梯和到期时间一致。原始作答载荷、策略版本、FSRS 包版本、配置和时钟均需入事件，避免只能看到最终数字却无法解释来源。

## 12. 页面和用户动线

## 12.1 教学助手测试实验室

开发者工具增加“教学助手：对话与复习”入口。实验室首页展示：

- Mock 数据提示；
- “开始问题探索”；
- “开始复习”；
- 当前记忆项数量；
- 时间模拟器；
- 学习事件查看器；
- “重置测试数据”。
- “注入一条 M3 作答事件”；
- “开启/关闭考前冲刺”。

重置前弹确认框，只清除本实验室进程内状态，不触碰其他 App 数据。

## 12.2 完整验收动线

1. 进入测试实验室；
2. 分别验证 Mock 原子、问题库和自由输入三个入口；
3. 选择“二次函数的顶点为什么在这里”；
4. 查看公式卡和可调参数素材；
5. 继续追问一轮；
6. 从第一轮回答显式创建支线，并验证回溯、折叠和返回活跃叶；
7. 打开 Mock 白板并返回；
8. 完成复述，保存并预览导出 JSON；
9. 勾选两个节点转为记忆项；
10. 进入复习并选择一组；
11. 完成七类卡片中的一组样例；
12. 查看 D/S/R、阶梯和下次到期时间变化；
13. 将时钟前进 7 天；
14. 再次进入复习，验证到期和 urgency 排序变化；
15. 重复提交同一答案，验证不重复更新；
16. 注入 Mock M3 事件并验证能力/优先级两个出口；
17. 打开 business model Demo，走出 3 层、2 条支线和 3 类素材；
18. 退出实验室并重新进入，确认数据已清空且提示一致。

## 13. 状态与失败处理

### 13.1 对话

- 重复提交：按钮禁用，幂等键阻止双节点；
- Mock Gateway 失败：保留问题和重试；
- 素材不存在：显示文本回答，不生成空卡；
- 树达到上限：停止新增，允许保存和转记忆；
- 导出复制失败：保留可选中的 JSON 预览并允许重试；
- 转换失败：候选保留，可重试；
- 重复转换：返回既有 MemoryItem。

### 13.2 闪卡

- payload 非法：跳过该呈现并记录 `invalid_presentation`，不判学生错误；
- 无可用呈现：该项退出本组并进入内容异常列表；
- 快速重复点击：提交中锁定按钮；
- 页面中断：保留本组位置；
- Mock 音频失败：允许重试，不显示正确答案。
- 助记策略非法：拒绝加载该项并记录内容异常，不在运行时临时放宽规则。

### 13.3 调度

- FSRS 反序列化失败：该项恢复为新卡并记录异常，其他项继续；
- 写入失败：状态、日志和事件全部回滚；
- 时钟倒退：拒绝更新并显示测试时间错误；
- dueAt 超过最大间隔：使用包配置上限；
- 配方槽位不足：按主体、热身、收尾顺序降级，不重复选项；
- 没有记忆项：显示从对话生成或加载 Mock 卡片的空状态入口；
- 外部 Sink 失败：FSRS 已提交状态不回滚，待发送信号保留为 pending 并允许重试，避免重复调度。

## 14. 测试设计

## 14.1 模型和 Repository

- Mock 数据 ID 唯一且所有引用存在；
- 七种卡片至少各有一个合法 fixture；
- 对话转记忆项幂等；
- 重置只影响实验室状态；
- 事件 ID 重放不重复写入。

## 14.2 1.2

- 三个入口都能创建会话；
- 五种提问脚手架只填模板、不自动发送；
- 连续提问追加到活跃叶；
- 只有显式操作创建分支；
- 节点可回溯、折叠、展开并返回活跃叶；
- 回答包含至少两种不同素材；
- 互动素材可真实改变图像；
- 超纲只讲大意且不越出素材范围，无关问题成为支线，不适宜输入被拒绝；
- 每条回答都有指向原理/条件的反问，无空泛反问；
- 空、超长和拒绝输入不创建节点；
- Gateway 失败后重试不重复问题；
- 白板接口收到正确 nodeId/atomId；
- 候选可编辑、取消和确认；
- 保存和版本化 JSON 导出包含完整父子关系；
- business model 固定路径满足 3 层、2 条支线和 3 类素材；
- 深度、宽度、素材和复述证据可从事件重建。

## 14.3 2.2

- 七种卡片题面不泄露答案；
- 图卡分诊规则同时拒绝缺图与装饰性滥配图；
- 任意关联允许助记、公式推导拒绝助记；
- 每种判定规则成功和失败各有测试；
- 错误只能映射 Again；
- 提示正确映射 Hard；
- 正常正确映射 Good；
- 快速正确建议 Easy；
- 答对立即下一张，答错展开解释；
- 超过 15 秒只记录观测事件，不被自动判错；
- 连错两次降阶；
- 非法 payload 不影响其他卡片。

## 14.4 2.3

- 固定 UTC 时间下的 FSRS 快照与预期一致；
- Again/Hard/Good/Easy 产生不同到期时间；
- 序列化后恢复保持 due、状态和版本；
- 关闭 fuzzing 后结果确定；
- 前进 1/7/14 天的 R 单调下降；
- urgency 随 R 下降、考试权重和后继影响上升；
- 配方包含热身、主体、薄弱、探索和收尾；
- 不足 12 项时不重复卡片；
- 严重过期降到 R1；
- 相同 eventId 不重复调度。
- 无提示正确率低于 0.70 时生成诊断事件；
- 每日新项上限只阻止新引入，不阻止到期复习；
- 考前冲刺只有主动开启时放宽上限并放大考试权重；
- R0–R3、R4/R5 有无提示分别产生正确的能力事件行为；
- 低稳定度优先级和 H.1 推荐写入对应 Mock Sink；
- 从完整事件流重算得到相同 D/S/R、阶梯和 dueAt。

## 14.5 Widget 与闭环

- 开发者工具入口可达；
- Mock 数据提示始终可见；
- 对话树可浏览和聚焦；
- 导出 JSON 可预览和复制；
- 转换后复习入口显示新增数量；
- 七种卡片都可完成；
- 时间模拟改变下一组；
- 新项上限、考前冲刺和 Mock M3 注入可观察；
- 退出重新进入后状态清空；
- 小屏无横向溢出，长回答和长卡片可滚动；
- 加载、错误、空状态和重试齐全。

## 15. 验收标准

### 15.1 功能闭环

- 从任一 Mock 问题开始，至少形成 3 层且包含 1 个显式支线的树；
- Mock 原子、问题库、自由输入三个入口都可独立开始；
- 一次会话至少出现 2 种素材，其中互动素材可操作；
- 树可回溯、折叠、保存、导出，business model Demo 达成单独验收；
- 至少一个节点能转为记忆项且重复确认不重复；
- 七类卡片协议和交互全部可演示；
- 四档评分真实驱动 FSRS；
- 时间前进后到期、R、urgency 和组卷发生可解释变化；
- 新项上限、目标成功率、能力事件边界和事件重算可验证；
- 页面不显示积压总数；
- 退出实验室后 Mock 状态清空。

### 15.2 架构边界

- Widget 不 import `fsrs`；
- Widget 不读取 Mock 常量；
- 所有时间来自 `LearningClock`；
- 所有状态更新经 `LearningStateRepository`；
- 白板和音频均通过接口；
- M3/H.1 出口均通过 Sink，失败信号可重试；
- 正式 API 接入不要求修改卡片 Widget 和 FSRS 适配器公开接口。

### 15.3 质量门槛

```powershell
dart analyze lib/main.dart lib/developer_tools.dart lib/features/learning_lab test
flutter test test/features/learning_lab
flutter test
```

所有新增公开类、异步状态转换、幂等和降级分支按仓库规范写简洁中文注释。不得把教学规则、Mock 数据和 Widget 写在同一文件。

### 15.4 原文功能追踪

以下表格用于防止“因为当前使用 Mock，就把正式需求删掉”。“Mock 验证”表示当前做出可操作实现；“接口预留”表示本期不伪造正式能力，但接口、事件和替换位置必须存在；“后续决策”表示原文自身仍未定稿，当前不得擅自拍板。

| 原文要求 | 本设计归属 | 验收位置 |
|---|---|---|
| 1.2 从原子进入 | Mock 验证 | 9.1、12.2、14.2 |
| 1.2 问题库与自由输入 | Mock 验证 | 8、9.1、14.2 |
| 1.2 超纲、不相关、不适宜边界 | Mock 验证 | 7.2、9.1、13.1、14.2 |
| 1.2 图、视频、交互、公式卡实时调用 | Mock 验证 | 8、9.3、9.4 |
| 1.2 素材不越关系边、不滥用、交互必须能操作 | Mock 验证 | 9.3、14.2 |
| 1.2 深挖、旁散、回溯、折叠、重开分支 | Mock 验证 | 7.2、9.2、12.2 |
| 1.2 提问脚手架与指向原理的反问 | Mock 验证 | 9.1、9.3、14.2 |
| 1.2 复述收口、保存、导出、转记忆项 | Mock 验证 | 9.2、9.6、12.2 |
| 1.2 一键白板 | Mock 验证 + 接口预留 | 9.5 |
| 1.2 思维树深度/广度、素材、复述证据 | Mock 验证 | 9.6、14.2 |
| 1.2 Skill 版本化与正式模型调用 | Gateway/策略版本预留 | 2.2、7.2、16.2 |
| 1.2 business model Demo | Mock 验证 | 8、12.2、14.2 |
| 1.2 学生真问题沉淀和教研审核入库 | 事件留痕 + 正式知识库接入时实现 | 16.1 |
| 1.2 树上限、跑题距离、时长、提问质量 | 40 节点/6 层 Mock 决策；其余保留后续产品决策 | 9.3 |
| 2.2 七类卡片与 R0–R4 适配 | Mock 验证 | 10.1、10.4、14.3 |
| 2.2 图卡三类必配、纯定义不配 | Mock 验证 | 10.1、14.3 |
| 2.2 助记仅限任意关联 | Mock 验证 | 7.3、10.4、14.3 |
| 2.2 选/填/拖/说与手势优先 | Mock 验证；“说”首版用完成确认，不做语音识别 | 10.1、10.2 |
| 2.2 答对不停留、答错展开、连错降级 | Mock 验证 | 10.2、14.3 |
| 2.2 单卡 15 秒 | 观测目标，不设惩罚倒计时 | 10.2、14.3 |
| 2.2 教研派生、错因、自建分享审核 | Repository/Sink 边界；正式内容与审核后续接入 | 2.2、2.3、16.1 |
| 2.3 FSRS D/S/R 与四档评分 | 真实算法验证 | 11.1–11.4、14.4 |
| 2.3 urgency 三因子 | Mock 权重 + 缺图回退 | 11.5、14.4 |
| 2.3 定长配方、正确率目标与 2–3 个候选组 | Mock 验证 | 11.5–11.7 |
| 2.3 R0–R5 升降级 | Mock 验证 | 10.4、11.4、14.4 |
| 2.3 能力分与稳定度分离、M3 双向事件 | Mock Sink 验证 + 正式 M3 预留 | 11.9、14.4 |
| 2.3 控新增、不控复习、主动冲刺 | Mock 验证 | 11.5.2、14.4 |
| 2.3 不显示积压、断档重采样 | Mock 验证 | 11.8、15.1 |
| 2.3 数字可追溯并可从事件重算 | Mock 验证 | 11.10、14.4 |
| 2.3 原子图、考纲权重、H.1 输出 | Mock 数据 + 接口预留 | 2.2、8、11.9 |
| 2.3 老师任务插队、配方 A/B、参数再拟合 | 后续决策，不在首版伪造 | 16.6 |

## 16. 后续正式接入路径

### 16.1 接 1.1 知识库

新增 `ApiLearningContentRepository`，把原子、边、问题、素材和 memory item API 转换为本文领域模型。学生问题的频次、树长和支线数据先作为候选事件上传，只有教研审核通过后才进入正式问题库。保留 Mock Repository 作为测试 fixture。

### 16.2 接正式对话

新增 `ApiLearningDialogueGateway`，输入当前原子、关系边范围、活跃路径和允许素材 ID。模型只返回回答、反问、素材引用和候选定义；服务端负责安全与结构校验。

正式 Skill 的版本写入 `strategyVersion`。升级、A/B 或回滚不改变页面协议；business model fixture 继续作为跨版本契约测试。

### 16.3 接正式持久化

新增 `ApiLearningStateRepository`，将 MemoryItem、FSRS Card、ReviewLog 和事件写入后端。服务端使用 eventId 幂等并事务更新。

### 16.4 接 3.3 白板

用正式 `WhiteboardLauncher` 替换 Mock，实现消息节点与白板快照关联。1.2 页面和控制器调用方式保持不变。

### 16.5 FSRS 服务端迁移

Mock 首版在 Flutter 本地执行 FSRS 便于离线演示和时间测试。正式多端版本以服务端为权威：

1. Flutter 继续提交四档评级和 eventId；
2. 服务端运行同版本 FSRS 并返回状态；
3. 迁移前用同一事件序列比较 Dart 与服务端实现；
4. 快照差异超过约定容差时阻断迁移；
5. Flutter 本地适配器保留为测试参考，不与服务端同时写权威状态。

### 16.6 尚未获得正式输入的决策

- 老师布置的复习任务如何插队；
- 组配方占比、组长度和最低样本量的 A/B 方案；
- FSRS 公开参数何时使用本产品延时复测数据重新拟合；
- 考纲版本与 `examWeight` 的维护责任；
- 学生自建卡、助记分享和班级公开的审核状态机。

这些项目保留配置、事件或发布接口边界，但在产品和上游数据未确认前不做假数据驱动的“正式逻辑”。

## 17. 设计依据

- 总功能与数据口径来自用户提供的《教学助手 · 学生端功能文档》；
- Dart FSRS 包当前版本、四档评分、UTC、指定复习时间、序列化和 fuzzing 配置来自：
  - https://pub.dev/packages/fsrs
  - https://pub.dev/documentation/fsrs/latest/fsrs/Scheduler-class.html
- Open Spaced Repetition 官方项目将 `dart-fsrs` 列为 FSRS 的 Dart 调度实现：
  - https://github.com/open-spaced-repetition/free-spaced-repetition-scheduler
