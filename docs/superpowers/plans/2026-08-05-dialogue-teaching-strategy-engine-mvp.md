# 1.2 Teaching Strategy Engine MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the scenario-selection lab with a conversation-first 10-minute micro-lesson that automatically combines five teaching strategies.

**Architecture:** Add a deterministic strategy engine between session state and the existing gateway. The engine selects one of five MVP modes from mastery, turn progress, recent student text, and error signals; the controller records every decision. Reuse the existing tree, material boundary, whiteboard, trace, and memory ports.

**Tech Stack:** Flutter, Dart, ChangeNotifier, flutter_test

## Global Constraints

- Students never choose a teaching mode or mastery level.
- One Teaching Engine selects modes; do not create separate agents.
- MVP modes are problem chain, Socratic questioning, error tracing, analogy transfer, and self explanation.
- All data remains deterministic Mock data and process-local.
- Existing material whitelist and input-boundary behavior must remain enforced.
- New state-machine and strategy decisions require concise Chinese comments.

---

### Task 1: Teaching strategy decision model

**Files:**
- Create: `lib/features/dialogue_exploration/teaching/teaching_strategy_engine.dart`
- Modify: `lib/features/dialogue_exploration/dialogue_exploration.dart`
- Test: `test/features/dialogue_exploration/teaching_strategy_engine_test.dart`

**Interfaces:**
- Consumes: `StudentMasterySnapshot`, recent student text, turn index, consecutive error count, closing flag.
- Produces: `TeachingStrategyDecision` with `mode`, `goal`, `reason`, `depth`, and `allowMaterial`.

- [ ] **Step 1: Write failing tests for all five mode triggers**

```dart
final mastery = StudentMasterySnapshot(
  atomId: 'negative-multiplication',
  level: StudentMasteryLevel.developing,
  recentEvidence: const [],
  misconceptionTags: const [],
  preferredMaterialKinds: const [],
  observedAt: DateTime.utc(2026, 8, 5),
  source: 'test',
);
expect(engine.decide(
  turnIndex: 0,
  studentText: '为什么负负得正？',
  consecutiveErrors: 0,
  isClosing: false,
  mastery: mastery,
).mode,
    TeachingDialogueMode.problemChain);
expect(engine.decide(
  turnIndex: 2,
  studentText: '太抽象了',
  consecutiveErrors: 0,
  isClosing: false,
  mastery: mastery,
).mode,
    TeachingDialogueMode.analogyTransfer);
expect(engine.decide(
  turnIndex: 2,
  studentText: '所以负负还是负数',
  consecutiveErrors: 1,
  isClosing: false,
  mastery: mastery,
).mode,
    TeachingDialogueMode.errorTracing);
expect(engine.decide(
  turnIndex: 5,
  studentText: '我来总结',
  consecutiveErrors: 0,
  isClosing: true,
  mastery: mastery,
).mode,
    TeachingDialogueMode.selfExplanation);
```

- [ ] **Step 2: Run `flutter test test/features/dialogue_exploration/teaching_strategy_engine_test.dart` and verify missing-type failures**
- [ ] **Step 3: Implement the enum, immutable decision, and priority rules**
- [ ] **Step 4: Re-run the focused test and verify all assertions pass**
- [ ] **Step 5: Commit the model and tests**

### Task 2: Session records automatic strategy changes

**Files:**
- Modify: `lib/features/dialogue_exploration/core/exploration_models.dart`
- Modify: `lib/features/dialogue_exploration/core/exploration_ports.dart`
- Modify: `lib/features/dialogue_exploration/core/teaching_session_controller.dart`
- Modify: `lib/features/dialogue_exploration/teaching/teaching_exploration_strategy.dart`
- Modify: `lib/features/dialogue_exploration/adapters/mock_exploration_gateway.dart`
- Test: `test/features/dialogue_exploration/adaptive_teaching_session_test.dart`

**Interfaces:**
- Consumes: `TeachingStrategyEngine.decide` before each gateway turn.
- Produces: active decision and immutable decision history in `TeachingSessionState`; each tutor node stores mode metadata.

- [ ] **Step 1: Write a failing controller test that starts in problem-chain mode, switches on an abstract/error signal, and ends in self-explanation mode**
- [ ] **Step 2: Run the focused test and verify state lacks strategy history**
- [ ] **Step 3: Thread decisions through request, response, node metadata, and controller state**
- [ ] **Step 4: Add deterministic Mock responses that express each strategy without empty “你觉得呢” prompts**
- [ ] **Step 5: Run focused and existing flow tests**
- [ ] **Step 6: Commit the controller integration**

### Task 3: Conversation-first lab entry

**Files:**
- Modify: `lib/features/dialogue_exploration/presentation/exploration_lab_page.dart`
- Modify: `lib/features/dialogue_exploration/presentation/exploration_session_page.dart`
- Modify: `lib/features/dialogue_exploration/adapters/mock_exploration_content_repository.dart`
- Test: `test/features/dialogue_exploration/exploration_page_test.dart`

**Interfaces:**
- Consumes: seed questions, automatically loaded Mock mastery, and `TeachingExplorationPage`.
- Produces: a chat-style opening screen with `exploration-topic-input`, seed chips, and a single start action; no mastery or mode selectors.

- [ ] **Step 1: Replace page expectations with a failing test for greeting, free input, seed question, and absence of old selectors**
- [ ] **Step 2: Run the page test and verify it fails against the scenario-card UI**
- [ ] **Step 3: Implement the conversation-first opening and resolve Mock scenario/mastery internally**
- [ ] **Step 4: Display progress and read-only strategy trace in the session page**
- [ ] **Step 5: Run page tests at standard and compact portrait sizes**
- [ ] **Step 6: Commit the UI replacement**

### Task 4: Session completion summary

**Files:**
- Modify: `lib/features/dialogue_exploration/core/exploration_outputs.dart`
- Modify: `lib/features/dialogue_exploration/presentation/exploration_session_page.dart`
- Test: `test/features/dialogue_exploration/exploration_flow_test.dart`
- Test: `test/features/dialogue_exploration/exploration_page_test.dart`

**Interfaces:**
- Consumes: tree, strategy history, confirmed diagnosis evidence, final self explanation.
- Produces: process-local Mock summary for thinking tree, understanding, error model, interest direction, and memory candidate.

- [ ] **Step 1: Write failing output and Widget tests for the five summary sections**
- [ ] **Step 2: Run focused tests and verify summary fields are missing**
- [ ] **Step 3: Build the summary from existing structured state without inventing unobserved evidence**
- [ ] **Step 4: Render the summary after self explanation and retain JSON export**
- [ ] **Step 5: Run all 1.2 tests and commit**

### Task 5: Final verification

**Files:**
- Verify: `lib/features/dialogue_exploration/**`
- Verify: `test/features/dialogue_exploration/**`
- Verify: `lib/main.dart`
- Verify: `test/widget_test.dart`

**Interfaces:**
- Consumes: completed MVP.
- Produces: reproducible verification evidence and a main-app testing path.

- [ ] **Step 1: Run `dart analyze lib/features/dialogue_exploration test/features/dialogue_exploration` and require no issues**
- [ ] **Step 2: Run `flutter test test/features/dialogue_exploration` and require all tests to pass**
- [ ] **Step 3: Run `flutter test` and require the repository suite to pass**
- [ ] **Step 4: Run `git diff --check` on owned files**
- [ ] **Step 5: Report the path `首页 → 开发者工具 → 1.2 对话探索实验室`, Mock boundaries, and remaining ten-mode roadmap**
