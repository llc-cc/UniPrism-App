# Practice Formula Keyboard Catalog Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the nine flat formula-keyboard categories with the approved three-primary/eight-section catalog and support every listed junior/senior-high math and physics key without changing the saved LaTeX answer contract.

**Architecture:** Keep `MathFieldEditingController` as the editor core. Split classification metadata, controlled insertion primitives, and the three subject catalogs into focused files; aggregate them behind the existing `practice_formula_key_catalog.dart` import boundary, then make the keyboard render primary categories, sections, and paged grids from that catalog.

**Tech Stack:** Flutter/Dart, `math_keyboard 0.3.3`, `flutter_math_fork`, `flutter_test`.

## Global Constraints

- Read and follow `docs/DEVELOPMENT_CODE_STANDARD.md` before editing code.
- Preserve `MathAnswerField → PracticeDraft.answer` as an un-delimited LaTeX `String`; do not add backend fields, network calls, caches, or dependencies.
- Keep the fixed four-column/five-row numeric pad and its current order.
- Official content has exactly three primary categories and eight sections; catalog-only advanced keys must not appear in those sections.
- Every new module, composite insertion, cursor rule, and deduplication branch needs a concise Chinese comment explaining why or the boundary condition.
- Use TDD for every behavior: add a focused failing test, run it and observe the expected failure, implement the minimum, then rerun the focused and regression tests.
- In the current managed environment, Flutter commands need sandbox escalation because the SDK cache and SDK Git metadata live under `D:\dev\flutter`; do not delete SDK lockfiles or terminate the user's Dart processes.
- Do not stage or commit unrelated dirty files already present in the workspace.

---

## File Structure

- Create `lib/features/practice_assessment/presentation/practice_formula_key_models.dart`: primary/section/kind/placement enums, labels, and immutable key specification.
- Create `lib/features/practice_assessment/presentation/practice_formula_insertions.dart`: public-editor insertions plus the only internal-node adapter for interleaved multi-slot templates and navigation.
- Create `lib/features/practice_assessment/presentation/practice_formula_common_catalog.dart`: alphabet, common symbols, common templates, and fixed numeric keys.
- Create `lib/features/practice_assessment/presentation/practice_formula_math_catalog.dart`: the 33 math symbols, 15 math templates, and hidden advanced catalog.
- Create `lib/features/practice_assessment/presentation/practice_formula_physics_catalog.dart`: 11 physics symbols, 51 units, and 10 constants.
- Modify `lib/features/practice_assessment/presentation/practice_formula_key_catalog.dart`: compatibility export and aggregate indexes only.
- Modify `lib/features/practice_assessment/presentation/practice_formula_keyboard.dart`: two-level navigation, page state, and catalog-driven rendering.
- Modify `test/features/practice_assessment/practice_formula_key_catalog_test.dart`: taxonomy, coverage, uniqueness, and exact output tests.
- Modify `test/features/practice_assessment/practice_formula_keyboard_test.dart`: hierarchy, pagination, fixed pad, and responsive layout tests.
- Modify `test/features/practice_assessment/math_answer_field_test.dart`: regression coverage for catalog integration and complex template draft output.

---

### Task 1: Classification Model and Aggregate Contract

**Files:**
- Create: `lib/features/practice_assessment/presentation/practice_formula_key_models.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_formula_key_catalog.dart`
- Test: `test/features/practice_assessment/practice_formula_key_catalog_test.dart`

**Interfaces:**
- Produces `PracticeFormulaPrimaryCategory`, `PracticeFormulaSection`, `PracticeFormulaKeyKind`, `PracticeFormulaKeyPlacement`, `PracticeFormulaInsertion`, and `PracticeFormulaKeySpec`.
- Produces `practiceFormulaPrimaryLabels`, `practiceFormulaSectionLabels`, `practiceFormulaSectionsByPrimary`, `practiceFormulaSectionKeys`, `practiceFormulaNumericKeys`, and `practiceFormulaExtendedKeys` from the aggregate file.

- [ ] **Step 1: Replace the old nine-category assertion with a failing hierarchy test**

```dart
test('目录固定为三个一级分类和八个二级标签', () {
  expect(
    PracticeFormulaPrimaryCategory.values.map((item) => item.name),
    <String>['common', 'mathematics', 'physics'],
  );
  expect(
    PracticeFormulaSection.values.map((item) => item.name),
    <String>[
      'lettersAndNumbers',
      'commonSymbols',
      'commonTemplates',
      'mathSymbols',
      'mathTemplates',
      'physicsSymbols',
      'physicsUnits',
      'physicsConstants',
    ],
  );
  expect(
    practiceFormulaSectionsByPrimary,
    <PracticeFormulaPrimaryCategory, List<PracticeFormulaSection>>{
      PracticeFormulaPrimaryCategory.common: <PracticeFormulaSection>[
        PracticeFormulaSection.lettersAndNumbers,
        PracticeFormulaSection.commonSymbols,
        PracticeFormulaSection.commonTemplates,
      ],
      PracticeFormulaPrimaryCategory.mathematics: <PracticeFormulaSection>[
        PracticeFormulaSection.mathSymbols,
        PracticeFormulaSection.mathTemplates,
      ],
      PracticeFormulaPrimaryCategory.physics: <PracticeFormulaSection>[
        PracticeFormulaSection.physicsSymbols,
        PracticeFormulaSection.physicsUnits,
        PracticeFormulaSection.physicsConstants,
      ],
    },
  );
});
```

- [ ] **Step 2: Run the focused test and observe RED**

Run: `flutter test test/features/practice_assessment/practice_formula_key_catalog_test.dart --plain-name "目录固定为三个一级分类和八个二级标签"`

Expected: compilation fails because the new enums and map do not exist.

- [ ] **Step 3: Add the immutable model with an insertion interface**

```dart
enum PracticeFormulaPrimaryCategory { common, mathematics, physics }

enum PracticeFormulaSection {
  lettersAndNumbers,
  commonSymbols,
  commonTemplates,
  mathSymbols,
  mathTemplates,
  physicsSymbols,
  physicsUnits,
  physicsConstants,
}

enum PracticeFormulaKeyKind { character, symbol, template, unit, constant }

enum PracticeFormulaKeyPlacement { fixedPad, sectionGrid, semanticShortcut }

abstract interface class PracticeFormulaInsertion {
  void apply(MathFieldEditingController controller);
}

typedef PracticeFormulaKeyAction =
    void Function(MathFieldEditingController controller);

final class CallbackFormulaInsertion implements PracticeFormulaInsertion {
  const CallbackFormulaInsertion(this.callback);

  final PracticeFormulaKeyAction callback;

  @override
  void apply(MathFieldEditingController controller) => callback(controller);
}

final class PracticeFormulaKeySpec {
  PracticeFormulaKeySpec(
    this.id,
    this.label,
    this.semanticLabel,
    PracticeFormulaKeyAction action, {
    this.isTexLabel = false,
  }) : name = semanticLabel,
       expectedLatex = '',
       kind = PracticeFormulaKeyKind.symbol,
       section = PracticeFormulaSection.commonSymbols,
       placement = PracticeFormulaKeyPlacement.sectionGrid,
       usage = '',
       insertion = CallbackFormulaInsertion(action);

  const PracticeFormulaKeySpec.catalog({
    required this.id,
    required this.label,
    required this.name,
    required this.semanticLabel,
    required this.expectedLatex,
    required this.kind,
    required this.section,
    required this.placement,
    required this.usage,
    required this.insertion,
    this.isTexLabel = false,
  });

  final String id;
  final String label;
  final String name;
  final String semanticLabel;
  final String expectedLatex;
  final PracticeFormulaKeyKind kind;
  final PracticeFormulaSection section;
  final PracticeFormulaKeyPlacement placement;
  final String usage;
  final PracticeFormulaInsertion insertion;
  final bool isTexLabel;

  void insert(MathFieldEditingController controller) => insertion.apply(controller);
}
```

The positional constructor exists only while the old catalog is being migrated. New catalog files must use `PracticeFormulaKeySpec.catalog`; remove every positional production use before Task 5 deletes the old aggregate map.

Add the exact Chinese labels `常用类/数学类/物理类` and `字母与数字/常用符号/常用公式模板/数学符号/数学公式模板/物理符号/物理单位/物理常数`.

- [ ] **Step 4: Make the aggregate file export the model and expose typed empty indexes temporarily**

Keep the old catalog definitions in place until Tasks 2–4 populate the new maps, but export the new model and add the typed hierarchy map so the RED test can turn GREEN without breaking the current Widget.

- [ ] **Step 5: Run the focused catalog test and observe GREEN**

Run the same command from Step 2. Expected: PASS.

- [ ] **Step 6: Commit only Task 1 files**

```powershell
git add -- lib/features/practice_assessment/presentation/practice_formula_key_models.dart lib/features/practice_assessment/presentation/practice_formula_key_catalog.dart test/features/practice_assessment/practice_formula_key_catalog_test.dart
git commit -m "refactor(practice): add hierarchical formula catalog model"
```

---

### Task 2: Controlled Insertions and Common Catalog

**Files:**
- Create: `lib/features/practice_assessment/presentation/practice_formula_insertions.dart`
- Create: `lib/features/practice_assessment/presentation/practice_formula_common_catalog.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_formula_key_catalog.dart`
- Test: `test/features/practice_assessment/practice_formula_key_catalog_test.dart`
- Test: `test/features/practice_assessment/math_answer_field_test.dart`

**Interfaces:**
- Consumes the Task 1 model.
- Produces `LeafFormulaInsertion`, `FunctionFormulaInsertion`, `PairFormulaInsertion`, `CompositeFormulaInsertion`, `UnitFormulaInsertion`, `practiceFormulaAlphabetKeys`, `insertPracticeFormulaText`, `practiceFormulaCommonSectionKeys`, and the fixed `practiceFormulaNumericKeys`.

- [ ] **Step 1: Add failing coverage tests for all common content**

Assert these exact section-grid IDs:

```dart
const commonSymbolIds = <String>{
  'plus-minus', 'dot-multiply', 'slash', 'equals', 'not-equal', 'approx',
  'less', 'greater', 'less-equal', 'greater-equal', 'percent', 'degree',
  'comma', 'semicolon', 'factorial', 'ellipsis',
};
const commonTemplateIds = <String>{
  'fraction', 'power', 'square', 'cube', 'subscript', 'sub-superscript',
  'sqrt', 'nth-root', 'parentheses', 'brackets', 'braces', 'absolute',
  'overline', 'vector', 'scientific-notation',
};
```

Also assert the fixed pad owns `0–9`, decimal, plus, minus, multiply, and divide, and that these IDs do not appear in a section grid. Assert alphabet generation yields 26 lowercase or uppercase keys plus separate `π α β θ` entries in `lettersAndNumbers`.

Add a public-path Widget test that opens the real keyboard, inserts scientific notation, fills `3` and `8`, and expects `onChanged` to receive `3\times10^{8}`. This must fail because the new template key does not exist.

- [ ] **Step 2: Run the common catalog tests and observe RED**

Run: `flutter test test/features/practice_assessment/practice_formula_key_catalog_test.dart --plain-name "常用目录覆盖唯一主位置"`

Expected: missing common catalog symbols and functions.

- [ ] **Step 3: Implement public insertion primitives**

Use `addLeaf`, `addFunction`, and complete paired leaves for ordinary content. Implement exact outputs:

```text
± \pm          · \cdot       / /            = =
≠ \ne          ≈ \approx     < <            > >
≤ \le          ≥ \ge         % \%           ° ^\circ
, ,             ; ;           ! !            … \cdots
```

`UnitFormulaInsertion` must add `\,` only when the current normalized LaTeX ends in a digit or `}` and must not add a leading space to an empty formula.

- [ ] **Step 4: Add an interleaved composite node adapter**

Create a private `TeXFunction` subclass that interleaves literal pieces with editable `argNodes`:

```dart
final class _PracticeCompositeFunction extends TeXFunction {
  _PracticeCompositeFunction({
    required TeXNode parent,
    required this.pieces,
  }) : assert(pieces.length >= 2),
       super('', parent, List<TeXArg>.filled(pieces.length - 1, TeXArg.braces));

  final List<String> pieces;

  @override
  String buildString({Color? cursorColor}) {
    final buffer = StringBuffer(pieces.first);
    for (var index = 0; index < argNodes.length; index++) {
      buffer
        ..write(argNodes[index].buildTeXString(cursorColor: cursorColor))
        ..write(pieces[index + 1]);
    }
    return buffer.toString();
  }
}
```

Keep all `math_keyboard/src` imports and the one protected notification suppression in this adapter file. `CompositeFormulaInsertion` inserts the custom function at the current cursor and moves the controller into `argNodes.first`.

- [ ] **Step 5: Implement the 15 common templates with exact skeletons**

```text
fraction             \frac{}{}
power                ^{}
square               ^{2}
cube                 ^{3}
subscript            _{}
sub-superscript      _{}^{}
sqrt                 \sqrt{}
nth-root             \sqrt[]{}
parentheses          \left(\right)
brackets             \left[\right]
braces               \left\{\right\}
absolute             \left\lvert\right\rvert
overline             \overline{}
vector               \vec{}
scientific-notation  {}\times10^{}
```

Use the composite adapter where literals must occur between slots; do not insert a complete template as one non-editable leaf.

- [ ] **Step 6: Preserve safe Chinese insertion and verify representative outputs**

Keep the existing TeX escape map. Add controller tests for cube, simultaneous sub/superscript, braces, absolute value, and scientific notation, filling each slot with numeric or letter keys before asserting the final LaTeX.

- [ ] **Step 7: Run common tests and the existing math field regressions**

Run:

```powershell
flutter test test/features/practice_assessment/practice_formula_key_catalog_test.dart
flutter test test/features/practice_assessment/math_answer_field_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit Task 2**

Commit message: `feat(practice): add common formula catalog and insertions`.

---

### Task 3: Complete Mathematics Catalog

**Files:**
- Create: `lib/features/practice_assessment/presentation/practice_formula_math_catalog.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_formula_key_catalog.dart`
- Test: `test/features/practice_assessment/practice_formula_key_catalog_test.dart`
- Test: `test/features/practice_assessment/math_answer_field_test.dart`

**Interfaces:**
- Consumes Task 2 insertion primitives.
- Produces `practiceFormulaMathSectionKeys` and `practiceFormulaExtendedKeys`.

- [ ] **Step 1: Add a failing exact-ID test for 33 math symbols**

The expected display/LaTeX pairs are:

```text
∞ \infty, ≡ \equiv, → \to, ′ ', ∅ \varnothing,
∈ \in, ∉ \notin, ⊂ \subset, ⊆ \subseteq, ∪ \cup, ∩ \cap,
∖ \setminus, ∁ \complement, | \mid,
ℕ \mathbb{N}, ℤ \mathbb{Z}, ℚ \mathbb{Q}, ℝ \mathbb{R}, ℂ \mathbb{C},
∀ \forall, ∃ \exists, ¬ \neg, ∧ \land, ∨ \lor,
⇒ \Rightarrow, ⇔ \Leftrightarrow,
∠ \angle, △ \triangle, ⊥ \perp, ∥ \parallel,
≅ \cong, ∼ \sim, σ \sigma
```

Assert there are exactly 33 IDs and explicitly assert empty set uses `\varnothing`, not `\emptyset`.

- [ ] **Step 2: Run the math-symbol test and observe RED**

Run the focused catalog test. Expected: the new section is empty or incomplete.

- [ ] **Step 3: Implement the 33 symbol specs and turn the test GREEN**

Use `LeafFormulaInsertion` only; each command-bearing leaf includes a safe trailing separator internally where required, while `expectedLatex` stores the normalized command without presentation spaces.

- [ ] **Step 4: Add a failing test for 15 mathematics templates**

Assert these IDs and exact skeletons:

```text
log-base              \log_{}\left(\right)
common-log            \lg\left(\right)
natural-log           \ln\left(\right)
sin                   \sin\left(\right)
cos                   \cos\left(\right)
tan                   \tan\left(\right)
derivative            f'\left(\right)
permutation           A_{}^{}
combination           C_{}^{}
probability           P\left(\right)
conditional-prob      P\left({}\mid{}\right)
set-builder           \left\{x\mid{}\right\}
open-interval         \left({},{}\right)
closed-interval       \left[{},{}\right]
cases                 \begin{cases}{}\\{}\end{cases}
```

For composite templates, fill slots in order and assert the final controller output rather than only checking metadata.

Add a real `MathAnswerField` test that enters conditional probability and expects `P\left(A\mid B\right)` from `onChanged`; observe it fail before adding the template.

- [ ] **Step 5: Run the template test and observe RED**

Expected: missing template IDs and insertions.

- [ ] **Step 6: Implement templates with composite pieces**

Use exact pieces such as `[r'P\left({', r'}\mid{', r'}\right)']`, `[r'\left({', r'},{', r'}\right)']`, and `[r'\begin{cases}{', r'}\\{', r'}\end{cases}']`. Keep the first cursor in the first semantic slot and rely on the shared composite navigation for subsequent slots.

- [ ] **Step 7: Move catalog-external advanced keys into `practiceFormulaExtendedKeys`**

Retain controlled specs for norm, directed segment, limit, sum, integral, product, cotangent, exponential, maximum, and minimum, but assert none of their IDs occur in `practiceFormulaSectionKeys.values.expand(...)`.

- [ ] **Step 8: Run catalog and keyboard regressions, then commit**

Run both formula catalog and keyboard test files. Commit message: `feat(practice): add complete mathematics formula catalog`.

---

### Task 4: Complete Physics Symbols, Units, and Constants

**Files:**
- Create: `lib/features/practice_assessment/presentation/practice_formula_physics_catalog.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_formula_key_catalog.dart`
- Test: `test/features/practice_assessment/practice_formula_key_catalog_test.dart`
- Test: `test/features/practice_assessment/math_answer_field_test.dart`

**Interfaces:**
- Consumes Task 2 insertion primitives and Task 1 metadata.
- Produces `practiceFormulaPhysicsSectionKeys` with 11 symbols, 51 units, and 10 constants.

- [ ] **Step 1: Add failing count and exact-command tests**

Physics symbols must be exactly:

```text
Δ \Delta, ρ \rho, η \eta, μ \mu, λ \lambda,
ν \nu, ω \omega, φ \varphi, Φ \Phi, γ \gamma,
nucleus {}_{}^{}{} (three editable semantic slots)
```

Assert `φ` writes `\varphi`, and fill the nucleus slots as mass `14`, atomic number `6`, element `C` to get `{}_{6}^{14}C`.

Add real `MathAnswerField` tests for `{}_{6}^{14}C` and `5\,\mathrm{m}/\mathrm{s}^{2}`; both must fail because the new physics keys do not exist.

- [ ] **Step 2: Run the physics-symbol test and observe RED**

Expected: missing `ν`, `Φ`, nucleus, and the wrong phi variant.

- [ ] **Step 3: Implement physics symbols and nucleus ordering**

Use a composite insertion whose user slot order is mass number, atomic number, element symbol but whose output pieces render `{}_{atomic}^{mass}element`. Add a Chinese comment because cursor order and serialized order intentionally differ.

- [ ] **Step 4: Add a failing exact 51-unit test**

The exact unit IDs/outputs are:

```text
mm \mathrm{mm}; nm \mathrm{nm}; cm \mathrm{cm}; m \mathrm{m}; km \mathrm{km};
mL \mathrm{mL}; L \mathrm{L}; mg \mathrm{mg}; g \mathrm{g}; kg \mathrm{kg}; t \mathrm{t};
s \mathrm{s}; ms \mathrm{ms}; min \mathrm{min}; h \mathrm{h};
℃ ^\circ\mathrm{C}; K \mathrm{K}; rad \mathrm{rad};
Hz \mathrm{Hz}; kHz \mathrm{kHz}; MHz \mathrm{MHz}; dB \mathrm{dB};
N \mathrm{N}; Pa \mathrm{Pa}; kPa \mathrm{kPa}; J \mathrm{J};
W \mathrm{W}; kW \mathrm{kW}; C \mathrm{C}; A \mathrm{A};
mA \mathrm{mA}; μA \mu\mathrm{A}; V \mathrm{V}; Ω \Omega;
kΩ \mathrm{k}\Omega; MΩ \mathrm{M}\Omega; F \mathrm{F};
μF \mu\mathrm{F}; Wb \mathrm{Wb}; T \mathrm{T}; mol \mathrm{mol};
eV \mathrm{eV}; u \mathrm{u}; m/s \mathrm{m}/\mathrm{s};
km/h \mathrm{km}/\mathrm{h}; m/s² \mathrm{m}/\mathrm{s}^{2};
kg/m³ \mathrm{kg}/\mathrm{m}^{3}; g/cm³ \mathrm{g}/\mathrm{cm}^{3};
N/C \mathrm{N}/\mathrm{C}; rad/s \mathrm{rad}/\mathrm{s};
kW·h \mathrm{kW}\cdot\mathrm{h}
```

Assert empty insertion has no `\,`, while inserting metre after `5` produces `5\,\mathrm{m}`.

- [ ] **Step 5: Run unit tests RED, implement all 51 specs, rerun GREEN**

Keep all units in `physicsUnits`, kind `unit`, placement `sectionGrid`; do not generate prefixed units dynamically.

- [ ] **Step 6: Add failing tests for 10 physical constants**

Use IDs `constant-g`, `constant-G`, `constant-c`, `constant-k`, `constant-e`, `constant-h`, `constant-NA`, `constant-kB`, `constant-R`, `constant-p0`. Store these exact `usage` strings and assert the combined insertions yield `N_{A}`, `k_{B}`, and `p_{0}`:

```text
g: 常取 9.8\,\mathrm{m}/\mathrm{s}^{2}，题目有时取 10\,\mathrm{m}/\mathrm{s}^{2}
G: 6.67\times10^{-11}\,\mathrm{N}\cdot\mathrm{m}^{2}/\mathrm{kg}^{2}
c: 3.0\times10^{8}\,\mathrm{m}/\mathrm{s}
k: 9.0\times10^{9}\,\mathrm{N}\cdot\mathrm{m}^{2}/\mathrm{C}^{2}
e: 1.60\times10^{-19}\,\mathrm{C}
h: 6.63\times10^{-34}\,\mathrm{J}\cdot\mathrm{s}
N_A: 6.02\times10^{23}\,\mathrm{mol}^{-1}
k_B: 1.38\times10^{-23}\,\mathrm{J}/\mathrm{K}
R: 8.31\,\mathrm{J}/(\mathrm{mol}\cdot\mathrm{K})
p_0: 常取 1.01\times10^{5}\,\mathrm{Pa}
```

- [ ] **Step 7: Implement constant semantic shortcuts and rerun all catalog tests**

Single-letter constants reuse leaf insertion instances; combined constants use the controlled subscript insertion. No long numeric value is placed in a key label.

- [ ] **Step 8: Commit Task 4**

Commit message: `feat(practice): add complete physics formula catalog`.

---

### Task 5: Catalog Aggregation and Validation

**Files:**
- Modify: `lib/features/practice_assessment/presentation/practice_formula_key_catalog.dart`
- Modify: `test/features/practice_assessment/practice_formula_key_catalog_test.dart`

**Interfaces:**
- Consumes all three subject catalogs.
- Finalizes `practiceFormulaSectionKeys`, `practiceFormulaNumericKeys`, `practiceFormulaExtendedKeys`, `practiceFormulaKeysForSection(section)`, and `validatePracticeFormulaCatalog()`.

- [ ] **Step 1: Add failing validation tests**

```dart
test('正式目录键位 ID 唯一且展示位置合法', () {
  expect(validatePracticeFormulaCatalog, returnsNormally);
  final official = practiceFormulaSectionKeys.values.expand((items) => items);
  expect(official.map((item) => item.id).toSet(), hasLength(official.length));
  expect(
    official.where((item) => item.placement == PracticeFormulaKeyPlacement.fixedPad),
    isEmpty,
  );
});
```

Add assertions for section counts: letters dynamic `26 + 4`, common symbols `16` grid keys plus `5` fixed entries in metadata, common templates `15`, math symbols `33`, math templates `15`, physics symbols `11`, physics units `51`, physics constants `10`.

- [ ] **Step 2: Run validation tests and observe RED**

Expected: duplicate IDs from reused current keys or missing placement filtering.

- [ ] **Step 3: Replace the legacy nine-category map with aggregate indexes**

Remove `PracticeFormulaKeyboardCategory`, `practiceFormulaCategoryLabels`, and `practiceFormulaCategoryKeys`. Keep compatibility through exports, not duplicate data. `validatePracticeFormulaCatalog()` must throw `StateError` with the duplicated ID or wrong section named in the message.

- [ ] **Step 4: Run all catalog tests and observe GREEN**

Run: `flutter test test/features/practice_assessment/practice_formula_key_catalog_test.dart`.

- [ ] **Step 5: Commit Task 5**

Commit message: `refactor(practice): aggregate validated formula key catalog`.

---

### Task 6: Two-Level Navigation and Paged Keyboard UI

**Files:**
- Modify: `lib/features/practice_assessment/presentation/practice_formula_keyboard.dart`
- Modify: `test/features/practice_assessment/practice_formula_keyboard_test.dart`

**Interfaces:**
- Consumes the finalized catalog functions from Task 5.
- Keeps the public `PracticeFormulaKeyboard(controller:, onDone:)` constructor unchanged.

- [ ] **Step 1: Replace flat-category Widget expectations with failing two-level navigation tests**

Assert these keys exist:

```text
practice-formula-primary-common
practice-formula-primary-mathematics
practice-formula-primary-physics
practice-formula-section-lettersAndNumbers
practice-formula-section-commonSymbols
practice-formula-section-commonTemplates
```

Tap mathematics and assert only `mathSymbols/mathTemplates` section buttons appear; tap physics and assert only its three section buttons appear. Tapping a primary category must select its first section.

- [ ] **Step 2: Run the hierarchy Widget test and observe RED**

Expected: the old flat category keys are still rendered.

- [ ] **Step 3: Implement primary and section state**

Replace `_category` with `_primaryCategory`, `_section`, and `_pageIndex`. Add `_selectPrimary` and `_selectSection`; both reset `_pageIndex` to zero, and `_selectPrimary` chooses `practiceFormulaSectionsByPrimary[primary]!.first`.

On wide screens render a primary button group followed by selected section buttons in the left rail. On narrow screens render two independent horizontal scrollers. Keep Chinese comments on the reset behavior because it prevents stale out-of-range pages.

- [ ] **Step 4: Add failing pagination tests**

Set the section to physics units and assert:

- page 1 shows `unit-mm` and no `unit-kW-hour`;
- the indicator reads `1/3`;
- tapping `practice-formula-page-next` shows page `2/3`;
- tapping next again shows `unit-kW-hour` and page `3/3`;
- switching to physics symbols resets the page controls and shows no pagination for an 11-key section.

- [ ] **Step 5: Implement 20-key paging**

Use `const _pageSize = 20`, `sublist(start, min(start + _pageSize, keys.length))`, and a compact previous/indicator/next row below the four-column grid. Disable, rather than remove, the previous/next buttons at boundaries so layout remains stable.

The letters section remains seven columns with uppercase and Chinese action buttons prepended; its 26 letters are not routed through the 20-key pager.

- [ ] **Step 6: Update key rendering and navigation adapter calls**

Replace `key.action(controller)` with `key.insert(controller)`. Move any remaining `TeXFunction` cursor inspection out of the Widget and call the navigation helper from `practice_formula_insertions.dart`, leaving the Widget free of `math_keyboard/src` imports.

- [ ] **Step 7: Preserve the fixed numeric pad and `abc` shortcut**

The existing five row assertions must continue to pass. `abc` selects primary `common`, section `lettersAndNumbers`, and page zero without toggling uppercase.

- [ ] **Step 8: Add responsive tests at 375, 720, and 1100 pixels**

For every primary/section pair, select it and assert `tester.takeException()` is null. At 375 pixels assert both category rows are horizontally scrollable and all key grids stay within the keyboard bounds.

- [ ] **Step 9: Run Widget tests and commit**

Run:

```powershell
flutter test test/features/practice_assessment/practice_formula_keyboard_test.dart
flutter test test/features/practice_assessment/math_answer_field_test.dart
```

Commit message: `feat(practice): add hierarchical paged formula keyboard`.

---

### Task 7: End-to-End Regression and Delivery Documentation

**Files:**
- Modify only if a test exposes an in-scope defect: files created or modified in Tasks 1–6

**Interfaces:**
- Verifies the public answer field and draft contract; adds no new production interface.

- [ ] **Step 1: Run the public-path integration tests added RED-first in Tasks 2–4**

Confirm scientific notation, conditional probability, nucleus, and compound-unit tests all receive exact un-delimited LaTeX and still pass after dismissing/reopening the keyboard.

- [ ] **Step 2: Implement only wiring fixes demonstrated by a failing regression**

Do not change the answer protocol, 1,500-character limit, focus behavior, or draft synchronization.

- [ ] **Step 3: Run formatting, analysis, and the complete relevant Flutter suite**

```powershell
dart format lib/features/practice_assessment/presentation test/features/practice_assessment
dart analyze lib/main.dart test
flutter test test/features/practice_assessment
```

Expected: all commands exit 0 with no new warnings. If repository-wide pre-existing failures remain, capture exact command output and distinguish them from the focused passing suite.

- [ ] **Step 4: Inspect the final diff and catalog counts**

Run `git diff --check`, confirm no unrelated paths are included, and record the eight section counts plus any remote-backend LaTeX commands that still need integration verification.

- [ ] **Step 5: Commit the regression closure**

Commit message: `test(practice): verify complete formula keyboard catalog`.

---

## Plan Self-Review

- Spec coverage: Tasks 1–6 cover classification, unique placement, all common/math/physics content, complex cursor structures, constants, unit paging, responsive UI, and fixed numeric controls; Task 7 covers the unchanged answer contract and delivery verification.
- Scope: backend equivalence, new dependencies, search/favorites, handwriting, long-press variants, and custom layouts remain excluded.
- Type consistency: all catalogs expose `List<PracticeFormulaKeySpec>` keyed by `PracticeFormulaSection`; Widgets call `PracticeFormulaKeySpec.insert`; only the insertion adapter imports internal node types.
- No task instructs deletion of SDK locks, process termination, or staging of unrelated workspace changes.
