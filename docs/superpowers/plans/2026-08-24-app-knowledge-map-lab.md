# App Knowledge Map Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Flutter App 的 5174 开发环境中实现可响应式下钻的高中数学三级知识图谱实验页。

**Architecture:** 静态目录模型负责一级、二级、三级数据与统计，Stateful 页面只维护当前模块、主题和知识点选择。独立开发路由提供直接验收入口，同时通过对话实验页的功能区 B 复用页面导航。

**Tech Stack:** Flutter、Dart、Material 3、flutter_test

**Spec:** `docs/superpowers/specs/2026-08-24-app-knowledge-map-lab-design.md`

## Global Constraints

- 仅修改 `feature/student-dialogue-exploration-1-2` 独立工作树。
- 页面不得依赖网络或后端知识接口。
- 新公开类型使用简洁中文 Dart 文档注释。
- 先写失败测试并确认失败，再编写生产代码。
- 不覆盖工作树原有的 Flutter 自动生成文件改动。

---

### Task 1: 目录模型与三级页面

**Files:**
- Create: `lib/features/dialogue_exploration/presentation/knowledge_map/high_school_math_catalog.dart`
- Create: `lib/features/dialogue_exploration/presentation/knowledge_map/high_school_math_knowledge_map_page.dart`
- Test: `test/features/dialogue_exploration/high_school_math_knowledge_map_page_test.dart`

**Interfaces:**
- Produces: `HighSchoolMathCatalog.modules` 与 `HighSchoolMathKnowledgeMapPage`

- [ ] **Step 1: Write the failing widget tests**

测试默认模块统计、点击主题进入三级、面包屑返回、未接入模块空态，以及 390px 窄屏不溢出。

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/dialogue_exploration/high_school_math_knowledge_map_page_test.dart`

Expected: FAIL，因为页面和目录类型尚不存在。

- [ ] **Step 3: Implement the catalog and page**

目录保存 9 个一级模块及前两个模块的 5 个二级主题、25 个三级知识点。页面通过 `LayoutBuilder` 在桌面双栏和窄屏纵向布局之间切换，使用稳定 `ValueKey` 暴露可测试交互。

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/dialogue_exploration/high_school_math_knowledge_map_page_test.dart`

Expected: PASS。

### Task 2: 开发路由与功能区 B 接入

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/features/dialogue_exploration/presentation/teaching_mode_selection_stage.dart`
- Modify: `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`
- Modify: `test/developer_tools_web_test.dart`
- Modify: `test/features/dialogue_exploration/math_interaction_lab_page_test.dart`

**Interfaces:**
- Consumes: `HighSchoolMathKnowledgeMapPage`
- Produces: `/knowledge-map-lab` 开发路由与 `onFunctionAreaBTap` 页面回调

- [ ] **Step 1: Write failing integration tests**

断言开发路由能构造知识图谱页面，功能区 B 点击时调用页面层回调。

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/developer_tools_web_test.dart test/features/dialogue_exploration/math_interaction_lab_page_test.dart`

Expected: FAIL，因为路由和 B 区回调尚未接入。

- [ ] **Step 3: Implement the route and navigation callbacks**

仅在非生产开发路由中注册 `/knowledge-map-lab`；功能区 B 的导航由 `RemoteExplorationLabPage` 注入，侧栏不直接依赖具体页面。

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/developer_tools_web_test.dart test/features/dialogue_exploration/math_interaction_lab_page_test.dart`

Expected: PASS。

### Task 3: Verification and local preview

**Files:**
- Verify only; no additional production files.

**Interfaces:**
- Consumes: all changes from Tasks 1 and 2.

- [ ] **Step 1: Format changed Dart files**

Run: `dart format` on the exact changed Dart files.

- [ ] **Step 2: Run focused tests and analysis**

Run the three related test files, then `dart analyze lib/main.dart`.

- [ ] **Step 3: Start the App Web preview**

Run: `flutter run -d web-server --web-hostname localhost --web-port 5174 -t lib/main.dart --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=APP_ENV=development --dart-define=ENABLE_DEVELOPER_TOOLS=true`

- [ ] **Step 4: Open the direct acceptance route**

Open: `http://localhost:5174/#/knowledge-map-lab`
