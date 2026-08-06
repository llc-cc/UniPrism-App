# 1.2 Exploration Workbench Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让浏览器会话页具备图二的桌面工作台层级，并提升负数乘法 Mock 回答的针对性。

**Architecture:** Flutter 页面只负责布局、树和素材渲染；Next.js 教学引擎根据当前原子、问题和轮次生成确定性安全回答。现有 API 契约保持不变。

**Tech Stack:** Flutter/Dart、Next.js/TypeScript、Flutter Test、Vitest

## Global Constraints

- 不新增外部依赖、数据表或第二套素材内容体系。
- 保留会话、分支、回溯、记忆候选和导出契约。
- 新增业务判断和状态流程写简洁中文注释。

---

### Task 1: 桌面工作台层级

**Files:**
- Modify: `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`
- Modify: `lib/features/dialogue_exploration/presentation/chapter_workspace_components.dart`
- Test: `test/features/dialogue_exploration/live_tree_page_test.dart`

**Interfaces:**
- Consumes: `RemoteLearningSessionSnapshot`、`LearningChapterOverviewSnapshot`
- Produces: 顶部状态栏、当前方向卡、双树常驻侧栏、探索统计卡

- [ ] 写失败组件测试，断言桌面页同时出现进度、计时、当前方向、双树与统计。
- [ ] 运行 `flutter test test/features/dialogue_exploration/live_tree_page_test.dart`，确认新增断言失败。
- [ ] 实现状态栏、左右比例、紧凑树和统计布局。
- [ ] 重跑组件测试并确认通过。

### Task 2: 问题感知的 Mock 教学回答

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/dialogueEngine.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionTeachingEngine.test.ts`

**Interfaces:**
- Consumes: `TeachingEngineInput.question`、`atomId`、`turnIndex`、`path`
- Produces: 保持 `EvaluatedTeachingTurn` 不变的直答、具体反问和按问题选择的素材

- [ ] 写失败单元测试，覆盖核心问题、方向翻转和“不懂”三类输入。
- [ ] 运行目标 Vitest，确认回答仍为泛化模板而失败。
- [ ] 增加负数乘法确定性回答与素材调度函数。
- [ ] 重跑教学引擎测试并确认通过。

### Task 3: 联合验证

**Files:**
- Verify only

**Interfaces:**
- Consumes: 前后端本机服务
- Produces: 可在 `http://localhost:3001` 直接刷新的完整效果

- [ ] 运行 1.2 Flutter 全部测试与模块分析。
- [ ] 运行学习会话后端全部测试与 `npx tsc --noEmit`。
- [ ] 通过真实 HTTP 完成创建会话和三轮追问，检查答案、节点和素材变化。
- [ ] 重启或热更新网页服务，提供刷新测试路径。
