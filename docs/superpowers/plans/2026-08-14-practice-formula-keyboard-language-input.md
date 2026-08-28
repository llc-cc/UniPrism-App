# Practice Formula Keyboard Language Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add complete lower/upper-case Latin letters and safe native Chinese text insertion to the practice formula keyboard.

**Architecture:** Extend the controlled key catalog with a dedicated alphabet category and a pure text-to-TeX insertion helper. Keep case state and the native Chinese dialog in `PracticeFormulaKeyboard`, so answer persistence continues to receive one LaTeX string through the existing controller.

**Tech Stack:** Flutter, Dart, `math_keyboard`, `flutter_math_fork`, `flutter_test`.

## Global Constraints

- Preserve the existing practice draft and backend answer protocol.
- Insert Chinese as an escaped `\text{...}` node; empty or cancelled input is a no-op.
- Add no package or network dependency.
- Use TDD and run the practice feature suite plus targeted static analysis.

---

### Task 1: Alphabet catalog and safe text insertion

**Files:**
- Modify: `lib/features/practice_assessment/presentation/practice_formula_key_catalog.dart`
- Modify: `test/features/practice_assessment/practice_formula_key_catalog_test.dart`

**Interfaces:**
- Produces: `PracticeFormulaKeyboardCategory.letters`
- Produces: `practiceFormulaAlphabetKeys({required bool uppercase})`
- Produces: `insertPracticeFormulaText(MathFieldEditingController controller, String value)`

- [ ] **Step 1: Write failing catalog tests**

Assert literal category order, 26 lower-case labels, 26 upper-case labels, and escaped `\text{...}` insertion.

- [ ] **Step 2: Run the catalog test and verify RED**

Run: `flutter test test/features/practice_assessment/practice_formula_key_catalog_test.dart`

Expected: compile failure because the alphabet builder and text insertion helper do not exist.

- [ ] **Step 3: Implement the minimal catalog behavior**

Generate exactly 26 controlled key specs from ASCII code points. Escape `\\`, `{`, `}`, `%`, `_`, `#`, `$`, `&`, `^`, and `~` before inserting a `\text{...}` leaf.

- [ ] **Step 4: Run the catalog test and verify GREEN**

Run: `flutter test test/features/practice_assessment/practice_formula_key_catalog_test.dart`

Expected: all catalog tests pass.

### Task 2: Letter page, case switching, and Chinese dialog

**Files:**
- Modify: `lib/features/practice_assessment/presentation/practice_formula_keyboard.dart`
- Modify: `test/features/practice_assessment/practice_formula_keyboard_test.dart`

**Interfaces:**
- Consumes: alphabet keys and text insertion helper from Task 1.
- Produces: `practice-formula-key-chinese-input`, `practice-formula-chinese-field`, and `practice-formula-chinese-insert` user interactions.

- [ ] **Step 1: Write failing widget tests**

Verify that `abc` opens all 26 lower-case letters, a second tap switches to upper-case, a third tap returns to lower-case, and Chinese dialog confirmation inserts `\text{最大值}` while cancellation is a no-op.

- [ ] **Step 2: Run the keyboard test and verify RED**

Run: `flutter test test/features/practice_assessment/practice_formula_keyboard_test.dart`

Expected: failures for the missing letters category, case state, and Chinese dialog keys.

- [ ] **Step 3: Implement the minimal UI behavior**

Use seven columns for the letter grid, keep four columns for formula categories, let the existing `abc` shortcut toggle case only when the letter page is active, and show a native `AlertDialog` for Chinese text.

- [ ] **Step 4: Run the keyboard test and verify GREEN**

Run: `flutter test test/features/practice_assessment/practice_formula_keyboard_test.dart`

Expected: all keyboard tests pass with no overflow exception.

### Task 3: Regression verification and test build

**Files:**
- Verify only; no planned production file.

**Interfaces:**
- Consumes: completed catalog and UI behavior.
- Produces: a rebuilt local Web page for product testing.

- [ ] **Step 1: Run the practice feature suite**

Run: `flutter test test/features/practice_assessment`

Expected: all tests pass.

- [ ] **Step 2: Run targeted static analysis**

Run: `flutter analyze lib/features/practice_assessment/presentation/practice_formula_keyboard.dart lib/features/practice_assessment/presentation/practice_formula_key_catalog.dart test/features/practice_assessment/practice_formula_keyboard_test.dart test/features/practice_assessment/practice_formula_key_catalog_test.dart`

Expected: no issues found.

- [ ] **Step 3: Build Web and restart a fresh local port**

Run the existing development Mock build and serve `build/web` from a new localhost port so browser cache cannot reuse the previous keyboard bundle.

- [ ] **Step 4: Commit only scoped source and test files**

Commit message: `feat(practice): add alphabet and chinese formula input`
