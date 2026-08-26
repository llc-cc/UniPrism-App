# Knowledge Map Desktop Header Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Match the App knowledge-map desktop header and three-column panel alignment to Figma node `196:14814` without changing graph interactions.

**Architecture:** Refactor only the desktop composition in `_DesktopLayout`: a fixed first header row contains back/search/avatar, a fixed second header row contains title/level breadcrumb/fullscreen, and one shared content row stretches the left list and optional right detail panel to identical top and bottom bounds. Existing canvas, pan/zoom, catalog, and compact layout remain unchanged.

**Tech Stack:** Flutter, Dart, flutter_test

**Spec:** User-approved Figma design `GInLTnR1DSfc9hDiSwPZVr`, node `196:14814`

## Global Constraints

- App test page remains `/#/knowledge-map-lab` on port `5174`.
- Desktop Figma baseline is `1440 x 810`.
- Do not modify graph node interaction, zoom, pan, catalog data, or compact layout behavior.
- Preserve all unrelated dirty and untracked files in the worktree.

---

### Task 1: Lock the Figma desktop geometry with widget tests

**Files:**
- Modify: `test/features/dialogue_exploration/high_school_math_knowledge_map_page_test.dart`

**Interfaces:**
- Consumes: existing widget keys `knowledge-map-search-box`, `knowledge-map-fullscreen-button`, `knowledge-map-toolbar`, `knowledge-map-detail-pane`, and `knowledge-module-card-A`
- Produces: regression coverage for the approved desktop geometry

- [ ] **Step 1: Update the desktop specification test**

Assert literal Figma values at `1440 x 810`: search `200 x 45`, search font `14`, avatar `45`, fullscreen `39` with icon `24`, level button `129 x 42` with radius `6` and font `16`, breadcrumb font `14` and a `14` pixel horizontal gap.

- [ ] **Step 2: Update the panel alignment test**

Enter a third-level point and assert that the first module card inset implies the left panel and detail panel share the same top, that the detail panel starts at least `18` pixels below the fullscreen control, and that both panels have the same bottom edge.

- [ ] **Step 3: Run the targeted tests and verify RED**

Run:
`flutter test test/features/dialogue_exploration/high_school_math_knowledge_map_page_test.dart --plain-name 桌面搜索框与等级切换区按确认规格展示`

Then run:
`flutter test test/features/dialogue_exploration/high_school_math_knowledge_map_page_test.dart --plain-name 三级详情面板不遮挡右上角全屏按钮`

Expected: failures report the old `220 x 48`, `44`, `122 x 36`, and vertically offset panel geometry.

### Task 2: Implement the two-row header and shared content bounds

**Files:**
- Modify: `lib/features/dialogue_exploration/presentation/knowledge_map/high_school_math_knowledge_map_page.dart`

**Interfaces:**
- Consumes: existing `_DesktopToolbar`, `_ModuleList`, `_DesktopMapCanvas`, and `_KnowledgeDetailPanel`
- Produces: Figma-aligned desktop layout while preserving current callbacks and keys

- [ ] **Step 1: Refactor desktop composition**

Use desktop outer insets `left/right 40`, `top 21`, `bottom 48`; render a `45` pixel first header row, a `6` pixel row gap, a `45` pixel second header row, an `18` pixel content gap, then one stretched content row. Remove the conditional `30` pixel top padding from both side panels.

- [ ] **Step 2: Match component sizing and typography**

Set title to `24` semibold; search to `200 x 45`, `#F7F8FA`, radius `43`, font `14`; avatar to `45`; fullscreen to `39` with icon `24`; level button to `129 x 42`, radius `6`, font `16`; breadcrumb to `14` with line height `21.314` and `14` pixel gap.

- [ ] **Step 3: Run targeted tests and verify GREEN**

Run both Task 1 commands and confirm each exits successfully.

- [ ] **Step 4: Run full verification**

Run:
`flutter test test/features/dialogue_exploration/high_school_math_knowledge_map_page_test.dart`

Run:
`flutter analyze lib/features/dialogue_exploration/presentation/knowledge_map/high_school_math_knowledge_map_page.dart test/features/dialogue_exploration/high_school_math_knowledge_map_page_test.dart`

Expected: all widget tests pass and analysis reports no issues.

- [ ] **Step 5: Refresh the running test page**

Hot restart the existing Flutter Web server and verify `http://localhost:5174/#/knowledge-map-lab` returns HTTP `200`.
