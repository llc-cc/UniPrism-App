# Practice Formula Keyboard Mobile IME Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move case switching into a phone-style `⇧ 大写` key on the alphabet page and make Chinese entry explicitly use the platform text IME.

**Architecture:** Keep the existing controlled 26-letter catalog and escaped text insertion helper. Restrict this refinement to `PracticeFormulaKeyboard`: `abc` selects the alphabet page, the alphabet grid owns case state through a selected shift key, and the native text dialog requests the platform text keyboard with suggestions.

**Tech Stack:** Flutter, Dart, `math_keyboard`, `flutter_test`.

## Global Constraints

- Preserve the existing practice draft and backend answer protocol.
- The lower-case state has no `小写` label; the only case control label is `⇧ 大写`.
- Do not implement a custom Pinyin dictionary or candidate bar.
- Mobile uses the operating system IME; desktop Web uses the installed desktop IME.
- Add no package, network request, database table, or backend field.
- Follow TDD and verify the complete Flutter suite before completion.

---

### Task 1: Phone-style shift key

**Files:**
- Modify: `lib/features/practice_assessment/presentation/practice_formula_keyboard.dart`
- Modify: `test/features/practice_assessment/practice_formula_keyboard_test.dart`

**Interfaces:**
- Consumes: `practiceFormulaAlphabetKeys({required bool uppercase})`.
- Produces: widget key `practice-formula-key-uppercase`; `abc` remains `practice-formula-key-more-shortcut`.

- [ ] **Step 1: Write the failing widget test**

Assert that `abc` opens the letters page without changing case; the grid contains `⇧ 大写`, `中文`, and all 26 letters; tapping `practice-formula-key-uppercase` highlights that key and changes `a/z` to `A/Z`; tapping it again removes the highlight and restores lower-case labels. Assert no `小写` text is rendered.

- [ ] **Step 2: Run the keyboard test and verify RED**

Run: `flutter test test/features/practice_assessment/practice_formula_keyboard_test.dart`

Expected: FAIL because case still toggles through `abc` and the alphabet grid has no `uppercase` key.

- [ ] **Step 3: Implement the minimal shift behavior**

Change `_handleAlphabetShortcut()` to select only `PracticeFormulaKeyboardCategory.letters`. Insert a selected `_textActionButton` with id `uppercase`, label `⇧ 大写`, and an `onPressed` callback that toggles `_uppercaseLetters`; keep seven columns so the two controls plus 26 letters occupy exactly four rows.

- [ ] **Step 4: Run the keyboard test and verify GREEN**

Run: `flutter test test/features/practice_assessment/practice_formula_keyboard_test.dart`

Expected: all keyboard tests pass without overflow.

### Task 2: Explicit platform Chinese IME configuration

**Files:**
- Modify: `lib/features/practice_assessment/presentation/practice_formula_keyboard.dart`
- Modify: `test/features/practice_assessment/practice_formula_keyboard_test.dart`

**Interfaces:**
- Consumes: existing `_ChineseFormulaTextDialog` and `insertPracticeFormulaText(...)`.
- Produces: an autofocus native `TextField` configured with `TextInputType.text`, suggestions, autocorrect, and no automatic capitalization.

- [ ] **Step 1: Extend the failing Chinese input test**

Read the real `TextField` widget after tapping `practice-formula-key-chinese-input` and assert `autofocus == true`, `keyboardType == TextInputType.text`, `enableSuggestions == true`, `autocorrect == true`, and `textCapitalization == TextCapitalization.none`.

- [ ] **Step 2: Run the keyboard test and verify RED**

Run: `flutter test test/features/practice_assessment/practice_formula_keyboard_test.dart`

Expected: FAIL because the current field does not explicitly configure all platform IME properties.

- [ ] **Step 3: Configure the existing native field**

Set the five properties asserted above. Keep confirmation, cancellation, TeX escaping, and dialog-owned controller lifecycle unchanged.

- [ ] **Step 4: Run the keyboard test and verify GREEN**

Run: `flutter test test/features/practice_assessment/practice_formula_keyboard_test.dart`

Expected: all tests pass.

### Task 3: Verification and Web handoff

**Files:**
- Verify existing source and tests only.

**Interfaces:**
- Consumes: the completed shift and system IME behaviors.
- Produces: a fresh local Web test build; desktop testing uses the computer IME.

- [ ] **Step 1: Run the practice feature suite**

Run: `flutter test test/features/practice_assessment`

Expected: all tests pass.

- [ ] **Step 2: Run targeted static analysis**

Run: `flutter analyze lib/features/practice_assessment/presentation/practice_formula_keyboard.dart test/features/practice_assessment/practice_formula_keyboard_test.dart`

Expected: no issues found.

- [ ] **Step 3: Run the complete Flutter suite**

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 4: Build and serve a fresh Web bundle**

Build with the existing development Mock flags, serve `build/web` on a new localhost port, verify HTTP 200, and open `#/practice-assessment-lab`.

- [ ] **Step 5: Commit the scoped implementation**

Stage only the keyboard source, keyboard test, revised spec, and this plan. Commit message: `fix(practice): refine alphabet case and chinese ime`.

