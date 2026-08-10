# Student Learning Narrative UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将探索课堂从开发者状态展示改为学生目标、任务、发现和下一步驱动的学习叙事，同时保留既有教学闭环。

**Architecture:** 新增无副作用的学生叙事映射模块，把服务端阶段、证据和来源转换为 UI 文案；章节总览与会话页面只消费映射结果，不改 DTO、控制器和后端协议。现有素材、微测、反思和树形交互继续沿用原回调。

**Tech Stack:** Flutter、Dart、Material、flutter_test

## Global Constraints

- 不修改 Next.js API、Session 状态机、Evidence 数据结构或互动事件协议。
- 不在 Flutter 客户端推断掌握度，只投影服务端状态。
- 新增公开模块和关键映射规则使用简洁中文注释。
- 保留既有 `ValueKey` 和事件回调，确保旧交互继续工作。

---

### Task 1: 学生叙事映射

**Files:**
- Create: `lib/features/dialogue_exploration/presentation/student_learning_narrative.dart`
- Create: `test/features/dialogue_exploration/student_learning_narrative_test.dart`

**Interfaces:**
- Consumes: `RemoteTeachingStage`、`RemoteEvidenceState`、回答来源字符串、章节阶段 kind/status。
- Produces: `StudentLearningNarrative.stageTitle`、`stageLabel`、`verificationMessage`、`answerContextLabel`、`chapterPhaseTitle`、`chapterPhaseStatus`。

- [ ] **Step 1: 写失败测试**

```dart
test('technical teaching state becomes student-facing narrative', () {
  expect(StudentLearningNarrative.stageLabel(RemoteTeachingStage.asset), '动手验证');
  expect(StudentLearningNarrative.answerContextLabel('SAFE_FALLBACK'), '当前提示');
  expect(StudentLearningNarrative.answerContextLabel('MODEL_PRIOR'), isNull);
  expect(StudentLearningNarrative.chapterPhaseTitle('PRACTICE'), '动手试一试');
});
```

- [ ] **Step 2: 验证测试因模块缺失而失败**

Run: `flutter test test/features/dialogue_exploration/student_learning_narrative_test.dart`

Expected: FAIL，提示 `student_learning_narrative.dart` 或 `StudentLearningNarrative` 不存在。

- [ ] **Step 3: 实现最小映射模块**

实现静态纯函数；`verificationMessage` 使用 `missingCodes.length`，不得根据客户端行为自行增加证据。

- [ ] **Step 4: 验证映射测试通过**

Run: `flutter test test/features/dialogue_exploration/student_learning_narrative_test.dart`

Expected: PASS。

### Task 2: 章节总览学生化

**Files:**
- Modify: `lib/features/dialogue_exploration/presentation/chapter_workspace_components.dart`
- Modify: `test/features/dialogue_exploration/live_tree_page_test.dart`

**Interfaces:**
- Consumes: Task 1 的章节阶段文案映射。
- Produces: 学生旅程式章节标题、阶段卡与问题入口；保留原回调和 `ValueKey`。

- [ ] **Step 1: 写失败的 Widget 断言**

```dart
expect(find.text('今天的学习旅程'), findsOneWidget);
expect(find.text('先发现规律'), findsOneWidget);
expect(find.text('动手试一试'), findsOneWidget);
expect(find.text('回看我的发现'), findsOneWidget);
expect(find.text('章节学习工作台'), findsNothing);
```

- [ ] **Step 2: 运行单文件测试并确认文案断言失败**

Run: `flutter test test/features/dialogue_exploration/live_tree_page_test.dart`

Expected: FAIL，缺少新的学生旅程文案。

- [ ] **Step 3: 调整章节组件**

替换章节眉题、自由问题入口说明、阶段名称与状态；保留节点选择、进度值和入口按钮行为。

- [ ] **Step 4: 运行单文件测试确认通过**

Run: `flutter test test/features/dialogue_exploration/live_tree_page_test.dart`

Expected: PASS。

### Task 3: 探索会话时间线

**Files:**
- Modify: `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`
- Modify: `test/features/dialogue_exploration/live_tree_page_test.dart`

**Interfaces:**
- Consumes: Task 1 的阶段、验证和来源文案映射。
- Produces: `今天，我们一起发现` 开场、当前任务卡、`你的问题/一起验证/你的发现/下一步` 时间线。

- [ ] **Step 1: 写失败的学生叙事断言**

```dart
expect(find.text('今天，我们一起发现一个秘密'), findsOneWidget);
expect(find.text('我们验证一下'), findsOneWidget);
expect(find.text('还需要一次验证，确认你的想法'), findsOneWidget);
expect(find.text('AI 反问'), findsNothing);
expect(find.textContaining('证据 '), findsNothing);
expect(find.text('安全兜底'), findsNothing);
```

- [ ] **Step 2: 运行单文件测试并确认断言失败**

Run: `flutter test test/features/dialogue_exploration/live_tree_page_test.dart`

Expected: FAIL，旧技术文案仍存在。

- [ ] **Step 3: 实现学生叙事组件层级**

让 `_ClassroomGuideHeader` 接收主题和当前问题；让 `_GuidedTeachingActionPanel` 使用学生阶段旅程和验证提示；让 `_ExplorationTurnCard` 与 `_ExplorationClassroom` 使用时间线语义。保留素材、白板、微测和反思回调。

- [ ] **Step 4: 运行单文件测试确认交互和叙事均通过**

Run: `flutter test test/features/dialogue_exploration/live_tree_page_test.dart`

Expected: PASS，包括素材事件、微测和反思测试。

### Task 4: 全量验证

**Files:**
- Verify: `lib/main.dart`
- Verify: `test/`

**Interfaces:**
- Consumes: Tasks 1-3 的最终实现。
- Produces: 可交付的学生叙事 UI，不新增后端依赖。

- [ ] **Step 1: 格式化改动文件**

Run: `dart format lib/features/dialogue_exploration/presentation/student_learning_narrative.dart lib/features/dialogue_exploration/presentation/chapter_workspace_components.dart lib/features/dialogue_exploration/presentation/remote_exploration_page.dart test/features/dialogue_exploration/student_learning_narrative_test.dart test/features/dialogue_exploration/live_tree_page_test.dart`

- [ ] **Step 2: 运行规定静态分析**

Run: `dart analyze lib/main.dart test`

Expected: 无本次新增错误。

- [ ] **Step 3: 运行完整 Flutter 测试**

Run: `flutter test`

Expected: PASS；若存在无关历史失败，记录具体测试与本次相关测试结果。

- [ ] **Step 4: 在 1280px 与 390px Widget 尺寸复核关键入口**

确认 `open-concept-map`、`guided-asset-complete-button`、`guided-start-micro-check-button` 与 `guided-start-reflection-button` 仍可见或可滚动到达。

### Task 5: 章节总览结构收敛

**Files:**
- Modify: `lib/features/dialogue_exploration/presentation/chapter_workspace_components.dart`
- Modify: `test/features/dialogue_exploration/live_tree_page_test.dart`

**Interfaces:**
- Consumes: `LearningChapterOverviewSnapshot`、当前选中节点、两个既有问题控制器及原有创建会话回调。
- Produces: `student-mission-hero`、`chapter-learning-journey-strip`、`chapter-question-switcher`、`direct-ai-teacher-entry` 四个可测试的学生界面边界。

- [ ] **Step 1: 写结构失败测试**

```dart
expect(find.byKey(const ValueKey('student-mission-hero')), findsOneWidget);
expect(find.byKey(const ValueKey('chapter-learning-journey-strip')), findsOneWidget);
expect(find.byKey(const ValueKey('chapter-question-switcher')), findsOneWidget);
expect(find.byKey(const ValueKey('direct-ai-teacher-entry')), findsOneWidget);
expect(find.text('从一个问题开始探索'), findsNothing);
expect(find.text('预计 10 分钟'), findsNothing);
```

- [ ] **Step 2: 运行单文件测试并确认旧骨架导致失败**

Run: `flutter test test/features/dialogue_exploration/live_tree_page_test.dart`

Expected: FAIL，缺少新的任务卡、旅程条与折叠入口，并仍存在重复预览内容。

- [ ] **Step 3: 实现单一主任务结构**

将章节标题、当前节点问题、可选猜想输入与开始动作合并为 `_StudentMissionHero`；按钮调用 `onStartNode(selected.id, questionController.text)`，空白问题继续由既有控制器规则归一化。将阶段卡改成 `_ChapterLearningJourneyStrip`，不改变阶段数据来源。

- [ ] **Step 4: 折叠问题切换与独立 AI 入口**

用 `_ChapterQuestionSwitcher` 包裹 `ChapterKnowledgeTree`，用 `_DirectAiTeacherEntry` 的折叠状态隐藏独立问题表单；保留 `chapter-node-*`、`direct-ai-teacher-question` 和 `direct-ai-teacher-start` 的原回调边界。

- [ ] **Step 5: 运行单文件测试确认通过**

Run: `flutter test test/features/dialogue_exploration/live_tree_page_test.dart`

Expected: PASS，包括主任务创建会话、展开后切换节点与独立提问三条真实交互。

- [ ] **Step 6: 全量验证**

Run: `dart analyze lib/main.dart test`

Run: `flutter test`

Expected: 无本次新增错误，完整测试通过。

### Task 6: 修复展开换题后的操作死角

**Files:**
- Modify: `lib/features/dialogue_exploration/presentation/chapter_workspace_components.dart`
- Modify: `test/features/dialogue_exploration/live_tree_page_test.dart`

**Interfaces:**
- Consumes: `_ChapterQuestionSwitcher` 的当前节点、`busy` 状态与 `onStartNode(String nodeId, String? question)` 回调。
- Produces: 仅在换题列表展开时可见的 `chapter-enter-switched-node` 操作。

- [ ] **Step 1: 写失败的真实交互测试**

```dart
await tester.tap(find.byKey(const ValueKey('chapter-question-switcher')));
await tester.pumpAndSettle();
await tester.tap(find.byKey(const ValueKey('chapter-node-opposite-number')));
await tester.pumpAndSettle();
await tester.tap(find.byKey(const ValueKey('chapter-enter-switched-node')));
await tester.pumpAndSettle();
expect(api.lastCreateQuestion, '连续两次取相反数会怎样？');
```

- [ ] **Step 2: 运行单文件测试确认入口缺失**

Run: `flutter test test/features/dialogue_exploration/live_tree_page_test.dart --plain-name "chapter question switcher keeps a nearby start action"`

Expected: FAIL，提示找不到 `chapter-enter-switched-node`。

- [ ] **Step 3: 实现最小就近入口**

为 `_ChapterQuestionSwitcher` 增加 `busy` 与 `onStart` 参数，在 `ChapterKnowledgeTree` 下方渲染一个右对齐按钮；按钮只调用 `onStart(selected.id)`，不复制控制器或接口逻辑。

- [ ] **Step 4: 验证单文件与全量测试**

Run: `flutter test test/features/dialogue_exploration/live_tree_page_test.dart`

Run: `dart analyze lib/main.dart test`

Run: `flutter test`

Expected: 展开列表的入口交互通过，静态分析无本次新增错误，完整测试通过。
