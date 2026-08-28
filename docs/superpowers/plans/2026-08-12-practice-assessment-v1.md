# Practice Assessment V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an independent Flutter practice-assessment laboratory that loads a 19-item 2026 New Gaokao I Mathematics structure demo, records structured answers, produces deterministic answer results and evidence-aware ability observations, and exposes the future training-data contract.

**Architecture:** Add a new `lib/features/practice_assessment/` feature root with domain models and ports in `core`, orchestration in `application`, an in-memory V1 adapter in `adapters`, and UI in `presentation`. The module does not import `dialogue_exploration`; production HTTP and model inference remain behind ports while V1 runs entirely with self-authored demo content.

**Tech Stack:** Dart 3.12, Flutter Material 3, `ChangeNotifier`, `flutter_test`; no new dependencies.

## Global Constraints

- Work only on branch `feat/practice-assessment-v1` and stage only files listed by this plan.
- Follow `docs/DEVELOPMENT_CODE_STANDARD.md`; new public models, controllers, asynchronous flows, and evidence-safety branches require concise Chinese comments.
- Do not copy third-party recalled exam text. The mock catalog uses self-authored demonstration prompts while preserving the 8 single-choice, 3 multiple-choice, 3 fill-in, and 5 solution-question structure.
- `0..4` is the only persisted per-attempt ability band. Missing evidence is `insufficientEvidence`, never band `0`.
- The Flutter client does not infer long-term mastery or claim model confidence. V1 shows deterministic results and evidence observations only.
- No module under `lib/features/practice_assessment/` may import `features/dialogue_exploration`.
- Run focused tests after each task; before completion run `dart analyze lib/main.dart lib/developer_tools.dart lib/features/practice_assessment test/features/practice_assessment test/widget_test.dart` and relevant Flutter tests.

## File Structure

- `lib/features/practice_assessment/core/practice_models.dart`: immutable paper, question, rubric, draft, result, evidence, and training projection types.
- `lib/features/practice_assessment/core/practice_ports.dart`: repository and assessor interfaces.
- `lib/features/practice_assessment/core/rule_based_attempt_assessor.dart`: deterministic V1 answer judge and evidence generator.
- `lib/features/practice_assessment/core/ability_profile_aggregator.dart`: evidence-only profile aggregation for the local summary.
- `lib/features/practice_assessment/adapters/mock_gaokao_math_repository.dart`: 19-item self-authored structure demo and in-memory submissions.
- `lib/features/practice_assessment/application/practice_session_controller.dart`: loading, draft, navigation, submit, retry, and completion state.
- `lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart`: complete scrollable laboratory UI.
- `lib/features/practice_assessment/practice_assessment.dart`: stable public exports.
- `lib/main.dart`, `lib/developer_tools.dart`: one independent developer-tool entry.
- `test/features/practice_assessment/*.dart`, `test/widget_test.dart`: domain, controller, UI, and navigation regression tests.

---

### Task 1: Versioned domain contract and 19-item catalog

**Files:**
- Create: `lib/features/practice_assessment/core/practice_models.dart`
- Create: `lib/features/practice_assessment/core/practice_ports.dart`
- Create: `lib/features/practice_assessment/adapters/mock_gaokao_math_repository.dart`
- Create: `lib/features/practice_assessment/practice_assessment.dart`
- Test: `test/features/practice_assessment/practice_catalog_test.dart`

**Interfaces:**
- Produces: `PracticePaper`, `PracticeQuestion`, `QuestionRubric`, `QuestionDifficultyProfile`, `PracticeDraft`, `PracticeAttemptFacts`, `AbilityObservation`, `AttemptAssessment`, `TrainingExampleV1`, `PracticeRepository`, and `AttemptAssessor`.
- Produces: `MockGaokaoMathRepository.loadPaper()` returning exactly 19 ordered questions.

- [ ] **Step 1: Write the failing catalog and contract tests**

Create `test/features/practice_assessment/practice_catalog_test.dart` with assertions equivalent to:

```dart
test('2026 新高考 I 卷结构演示包含 19 题并保持题型分布', () async {
  final paper = await MockGaokaoMathRepository().loadPaper();

  expect(paper.id, 'cn-gaokao-2026-new-i-math-v1');
  expect(paper.questions.map((item) => item.number), orderedEquals(List.generate(19, (i) => i + 1)));
  expect(paper.questions.where((q) => q.type == PracticeQuestionType.singleChoice), hasLength(8));
  expect(paper.questions.where((q) => q.type == PracticeQuestionType.multipleChoice), hasLength(3));
  expect(paper.questions.where((q) => q.type == PracticeQuestionType.fillBlank), hasLength(3));
  expect(paper.questions.where((q) => q.type == PracticeQuestionType.solution), hasLength(5));
  expect(paper.isAuthorizedOfficialContent, isFalse);
});

test('能力证据不足时不能携带分数', () {
  expect(
    () => AbilityObservation(
      dimension: AbilityDimension.understanding,
      status: AbilityEvidenceStatus.insufficientEvidence,
      band: 2,
      confidence: 0,
      evidenceStepIds: const [],
      factCodes: const [],
      errorTags: const [],
    ),
    throwsArgumentError,
  );
});
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
flutter test test/features/practice_assessment/practice_catalog_test.dart
```

Expected: compilation fails because the practice-assessment library does not exist.

- [ ] **Step 3: Implement immutable domain models and ports**

Define these exact enum values and invariants in `practice_models.dart`:

```dart
enum PracticeQuestionType { singleChoice, multipleChoice, fillBlank, solution }
enum AbilityDimension { reading, understanding, calculation, reasoning, technique, selfCorrection, expression }
enum AbilityEvidenceStatus { observed, insufficientEvidence, notApplicable }
enum AttemptOutcome { correct, partiallyCorrect, incorrect }
enum PracticeContentSource { authorized, demonstration }
```

`AbilityObservation` must reject a non-null band for non-`observed` states, reject missing bands for `observed`, reject bands outside `0..4`, and reject confidence outside `0..1`. All exposed lists and maps must be unmodifiable.

Define ports in `practice_ports.dart`:

```dart
abstract interface class PracticeRepository {
  Future<PracticePaper> loadPaper();
  Future<AttemptAssessment> submitAttempt({
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
  });
}

abstract interface class AttemptAssessor {
  AttemptAssessment assess({
    required PracticeQuestion question,
    required PracticeDraft draft,
    required PracticeAttemptFacts facts,
  });
}
```

- [ ] **Step 4: Implement the self-authored 19-item structure catalog**

`MockGaokaoMathRepository` must construct 19 original demonstration questions with IDs `gk-2026-n1-math-q01` through `q19`, the required type distribution, at least one rubric step per question, a six-dimensional `0..4` difficulty profile, answer options for objective questions, and normalized expected answers. Set `isAuthorizedOfficialContent` to `false` and render a visible disclaimer in the paper title/subtitle.

Do not use any third-party question wording. The prompts should be short self-authored examples such as sample median, vector coefficient comparison, derivative tangent, conic parameters, probability distribution, and proof-step demonstrations.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```powershell
dart format lib/features/practice_assessment test/features/practice_assessment/practice_catalog_test.dart
flutter test test/features/practice_assessment/practice_catalog_test.dart
```

Expected: all catalog and invariant tests pass.

- [ ] **Step 6: Commit the domain slice**

```powershell
git add lib/features/practice_assessment/core lib/features/practice_assessment/adapters/mock_gaokao_math_repository.dart lib/features/practice_assessment/practice_assessment.dart test/features/practice_assessment/practice_catalog_test.dart
git commit -m "feat(practice): add assessment domain and paper catalog"
```

### Task 2: Deterministic answer judge, evidence scoring, and training projection

**Files:**
- Create: `lib/features/practice_assessment/core/rule_based_attempt_assessor.dart`
- Create: `lib/features/practice_assessment/core/ability_profile_aggregator.dart`
- Test: `test/features/practice_assessment/rule_based_attempt_assessor_test.dart`
- Test: `test/features/practice_assessment/ability_profile_aggregator_test.dart`

**Interfaces:**
- Consumes: Task 1 domain models.
- Produces: `RuleBasedAttemptAssessor.assess(...)` and `AbilityProfileAggregator.aggregate(Iterable<AttemptAssessment>)`.

- [ ] **Step 1: Write failing assessor tests for answer-only, reasoned, and revised attempts**

Cover these cases:

```dart
test('正确客观答案但没有过程时只形成确定结果', () {
  final assessment = assessor.assess(
    question: singleChoiceQuestion,
    draft: const PracticeDraft(answer: 'B', reasoning: '', revisionCount: 0),
    facts: const PracticeAttemptFacts(hintCount: 0, submissionCount: 1, durationSeconds: 30),
  );

  expect(assessment.outcome, AttemptOutcome.correct);
  expect(assessment.observationFor(AbilityDimension.understanding).status, AbilityEvidenceStatus.insufficientEvidence);
  expect(assessment.observationFor(AbilityDimension.reasoning).status, AbilityEvidenceStatus.insufficientEvidence);
});

test('命中 rubric 关键步骤时形成可追溯的理解和推理证据', () {
  final assessment = assessor.assess(
    question: reasoningQuestion,
    draft: const PracticeDraft(
      answer: '4',
      reasoning: '先利用总和约束，再用奇偶性排除，最后构造验证。',
      revisionCount: 0,
    ),
    facts: const PracticeAttemptFacts(hintCount: 0, submissionCount: 1, durationSeconds: 95),
  );

  expect(assessment.observationFor(AbilityDimension.reasoning).status, AbilityEvidenceStatus.observed);
  expect(assessment.observationFor(AbilityDimension.reasoning).evidenceStepIds, isNotEmpty);
});
```

Also test normalized single/multiple choice answers, whitespace-tolerant fill answers, partial solution-step matches, assisted evidence after hints, self-correction after revisions, and `TrainingExampleV1` containing no identity field.

- [ ] **Step 2: Run assessor tests and verify RED**

Run:

```powershell
flutter test test/features/practice_assessment/rule_based_attempt_assessor_test.dart test/features/practice_assessment/ability_profile_aggregator_test.dart
```

Expected: compilation fails because the assessor and aggregator are missing.

- [ ] **Step 3: Implement deterministic assessment rules**

Implement the following V1 behavior:

- Normalize choice answers by uppercase and sort multiple selections.
- Normalize free text by trimming whitespace and full-width punctuation only; do not claim symbolic algebra equivalence.
- Determine `correct`, `partiallyCorrect`, or `incorrect` from expected answers and matched rubric steps.
- A blank reasoning field yields `insufficientEvidence` for reading, understanding, reasoning, technique, and expression.
- Matching rubric step keywords yields `observed` evidence with real rubric step IDs; more independent matched steps raise bands up to `4`.
- A calculation-observable question may emit calculation evidence from a submitted numeric/expression answer; correctness alone does not create understanding evidence.
- `hintCount > 0` adds `assisted` to fact codes and caps affected evidence bands at `3`.
- `revisionCount > 0` produces self-correction evidence only when a later answer is correct or more rubric steps are matched.
- Every assessment carries `assessorVersion = 'rule-v1'` and `rubricVersion` copied from the question.

Add concise Chinese comments explaining why missing evidence is not a low score and why assisted completion is capped.

- [ ] **Step 4: Implement evidence-only profile aggregation**

`AbilityProfileAggregator` ignores non-observed dimensions, weights bands by confidence, returns `0..100` estimates, sample counts, and confidence. It must not fabricate an entry for a dimension with zero observations.

- [ ] **Step 5: Run focused tests and verify GREEN**

```powershell
dart format lib/features/practice_assessment test/features/practice_assessment
flutter test test/features/practice_assessment/rule_based_attempt_assessor_test.dart test/features/practice_assessment/ability_profile_aggregator_test.dart
```

Expected: all assessor and aggregator tests pass.

- [ ] **Step 6: Commit the scoring slice**

```powershell
git add lib/features/practice_assessment/core/rule_based_attempt_assessor.dart lib/features/practice_assessment/core/ability_profile_aggregator.dart test/features/practice_assessment/rule_based_attempt_assessor_test.dart test/features/practice_assessment/ability_profile_aggregator_test.dart
git commit -m "feat(practice): score deterministic ability evidence"
```

### Task 3: Session controller and in-memory repository flow

**Files:**
- Create: `lib/features/practice_assessment/application/practice_session_controller.dart`
- Modify: `lib/features/practice_assessment/adapters/mock_gaokao_math_repository.dart`
- Modify: `lib/features/practice_assessment/practice_assessment.dart`
- Test: `test/features/practice_assessment/practice_session_controller_test.dart`

**Interfaces:**
- Consumes: `PracticeRepository` and Task 1/2 types.
- Produces: `PracticeSessionController`, `PracticeSessionState`, and `PracticeSessionStatus`.

- [ ] **Step 1: Write failing controller tests**

Test these state transitions:

```dart
test('load exposes 19 questions and starts from question one', () async {
  await controller.load();
  expect(controller.state.status, PracticeSessionStatus.ready);
  expect(controller.state.paper!.questions, hasLength(19));
  expect(controller.state.currentQuestion.number, 1);
});

test('failed submission keeps the draft and supports retry', () async {
  await controller.load();
  controller.updateAnswer('B');
  repository.failNextSubmission = true;

  await controller.submitCurrent();

  expect(controller.state.status, PracticeSessionStatus.failure);
  expect(controller.state.currentDraft.answer, 'B');
  await controller.retrySubmission();
  expect(controller.state.resultForCurrent, isNotNull);
});
```

Also cover reasoning updates, objective option toggles, per-question draft preservation, previous/next boundaries, no duplicate submit while submitting, and completion only after all 19 questions have a result.

- [ ] **Step 2: Run controller tests and verify RED**

```powershell
flutter test test/features/practice_assessment/practice_session_controller_test.dart
```

Expected: compilation fails because the controller does not exist.

- [ ] **Step 3: Implement the controller state machine**

Use these statuses:

```dart
enum PracticeSessionStatus { idle, loading, ready, submitting, failure, completed }
```

The controller must:

- expose immutable snapshots of drafts and results;
- preserve drafts when navigating and when submission fails;
- generate `PracticeAttemptFacts` from controller-known submission/revision counters;
- ignore reentrant submit calls while `submitting`;
- clear only the last error after a successful retry;
- dispose without asynchronous notification after disposal.

Add concise Chinese comments around asynchronous retry and stale-result protection.

- [ ] **Step 4: Connect the mock repository to `RuleBasedAttemptAssessor`**

The repository delegates `submitAttempt` to the assessor, stores assessments keyed by question ID for test inspection, and supports a one-shot `failNextSubmission` switch only in the mock adapter.

- [ ] **Step 5: Run controller tests and verify GREEN**

```powershell
dart format lib/features/practice_assessment test/features/practice_assessment/practice_session_controller_test.dart
flutter test test/features/practice_assessment/practice_session_controller_test.dart
```

- [ ] **Step 6: Commit the session slice**

```powershell
git add lib/features/practice_assessment/application lib/features/practice_assessment/adapters/mock_gaokao_math_repository.dart lib/features/practice_assessment/practice_assessment.dart test/features/practice_assessment/practice_session_controller_test.dart
git commit -m "feat(practice): orchestrate assessment sessions"
```

### Task 4: Practice laboratory UI

**Files:**
- Create: `lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart`
- Modify: `lib/features/practice_assessment/practice_assessment.dart`
- Test: `test/features/practice_assessment/practice_assessment_lab_page_test.dart`

**Interfaces:**
- Consumes: `PracticeSessionController`.
- Produces: `PracticeAssessmentLabPage` with injectable controller for tests and a default mock factory for developer tools.

- [ ] **Step 1: Write failing widget tests**

Cover loading, paper disclaimer, 19-item navigation, type-specific answer controls, optional reasoning, submit result, missing-evidence copy, retry, and long-content scrolling. Key expectations:

```dart
expect(find.byKey(const ValueKey('practice-paper-disclaimer')), findsOneWidget);
expect(find.textContaining('演示题目'), findsWidgets);
expect(find.byKey(const ValueKey('practice-question-1')), findsOneWidget);
expect(find.byKey(const ValueKey('practice-reasoning-input')), findsOneWidget);
expect(find.text('过程证据不足'), findsOneWidget);
```

- [ ] **Step 2: Run widget tests and verify RED**

```powershell
flutter test test/features/practice_assessment/practice_assessment_lab_page_test.dart
```

- [ ] **Step 3: Implement the responsive page**

The page contains:

- app bar title `练习评分实验室`;
- visible non-official-content disclaimer;
- progress summary and horizontal/wrapping 1–19 question navigator;
- question type, number, prompt, options, answer input, and optional reasoning input;
- previous, next, submit, and retry actions;
- deterministic result card and observed evidence list;
- explicit `过程证据不足` copy for dimensions without evidence;
- scrollable content on phone and constrained wide layout on desktop.

Do not display internal confidence values or convert a single attempt into a long-term mastery claim.

- [ ] **Step 4: Run widget tests and verify GREEN**

```powershell
dart format lib/features/practice_assessment test/features/practice_assessment/practice_assessment_lab_page_test.dart
flutter test test/features/practice_assessment/practice_assessment_lab_page_test.dart
```

- [ ] **Step 5: Commit the UI slice**

```powershell
git add lib/features/practice_assessment/presentation lib/features/practice_assessment/practice_assessment.dart test/features/practice_assessment/practice_assessment_lab_page_test.dart
git commit -m "feat(practice): add assessment laboratory UI"
```

### Task 5: Independent developer-tools entry

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/developer_tools.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `PracticeAssessmentLabPage.mock()` or equivalent default constructor.
- Produces: developer tool key `developer-tool-practice-assessment`.

- [ ] **Step 1: Add a failing navigation regression test**

Extend `test/widget_test.dart`:

```dart
testWidgets('developer tools opens the independent practice assessment lab', (tester) async {
  await pumpAtSize(tester, const Size(390, 1000), const DeveloperToolsPage());
  final entry = find.byKey(const ValueKey('developer-tool-practice-assessment'));
  expect(entry, findsOneWidget);
  await tester.tap(entry);
  await tester.pumpAndSettle();
  expect(find.text('练习评分实验室'), findsOneWidget);
});
```

- [ ] **Step 2: Run the navigation test and verify RED**

```powershell
flutter test test/widget_test.dart --plain-name "developer tools opens the independent practice assessment lab"
```

- [ ] **Step 3: Add the independent import and entry**

Import `features/practice_assessment/practice_assessment.dart` in `main.dart`. Add an entry before the dialogue exploration entry in `developer_tools.dart`:

- key: `developer-tool-practice-assessment`;
- icon: `Icons.fact_check_rounded`;
- title: `练习评分实验室`;
- description: `19 题作答、规则判题与能力证据`;
- navigation target: the mock-backed practice page.

Do not pass a dialogue/prestudy controller into the page.

- [ ] **Step 4: Run the navigation regression and focused practice tests**

```powershell
dart format lib/main.dart lib/developer_tools.dart test/widget_test.dart
flutter test test/widget_test.dart --plain-name "developer tools opens the independent practice assessment lab"
flutter test test/features/practice_assessment
```

- [ ] **Step 5: Commit the integration slice**

```powershell
git add lib/main.dart lib/developer_tools.dart test/widget_test.dart
git commit -m "feat(practice): expose independent assessment lab"
```

### Task 6: Full verification and module handoff

**Files:**
- Create: `docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md`
- Modify only if verification finds a practice-owned issue: files created or modified in Tasks 1–5.

**Interfaces:**
- Produces: commands, current V1 behavior, data ownership, production-backend boundary, and small-model training handoff.

- [ ] **Step 1: Write the handoff document**

Document:

- developer-tools navigation path;
- 19-item structure and demonstration-content disclaimer;
- domain/adapter/controller/UI boundaries;
- exact `PracticeRepository` and `AttemptAssessor` replacement points;
- training example fields and privacy exclusions;
- why V1 evidence is not a high-stakes diagnosis;
- production backend and authorized-content prerequisites.

- [ ] **Step 2: Run static analysis**

```powershell
dart analyze lib/main.dart lib/developer_tools.dart lib/features/practice_assessment test/features/practice_assessment test/widget_test.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Run all practice and integration tests**

```powershell
flutter test test/features/practice_assessment test/widget_test.dart test/developer_tools_web_test.dart
```

Expected: all tests pass. If unrelated existing tests fail, rerun the focused practice tests and record the unrelated failures separately.

- [ ] **Step 4: Verify separation and diff hygiene**

```powershell
rg -n "dialogue_exploration" lib/features/practice_assessment test/features/practice_assessment
git diff --check HEAD
git status --short
```

Expected: the `rg` command has no matches; `git diff --check HEAD` has no whitespace errors. Review `git status` and stage only practice-owned files because the worktree contains pre-existing unrelated changes.

- [ ] **Step 5: Commit the handoff**

```powershell
git add docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md
git commit -m "docs(practice): hand off assessment v1"
```

- [ ] **Step 6: Record final evidence**

Report the branch, commit list, focused test counts, static-analysis result, unchanged unrelated worktree files, and these known limitations: self-authored demonstration content, in-memory storage, rule-based evidence only, no production API, and no trained small-model weights.
