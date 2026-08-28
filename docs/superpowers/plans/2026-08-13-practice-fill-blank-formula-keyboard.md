# Practice Fill-Blank Formula Keyboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the practice fill-blank plain text answer with a typeset LaTeX math field and keyboard, while preserving the existing draft/event/submit pipeline and making the backend accept the keyboard's safe LaTeX representations.

**Architecture:** Flutter owns formula editing and emits delimiter-free LaTeX through the existing `onAnswer(String)` callback. The practice controller and repository continue treating the answer as an opaque string. The backend validates fill-blank LaTeX before persistence/submission and canonicalizes only a controlled representation subset before the existing rule assessor compares answers.

**Tech Stack:** Flutter 3 / Dart 3.12, `math_keyboard` 0.3.3, Flutter Widget Tests, Next.js/TypeScript, KaTeX 0.16, Vitest.

## Global Constraints

- Only `PracticeQuestionType.fillBlank` uses the math field; choice and solution question controls remain unchanged.
- Stored answers are delimiter-free LaTeX strings, never rendered HTML, SVG, images, or client AST objects.
- Formula answers are limited to 1,500 characters in both Flutter and the backend formula boundary.
- Evidence-insufficient and existing cognition/profile behavior must not change.
- New modules, state synchronization, validation, and security branches require concise Chinese comments under `docs/DEVELOPMENT_CODE_STANDARD.md`.
- Preserve all unrelated dirty-worktree changes and stage only files listed by each task.

---

### Task 1: Add the Flutter math-field adapter

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/features/practice_assessment/presentation/practice_formula_config.dart`
- Create: `lib/features/practice_assessment/presentation/math_answer_field.dart`
- Create: `test/features/practice_assessment/math_answer_field_test.dart`

**Interfaces:**
- Consumes: `String value`, `ValueChanged<String> onChanged`, `bool enabled`, `String questionId`, and an optional `MathFieldEditingController` for deterministic integration tests.
- Produces: `MathAnswerField`, a stateful wrapper that emits delimiter-free LaTeX and synchronizes an externally restored value without echoing `onChanged`.

- [ ] **Step 1: Add only the package needed to compile the wished-for test API**

Add `math_keyboard: 0.3.3` under `dependencies`, then run:

```powershell
flutter pub get
```

Expected: `pubspec.lock` contains `math_keyboard` and its transitive dependencies.

- [ ] **Step 2: Write the failing adapter tests**

Create tests that use the public widget API:

```dart
await tester.pumpWidget(MaterialApp(
  home: MathKeyboardViewInsets(
    child: Scaffold(
      body: MathAnswerField(
        questionId: 'q12',
        value: r'\frac{3}{2}',
        enabled: true,
        controller: controller,
        onChanged: changes.add,
      ),
    ),
  ),
));
expect(find.byKey(const ValueKey('practice-math-answer-field')), findsOneWidget);
expect(changes, isEmpty);
```

Add a stateful host test that replaces `value` with `r'\sqrt{2}'` and verifies no callback is emitted during external synchronization. Add a user-edit test that calls `controller.addLeaf('2')` and verifies the callback receives `2` exactly once.

- [ ] **Step 3: Run the tests and verify RED**

Run:

```powershell
flutter test test/features/practice_assessment/math_answer_field_test.dart
```

Expected: FAIL because `MathAnswerField` does not exist.

- [ ] **Step 4: Implement the minimal adapter**

Implement `MathAnswerField` with:

```dart
final class MathAnswerField extends StatefulWidget {
  const MathAnswerField({
    super.key,
    required this.questionId,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.controller,
  });

  final String questionId;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final MathFieldEditingController? controller;
}
```

Create and dispose an owned `MathFieldEditingController` and `FocusNode`; never dispose a caller-supplied controller. Parse external strings with `TeXParser(value).parse()` and call `controller.updateValue(expression)`. In `didUpdateWidget`, update only when the external value differs and guard that write with `_isSynchronizingExternalValue`. Put `practiceFormulaVariables = ['x', 'y', 'z', 'a', 'b', 'c', 'n']` and `practiceFormulaAnswerMaxLength = 1500` in `practice_formula_config.dart`. Configure `MathField` with `MathKeyboardType.expression`, those variables, the practice purple focus border, a maximum-length error message, and keys `practice-math-answer-field` / `practice-math-answer-input`.

- [ ] **Step 5: Run the adapter tests and static analysis**

Run:

```powershell
flutter test test/features/practice_assessment/math_answer_field_test.dart
flutter analyze lib/features/practice_assessment/presentation/math_answer_field.dart lib/features/practice_assessment/presentation/practice_formula_config.dart
```

Expected: all adapter tests PASS; analysis has no new error.

- [ ] **Step 6: Commit the adapter**

```powershell
git add pubspec.yaml pubspec.lock lib/features/practice_assessment/presentation/practice_formula_config.dart lib/features/practice_assessment/presentation/math_answer_field.dart test/features/practice_assessment/math_answer_field_test.dart
git commit -m "feat(practice): add fill blank math input"
```

---

### Task 2: Wire the math field into the real practice page

**Files:**
- Modify: `lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart`
- Modify: `lib/features/practice_assessment/practice_assessment.dart`
- Modify: `test/features/practice_assessment/practice_assessment_lab_page_test.dart`
- Modify: `test/features/practice_assessment/practice_session_controller_test.dart`

**Interfaces:**
- Consumes: `MathAnswerField` from Task 1 and existing `PracticeSessionController.updateAnswer`.
- Produces: fill-blank-only formula editing through the unchanged `PracticeDraft.answer` and remote draft DTO.

- [ ] **Step 1: Write failing page integration tests**

Add Widget tests that load the mock paper, select question index `11` (question 12), and assert:

```dart
expect(find.byKey(const ValueKey('practice-math-answer-field')), findsOneWidget);
expect(find.byKey(const ValueKey('practice-answer-input')), findsNothing);
```

Switch to question index `18` and assert the solution text input still exists and the math field does not. Add a draft test that writes `r'\frac{3}{2}'`, switches to question 13, returns to question 12, and expects `controller.state.currentDraft.answer` to remain the same.

- [ ] **Step 2: Run page tests and verify RED**

Run:

```powershell
flutter test test/features/practice_assessment/practice_assessment_lab_page_test.dart test/features/practice_assessment/practice_session_controller_test.dart
```

Expected: FAIL because fill-blank still renders `TextFormField`.

- [ ] **Step 3: Implement page integration**

Wrap the page's `Scaffold` with `MathKeyboardViewInsets`. In `_QuestionCard`, render:

```dart
if (question.type == PracticeQuestionType.fillBlank)
  MathAnswerField(
    key: ValueKey('practice-math-answer-${question.id}'),
    questionId: question.id,
    value: draft.answer,
    enabled: !isSubmitting,
    onChanged: onAnswer,
  )
else if (!isChoice)
  // existing TextFormField for solution questions
```

Do not change the controller, repository DTO, or event payload. Export the new widget only if tests or another feature require the public barrel.

- [ ] **Step 4: Run integration and repository regression tests**

Run:

```powershell
flutter test test/features/practice_assessment/practice_assessment_lab_page_test.dart test/features/practice_assessment/practice_session_controller_test.dart test/features/practice_assessment/remote_practice_repository_test.dart
```

Expected: all tests PASS and the repository request body still contains the exact LaTeX answer string.

- [ ] **Step 5: Commit page integration**

```powershell
git add lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart lib/features/practice_assessment/practice_assessment.dart test/features/practice_assessment/practice_assessment_lab_page_test.dart test/features/practice_assessment/practice_session_controller_test.dart
git commit -m "feat(practice): use math keyboard for fill blanks"
```

---

### Task 3: Validate and canonicalize fill-blank LaTeX on the backend

**Files:**
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/practice-assessment/formulaAnswer.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/practice-assessment/factExtractor.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/lib/practice-assessment/sessionService.ts`
- Create: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/practiceFormulaAnswer.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/practiceAssessmentEvidence.test.ts`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/tests/unit/practiceAssessmentService.test.ts`

**Interfaces:**
- Produces: `validateFillBlankFormula(value: string): void` and `canonicalizeFillBlankAnswer(value: string): string`.
- Consumes: KaTeX with `{ throwOnError: true, trust: false, strict: 'warn' }` and the existing `normalizePracticeAnswer` call site.

- [ ] **Step 1: Write failing formula boundary tests**

Cover the exact accepted/rejected behavior:

```ts
expect(canonicalizeFillBlankAnswer(String.raw`\frac{3}{2}`)).toBe('3/2');
expect(canonicalizeFillBlankAnswer(String.raw`\sqrt{2}`)).toBe('sqrt(2)');
expect(() => validateFillBlankFormula(String.raw`\fracc{3}{2}`)).toThrow();
expect(() => validateFillBlankFormula(String.raw`\href{https://x.test}{x}`)).toThrow();
expect(() => validateFillBlankFormula('x'.repeat(1501))).toThrow();
```

Add an evidence test proving a `FILL_BLANK` answer `r'\frac{3}{2}'` is `CORRECT` against rubric answer `3/2`, while selection and solution normalization remain unchanged.

- [ ] **Step 2: Run formula/evidence tests and verify RED**

Run from the backend repository:

```powershell
npm test -- --run tests/unit/practiceFormulaAnswer.test.ts tests/unit/practiceAssessmentEvidence.test.ts
```

Expected: FAIL because the formula module and canonicalization do not exist.

- [ ] **Step 3: Implement controlled validation and canonicalization**

`validateFillBlankFormula` must reject empty input, values over 1,500 characters, and trust/HTML/URL/macro commands before calling KaTeX strict parsing. Convert the keyboard-generated subset deterministically:

- normalize Unicode `× ÷ π ≤ ≥ ≠` to controlled TeX/infix equivalents;
- recursively convert `\frac{a}{b}` to `a/b` with parentheses only when an operand is composite;
- convert `\sqrt{a}` to `sqrt(a)`;
- normalize `\times`, `\cdot`, `\div`, `\pi`, `\le`, `\ge`, and `\ne`;
- remove TeX layout-only whitespace without proving symbolic identities.

Call `canonicalizeFillBlankAnswer` only for `FILL_BLANK` inside `normalizePracticeAnswer`.

- [ ] **Step 4: Add service RED tests for no-write validation**

In `practiceAssessmentService.test.ts`, create repository doubles whose `saveDraft` and `createAttemptWithObservationsAndProfile` increment counters. Verify malformed/overlong fill-blank formulas reject before either counter changes. Also verify a valid `r'\frac{3}{2}'` draft reaches the existing write path.

- [ ] **Step 5: Run service test and verify RED**

```powershell
npm test -- --run tests/unit/practiceAssessmentService.test.ts
```

Expected: FAIL because `saveDraft` and `submitAttempt` do not call formula validation.

- [ ] **Step 6: Wire validation into both write boundaries**

In `saveDraft`, after resolving the question and before `repository.saveDraft`, validate `input.answer` when `question.type === 'FILL_BLANK'`. In the locked submit transaction, validate `progress.answer` before constructing `assessmentInput`. Translate validation failures to an `ApiError('VALIDATION_ERROR', '数学公式格式不正确，请检查后重试。', 422)` without echoing the submitted formula.

- [ ] **Step 7: Run backend practice tests, typecheck, and lint**

```powershell
npm test -- --run tests/unit/practiceFormulaAnswer.test.ts tests/unit/practiceAssessmentEvidence.test.ts tests/unit/practiceAssessmentService.test.ts
npm test -- --run tests/unit/practice*.test.ts
npm run typecheck
npx eslint lib/practice-assessment/formulaAnswer.ts lib/practice-assessment/factExtractor.ts lib/practice-assessment/sessionService.ts tests/unit/practiceFormulaAnswer.test.ts
```

Expected: all targeted tests PASS; typecheck and ESLint exit `0`.

- [ ] **Step 8: Commit backend formula support**

```powershell
git add lib/practice-assessment/formulaAnswer.ts lib/practice-assessment/factExtractor.ts lib/practice-assessment/sessionService.ts tests/unit/practiceFormulaAnswer.test.ts tests/unit/practiceAssessmentEvidence.test.ts tests/unit/practiceAssessmentService.test.ts
git commit -m "feat(practice): validate fill blank latex answers"
```

---

### Task 4: Complete end-to-end verification and handoff

**Files:**
- Modify: `docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md`
- Modify: `D:/ywkeji/Uniprism/UniPrism_New-main/docs/PRACTICE_ASSESSMENT_V1_OPERATIONS.md`

**Interfaces:**
- Consumes: the completed Flutter math field and backend formula boundary.
- Produces: executable test instructions for question 12–14 in Mock and Remote modes.

- [ ] **Step 1: Update the handoff documents**

Document that fill-blank answers are delimiter-free LaTeX, list questions 12–14 as the manual test path, and state that `\frac{3}{2}` must be accepted against the existing `3/2` rubric answer. Include the existing Remote App command/URL and the backend start prerequisite without duplicating secrets.

- [ ] **Step 2: Run the full scoped frontend gate**

```powershell
flutter test test/features/practice_assessment
flutter analyze lib/features/practice_assessment test/features/practice_assessment
```

Expected: all practice Flutter tests PASS; analyze has no new error.

- [ ] **Step 3: Run the full scoped backend gate**

```powershell
npm test -- --run tests/unit/practice*.test.ts
npm run typecheck
```

Expected: all practice backend tests PASS; typecheck exits `0`.

- [ ] **Step 4: Perform a local browser smoke test**

Start/reuse backend port `3000`, build/serve the Flutter Web app on `5173` in Remote mode, open `/#/practice-assessment-lab`, select question 12, enter a fraction using the math keyboard, switch away and back, submit, then refresh and verify the saved formula is restored and judged correctly.

- [ ] **Step 5: Commit handoff updates**

Commit only the two documentation files in their respective repositories:

```powershell
git add docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md
git commit -m "docs(practice): hand off formula keyboard testing"
```

```powershell
git add docs/PRACTICE_ASSESSMENT_V1_OPERATIONS.md
git commit -m "docs(practice): document latex answer operations"
```
