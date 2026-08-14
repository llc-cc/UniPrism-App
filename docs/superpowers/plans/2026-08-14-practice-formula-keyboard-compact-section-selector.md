# Practice Formula Keyboard Compact Section Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove free-form Chinese text input from the practice formula keyboard and replace secondary section button groups with the approved compact inline dropdown.

**Architecture:** Keep `PracticeFormulaKeyboard` as the sole owner of primary category, section, page, and letter-case UI state. The dropdown reads its options directly from `practiceFormulaSectionsByPrimary`, while the existing catalog, insertion strategies, `MathFieldEditingController`, draft flow, and backend contract remain unchanged.

**Tech Stack:** Flutter 3 / Dart 3, Material 3 `DropdownButton`, `flutter_test`, `math_keyboard` 0.3.3.

## Global Constraints

- Work only on `feat/practice-assessment-v1`; do not create another branch or worktree.
- Preserve the existing three primary categories, eight secondary sections, 20-item pagination, fixed numeric pad, uppercase state, and LaTeX output.
- “删除中文” means remove only the formula keyboard's free-form Chinese text entry; retain Chinese UI labels.
- Wide layout keeps primary categories in the left rail; narrow layout keeps the horizontal primary rail.
- The secondary selector is approximately 154px wide and 34px high, uses an overlay menu, and resets pagination on selection.
- Do not stage or modify unrelated dirty workspace files.
- New or materially changed state transitions require concise Chinese comments explaining the boundary or reason.

---

### Task 1: Remove Free-form Chinese Formula Input

**Files:**
- Modify: `test/features/practice_assessment/practice_formula_keyboard_test.dart`
- Modify: `test/features/practice_assessment/practice_formula_key_catalog_test.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_formula_keyboard.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_formula_insertions.dart`

**Interfaces:**
- Consumes: `PracticeFormulaKeyboard(controller:, onDone:)` and `practiceFormulaLetterAndNumberKeys(uppercase:)`.
- Produces: a letter grid containing only the uppercase toggle plus the 30 catalog keys; no `practice-formula-key-chinese-input`, dialog, or `insertPracticeFormulaText` API remains.

- [ ] **Step 1: Replace the Chinese-input Widget test with a failing absence test**

In `practice_formula_keyboard_test.dart`, replace the current test named `中文入口使用系统文本框并安全插入公式` with:

```dart
testWidgets('字母页不再提供中文自由文本入口', (tester) async {
  final controller = MathFieldEditingController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(_app(controller));

  expect(find.byKey(_key('chinese-input')), findsNothing);
  expect(
    find.byKey(const ValueKey('practice-formula-chinese-field')),
    findsNothing,
  );
  expect(find.byType(AlertDialog), findsNothing);
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
flutter test test\features\practice_assessment\practice_formula_keyboard_test.dart --plain-name "字母页不再提供中文自由文本入口"
```

Expected: FAIL because `practice-formula-key-chinese-input` still exists.

- [ ] **Step 3: Remove the Chinese entry and its isolated adapter**

In `practice_formula_keyboard.dart`:

- remove the `chinese-input` `_textActionButton` from `_contentPad`;
- remove `_showChineseInput`;
- remove `_ChineseFormulaTextDialog` and `_ChineseFormulaTextDialogState`.

In `practice_formula_insertions.dart`, remove the now-unused public function:

```dart
void insertPracticeFormulaText(
  MathFieldEditingController controller,
  String value,
)
```

In `practice_formula_key_catalog_test.dart`, remove the test named `中文文本以受控 text 节点插入并转义 TeX 特殊字符`.

- [ ] **Step 4: Format and verify GREEN**

Run:

```powershell
& 'D:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe' format lib\features\practice_assessment\presentation\practice_formula_keyboard.dart lib\features\practice_assessment\presentation\practice_formula_insertions.dart test\features\practice_assessment\practice_formula_keyboard_test.dart test\features\practice_assessment\practice_formula_key_catalog_test.dart
flutter test test\features\practice_assessment\practice_formula_keyboard_test.dart --plain-name "字母页不再提供中文自由文本入口"
flutter test test\features\practice_assessment\practice_formula_key_catalog_test.dart test\features\practice_assessment\practice_formula_keyboard_test.dart
```

Expected: both commands pass; the letter grid still contains the uppercase toggle and all 30 catalog keys.

- [ ] **Step 5: Commit Task 1**

```powershell
git add -- lib/features/practice_assessment/presentation/practice_formula_keyboard.dart lib/features/practice_assessment/presentation/practice_formula_insertions.dart test/features/practice_assessment/practice_formula_keyboard_test.dart test/features/practice_assessment/practice_formula_key_catalog_test.dart
git commit -m "refactor(practice): remove formula chinese input"
```

---

### Task 2: Replace Secondary Buttons with the Compact Dropdown

**Files:**
- Modify: `test/features/practice_assessment/practice_formula_keyboard_test.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_formula_keyboard.dart`
- Modify: `docs/superpowers/specs/2026-08-14-practice-formula-keyboard-compact-section-selector-design.md`

**Interfaces:**
- Consumes: `practiceFormulaSectionsByPrimary`, `practiceFormulaSectionLabels`, `_selectPrimary(PracticeFormulaPrimaryCategory)`, and `_selectSection(PracticeFormulaSection)`.
- Produces: `_compactSectionSelector()` with trigger key `practice-formula-section-selector` and option keys `practice-formula-section-<section.name>`.

- [ ] **Step 1: Rewrite navigation tests for the selector and verify RED**

Update the desktop test to expect the selector instead of secondary buttons:

```dart
expect(
  find.byKey(const ValueKey('practice-formula-section-selector')),
  findsOneWidget,
);
expect(find.text('字母与数字'), findsOneWidget);
```

Update the primary-category test to open the selector and assert that only sections belonging to the selected primary category are present:

```dart
await _selectPrimary(tester, PracticeFormulaPrimaryCategory.mathematics);
await tester.tap(
  find.byKey(const ValueKey('practice-formula-section-selector')),
);
await tester.pumpAndSettle();
expect(
  find.byKey(_sectionKey(PracticeFormulaSection.mathSymbols)),
  findsOneWidget,
);
expect(
  find.byKey(_sectionKey(PracticeFormulaSection.mathTemplates)),
  findsOneWidget,
);
expect(
  find.byKey(_sectionKey(PracticeFormulaSection.commonSymbols)),
  findsNothing,
);
```

Replace the old `_selectSection` helper with:

```dart
Future<void> _selectSection(
  WidgetTester tester,
  PracticeFormulaSection section,
) async {
  await tester.tap(
    find.byKey(const ValueKey('practice-formula-section-selector')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_sectionKey(section)).last);
  await tester.pumpAndSettle();
}
```

In the 375px test, expect `practice-formula-section-selector-row` and assert that `practice-formula-section-scroll` is absent.

Run:

```powershell
flutter test test\features\practice_assessment\practice_formula_keyboard_test.dart --plain-name "桌面端显示两级导航并保持右侧五行数字区"
```

Expected: FAIL because the selector does not exist yet.

- [ ] **Step 2: Implement the selector from the existing category map**

In `practice_formula_keyboard.dart`:

1. Rename `_verticalNavigationRail` to `_verticalPrimaryRail` and remove its secondary-button loop and divider.
2. Remove `_horizontalSectionRail`, `_sectionButton`, and the unused secondary-button path.
3. Add `_contentArea({required bool isWide})`, used by both wide and narrow layouts:

```dart
Widget _contentArea({required bool isWide}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _compactSectionSelector(),
      const SizedBox(height: 8),
      _contentPad(isWide: isWide),
    ],
  );
}
```

4. Add the compact selector:

```dart
Widget _compactSectionSelector() {
  final sections = practiceFormulaSectionsByPrimary[_primaryCategory]!;
  return Row(
    key: const ValueKey('practice-formula-section-selector-row'),
    children: [
      const Text(
        '二级',
        style: TextStyle(
          color: Color(0xFF687080),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(width: 8),
      Container(
        width: 154,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFC8CFDA)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<PracticeFormulaSection>(
            key: const ValueKey('practice-formula-section-selector'),
            value: _section,
            isExpanded: true,
            isDense: true,
            borderRadius: BorderRadius.circular(8),
            icon: const Icon(Icons.expand_more_rounded, size: 20),
            items: [
              for (final section in sections)
                DropdownMenuItem<PracticeFormulaSection>(
                  key: ValueKey('practice-formula-section-${section.name}'),
                  value: section,
                  child: Text(
                    practiceFormulaSectionLabels[section]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
            onChanged: (section) {
              if (section != null) _selectSection(section);
            },
          ),
        ),
      ),
    ],
  );
}
```

Use `_contentArea(isWide: true)` inside the wide `Expanded` and `_contentArea(isWide: false)` below the narrow primary rail. Keep `_selectPrimary` and `_selectSection` as the only transition methods so section membership and page reset remain atomic.

- [ ] **Step 3: Run focused selector and responsive tests**

Run:

```powershell
& 'D:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe' format lib\features\practice_assessment\presentation\practice_formula_keyboard.dart test\features\practice_assessment\practice_formula_keyboard_test.dart
flutter test test\features\practice_assessment\practice_formula_keyboard_test.dart
```

Expected: all keyboard tests pass, including primary filtering, 3-page units, 375px, 720px, and 1100px cases.

- [ ] **Step 4: Run complete module verification**

Run:

```powershell
flutter analyze lib\features\practice_assessment\presentation
flutter analyze test\features\practice_assessment
flutter test test\features\practice_assessment
```

Expected: both analyzers report `No issues found`; all practice-assessment tests pass.

- [ ] **Step 5: Mark the design implemented and commit Task 2**

Change the design status from `已批准，待实施` to `已批准并实现`, then run `git diff --check` and commit only the three files:

```powershell
git add -- docs/superpowers/specs/2026-08-14-practice-formula-keyboard-compact-section-selector-design.md lib/features/practice_assessment/presentation/practice_formula_keyboard.dart test/features/practice_assessment/practice_formula_keyboard_test.dart
git commit -m "feat(practice): compact formula section selector"
```

- [ ] **Step 6: Rebuild and refresh the local preview**

Run:

```powershell
flutter build web --debug --dart-define=APP_ENV=development --dart-define=ENABLE_DEVELOPER_TOOLS=true --dart-define=PRACTICE_ASSESSMENT_REMOTE=false
```

Restart only the Python process listening on `127.0.0.1:5174`, serve `build/web`, verify HTTP 200, and open:

```text
http://127.0.0.1:5174/#/practice-assessment-lab
```

Expected: the browser shows the current source with no Chinese key and the compact inline secondary selector.
