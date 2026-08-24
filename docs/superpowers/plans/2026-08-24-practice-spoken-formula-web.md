# Practice Spoken Formula Web Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Chrome/Edge microphone flow that converts one short Chinese mathematical utterance into validated LaTeX, previews it, and inserts the confirmed candidate at the current formula cursor.

**Architecture:** `SpeechFormulaController` orchestrates an injected browser recognizer and spoken-formula repository. The remote repository calls the approved practice API; because the canonical backend source is unavailable, the mock lab receives an explicit demo-only converter so the full Web UI can be exercised safely. A separate guard validates LaTeX before the existing editor inserts it.

**Tech Stack:** Flutter Web, Dart 3.12, `speech_to_text` 7.4.0, `math_keyboard` 0.3.3, `flutter_math_fork` 0.7.4, `http` 1.2.2, Flutter Test.

**Spec:** `docs/superpowers/specs/2026-08-24-practice-spoken-formula-web-design.md`

## Global Constraints

- Initial runtime support is Flutter Web on Chrome and Edge only.
- Each run accepts one short `zh-CN` utterance; continuous dictation, audio upload, offline recognition, mobile permissions and whiteboard OCR are excluded.
- The client sends only final recognized text and contains no provider secret.
- Demo conversion is available only from `PracticeAssessmentLabPage.mock`; remote mode never falls back silently.
- Conversion must transcribe without solving, simplifying or correcting mathematics.
- Existing answer persistence remains one LaTeX string; confirmation is mandatory before insertion.
- New asynchronous and security branches require concise Chinese comments under `docs/DEVELOPMENT_CODE_STANDARD.md`.

## File Map

- Create `core/spoken_formula.dart` for immutable types and ports.
- Create `application/speech_formula_controller.dart` for cancel-safe orchestration.
- Create three `adapters/platform_speech_formula_recognizer*.dart` files for conditional Web support.
- Create `adapters/remote_spoken_formula_repository.dart` and `adapters/demo_spoken_formula_repository.dart`.
- Create `presentation/practice_formula_latex_guard.dart` and `presentation/practice_formula_voice_panel.dart`.
- Modify `presentation/math_answer_field.dart`, `presentation/practice_assessment_lab_page.dart`, `practice_assessment.dart`, `pubspec.yaml` and `pubspec.lock`.
- Add focused tests under `test/features/practice_assessment/`.

---

### Task 1: Domain Types and Cancel-Safe Controller

**Files:**
- Create: `lib/features/practice_assessment/core/spoken_formula.dart`
- Create: `lib/features/practice_assessment/application/speech_formula_controller.dart`
- Test: `test/features/practice_assessment/speech_formula_controller_test.dart`

**Interfaces:**
- Produces `SpeechFormulaRecognizer.initialize/listen/stop/cancel`.
- Produces `SpokenFormulaRepository.convert({required String text, String locale = 'zh-CN'})`.
- Produces `SpokenFormulaConversion(recognizedText, normalizedText, latex, alternatives, warnings)`.
- Produces `SpeechFormulaController.startListening/stopListening/retryConversion/selectCandidate/reset`.

- [ ] **Step 1: Write failing controller tests**

Cover success, permission denial, empty final text, conversion failure, retry, cancellation and stale callbacks. The critical stale-result test must follow this shape:

```dart
await controller.startListening();
recognizer.emit('x 的平方', isFinal: true);
await controller.reset();
repository.complete(conversion(latex: 'x^2'));
await Future<void>.delayed(Duration.zero);
expect(controller.state.status, SpeechFormulaStatus.idle);
expect(controller.state.conversion, isNull);
```

- [ ] **Step 2: Run RED test**

Run: `flutter test test/features/practice_assessment/speech_formula_controller_test.dart`

Expected: FAIL because the types do not exist.

- [ ] **Step 3: Implement the minimal ports and state machine**

Use statuses `idle`, `requestingPermission`, `listening`, `converting`, `preview`, `error`. Increment `_operationId` before every run and reset; after each `await`, update state only if the captured ID is current and the controller is not disposed. Trim final text, convert once, and expose a Chinese recovery message rather than raw exceptions.

- [ ] **Step 4: Run GREEN test**

Run: `flutter test test/features/practice_assessment/speech_formula_controller_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/practice_assessment/core/spoken_formula.dart lib/features/practice_assessment/application/speech_formula_controller.dart test/features/practice_assessment/speech_formula_controller_test.dart
git commit -m "feat(practice): add spoken formula state machine"
```

---

### Task 2: Remote and Demo Conversion Repositories

**Files:**
- Create: `lib/features/practice_assessment/adapters/remote_spoken_formula_repository.dart`
- Create: `lib/features/practice_assessment/adapters/demo_spoken_formula_repository.dart`
- Test: `test/features/practice_assessment/spoken_formula_repository_test.dart`

**Interfaces:**
- Consumes Task 1 repository/result types and existing `PracticeApiClient`.
- Produces `RemoteSpokenFormulaRepository(PracticeApiClient api)`.
- Produces `const DemoSpokenFormulaRepository()` for mock mode only.

- [ ] **Step 1: Write failing contract tests**

Assert remote `POST /api/practice/formulas/from-spoken-text` sends exactly:

```json
{"text":"x 的平方","locale":"zh-CN"}
```

Return a standard `{ok,data}` envelope and assert strict mapping of all five response fields. Add malformed-envelope tests. For demo mode assert `x 加 x` returns `x+x`, not `2x`.

- [ ] **Step 2: Run RED test**

Run: `flutter test test/features/practice_assessment/spoken_formula_repository_test.dart`

Expected: FAIL because adapters are missing.

- [ ] **Step 3: Implement strict adapters**

Remote mapping rejects blank required strings, ignores non-string list members and caps alternatives at two. Demo mode removes whitespace/full-width punctuation and supports these exact acceptance cases:

```dart
const exact = <String, String>{
  'x的平方加二x加一': 'x^2+2x+1',
  '根号下x加一': r'\sqrt{x+1}',
  '二分之一乘以mv的平方': r'\frac{1}{2}mv^2',
  '从零到一积分x的平方dx': r'\int_0^1x^2\,dx',
  'x加x': 'x+x',
};
```

`负二的平方` returns main `(-2)^2`, alternative `-2^2`, and a scope warning. Unsupported expressions throw `SpokenFormulaConversionException`; never guess a nearby formula.

- [ ] **Step 4: Run GREEN test**

Run: `flutter test test/features/practice_assessment/spoken_formula_repository_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/practice_assessment/adapters/remote_spoken_formula_repository.dart lib/features/practice_assessment/adapters/demo_spoken_formula_repository.dart test/features/practice_assessment/spoken_formula_repository_test.dart
git commit -m "feat(practice): add spoken formula repositories"
```

---

### Task 3: Web Speech Adapter

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/features/practice_assessment/adapters/platform_speech_formula_recognizer.dart`
- Create: `lib/features/practice_assessment/adapters/platform_speech_formula_recognizer_stub.dart`
- Create: `lib/features/practice_assessment/adapters/platform_speech_formula_recognizer_web.dart`
- Test: `test/features/practice_assessment/platform_speech_formula_recognizer_test.dart`

**Interfaces:**
- Consumes Task 1 recognizer port.
- Produces `SpeechFormulaRecognizer createPlatformSpeechFormulaRecognizer()`.

- [ ] **Step 1: Write a failing factory test**

Assert construction returns `SpeechFormulaRecognizer` and does not request permission. Real microphone behavior stays outside automated tests.

- [ ] **Step 2: Run RED test**

Run: `flutter test test/features/practice_assessment/platform_speech_formula_recognizer_test.dart`

Expected: FAIL because the factory is missing.

- [ ] **Step 3: Add dependency and adapters**

Add `speech_to_text: 7.4.0`. Conditional-export the stub unless `dart.library.js_interop` is available. The Web adapter owns one `SpeechToText`, initializes once, listens with `localeId: 'zh-CN'`, partial results enabled and `cancelOnError: true`, and maps `recognizedWords/finalResult` into the Task 1 callback. The stub returns unsupported and keeps stop/cancel idempotent. Do not log transcripts.

- [ ] **Step 4: Fetch and verify**

Run: `flutter pub get`

Run: `flutter test test/features/practice_assessment/platform_speech_formula_recognizer_test.dart test/features/practice_assessment/speech_formula_controller_test.dart`

Expected: PASS without opening permissions.

- [ ] **Step 5: Commit**

```powershell
git add -- pubspec.yaml pubspec.lock lib/features/practice_assessment/adapters/platform_speech_formula_recognizer.dart lib/features/practice_assessment/adapters/platform_speech_formula_recognizer_stub.dart lib/features/practice_assessment/adapters/platform_speech_formula_recognizer_web.dart test/features/practice_assessment/platform_speech_formula_recognizer_test.dart
git commit -m "feat(practice): add web speech recognizer"
```

---

### Task 4: LaTeX Guard and Cursor Insertion

**Files:**
- Create: `lib/features/practice_assessment/presentation/practice_formula_latex_guard.dart`
- Test: `test/features/practice_assessment/practice_formula_latex_guard_test.dart`

**Interfaces:**
- Produces `validatePracticeFormulaLatex(String)` with `isValid/errorMessage`.
- Produces `insertValidatedPracticeFormulaLatex(MathFieldEditingController, String)`.

- [ ] **Step 1: Write failing guard tests**

Cover valid fraction/root/integral/sum/limit; blank/overlength values; unbalanced rendering; and forbidden commands `def`, `newcommand`, `input`, `include`, `includegraphics`, `href`, `htmlClass`, `htmlId`, `style`, `url`. Verify cursor insertion:

```dart
final controller = MathFieldEditingController()
  ..addLeaf('a')
  ..addLeaf('b')
  ..goBack();
insertValidatedPracticeFormulaLatex(controller, r'\frac{1}{2}');
expect(controller.currentEditingValue(placeholderWhenEmpty: false),
    r'a\frac{1}{2}b');
```

- [ ] **Step 2: Run RED test**

Run: `flutter test test/features/practice_assessment/practice_formula_latex_guard_test.dart`

Expected: FAIL because the guard is missing.

- [ ] **Step 3: Implement allowlist, rendering check and insertion**

Allow only the initial formula commands used by the catalog and acceptance set. Require `Math.tex(latex).parseError == null`. Only then call `controller.addLeaf(latex)`, preserving the current cursor and treating the confirmed result as one atomic filled expression. Invalid input throws before mutation.

- [ ] **Step 4: Run GREEN test**

Run: `flutter test test/features/practice_assessment/practice_formula_latex_guard_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/practice_assessment/presentation/practice_formula_latex_guard.dart test/features/practice_assessment/practice_formula_latex_guard_test.dart
git commit -m "feat(practice): guard spoken formula latex"
```

---

### Task 5: Voice Status and Preview Panel

**Files:**
- Create: `lib/features/practice_assessment/presentation/practice_formula_voice_panel.dart`
- Test: `test/features/practice_assessment/practice_formula_voice_panel_test.dart`

**Interfaces:**
- Consumes Task 1 controller.
- Produces `PracticeFormulaVoicePanel(controller:, onInsert:)`.
- Produces keys `practice-formula-voice-start/stop/transcript/preview/retry/cancel/insert` and `practice-formula-voice-alternative-<index>`.

- [ ] **Step 1: Write failing Widget tests**

Cover idle, requesting permission, listening/partial transcript, converting, preview, alternatives/warnings, recoverable error, cancel and unsupported copy. Assert `onInsert` remains untouched until the insert button is tapped, then receives only the selected LaTeX. Render at 375px and require `tester.takeException()` to be null.

- [ ] **Step 2: Run RED test**

Run: `flutter test test/features/practice_assessment/practice_formula_voice_panel_test.dart`

Expected: FAIL because the panel is missing.

- [ ] **Step 3: Implement the responsive panel**

Use `AnimatedBuilder(animation: controller)`. Idle displays one outlined microphone action. Listening displays a red state indicator, transcript and Stop. Converting displays progress. Preview renders `Math.tex(selectedLatex)`, recognized text, warnings and candidate choices. Cancel/Retry/Insert use `Wrap` on narrow screens. Insert invokes `onInsert` then resets the controller; duplicate actions are disabled during asynchronous states.

- [ ] **Step 4: Run GREEN test**

Run: `flutter test test/features/practice_assessment/practice_formula_voice_panel_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/practice_assessment/presentation/practice_formula_voice_panel.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart
git commit -m "feat(practice): add spoken formula preview panel"
```

---

### Task 6: Formula Field and Lab Composition

**Files:**
- Modify: `lib/features/practice_assessment/presentation/math_answer_field.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart`
- Modify: `lib/features/practice_assessment/practice_assessment.dart`
- Modify: `test/features/practice_assessment/math_answer_field_test.dart`
- Test: `test/features/practice_assessment/practice_spoken_formula_composition_test.dart`

**Interfaces:**
- Adds optional `SpeechFormulaController? speechFormulaController` to `MathAnswerField`.
- Mock factory owns Web recognizer plus demo repository; remote factory owns Web recognizer plus remote repository using the same `PracticeApiClient`.

- [ ] **Step 1: Write failing integration tests**

Use a preview-ready injected controller. Focus the answer field, assert the voice panel appears above the keyboard, assert no answer change before confirmation, then tap Insert and assert one `onChanged` value with the candidate at the current cursor. Also cover controller omitted, disabled question, cancellation, and the combined 375px panel/keyboard layout.

- [ ] **Step 2: Run RED test**

Run: `flutter test test/features/practice_assessment/math_answer_field_test.dart test/features/practice_assessment/practice_spoken_formula_composition_test.dart`

Expected: FAIL because composition is absent.

- [ ] **Step 3: Integrate without changing persistence**

Place `PracticeFormulaVoicePanel` immediately before `PracticeFormulaKeyboard` only when focused, enabled and injected. On confirmation call the Task 4 insertion helper, derive `currentEditingValue(placeholderWhenEmpty: false)`, and pass it through `_handleChanged` exactly once. The page owns/disposes factory-created speech controllers and passes one through `_QuestionCard`. Remote failures remain remote failures; never switch to demo mode.

- [ ] **Step 4: Run focused practice suite**

Run: `flutter test test/features/practice_assessment`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/features/practice_assessment/presentation/math_answer_field.dart lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart lib/features/practice_assessment/practice_assessment.dart test/features/practice_assessment/math_answer_field_test.dart test/features/practice_assessment/practice_spoken_formula_composition_test.dart
git commit -m "feat(practice): integrate web spoken formula input"
```

---

### Task 7: Verification and Real Browser Acceptance

**Files:**
- Modify only explicit files required to correct failures introduced by Tasks 1–6.

**Interfaces:**
- Produces a verified Web build and a documented backend limitation.

- [ ] **Step 1: Format and analyze**

Run: `dart format lib/features/practice_assessment test/features/practice_assessment`

Run: `flutter analyze lib/features/practice_assessment test/features/practice_assessment`

Expected: no new analyzer errors.

- [ ] **Step 2: Run tests**

Run: `flutter test test/features/practice_assessment`

Expected: PASS.

Run: `flutter test`

Expected: PASS, or report unrelated pre-existing failures with exact names; no spoken-formula test may fail.

- [ ] **Step 3: Build Web**

Run: `flutter build web`

Expected: exit code 0 and generated `build/web` assets.

- [ ] **Step 4: Exercise the real microphone**

Run: `flutter run -d chrome`

On localhost, grant microphone access in the mock practice lab. Verify the five demo expressions, stop/cancel/retry, and the ambiguous negative-square candidate. Repeat permission/start/stop in Edge. Existing formula keyboard must remain usable throughout.

- [ ] **Step 5: Check secret and transcript safety**

Run: `rg -n "OPENAI_API_KEY|DEEPSEEK_API_KEY|app_key|print\(.*transcript" lib web`

Expected: no new embedded key or transcript logging.

- [ ] **Step 6: Commit only verification fixes when present**

Stage explicit filenames and commit `test(practice): verify web spoken formula flow`. Do not create an empty commit.

## Production Backend Follow-Up

The canonical Next.js backend source is absent from this workspace and from the currently accessible `llc-cc` repositories. This plan therefore delivers the real microphone flow, validated editor integration and complete remote contract, plus a demo-only converter for local Web testing. Remote mode will correctly surface a missing-route/service error until `/api/practice/formulas/from-spoken-text` is implemented in the canonical backend.

When that source is available, create a separate backend plan covering authenticated validation, per-identity rate limiting, structured model output, server-side LaTeX allowlisting, redacted logs and Vitest. Provider keys and production model calls must never be added to this Flutter repository.
