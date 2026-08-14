# Practice Formula Keyboard Collapsible Section Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move secondary formula sections out of the content-area dropdown and into collapsible navigation owned by their primary category.

**Architecture:** Keep all UI state in `PracticeFormulaKeyboard`. Wide layout renders secondary buttons directly below the active primary button; narrow layout renders the same active section list in a collapsible horizontal panel below the primary rail. Existing catalog mappings remain the only source of category membership.

**Tech Stack:** Flutter 3 / Dart 3, Material 3 buttons and icons, `flutter_test`, `math_keyboard` 0.3.3.

## Global Constraints

- Work directly on `feat/practice-assessment-v1`; do not create a branch or worktree.
- Preserve the three primary categories, eight secondary sections, 20-item pagination, fixed numeric pad, uppercase state, deleted Chinese input, and LaTeX output.
- Remove `practice-formula-section-selector` and all dropdown-specific UI from the formula content area.
- Wide layout nests visible secondary items under the active primary; narrow layout places them in a collapsible row immediately below the horizontal primary rail.
- Switching primary categories selects the first section and resets pagination; collapsing the current primary changes display state only.
- Do not stage unrelated dirty files.

---

### Task 1: Replace the dropdown with collapsible primary-owned navigation

**Files:**
- Modify: `lib/features/practice_assessment/presentation/practice_formula_keyboard.dart`
- Modify: `test/features/practice_assessment/practice_formula_keyboard_test.dart`
- Modify: `test/features/practice_assessment/math_answer_field_test.dart`

**Interfaces:**
- Consumes: `practiceFormulaSectionsByPrimary`, `practiceFormulaSectionLabels`, `_selectSection(PracticeFormulaSection)`.
- Produces: `_sectionsExpanded`, `_handlePrimaryPressed(PracticeFormulaPrimaryCategory)`, `_sectionButton(PracticeFormulaSection, {required bool compact})`, keys `practice-formula-section-panel` and `practice-formula-section-<section.name>`.

- [ ] **Step 1: Rewrite the keyboard tests and verify RED**

Update the desktop test to assert that section buttons are visible in the navigation rail and the dropdown is absent:

```dart
expect(find.byKey(_sectionKey(PracticeFormulaSection.lettersAndNumbers)), findsOneWidget);
expect(
  find.byKey(const ValueKey('practice-formula-section-selector')),
  findsNothing,
);
```

Update the primary-category test to tap mathematics, assert only mathematics sections are present, tap mathematics again and assert all section keys are absent, then tap mathematics once more and assert they return without changing the active section grid.

In the 375px test, expect `practice-formula-section-panel`, assert the selector is absent, collapse the active primary and assert the panel disappears, then expand it before iterating sections.

Run:

```powershell
flutter test test\features\practice_assessment\practice_formula_keyboard_test.dart
```

Expected: FAIL because the current implementation still renders `practice-formula-section-selector` and has no collapsible section panel.

- [ ] **Step 2: Implement the minimal collapsible navigation**

In `practice_formula_keyboard.dart`:

```dart
bool _sectionsExpanded = true;

void _handlePrimaryPressed(PracticeFormulaPrimaryCategory primary) {
  if (primary == _primaryCategory) {
    setState(() => _sectionsExpanded = !_sectionsExpanded);
    return;
  }
  setState(() {
    _primaryCategory = primary;
    _section = practiceFormulaSectionsByPrimary[primary]!.first;
    _pageIndex = 0;
    _sectionsExpanded = true;
  });
}
```

Make `_primaryButton` call `_handlePrimaryPressed`, show `expand_more` only for the active expanded primary and `chevron_right` otherwise, and expose expanded semantics.

Restore `_sectionButton` as a compact nested button using the existing section labels and `_selectSection`. In the wide rail, emit the active primary's section buttons immediately after that primary when `_sectionsExpanded` is true. In narrow layout, add `_horizontalSectionPanel()` directly below `_horizontalPrimaryRail()` only while expanded.

Remove `_contentArea` and `_compactSectionSelector`; wide and narrow layouts render `_contentPad` directly. Update `_handleAlphabetShortcut` so it also sets `_sectionsExpanded = true`.

- [ ] **Step 3: Migrate integration-test section selection**

In both test files, `_selectSection`/`_selectFormulaSection` must tap the visible `practice-formula-section-<name>` button directly and pump, without opening a dropdown overlay.

- [ ] **Step 4: Format and verify GREEN**

Run:

```powershell
& 'D:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe' format lib\features\practice_assessment\presentation\practice_formula_keyboard.dart test\features\practice_assessment\practice_formula_keyboard_test.dart test\features\practice_assessment\math_answer_field_test.dart
flutter analyze lib\features\practice_assessment\presentation\practice_formula_keyboard.dart test\features\practice_assessment\practice_formula_keyboard_test.dart test\features\practice_assessment\math_answer_field_test.dart
flutter test test\features\practice_assessment
```

Expected: analyzer reports `No issues found` and all practice-assessment tests pass.

- [ ] **Step 5: Commit the implementation**

Mark the design status `已批准并实现`, run `git diff --check`, then commit only the design, keyboard, and two test files:

```powershell
git add -- docs/superpowers/specs/2026-08-14-practice-formula-keyboard-collapsible-section-navigation-design.md lib/features/practice_assessment/presentation/practice_formula_keyboard.dart test/features/practice_assessment/practice_formula_keyboard_test.dart test/features/practice_assessment/math_answer_field_test.dart
git commit -m "fix(practice): nest collapsible formula sections"
```

### Task 2: Refresh the local acceptance page

**Files:**
- Generated only: `build/web`

**Interfaces:**
- Consumes: committed Flutter source at `feat/practice-assessment-v1`.
- Produces: local Mock acceptance page on `http://127.0.0.1:5174/#/practice-assessment-lab`.

- [ ] **Step 1: Build the acceptance bundle**

```powershell
flutter build web --debug --dart-define=APP_ENV=development --dart-define=ENABLE_DEVELOPER_TOOLS=true --dart-define=PRACTICE_ASSESSMENT_REMOTE=false
```

- [ ] **Step 2: Restart only port 5174 and verify**

Resolve the exact PID listening on 5174, stop only that process, serve `build/web`, verify HTTP 200, and open the acceptance URL. Keep the existing backend on port 3000 untouched.
