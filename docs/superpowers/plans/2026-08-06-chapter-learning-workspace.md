# Chapter Learning Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a chapter-level workspace that exposes the whole learning path, improves stuck-student dialogue, and switches between the chapter knowledge tree and the student's thinking tree.

**Architecture:** Add a backend-owned chapter overview contract supplied by the existing Mock Knowledge Provider. Flutter parses that contract into a focused chapter controller and renders it in the remote exploration page; the existing Learning Session API remains the sole source for the personal thinking tree. Improve the deterministic development dialogue engine and prompt rules at the backend so all clients receive the same non-repetitive stuck-state behavior.

**Tech Stack:** Flutter/Dart, Next.js/TypeScript, Zod, Vitest, Flutter widget tests.

## Global Constraints

- Keep chapter knowledge data in the backend Mock Provider; do not hardcode curriculum facts in Flutter widgets.
- The old Mock exploration page must no longer be reachable from the developer entry.
- A stuck turn must not request self-explanation or necessary-condition recall.
- New business state and asynchronous paths require concise Chinese comments.
- Frontend changes require related Flutter tests; backend changes require related Vitest tests and TypeScript checking.

---

### Task 1: Chapter overview backend contract

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/contracts.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/knowledgeProvider.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/http.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/app/api/learning-chapters/[chapterId]/route.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningChapterOverview.test.ts`

**Interfaces:**
- Produces: `LearningChapterOverviewDto`, `KnowledgeProvider.getChapterOverview(chapterId)`, and `GET /api/learning-chapters/:chapterId`.
- Consumes: existing knowledge atom IDs and learning CORS wrapper.

- [ ] Write failing tests asserting three visible phases and an ordered negative-number knowledge tree.
- [ ] Run the focused Vitest file and confirm the chapter method/route is missing.
- [ ] Add strict DTO types, Mock Provider fixtures, and a read-only route with existing ownership/CORS conventions.
- [ ] Run the focused test and TypeScript check.
- [ ] Commit the backend chapter contract only.

### Task 2: Stuck-state and repetition-safe dialogue

**Files:**
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/dialogueEngine.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/strategyEngine.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/learning-session/sessionService.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionTeachingEngine.test.ts`
- Test: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/learningSessionService.test.ts`

**Interfaces:**
- Consumes: current path and `isStuck` signal.
- Produces: contextual local fallback turns with lower-threshold follow-up questions and normalized recent-turn deduplication.

- [ ] Write failing tests reproducing “不懂” followed by a self-explanation prompt and repeated fallback output.
- [ ] Run the focused tests and confirm both behaviors fail.
- [ ] Add stuck-specific answer/follow-up generation and recent answer/question avoidance to local fallback and production prompt context.
- [ ] Run all learning-session backend tests and `npx tsc --noEmit`.
- [ ] Commit the dialogue behavior change.

### Task 3: Flutter chapter models and transport

**Files:**
- Modify: `lib/features/dialogue_exploration/adapters/remote_exploration_dto.dart`
- Modify: `lib/features/dialogue_exploration/adapters/remote_exploration_api.dart`
- Modify: `lib/features/dialogue_exploration/core/remote_exploration_session_controller.dart`
- Test: `test/features/dialogue_exploration/remote_exploration_session_controller_test.dart`

**Interfaces:**
- Consumes: `GET /api/learning-chapters/:chapterId`.
- Produces: `LearningChapterOverviewSnapshot`, selected chapter node state, and `startFromChapterNode(nodeId)`.

- [ ] Write failing controller tests for loading a chapter, selecting a node without mutation, and starting with that node's atom/hook question.
- [ ] Run the focused Flutter test and confirm the new API/state is absent.
- [ ] Add strict DTO parsing, timeout-safe API transport, and controller selection/start behavior.
- [ ] Run the focused controller tests.
- [ ] Commit transport and controller changes.

### Task 4: Chapter workspace and dual trees

**Files:**
- Create: `lib/features/dialogue_exploration/presentation/chapter_workspace_components.dart`
- Modify: `lib/features/dialogue_exploration/presentation/remote_exploration_page.dart`
- Test: `test/features/dialogue_exploration/chapter_workspace_page_test.dart`
- Modify: `test/features/dialogue_exploration/live_tree_page_test.dart`

**Interfaces:**
- Consumes: chapter snapshot and remote learning session controller.
- Produces: phase cards, chapter route, chapter/personal tree switcher, and responsive single-page workspace.

- [ ] Write failing widget tests for the three phase cards, chapter nodes, node-start behavior, and independent tree tabs.
- [ ] Run the focused widget tests and verify missing UI failures.
- [ ] Build the chapter header, phase overview, node map, and dual-tree panel without duplicating API state.
- [ ] Run the focused tests and the full dialogue-exploration test directory.
- [ ] Commit the chapter workspace UI.

### Task 5: Unify entry and browser verification

**Files:**
- Modify: `lib/developer_tools.dart`
- Modify: `lib/features/dialogue_exploration/dialogue_exploration.dart`
- Modify: `lib/features/dialogue_exploration/dialogue_exploration_demo.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: `RemoteExplorationLabPage` chapter workspace.
- Produces: one developer/browser entry with no legacy Mock Gateway route.

- [ ] Write or update the entry test to assert the chapter workspace title and absence of the legacy Mock notice.
- [ ] Run the test and verify it fails before route/copy changes.
- [ ] Point all 1.2 developer/demo entry code at the chapter workspace and remove legacy wording.
- [ ] Run widget tests, module analysis, and a debug web build against `API_BASE_URL=http://localhost:3000`.
- [ ] Restart the existing local backend/browser processes and smoke-test chapter load, stuck response, and dual-tree switching.
- [ ] Commit the entry integration.

