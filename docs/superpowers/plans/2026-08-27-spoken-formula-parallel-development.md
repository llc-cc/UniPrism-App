# Spoken Formula Parallel Development Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parallelize the remaining spoken-formula work so one model builds a general Chinese mathematical semantic engine while Codex owns deadlines, model/API fallback orchestration, Flutter integration, independent acceptance, and final merging.

**Architecture:** Keep Canonical Math AST as the only trusted mathematical boundary. A general compositional semantic engine produces audited AST candidates without calling any model; the V2 resolver then runs deterministic parsing, the semantic engine, an optional bounded local Math-AST model, and a bounded MiniMax fallback under one request budget. Flutter continues to show only audited formula candidates, reverse speech, clarification, and explicit insertion.

**Tech Stack:** TypeScript 5, Node.js 22, Next.js 16, Zod 4, Vitest 4, Flutter 3, Dart 3.12, SenseVoiceSmall CPU, existing llama.cpp/OpenAI-compatible local model adapter, existing MiniMax Compact AST adapter.

**Spec:** `docs/superpowers/specs/2026-08-27-spoken-formula-resilient-local-resolution-design.md`, plus the parallel ownership and architecture delta approved in chat on 2026-08-27 and recorded in this plan.

**Metric definitions:** `candidateCoverageRate` is the proportion of human-reviewed, semantically supported inputs for which the local semantic engine returns a candidate. `expectedTop3Rate` is formula correctness among those supported inputs. `boundaryDecisionRate` is the proportion of reviewed ambiguity/unsupported inputs that avoid a guessed unique formula. Final V2 `actionableRate` means a safe resolved formula, candidate choice, or targeted clarification before the deadline; infrastructure errors and watchdog expiry are not actionable.

## Global Constraints

- Read `docs/DEVELOPMENT_CODE_STANDARD.md` before modifying either repository.
- Do not add complete-utterance lookup tables or screenshot-specific production branches.
- Every generated formula must originate from Canonical Math AST and pass schema, semantic, candidate, LaTeX, and reverse-speech checks.
- The V2 public response remains `resolved | candidates | clarification`; Flutter never receives AST, confidence, provider, prompt, or raw model output.
- Semantic ambiguity is not an infrastructure error. Never silently discard a condition, domain, quantifier, sign, exponent, denominator, or scope marker.
- The five-second stop-to-actionable watchdog remains absolute. Increasing an internal timeout must not create a second independent five-second budget.
- MiniMax may run only after deterministic and compositional local misses. Cache keys and logs use hashes or aggregate fields; never log transcripts, formulas, AST, audio, tokens, or identity.
- Real audio is never saved. Simulated or synthesized audio cannot be reported as real-microphone evidence.
- Text-fixture accuracy is not production ASR accuracy. A 95% held-out text gate must be labelled as such.
- No agent may push, merge shared branches, deploy, change secrets, or stop user-owned processes without explicit approval.

## Current Baselines

| Repository | Worktree | Branch | Baseline commit |
|---|---|---|---|
| Flutter app | `D:\dev\Uniprism\uniprism_app\.worktrees\local-sensevoice-web-integration` | `feature/local-sensevoice-web-integration` | `b9ee6f6e454b935395fdff5914f1ea3525c237e9` |
| Shared backend | `D:\dev\Uniprism\uniprism_app\.worktrees\spoken-formula-resilience-backend` | `feature/spoken-formula-resilience-backend` | `5a98c7e7427395c7380c400f794ccacb85b891d0` |

Baseline evidence: backend practice-formula suites pass 347 tests; Flutter practice-assessment suites pass 312 tests with 2 existing skips. The hard-10 benchmark reports P50 2.270 ms, P95 22.864 ms, max 22.864 ms, zero generic failures, and zero cloud calls. These fixtures do not establish free-form 95% accuracy.

### Execution roots

- Run Tasks O0–O4 and backend portions of Tasks C0–C3 in the shared-backend worktree or its isolated semantic-engine worktree.
- Run Flutter portions of Tasks C1 and C4 in the Flutter-app worktree.
- Never run a command merely because its relative path exists in the other repository; verify `git remote -v`, branch, and HEAD before every commit.

## Ownership Matrix

| Area | Other model owns | Codex owns |
|---|---|---|
| General semantic engine | Tokenization, normalization, compositional grammar, logical/conditional AST support, development corpus, local benchmark | Independent held-out corpus and final acceptance |
| Existing fast parser | Read and reuse only | Keeps current production stage stable until integration |
| V2 route and resolver | Must not edit | Budget propagation, stage orchestration, audit, fallback, logging |
| Local model and MiniMax | Must not edit or call | Request-scoped deadlines, local-model adapter reuse, MiniMax fallback after local miss, ambiguity, or audit rejection |
| Flutter | Must not edit | SenseVoice budget, repository request budget, state/UI regression |
| Integration | Supplies reviewed commits and report | Cherry-picks, resolves conflicts, runs full verification, opens page |

### Files forbidden to the other model

- `lib/practice-formula/localResolutionService.ts`
- `lib/practice-formula/resolutionHttp.ts`
- `lib/practice-formula/resolutionContracts.ts`
- `lib/practice-formula/configuredConverter.ts`
- `lib/practice-formula/localModelClient.ts`
- `lib/practice-formula/miniMaxCompactAstClient.ts`
- `app/api/practice/formulas/resolve-spoken-text/route.ts`
- all Flutter files

### Files reserved for the other model

- `lib/practice-formula/semantic/*`
- `tests/unit/practiceFormulaSemantic*.test.ts`
- `tests/fixtures/practice-spoken-formula-semantic-dev-v1.json`
- `scripts/benchmark-spoken-formula-semantic.ts`
- AST core and model-protocol files required by Task O2's general logical node:
  - `lib/practice-formula/mathAst.ts`
  - `lib/practice-formula/mathAstLatex.ts`
  - `lib/practice-formula/mathAstSpeechZhCn.ts`
  - `lib/practice-formula/mathAstJsonSchema.ts`
  - `lib/practice-formula/compactMathAst.ts`
  - `lib/practice-formula/candidateAudit.ts`
  - `tests/unit/practiceFormulaMathAst.test.ts`
  - `tests/unit/practiceFormulaMathAstLatex.test.ts`
  - `tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts`
  - `tests/unit/practiceFormulaMathAstJsonSchema.test.ts`
  - `tests/unit/practiceFormulaCompactAst.test.ts`
  - `tests/unit/practiceFormulaCandidateAudit.test.ts`

## Frozen Handoff Interface

The other model must export this interface from `lib/practice-formula/semantic/index.ts`:

```ts
import type { SpokenFormulaModelOutput } from '../contracts';

export type SemanticMissReason =
  | 'EMPTY'
  | 'UNCONSUMED_TOKENS'
  | 'UNSUPPORTED_INTENT'
  | 'AMBIGUOUS_SCOPE';

export type SemanticParseResult =
  | { kind: 'candidate'; output: SpokenFormulaModelOutput }
  | { kind: 'miss'; normalizedText: string; reason: SemanticMissReason };

export function parseSemanticSpokenFormula(
  spokenText: string,
): SemanticParseResult;
```

Contract rules:

- `candidate.output.status` is only `ok` or `ambiguous`; unsupported input is a `miss`.
- `ok` contains exactly one primary AST and no alternatives.
- `ambiguous` contains a primary AST plus one or two semantically distinct alternatives.
- `normalizedText` is bounded to 300 characters and never contains generated instructions.
- No probability is fabricated. Deterministic completeness is expressed by `candidate` versus `miss`.
- Production code contains no full transcript-to-AST map.

## Parallel Execution Order

```text
Other model: O0 -> O1 -> O2 -> O3 -> O4 ─────────┐
                                                   ├-> C3 integration -> C4 final acceptance
Codex:       C0 -> C1 -> C2 + hidden corpus ──────┘
```

---

### Task O0: Create the Other Model's Isolated Backend Branch

**Files:** No source files.

**Interfaces:**
- Consumes: backend commit `5a98c7e7427395c7380c400f794ccacb85b891d0`.
- Produces: branch `feature/spoken-formula-semantic-engine` in a separate worktree.

- [ ] **Step 1: Verify the base and dirty state**

```powershell
git status --short --branch
git rev-parse HEAD
git show -s --format=%s 5a98c7e7427395c7380c400f794ccacb85b891d0
```

Expected: the base commit exists. Do not reuse a worktree with unrelated changes.

- [ ] **Step 2: Create an isolated worktree**

Use `superpowers:using-git-worktrees`. Suggested location:

```text
D:\dev\Uniprism\uniprism_app\.worktrees\spoken-formula-semantic-engine
```

Expected branch: `feature/spoken-formula-semantic-engine`, based exactly on `5a98c7e`.

- [ ] **Step 3: Run the semantic-area baseline**

```powershell
npm test -- --run tests/unit/practiceFormulaLocalParser.test.ts tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaCandidateAudit.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts
npm run typecheck
```

Expected: PASS. Record counts in the handoff report.

---

### Task O1: Build Generic Mathematical Tokenization and Normalization

**Files:**
- Create: `lib/practice-formula/semantic/types.ts`
- Create: `lib/practice-formula/semantic/tokenizer.ts`
- Create: `lib/practice-formula/semantic/normalizer.ts`
- Create: `lib/practice-formula/semantic/index.ts`
- Create: `tests/unit/practiceFormulaSemanticNormalizer.test.ts`

**Interfaces:**
- Consumes: raw Chinese ASR text up to 300 characters.
- Produces: internal `NormalizedSpokenMath` tokens with source offsets. Task O2 adds the frozen `SemanticParseResult` export after the parser exists, so the O1 commit remains independently compilable.

- [ ] **Step 1: Write failing normalization tests**

```ts
it.each([
  ['2. x 大于零，x 加四除以 x 大于等于四', 'x大于零x加四除以x大于等于四'],
  ['第二题：当 y 小于三时，y 的平方大于等于零', '当y小于三时y的平方大于等于零'],
  ['一、若 a 不等于零，则 a 除以 a 等于一', '若a不等于零则a除以a等于一'],
])('removes list markers without removing mathematics', (input, normalized) => {
  expect(normalizeSpokenMath(input).normalizedText).toBe(normalized);
});

it.each(['二点五', '二点五次方', 'x等于二点五'])(
  'preserves spoken decimals: %s',
  (input) => expect(normalizeSpokenMath(input).normalizedText).toContain('二点五'),
);
```

- [ ] **Step 2: Run RED**

```powershell
npm test -- --run tests/unit/practiceFormulaSemanticNormalizer.test.ts
```

Expected: FAIL because the semantic modules do not exist.

- [ ] **Step 3: Implement token classes, not utterance templates**

Use these token kinds:

```ts
export type SemanticTokenKind =
  | 'symbol' | 'number' | 'operator' | 'relation'
  | 'conditionStart' | 'conditionEnd' | 'logic'
  | 'scope' | 'intentLabel' | 'listMarker' | 'unknown';

export type SemanticToken = {
  kind: SemanticTokenKind;
  text: string;
  start: number;
  end: number;
};
```

List-marker removal must be anchored at the start and followed by a mathematical token. Decimal `点` stays a number token. Intent labels such as `基本不等式`, `写成公式`, and `结果为` may be tagged but cannot delete a condition or expression.

At this stage, `semantic/index.ts` exports only tokenization/normalization types and functions; it must not export an undefined parser symbol.

- [ ] **Step 4: Run GREEN and regression tests**

```powershell
npm test -- --run tests/unit/practiceFormulaSemanticNormalizer.test.ts tests/unit/practiceFormulaLocalParser.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/practice-formula/semantic tests/unit/practiceFormulaSemanticNormalizer.test.ts
git commit -m "feat(practice): tokenize spoken math semantics"
```

---

### Task O2: Implement Compositional Statements and General Logical AST

**Files:**
- Create: `lib/practice-formula/semantic/parser.ts`
- Create: `tests/unit/practiceFormulaSemanticParser.test.ts`
- Modify: `lib/practice-formula/mathAst.ts`
- Modify: `lib/practice-formula/mathAstLatex.ts`
- Modify: `lib/practice-formula/mathAstSpeechZhCn.ts`
- Modify: `lib/practice-formula/mathAstJsonSchema.ts`
- Modify: `lib/practice-formula/compactMathAst.ts`
- Modify: `lib/practice-formula/candidateAudit.ts`
- Modify: `tests/unit/practiceFormulaMathAst.test.ts`
- Modify: `tests/unit/practiceFormulaMathAstLatex.test.ts`
- Modify: `tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts`
- Modify: `tests/unit/practiceFormulaMathAstJsonSchema.test.ts`
- Modify: `tests/unit/practiceFormulaCompactAst.test.ts`
- Modify: `tests/unit/practiceFormulaCandidateAudit.test.ts`

**Interfaces:**
- Consumes: Task O1 tokens and `parseLocalSpokenFormula` for atomic expressions and relations.
- Produces: the frozen `parseSemanticSpokenFormula` result.

- [ ] **Step 1: Write failing family-level tests**

```ts
it.each([
  ['x 大于零，x 加四除以 x 大于等于四，基本不等式', String.raw`x+\frac{4}{x}\geq4\mid x>0`],
  ['当 y 小于三时，y 的平方大于等于零', String.raw`y^{2}\geq0\mid y<3`],
  ['若 a 不等于零，则 a 除以 a 等于一', String.raw`\frac{a}{a}=1\mid a\neq0`],
])('composes arbitrary condition and conclusion: %s', (spokenText, expectedLatex) => {
  const result = parseSemanticSpokenFormula(spokenText);
  expect(result.kind).toBe('candidate');
  if (result.kind !== 'candidate' || result.output.primary === null) return;
  expect(renderMathAstToLatex(result.output.primary)).toBe(expectedLatex);
});
```

Add separate cases with different symbols, constants, functions, derivatives, intervals, and nested fractions. The parser must recursively parse condition and conclusion; it may not branch on the complete strings above.

- [ ] **Step 2: Run RED**

```powershell
npm test -- --run tests/unit/practiceFormulaSemanticParser.test.ts
```

Expected: FAIL because compositional parsing is missing.

- [ ] **Step 3: Implement grammar productions**

First split only on top-level structural delimiters, then implement these non-left-recursive precedence levels over each span:

```text
statement       := prefixedConditional | postfixedConditional | implication
prefixedConditional := conditionStart implication conditionJoin statement
postfixedConditional := implication conditionTail implication conditionEnd
implication     := disjunction [impliesOperator implication]
disjunction     := conjunction {orOperator conjunction}
conjunction     := atomicMath {andOperator atomicMath}
conditionStart  := 若 | 当 | 在
conditionJoin   := 则 | 时 | 条件下
conditionTail   := 当 | 在
conditionEnd    := 时 | 条件下
impliesOperator := 推出 | 可得 | 因此
orOperator      := 或 | 或者
andOperator     := 且 | 并且
```

The parser locates paired condition markers before expression parsing, so `则`, `时`, and `条件下` delimit spans instead of being consumed by `atomicMath`. Reject unmatched or multiply matched scope markers as `AMBIGUOUS_SCOPE`; do not recover by dropping tokens.

Use existing `conditional` AST for one condition. Add this node for conjunction, disjunction, and implication so these structures never lose information:

```ts
| { type: 'logical'; op: 'and' | 'or' | 'implies'; operands: MathAstNode[] }
```

Render it as `\land`, `\lor`, or `\Rightarrow`; reverse speech must say `并且`, `或者`, or `推出`. Extend canonical schema recursion, JSON schema, Compact AST encoding/decoding, semantic limits, audit walking, symbol checks, and tests. Never discard the condition to make the conclusion parse.

Task O2 completes the frozen `parseSemanticSpokenFormula` export in `semantic/index.ts`. Its implementation must call candidate limits and audit before returning `candidate`; an audit failure becomes a typed `miss`, never an unchecked formula.

- [ ] **Step 4: Add ambiguity and miss tests**

Inputs with two valid scopes produce `ambiguous` with two audited ASTs. Inputs containing proof requests, prose explanations, or unconsumed mathematical tokens produce a typed `miss`; they must not produce a guessed partial formula.

- [ ] **Step 5: Run GREEN and all AST gates**

```powershell
npm test -- --run tests/unit/practiceFormulaSemanticParser.test.ts tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts tests/unit/practiceFormulaMathAstJsonSchema.test.ts tests/unit/practiceFormulaCompactAst.test.ts tests/unit/practiceFormulaCandidateAudit.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 6: Reject full-string mappings**

```powershell
rg -n "x加四除以x|基本不等式.*return|new Map.*spoken|Record<string.*MathAst" lib/practice-formula/semantic
```

Expected: no production mapping of complete utterances to AST.

- [ ] **Step 7: Commit**

```powershell
git add lib/practice-formula/semantic lib/practice-formula/mathAst.ts lib/practice-formula/mathAstLatex.ts lib/practice-formula/mathAstSpeechZhCn.ts lib/practice-formula/mathAstJsonSchema.ts lib/practice-formula/compactMathAst.ts lib/practice-formula/candidateAudit.ts tests/unit/practiceFormulaSemanticParser.test.ts tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts tests/unit/practiceFormulaMathAstJsonSchema.test.ts tests/unit/practiceFormulaCompactAst.test.ts tests/unit/practiceFormulaCandidateAudit.test.ts
git commit -m "feat(practice): compose spoken math statements"
```

---

### Task O3: Create a Diverse Development Corpus and Metamorphic Gates

**Files:**
- Create: `tests/fixtures/practice-spoken-formula-semantic-dev-v1.json`
- Create: `tests/unit/practiceFormulaSemanticCorpus.test.ts`

**Interfaces:**
- Consumes: Task O2 parser.
- Produces: 120 reviewed text-to-LaTeX development cases and aggregate metrics.

- [ ] **Step 1: Create the fixture with an explicit schema**

```json
{
  "version": 1,
  "cases": [
    {
      "id": "condition-001",
      "category": "condition",
      "spokenText": "当 y 小于三时 y 的平方大于等于零",
      "expectedOutcome": "resolved",
      "expectedLatexTop3": ["y^{2}\\geq0\\mid y<3"]
    }
  ]
}
```

Use exactly 12 categories with 10 cases each: arithmetic scope, fractions/roots, functions/logarithms, relations/chains, conditions, logic/implication, domains/sets/intervals, piecewise definitions, derivatives, integrals/limits, sums/products, and combinatorics/geometry symbols. Vary variables, numbers, operation depth, clause order, and spoken synonyms. Include exactly 100 semantically supported inputs and 20 boundary inputs that must return a miss or ambiguity rather than a guessed unique formula.

- [ ] **Step 2: Write the aggregate gate**

The test independently renders returned AST and checks expected Top-3. It must report per-category counts without printing transcripts or formulas.

```ts
expect(summary.total).toBe(120);
expect(summary.supportedTotal).toBe(100);
expect(summary.boundaryTotal).toBe(20);
expect(summary.candidateCoverageRate).toBeGreaterThanOrEqual(0.95);
expect(summary.expectedTop3Rate).toBeGreaterThanOrEqual(0.90);
expect(summary.boundaryDecisionRate).toBe(1);
expect(summary.partialParseCount).toBe(0);
```

- [ ] **Step 3: Add metamorphic variants**

For at least 30 base cases, generate punctuation, whitespace, safe list markers, and neutral intent-label variants. All variants must preserve the same semantic signature. Decimal and scope-changing variants must not be treated as equivalent.

- [ ] **Step 4: Run corpus gates**

```powershell
npm test -- --run tests/unit/practiceFormulaSemanticCorpus.test.ts tests/unit/practiceFormulaSemanticParser.test.ts
```

Expected: PASS without lowering thresholds.

- [ ] **Step 5: Commit**

```powershell
git add tests/fixtures/practice-spoken-formula-semantic-dev-v1.json tests/unit/practiceFormulaSemanticCorpus.test.ts
git commit -m "test(practice): cover unseen spoken math structures"
```

---

### Task O4: Benchmark and Hand Off the Semantic Engine

**Files:**
- Create: `scripts/benchmark-spoken-formula-semantic.ts`
- Create: `docs/qa/spoken-formula-semantic-engine-report.md`
- Modify: `package.json`

**Interfaces:**
- Consumes: Task O3 corpus.
- Produces: privacy-safe timing summary, commit range, and integration instructions.

- [ ] **Step 1: Add the CLI and script**

Add:

```json
"qa:spoken-formula-semantic": "tsx scripts/benchmark-spoken-formula-semantic.ts"
```

CLI stdout contains only fixture version, counts, candidate coverage rate, Top-3 rate, boundary-decision rate, P50/P95/max, ambiguity count, and miss-reason counts. It exits non-zero unless candidate coverage is at least 0.95, Top-3 rate is at least 0.90, boundary-decision rate is exactly 1, partial parses are zero, and P95 is below 100 ms.

- [ ] **Step 2: Run full semantic verification**

```powershell
npm test -- --run tests/unit/practiceFormulaSemanticNormalizer.test.ts tests/unit/practiceFormulaSemanticParser.test.ts tests/unit/practiceFormulaSemanticCorpus.test.ts tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts tests/unit/practiceFormulaMathAstJsonSchema.test.ts tests/unit/practiceFormulaCompactAst.test.ts tests/unit/practiceFormulaCandidateAudit.test.ts
npm run qa:spoken-formula-semantic
npm run typecheck
```

- [ ] **Step 3: Write the report**

Record base/head commits, changed files, exact commands/results, corpus distribution, aggregate metrics, known misses, and confirmation that no model/API is called. Do not claim production 95% accuracy.

- [ ] **Step 4: Commit and deliver**

```powershell
git add scripts/benchmark-spoken-formula-semantic.ts docs/qa/spoken-formula-semantic-engine-report.md package.json
git commit -m "test(practice): benchmark spoken semantic engine"
git status --short --branch
git log --oneline 5a98c7e..HEAD
```

Deliver commit hashes and the report path to Codex. Do not merge or push.

---

### Task C0: Preserve Integration Baselines and Create Independent Acceptance Data

**Files:**
- Create in backend: `tests/fixtures/practice-spoken-formula-semantic-heldout-v1.json`
- Create in backend: `tests/unit/practiceFormulaSemanticHeldout.test.ts`

**Interfaces:**
- Consumes: no semantic-engine implementation details.
- Produces: 200 independently reviewed held-out text cases that the other model did not use during development.

- [ ] **Step 1: Keep current worktrees stable**

Do not edit the other model's worktree. Record frontend `b9ee6f6` and backend `5a98c7e` status before parallel changes.

- [ ] **Step 2: Draft the held-out distribution independently**

Draft category quotas and expected outcomes in parallel, but do not expose utterances to the other model. After Task O3 freezes the development corpus, author and commit the exact 200 utterances: 170 supported and 30 ambiguity/unsupported boundary cases. Use the same 12 high-school categories, different structures and wording, and at least three clause-order variants. Expected LaTeX is reviewed manually and never generated by the parser under test.

- [ ] **Step 3: Keep the held-out gate outside the other model's development loop**

Run it only after Task O4 delivery. Among the 170 supported cases, the integration target is candidate coverage at least 0.95 and semantic Top-3 rate at least 0.95. Among the 30 boundary cases, boundary-decision rate must be exactly 1. Silent partial parses must be zero and P95 must be below 100 ms. Report these as held-out text metrics, not production voice accuracy.

---

### Task C1: Propagate One Deadline Through SenseVoice and V2 Requests

**Files:**
- Modify: `lib/features/practice_assessment/core/spoken_formula.dart`
- Modify: `lib/features/practice_assessment/application/speech_formula_controller.dart`
- Modify: `lib/features/practice_assessment/adapters/sensevoice_asr_client.dart`
- Modify: `lib/features/practice_assessment/adapters/local_sensevoice_speech_formula_recognizer.dart`
- Modify: `lib/features/practice_assessment/adapters/platform_speech_formula_recognizer_web.dart`
- Modify: `lib/features/practice_assessment/adapters/remote_spoken_formula_repository.dart`
- Modify: `test/features/practice_assessment/sensevoice_asr_client_test.dart`
- Modify: `test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart`
- Modify: `test/features/practice_assessment/platform_speech_formula_recognizer_web_test.dart`
- Modify: `test/features/practice_assessment/speech_formula_controller_test.dart`
- Modify: `test/features/practice_assessment/spoken_formula_repository_test.dart`
- Create in backend: `lib/practice-formula/resolutionInput.ts`
- Modify in backend: `lib/practice-formula/resolutionHttp.ts`
- Modify in backend: `tests/unit/practiceSpokenFormulaResolutionRoute.test.ts`
- Modify in backend: `tests/unit/practiceSpokenFormulaResolutionNextRoute.test.ts`

**Interfaces:**
- Consumes: controller `totalDeadline` and measured finalization elapsed.
- Produces: request-scoped remaining budgets for ASR and V2 resolution without independent fixed deadlines.

- [ ] **Step 1: Write failing budget tests**

Prove that an ASR request may exceed the disproven 1800 ms limit but cannot exceed the single controller watchdog. Prove that the V2 request body carries a clamped integer `budgetMs`, and malformed or excessive values are rejected.

```dart
expect(asrTimeout, const Duration(milliseconds: 3800));
expect(sentJson['budgetMs'], remaining.inMilliseconds);
```

The 3800 ms value is a maximum cap, not a new total budget; the controller watchdog still stops the whole operation at 5000 ms.

- [ ] **Step 2: Implement request-scoped timeout override**

Change the ASR port to:

```dart
Future<String> transcribe(
  Uint8List wavBytes, {
  required Duration timeout,
});
```

Define one `spokenFormulaTotalDeadline` constant in `core/spoken_formula.dart`. Use it as the controller default and as the injectable `finalizationDeadline` default for the Local recognizer; the web composition passes the same constant explicitly. The Local recognizer records the stop/finalization start time, computes the remaining budget immediately before upload, and passes `min(remaining, 3800 ms)`. Non-positive remaining time fails before HTTP. The client constructor default remains for independent callers. Tests inject the deadline and processing clock so timing stays deterministic.

- [ ] **Step 3: Propagate resolution budget**

Flutter sends `{text, locale, budgetMs}` where `budgetMs` equals the controller's current remaining time. Backend accepts only integer values from 1 through 5000 ms, computes `effectiveBudgetMs = min(budgetMs, 4500)`, and owns an absolute abort timer. It never increases a small client budget: if less than 250 ms remains, the resolver returns a targeted clarification without starting a model/API stage.

- [ ] **Step 4: Verify**

```powershell
flutter test --no-pub test/features/practice_assessment/sensevoice_asr_client_test.dart test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart test/features/practice_assessment/speech_formula_controller_test.dart test/features/practice_assessment/spoken_formula_repository_test.dart
```

Run the affected backend route suites and both type analyzers:

```powershell
npm test -- --run tests/unit/practiceSpokenFormulaResolutionRoute.test.ts tests/unit/practiceSpokenFormulaResolutionNextRoute.test.ts
npm run typecheck
```

Commit backend and frontend changes separately:

```powershell
git commit -m "feat(practice): accept spoken formula resolution budgets"
git commit -m "fix(practice): share spoken formula deadline budget"
```

---

### Task C2: Add Budgeted Local-Model and MiniMax Fallback to V2

**Files:**
- Create: `lib/practice-formula/resolutionStages.ts`
- Create: `tests/unit/practiceFormulaResolutionStages.test.ts`
- Modify: `lib/practice-formula/localResolutionService.ts`
- Modify: `lib/practice-formula/localModelClient.ts`
- Modify: `lib/practice-formula/miniMaxCompactAstClient.ts`
- Modify: `tests/unit/practiceFormulaLocalResolutionService.test.ts`
- Modify: `tests/unit/practiceFormulaLocalModelClient.test.ts`
- Modify: `tests/unit/practiceFormulaMiniMaxCompactAstClient.test.ts`
- Modify: `tests/unit/practiceSpokenFormulaResolutionRoute.test.ts`
- Modify: `tests/unit/practiceSpokenFormulaResolutionNextRoute.test.ts`

**Interfaces:**
- Consumes: current parser, frozen semantic parser interface, existing local-model and MiniMax Compact AST adapters, request `budgetMs`.
- Produces: one audited V2 response under the server deadline.

- [ ] **Step 1: Define injectable stages and write RED tests**

```ts
export type ResolutionStageContext = {
  signal: AbortSignal;
  remainingMs: () => number;
};

export type FormulaAstStage = (
  input: SpokenFormulaInput,
  context: ResolutionStageContext,
) => Promise<SpokenFormulaModelOutput | undefined>;
```

Tests cover: deterministic hit makes zero model/API calls; semantic hit makes zero model/API calls; local-model hit makes zero MiniMax calls; invalid AST continues only while budget remains; MiniMax runs once for a genuine miss; timeout returns targeted clarification; duplicate requests share one hashed in-flight fallback.

The local Math-AST stage is enabled only when configuration is present and its recorded warm P95 is at most 900 ms. If that gate is not met on the deployment machine, skip it rather than spending the MiniMax budget on a slower local model. Unit tests cover both routing decisions.

- [ ] **Step 2: Implement stage order**

```text
current deterministic parser
-> compositional semantic parser
-> optional local Math-AST model, capped by remaining budget
-> MiniMax Compact AST, only when no unique local candidate survives audit and budget remains
-> audited candidates or targeted clarification
```

All local/model outputs pass `parseMiniMaxCompactAstResponse` or the full Math AST schema as applicable, then `auditFormulaCandidate`. A stage cannot return raw LaTeX.

- [ ] **Step 3: Enforce cost and privacy**

Cache by SHA-256 of locale plus transcript. Log only stage name, outcome, elapsed time, aggregate fallback rate, model identifier, and usage counts. Add a test logger that fails if transcript, LaTeX, AST keys, or raw response values appear.

- [ ] **Step 4: Replace 30-second/4.5-second legacy behavior for V2 only**

Adapters accept a request timeout or abort signal. Legacy endpoints keep backward-compatible defaults. V2 caps the qualified local-model stage at 900 ms and every MiniMax attempt at `remainingMs - 150`; it never starts either stage with less than 250 ms remaining. The 150 ms reserve belongs to audit and response serialization, not another provider call.

- [ ] **Step 5: Run verification and commit**

Run all practice-formula suites, typecheck, focused ESLint, provider scans, V2 route suites, and real CLI benchmark. Commit with:

```powershell
git commit -m "feat(practice): resolve spoken formulas with bounded fallbacks"
```

---

### Task C3: Integrate and Independently Review the Other Model's Engine

**Files:**
- Cherry-pick only reviewed Task O1–O4 commits.
- Modify: `lib/practice-formula/resolutionStages.ts`
- Test: `tests/unit/practiceFormulaSemanticHeldout.test.ts`

**Interfaces:**
- Consumes: frozen `parseSemanticSpokenFormula` export.
- Produces: semantic stage registered between the current parser and model stages.

- [ ] **Step 1: Review before cherry-pick**

Check every reserved/forbidden file, full-string mapping scan, AST exhaustiveness, source-symbol audit, reverse speech, corpus independence, and benchmark evidence. Reject changes outside ownership.

- [ ] **Step 2: Cherry-pick in order**

Cherry-pick the other model's commits one at a time. Resolve no conflict by deleting validation or weakening tests.

- [ ] **Step 3: Run the hidden held-out gate**

```powershell
npm test -- --run tests/unit/practiceFormulaSemanticHeldout.test.ts
```

If actionable or Top-3 is below 0.95, report per-category misses to the other model without sharing the exact held-out utterances. The other model fixes grammar classes using new development examples, then supplies a new reviewed commit.

- [ ] **Step 4: Run full backend verification**

```powershell
npm run typecheck
npm test -- --run
npm run qa:spoken-formula-resolution
npm run qa:spoken-formula-semantic
```

Expected: all gates pass without weakening thresholds.

---

### Task C4: End-to-End Acceptance and Final Delivery

**Files:**
- Modify: `docs/qa/spoken-formula-resolution-phase-one-report.md`
- Modify: `test/features/practice_assessment/spoken_formula_resolution_end_to_end_test.dart`

**Interfaces:**
- Consumes: integrated backend, SenseVoice 8000, Flutter Web, real microphone.
- Produces: evidence-backed delivery and branch integration choices.

- [ ] **Step 1: Run Flutter verification**

```powershell
flutter test --no-pub test/features/practice_assessment
dart analyze lib/main.dart test/features/practice_assessment
flutter build web --dart-define=APP_ENV=development --dart-define=ENABLE_DEVELOPER_TOOLS=true --dart-define=API_BASE_URL=http://localhost:3001 --dart-define=PRACTICE_ASSESSMENT_REMOTE=false --dart-define=SPOKEN_FORMULA_ASR_MODE=sensevoiceLocal --dart-define=SENSEVOICE_BASE_URL=http://127.0.0.1:8000
```

- [ ] **Step 2: Run immediate real-microphone acceptance**

Before presenting the local development build as ready for user testing, run 10 utterances spoken by the current tester: three current local families, four difficult held-out structures, and three conversational paraphrases. All 10 must produce an actionable response within five seconds, at least 9 must include the intended formula in Top-3, and no incorrect formula may be auto-inserted. Record only anonymized outcome, corrected transcript, semantic correctness, and stop-to-actionable duration. Save no audio.

- [ ] **Step 3: Run the production-release real-microphone gate**

Before claiming production voice accuracy, run 30 different utterances from three speakers: 10 current local families, 10 difficult held-out structures, and 10 conversational paraphrases. All 30 must be actionable, at least 29 must include the intended formula in Top-3, no incorrect formula may be auto-inserted, and stop-to-actionable P95 must be at most five seconds. This broader gate is mandatory for a production-accuracy claim; the immediate 10-case check cannot substitute for it.

- [ ] **Step 4: Report metrics honestly**

Report ASR transcript accuracy separately from transcript-to-formula semantic accuracy. Report resolved/candidate/clarification rates, local/local-model/MiniMax routing rates, cloud cost units, P50/P95/max, and manual correction rate. Do not claim production 95% unless the real-audio sample and held-out methodology justify it.

- [ ] **Step 5: Final review and branch handoff**

Run `superpowers:verification-before-completion`, then `superpowers:requesting-code-review`, then `superpowers:finishing-a-development-branch`. Present merge/cherry-pick choices to the user; do not push or merge automatically.

---

## Copy-Paste Task for the Other Model

```text
You own only Tasks O0–O4 in:
D:\dev\Uniprism\uniprism_app\.worktrees\local-sensevoice-web-integration\docs\superpowers\plans\2026-08-27-spoken-formula-parallel-development.md

Backend base commit:
5a98c7e7427395c7380c400f794ccacb85b891d0

Create branch:
feature/spoken-formula-semantic-engine

Read docs/DEVELOPMENT_CODE_STANDARD.md and the complete plan before editing.
Use an isolated worktree, strict TDD, apply_patch, and one reviewed commit per task.
Do not create subagents unless the user explicitly authorizes them.
Do not edit V2 routes/resolvers/contracts, model providers, MiniMax/local-model clients, configuredConverter, or Flutter.
Do not add full-utterance maps. Build tokenization and compositional grammar whose operands recurse over arbitrary mathematical expressions.
Every candidate must remain Canonical Math AST; never emit raw LaTeX from production parsing.
Run all commands in Tasks O0–O4, write the handoff report, and return commit hashes plus exact test results. Do not merge, push, deploy, download models, or change secrets.
```

## Merge Conflict Policy

1. Other-model commits are reviewed before cherry-pick.
2. Ownership violations are fixed on the other-model branch, not manually hidden during merge.
3. AST core conflicts are resolved by retaining the union of schema validation, renderer support, reverse speech, audit walking, depth/node limits, and exhaustive switches.
4. No failing test is deleted, skipped, or weakened to complete a merge.
5. Codex owns the final integrated commit and reports every remaining limitation.
