# Spoken Formula Resilient Resolution Phase One Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every valid in-scope spoken high-school formula reach a safe `resolved`, `candidates`, or `clarification` state within five seconds, while the ten known difficult expressions resolve locally without MiniMax.

**Architecture:** Keep SenseVoiceSmall as the real local CPU ASR boundary, add a versioned local-only resolution endpoint in the shared Next.js backend, and make Canonical Math AST the only source for LaTeX and simplified-Chinese reverse speech. Flutter owns the total post-stop deadline and explicit confirmation state machine; the legacy endpoint remains unchanged for other clients.

**Tech Stack:** Flutter/Dart, `http`, `flutter_math_fork`, Next.js 16, TypeScript, Zod, Vitest, existing Canonical Math AST and LaTeX guard.

**Spec:** [2026-08-27-spoken-formula-resilient-local-resolution-design.md](../specs/2026-08-27-spoken-formula-resilient-local-resolution-design.md)

## Global Constraints

- Frontend work happens only in `D:\dev\Uniprism\uniprism_app\.worktrees\local-sensevoice-web-integration` on `feature/local-sensevoice-web-integration`.
- Backend work starts from commit `7355b54` in a new isolated worktree. Do not edit the dirty checkout at `D:\ywkeji\Uniprism\UniPrism_New-main`.
- Before implementation, invoke `superpowers:using-git-worktrees`; after all verification, invoke `superpowers:verification-before-completion` and `superpowers:finishing-a-development-branch`.
- Use test-driven development: add one failing behavior, run it and observe the expected failure, implement the minimum production code, then rerun the focused tests.
- Add concise Chinese comments to new public modules, async state transitions, deadline/cancellation branches, and security/privacy decisions. Do not comment obvious assignments or styling.
- `POST /api/practice/formulas/from-spoken-text` remains backward compatible. New Flutter code uses only `POST /api/practice/formulas/resolve-spoken-text`.
- The new endpoint is deterministic and local-only in phase one. It must not import or call `configuredConverter`, MiniMax, Qwen, or any other model provider.
- Mathematical uncertainty is a successful `200` response with `candidates` or `clarification`; only microphone, ASR, transport, malformed server response, or service unavailability use `infrastructureError`.
- Never log audio, raw/normalized transcript, LaTeX, complete AST, model output, or answer content. Anonymous logs may contain route name, outcome, fixed reason code, candidate count, parser version, and duration.
- Candidate LaTeX must come from validated Canonical Math AST through `renderMathAstToLatex` and `assertSafeFormulaLatex`. Flutter never receives or constructs AST.
- Phase one does not claim 95% production accuracy. It delivers the ten permanent hard regressions and the protocol/measurement foundation; the 200-text/50-audio and 1,000-text/500-audio gates belong to later plans.

---

### Task 0: Isolate Both Repositories and Record Baselines

**Files:**

- Read: `D:\dev\Uniprism\uniprism_app\docs\DEVELOPMENT_CODE_STANDARD.md`
- Validate: `D:\dev\Uniprism\uniprism_app\.worktrees\local-sensevoice-web-integration`
- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend`

- [ ] **Step 1: Load the required execution and worktree skills**

Invoke `superpowers:executing-plans` for inline execution or `superpowers:subagent-driven-development` for delegated execution, then invoke `superpowers:using-git-worktrees` before any source edit.

- [ ] **Step 2: Confirm the frontend worktree is isolated and clean**

Run:

```powershell
git -C D:\dev\Uniprism\uniprism_app\.worktrees\local-sensevoice-web-integration status --short --branch
git -C D:\dev\Uniprism\uniprism_app\.worktrees\local-sensevoice-web-integration log -1 --oneline
```

Expected: branch `feature/local-sensevoice-web-integration`, no uncommitted source changes, and the design commit at or after `f4a829e`. The plan/spec documentation commit created after this plan is also acceptable.

- [ ] **Step 3: Create the backend worktree from the known backend commit**

Run:

```powershell
git -C D:\ywkeji\Uniprism\UniPrism_New-main worktree add D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend -b feature/spoken-formula-resilience-backend 7355b54
git -C D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend status --short --branch
```

Expected: the new worktree is clean on `feature/spoken-formula-resilience-backend`. If the directory or branch already exists, inspect and reuse it only when it is clean and points to the expected commit ancestry; do not delete or reset it.

- [ ] **Step 4: Run focused baseline tests before changing behavior**

Backend:

```powershell
npm test -- --run tests/unit/practiceFormulaLocalParser.test.ts tests/unit/practiceFormulaConfiguredConverter.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts
```

Run from `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend`.

Frontend:

```powershell
flutter test test/features/practice_assessment/spoken_formula_repository_test.dart test/features/practice_assessment/speech_formula_controller_test.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart test/features/practice_assessment/sensevoice_asr_client_test.dart
```

Run from the frontend worktree. Record any pre-existing failure before proceeding; do not disguise it as a regression introduced by this plan.

---

### Task 1: Define the Versioned Backend Resolution Contract

**Files:**

- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\lib\practice-formula\resolutionContracts.ts`
- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\tests\unit\practiceFormulaResolutionContracts.test.ts`

- [ ] **Step 1: Write failing contract-invariant tests**

Add tests that accept one representative payload for each outcome and reject all invalid combinations:

```ts
import { describe, expect, it } from 'vitest';
import { spokenFormulaResolutionSchema } from '@/lib/practice-formula/resolutionContracts';

const candidate = {
  id: 'candidate-1',
  latex: String.raw`\frac{1}{x^{2}+1}`,
  spokenBack: '一除以括号 x 的平方加一括号',
};

describe('spoken formula resolution contract', () => {
  it.each([
    ['resolved', [candidate], null],
    ['candidates', [candidate, { ...candidate, id: 'candidate-2', latex: String.raw`\frac{1}{x^{2}}+1` }], null],
    ['clarification', [], {
      question: '我还不能确定“整体”修饰哪一部分，请选择下一步。',
      focusText: '整体',
      options: [
        { id: 'retry-recording', label: '重新录音', action: 'retryRecording' },
        { id: 'use-keyboard', label: '保留识别文字并使用公式键盘', action: 'useKeyboard' },
      ],
    }],
  ])('accepts %s', (outcome, candidates, clarification) => {
    expect(spokenFormulaResolutionSchema.safeParse({
      resolutionId: 'resolution-1',
      recognizedText: '一除以 x 平方加一',
      normalizedText: '一除以x平方加一',
      outcome,
      candidates,
      clarification,
      warnings: [],
    }).success).toBe(true);
  });

  it.each([
    ['resolved', [], null],
    ['resolved', [candidate, { ...candidate, id: 'candidate-2' }], null],
    ['candidates', [candidate], null],
    ['clarification', [], null],
  ])('rejects invalid %s cardinality', (outcome, candidates, clarification) => {
    expect(spokenFormulaResolutionSchema.safeParse({
      resolutionId: 'resolution-1', recognizedText: 'x', normalizedText: 'x',
      outcome, candidates, clarification, warnings: [],
    }).success).toBe(false);
  });
});
```

- [ ] **Step 2: Run the focused test and observe the missing-module failure**

```powershell
npm test -- --run tests/unit/practiceFormulaResolutionContracts.test.ts
```

Expected: FAIL because `resolutionContracts.ts` does not exist.

- [ ] **Step 3: Implement the strict Zod schema and exported TypeScript types**

The public structures must be exactly:

```ts
export type SpokenFormulaResolutionOutcome = 'resolved' | 'candidates' | 'clarification';
export type SpokenFormulaClarificationAction =
  | 'selectCandidate'
  | 'retryRecording'
  | 'useKeyboard';

export type SpokenFormulaResolutionCandidate = {
  id: string;
  latex: string;
  spokenBack: string;
};

export type SpokenFormulaClarification = {
  question: string;
  focusText: string;
  options: Array<{
    id: string;
    label: string;
    action: SpokenFormulaClarificationAction;
    candidateId?: string;
  }>;
};

export type SpokenFormulaResolution = {
  resolutionId: string;
  recognizedText: string;
  normalizedText: string;
  outcome: SpokenFormulaResolutionOutcome;
  candidates: SpokenFormulaResolutionCandidate[];
  clarification: SpokenFormulaClarification | null;
  warnings: string[];
};
```

Use `.strict()` for every object. Constrain IDs to `^[A-Za-z0-9_-]{1,80}$`, LaTeX to 512 characters, user-visible strings to the existing safe text rule and suitable limits, candidates to at most three, warnings to at most three, and clarification options to two or three. Add `superRefine` rules for outcome cardinality, unique candidate/option IDs, and `selectCandidate` requiring an ID present in `candidates`; non-selection actions must not contain `candidateId`.

- [ ] **Step 4: Run the contract tests and typecheck**

```powershell
npm test -- --run tests/unit/practiceFormulaResolutionContracts.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit the backend contract**

```powershell
git add lib/practice-formula/resolutionContracts.ts tests/unit/practiceFormulaResolutionContracts.test.ts
git commit -m "feat(practice): define spoken formula resolution contract"
```

---

### Task 2: Add Canonical AST Safety Reasons and Simplified-Chinese Reverse Speech

**Files:**

- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\lib\practice-formula\candidateAudit.ts`
- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\lib\practice-formula\mathAstSpeechZhCn.ts`
- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\tests\unit\practiceFormulaCandidateAudit.test.ts`
- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\tests\unit\practiceFormulaMathAstSpeechZhCn.test.ts`

- [ ] **Step 1: Write failing reverse-speech tests for dangerous scopes**

Construct AST values directly and assert exact output for these structures:

| Structure | Required `spokenText` fragment | Required signature fragment |
|---|---|---|
| `1 / (x² + 1)` | `一除以括号 x 的平方加一括号` | `divide(number:1,add(power(symbol:x,number:2),number:1))` |
| `1 / x² + 1` | `一除以 x 的平方，再加一` | `add(divide(number:1,power(symbol:x,number:2)),number:1)` |
| square root | `根号括号…括号` for an additive radicand | `root(` |
| sum | `对 k 从一到 n 的…求和` | `sum(variable:symbol:k,lower:number:1,upper:symbol:n` |
| definite integral | `从负一到一，对…关于 x 积分` | `integral(variable:symbol:x` |
| derivative at point | `在 x 等于二处的二阶导数` | `derivative(order:2,variable:symbol:x,at:number:2` |
| three-branch piecewise | all three `当…时` clauses | `piecewise(` |

Also assert that every returned segment has a non-empty `path`, `text`, and a role from the closed role union.

- [ ] **Step 2: Write failing audit tests for fixed reason codes**

Define and test this closed union:

```ts
export type CandidateRejectionReason =
  | 'SCHEMA_INVALID'
  | 'NODE_UNSUPPORTED'
  | 'ARITY_INVALID'
  | 'SOURCE_SYMBOL_ADDED'
  | 'SOURCE_SYMBOL_DROPPED'
  | 'SCOPE_CONFLICT'
  | 'SEMANTIC_LIMIT_EXCEEDED'
  | 'LATEX_GUARD_REJECTED';
```

Tests must cover an unknown node, a function with invalid arity, source `x` with candidate symbol `y`, source `x 加 y` with candidate only `x`, a depth-over-16 AST, and an injected LaTeX guard failure. The thrown error exposes only `.reasonCode`, never the original AST, transcript, rendered LaTeX, or underlying exception message.

- [ ] **Step 3: Run both tests and observe missing-module failures**

```powershell
npm test -- --run tests/unit/practiceFormulaCandidateAudit.test.ts tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts
```

Expected: FAIL because both modules are absent.

- [ ] **Step 4: Implement the reverse-speech pure function**

Expose this public API:

```ts
export type MathSpeechSegmentRole =
  | 'operator' | 'operand' | 'scope' | 'bound' | 'condition';

export type MathSpeechSegment = {
  path: string;
  text: string;
  role: MathSpeechSegmentRole;
};

export type MathAstSpeechZhCn = {
  spokenText: string;
  semanticSignature: string;
  segments: MathSpeechSegment[];
};

/** 把已审核 Canonical AST 反向朗读为简体中文，并保留可比较的结构签名。 */
export function renderMathAstSpeechZhCn(node: MathAstNode): MathAstSpeechZhCn;
```

Use exhaustive `switch` handling for every existing `MathAstNode` variant. Signatures use deterministic prefix notation and fixed field order; never derive them from LaTeX. Use explicit scope words around additive/relation children of division, root, power, derivative, binder and integral. Read constants and functions through closed lookup tables. Use paths such as `$`, `$.left`, `$.right`, `$.cases[0].condition`; never serialize AST into a segment.

- [ ] **Step 5: Implement the candidate audit boundary**

Expose:

```ts
export type AuditedFormulaCandidate = {
  ast: MathAstNode;
  latex: string;
  spokenBack: string;
  semanticSignature: string;
};

export function auditFormulaCandidate(
  sourceText: string,
  input: unknown,
  dependencies?: {
    guardLatex?: (latex: string) => string;
  },
): AuditedFormulaCandidate;
```

The implementation order is fixed: Zod schema parse -> node/arity classification -> `assertMathAstCandidateLimits` -> source/candidate ASCII-and-Greek symbol set comparison -> deterministic LaTeX rendering -> LaTeX guard -> reverse speech. Map only to the fixed reason codes. Do not attach unsafe values to the error or logger.

- [ ] **Step 6: Run focused tests and typecheck**

```powershell
npm test -- --run tests/unit/practiceFormulaCandidateAudit.test.ts tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 7: Commit the safety and reverse-speech modules**

```powershell
git add lib/practice-formula/candidateAudit.ts lib/practice-formula/mathAstSpeechZhCn.ts tests/unit/practiceFormulaCandidateAudit.test.ts tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts
git commit -m "feat(practice): audit and reverse-read formula AST"
```

---

### Task 3: Cover Difficult Calculus, Binder, Logarithm, and Combinatoric Speech Locally

**Files:**

- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\tests\fixtures\practice-spoken-formula-hard-v1.json`
- Modify: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\lib\practice-formula\localSpokenFormulaParser.ts`
- Modify: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\tests\unit\practiceFormulaLocalParser.test.ts`

- [ ] **Step 1: Add the versioned ten-case hard fixture**

The fixture must contain exactly the ten approved utterances and semantic expectations from the design spec. Use the same versioned shape as the existing local fixture and these exact deterministic-renderer outputs:

```json
{
  "version": 1,
  "cases": [
    { "id": "hard-01", "category": "derivative", "spokenText": "求函数 x 的三次方加二 x 在 x 等于二处的二阶导数", "expectedStatus": "ok", "expectedLatex": ["\\left.\\frac{d^{2}}{dx^{2}}\\left(x^{3}+2x\\right)\\right|_{x=2}"], "expectedAlternatives": [] },
    { "id": "hard-02", "category": "summation", "spokenText": "对 k 从一到 n 的 k 平方求和", "expectedStatus": "ok", "expectedLatex": ["\\sum_{k=1}^{n}k^{2}"], "expectedAlternatives": [] },
    { "id": "hard-03", "category": "interval", "spokenText": "x 在零和一之间并且包含零但不包含一", "expectedStatus": "ok", "expectedLatex": ["\\left[0,1\\right)"], "expectedAlternatives": [] },
    { "id": "hard-04", "category": "set-builder", "spokenText": "所有满足 x 平方小于四的 x 组成的集合", "expectedStatus": "ok", "expectedLatex": ["\\left\\{x\\mid x^{2}<4\\right\\}"], "expectedAlternatives": [] },
    { "id": "hard-05", "category": "piecewise", "spokenText": "当 x 小于零时 f x 等于负一，当 x 等于零时 f x 等于零，当 x 大于零时 f x 等于一", "expectedStatus": "ok", "expectedLatex": ["f\\left(x\\right)=\\begin{cases}-1,&x<0\\\\0,&x=0\\\\1,&x>0\\end{cases}"], "expectedAlternatives": [] },
    { "id": "hard-06", "category": "derivative", "spokenText": "函数 x 平方加一整体除以 x 减一关于 x 的导数", "expectedStatus": "ok", "expectedLatex": ["\\frac{d}{dx}\\frac{x^{2}+1}{x-1}"], "expectedAlternatives": [] },
    { "id": "hard-07", "category": "integral", "spokenText": "从负一到一的根号下一减 x 平方关于 x 的定积分", "expectedStatus": "ok", "expectedLatex": ["\\int_{-1}^{1}\\sqrt{1-x^{2}}\\,dx"], "expectedAlternatives": [] },
    { "id": "hard-08", "category": "limit", "spokenText": "x 趋近于零时根号下一加 x 再减一整体除以 x 的极限", "expectedStatus": "ok", "expectedLatex": ["\\lim_{x\\to0}\\frac{\\sqrt{1+x}-1}{x}"], "expectedAlternatives": [] },
    { "id": "hard-09", "category": "logarithm", "spokenText": "以二为底 x 加一的对数加上 x 减一的自然对数等于三", "expectedStatus": "ok", "expectedLatex": ["\\log_{2}\\left(x+1\\right)+\\ln\\left(x-1\\right)=3"], "expectedAlternatives": [] },
    { "id": "hard-10", "category": "combinatoric", "spokenText": "从 n 个里面选两个的组合数等于 n 乘 n 减一整体除以二", "expectedStatus": "ok", "expectedLatex": ["C_{n}^{2}=\\frac{n\\cdot\\left(n-1\\right)}{2}"], "expectedAlternatives": [] }
  ]
}
```

- [ ] **Step 2: Add failing local-parser tests for cases 1, 2, 6, 7, 8, 9 and 10**

Load the fixture and filter the IDs. For each case assert `status === 'ok'`, `primary !== null`, exact deterministic LaTeX, and no alternatives. Also assert the top-level semantic AST kind for derivative, binder, integral, limit, logarithm relation, and combinatoric relation so equivalent-looking but mis-scoped LaTeX cannot pass. Retain the existing 30-case benchmark test unchanged.

- [ ] **Step 3: Run the focused test and verify these cases fail before implementation**

```powershell
npm test -- --run tests/unit/practiceFormulaLocalParser.test.ts
```

Expected: the new difficult cases fail while the existing cases continue to pass.

- [ ] **Step 4: Expand compositional normalization and parser entry forms**

Implement reusable forms rather than ten exact-string branches:

- normalize `根号下` to the existing scoped-root form and `整体` to `整个式子` only when it is a scope marker;
- accept `求函数 <expr> 在 <var> 等于 <point> 处的 <order> 阶导数`;
- accept `函数 <expr> 关于 <var> 的导数` and preserve the entire fraction as derivative body;
- accept `对 <var> 从 <lower> 到 <upper> 的 <body> 求和/求积`;
- accept definite integrals with explicit `关于 <var>` rather than inferring the first symbol;
- allow combinatoric nodes as operands of relations without duplicating the combinatoric grammar;
- preserve additive arguments inside base-`log` and `ln` by using expression boundaries, not greedy whole-sentence matching;
- treat `整体除以` as explicit full-left-scope division.

Keep `parseExpression` compositional. Add small helpers such as `parseScopedOperand`, `parseAggregate`, or `parseMathAtom`; do not add a map keyed by the full fixture sentences.

- [ ] **Step 5: Run the focused parser and legacy converter tests**

```powershell
npm test -- --run tests/unit/practiceFormulaLocalParser.test.ts tests/unit/practiceFormulaConfiguredConverter.test.ts tests/unit/practiceSpokenFormula.test.ts
```

Expected: all selected tests PASS.

- [ ] **Step 6: Commit the calculus and expression coverage**

```powershell
git add lib/practice-formula/localSpokenFormulaParser.ts tests/unit/practiceFormulaLocalParser.test.ts tests/fixtures/practice-spoken-formula-hard-v1.json
git commit -m "feat(practice): parse difficult spoken formula structures locally"
```

---

### Task 4: Cover Endpoint Intervals, Set Builders, and Arbitrary Piecewise Branches

**Files:**

- Modify: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\lib\practice-formula\localSpokenFormulaParser.ts`
- Modify: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\tests\unit\practiceFormulaLocalParser.test.ts`

- [ ] **Step 1: Add failing tests for hard cases 3, 4 and 5**

Add these structural assertions in addition to exact LaTeX:

```ts
expect(interval.primary).toMatchObject({
  type: 'interval', leftClosed: true, rightClosed: false,
});
expect(setBuilder.primary).toMatchObject({
  type: 'setBuilder', variable: { type: 'symbol', name: 'x' },
});
expect(piecewise.primary).toMatchObject({
  type: 'relation',
  right: { type: 'piecewise', cases: [{}, {}, {}] },
});
```

- [ ] **Step 2: Run the test and observe the three expected failures**

```powershell
npm test -- --run tests/unit/practiceFormulaLocalParser.test.ts
```

- [ ] **Step 3: Implement reusable structural parsers**

- Parse `<variable> 在 <left> 和 <right> 之间` plus independent inclusion clauses. Map `包含左端点/包含零` to `leftClosed`, `不包含右端点/不包含一` to `rightClosed`; if a clause cannot be assigned to exactly one endpoint, do not return `ok`.
- Parse `所有满足 <condition> 的 <variable> 组成的集合` into `setBuilder`, and require the condition AST to actually contain the named variable.
- Tokenize repeated `当 <condition> 时 f x 等于 <expression>` clauses into one function identity and any number from two through eight of `piecewise.cases`. Reject mixed function names or variables.
- Keep the existing one-condition-plus-otherwise forms working.

- [ ] **Step 4: Run parser, AST semantic, and LaTeX tests**

```powershell
npm test -- --run tests/unit/practiceFormulaLocalParser.test.ts tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts
npm run typecheck
```

Expected: PASS, including all ten hard expressions and the existing 30 cases.

- [ ] **Step 5: Commit the structural grammar coverage**

```powershell
git add lib/practice-formula/localSpokenFormulaParser.ts tests/unit/practiceFormulaLocalParser.test.ts
git commit -m "feat(practice): parse spoken sets intervals and piecewise formulas"
```

---

### Task 5: Build the Local Resolution Orchestrator and New Next.js Route

**Files:**

- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\lib\practice-formula\localResolutionService.ts`
- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\lib\practice-formula\resolutionHttp.ts`
- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\app\api\practice\formulas\resolve-spoken-text\route.ts`
- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\tests\unit\practiceFormulaLocalResolutionService.test.ts`
- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\tests\unit\practiceSpokenFormulaResolutionRoute.test.ts`
- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\tests\unit\practiceSpokenFormulaResolutionNextRoute.test.ts`

- [ ] **Step 1: Write failing service tests for all outcomes and privacy**

Test these behaviors:

1. An `ok` local AST becomes `resolved`, one audited candidate, and reverse speech.
2. `负二的平方` becomes `candidates`, exactly two semantically distinct candidates, each with reverse speech.
3. An unconsumed in-scope expression becomes `clarification`, preserves `recognizedText`, names a bounded `focusText`, and offers `retryRecording` plus `useKeyboard`; it never throws a generic conversion error.
4. Proof/process speech becomes a specific clarification that asks for the formula to insert, not a model call.
5. A rejected candidate becomes clarification and logs only a fixed reason code plus anonymous timing/count fields.
6. All ten hard fixture cases are `resolved` locally and contain expected LaTeX.
7. The service module has no MiniMax dependency; inject a logger only, not a model provider.

The service public boundary is:

```ts
export type LocalResolutionDependencies = {
  now?: () => number;
  createId?: () => string;
  logDecision?: (event: {
    outcome: SpokenFormulaResolutionOutcome;
    reasonCode?: CandidateRejectionReason;
    candidateCount: number;
    latencyMs: number;
    parserVersion: 1;
  }) => void;
};

export function createLocalSpokenFormulaResolver(
  dependencies?: LocalResolutionDependencies,
): (input: unknown) => Promise<SpokenFormulaResolution>;
```

- [ ] **Step 2: Write failing HTTP and route wiring tests**

Use a `NextRequest` to the new URL and assert the standard `{ok:true,data}` envelope, CORS preflight, the same 20-per-minute IP rate limit behavior, input validation, and exact response contract. Mock `localResolutionService`, not the legacy converter.

- [ ] **Step 3: Run focused tests and observe missing-module failures**

```powershell
npm test -- --run tests/unit/practiceFormulaLocalResolutionService.test.ts tests/unit/practiceSpokenFormulaResolutionRoute.test.ts tests/unit/practiceSpokenFormulaResolutionNextRoute.test.ts
```

- [ ] **Step 4: Implement local outcome orchestration**

Use `parseLocalSpokenFormula`, `auditFormulaCandidate`, semantic-signature deduplication, and request-scoped opaque IDs from `randomUUID()`. Ordering is deterministic: primary first, then alternatives, after signature deduplication. Enforce `resolved` one candidate and `candidates` two or three. For unresolved input return this concrete recovery structure rather than throwing:

```ts
{
  outcome: 'clarification',
  candidates: [],
  clarification: {
    question: `我还不能确定“${focusText}”的数学作用范围，请选择下一步。`,
    focusText,
    options: [
      { id: 'retry-recording', label: '重新录音', action: 'retryRecording' },
      { id: 'use-keyboard', label: '保留识别文字并使用公式键盘', action: 'useKeyboard' },
    ],
  },
}
```

Derive `focusText` from the shortest unresolved normalized span and cap it before returning. If no narrower diagnostic exists, use the normalized expression capped to 24 characters. Do not put it in logs.

- [ ] **Step 5: Implement the new HTTP adapter and route**

`resolutionHttp.ts` mirrors the existing validation/rate-limit/CORS boundary but depends on the new resolver and validates its result with `spokenFormulaResolutionSchema` before `ok(...)`. The route must be exactly:

```ts
import { learningApiOptions } from '@/lib/learning-session/http';
import { resolveLocalSpokenFormula } from '@/lib/practice-formula/localResolutionService';
import { createSpokenFormulaResolutionApi } from '@/lib/practice-formula/resolutionHttp';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const api = createSpokenFormulaResolutionApi({ resolve: resolveLocalSpokenFormula });
export const POST = api.resolve;
export const OPTIONS = learningApiOptions;
```

- [ ] **Step 6: Verify the new route never reaches cloud/model code**

Run:

```powershell
rg -n "configuredConverter|MiniMax|resolveSpokenFormulaModelCall|localModel" lib/practice-formula/localResolutionService.ts lib/practice-formula/resolutionHttp.ts app/api/practice/formulas/resolve-spoken-text/route.ts
```

Expected: no matches.

- [ ] **Step 7: Run backend focused verification**

```powershell
npm test -- --run tests/unit/practiceFormulaResolutionContracts.test.ts tests/unit/practiceFormulaCandidateAudit.test.ts tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts tests/unit/practiceFormulaLocalParser.test.ts tests/unit/practiceFormulaLocalResolutionService.test.ts tests/unit/practiceSpokenFormulaResolutionRoute.test.ts tests/unit/practiceSpokenFormulaResolutionNextRoute.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts
npm run typecheck
```

Expected: PASS. The two legacy route tests prove compatibility was preserved.

- [ ] **Step 8: Commit the local resolution endpoint**

```powershell
git add lib/practice-formula/localResolutionService.ts lib/practice-formula/resolutionHttp.ts app/api/practice/formulas/resolve-spoken-text/route.ts tests/unit/practiceFormulaLocalResolutionService.test.ts tests/unit/practiceSpokenFormulaResolutionRoute.test.ts tests/unit/practiceSpokenFormulaResolutionNextRoute.test.ts
git commit -m "feat(practice): add local spoken formula resolution endpoint"
```

---

### Task 6: Migrate Flutter to the Versioned Resolution DTO

**Files:**

- Modify: `lib/features/practice_assessment/core/spoken_formula.dart`
- Modify: `lib/features/practice_assessment/adapters/remote_spoken_formula_repository.dart`
- Modify: `lib/features/practice_assessment/adapters/demo_spoken_formula_repository.dart`
- Modify: `test/features/practice_assessment/spoken_formula_repository_test.dart`
- Modify: `test/features/practice_assessment/practice_spoken_formula_composition_test.dart`

- [ ] **Step 1: Replace old repository tests with failing V2 mapping tests**

Assert that the repository posts only `{text, locale}` to `/api/practice/formulas/resolve-spoken-text`, maps all three outcomes, preserves candidate ID/LaTeX/reverse speech, validates clarification actions, and rejects malformed cardinalities or unknown enum values with a safe `SpokenFormulaResolutionException`.

The resolved fixture is:

```dart
{
  'resolutionId': 'resolution-1',
  'recognizedText': 'x 的平方',
  'normalizedText': 'x的平方',
  'outcome': 'resolved',
  'candidates': [
    {'id': 'candidate-1', 'latex': r'x^2', 'spokenBack': 'x 的平方'},
  ],
  'clarification': null,
  'warnings': <String>[],
}
```

- [ ] **Step 2: Run the repository test and observe the old-endpoint/old-shape failure**

```powershell
flutter test test/features/practice_assessment/spoken_formula_repository_test.dart
```

- [ ] **Step 3: Implement immutable Dart domain values and repository boundary**

Use these public shapes:

```dart
enum SpokenFormulaOutcome { resolved, candidates, clarification }
enum SpokenFormulaClarificationAction {
  selectCandidate,
  retryRecording,
  useKeyboard,
}

final class SpokenFormulaCandidate {
  const SpokenFormulaCandidate({
    required this.id,
    required this.latex,
    required this.spokenBack,
  });
  final String id;
  final String latex;
  final String spokenBack;
}

final class SpokenFormulaResolution {
  const SpokenFormulaResolution({
    required this.resolutionId,
    required this.recognizedText,
    required this.normalizedText,
    required this.outcome,
    required this.candidates,
    required this.clarification,
    required this.warnings,
  });
  // Fields match the server contract exactly; no AST or confidence is present.
}

abstract interface class SpokenFormulaRepository {
  Future<SpokenFormulaResolution> resolve({
    required String text,
    String locale = 'zh-CN',
    required Duration timeout,
  });
}
```

Create corresponding immutable clarification and option classes. Put JSON parsing only in `remote_spoken_formula_repository.dart`; enforce the same cardinality and action/candidate invariants as the backend. The demo repository remains test/development-only but must return the V2 domain shape and clarification instead of throwing its old “换一种说法” message.

- [ ] **Step 4: Use the new endpoint and caller-supplied deadline**

`RemoteSpokenFormulaRepository.resolve` calls:

```dart
final data = await api.request(
  'POST',
  '/api/practice/formulas/resolve-spoken-text',
  body: <String, Object?>{'text': text, 'locale': locale},
  requestTimeout: timeout,
);
```

There must be no 70-second constant in the repository.

- [ ] **Step 5: Run repository/composition tests and analyze affected code**

```powershell
flutter test test/features/practice_assessment/spoken_formula_repository_test.dart test/features/practice_assessment/practice_spoken_formula_composition_test.dart
dart analyze lib/features/practice_assessment/core/spoken_formula.dart lib/features/practice_assessment/adapters/remote_spoken_formula_repository.dart lib/features/practice_assessment/adapters/demo_spoken_formula_repository.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the Flutter contract migration**

```powershell
git add lib/features/practice_assessment/core/spoken_formula.dart lib/features/practice_assessment/adapters/remote_spoken_formula_repository.dart lib/features/practice_assessment/adapters/demo_spoken_formula_repository.dart test/features/practice_assessment/spoken_formula_repository_test.dart test/features/practice_assessment/practice_spoken_formula_composition_test.dart
git commit -m "feat(practice): consume resilient spoken formula resolutions"
```

---

### Task 7: Enforce the Five-Second Flutter Deadline and Cancellation Isolation

**Files:**

- Modify: `lib/features/practice_assessment/core/spoken_formula.dart`
- Modify: `lib/features/practice_assessment/adapters/local_sensevoice_speech_formula_recognizer.dart`
- Modify: `lib/features/practice_assessment/adapters/platform_speech_formula_recognizer_web.dart`
- Modify: `lib/features/practice_assessment/application/speech_formula_controller.dart`
- Modify: `test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart`
- Modify: `test/features/practice_assessment/platform_speech_formula_recognizer_web_test.dart`
- Modify: `test/features/practice_assessment/speech_formula_controller_test.dart`

- [ ] **Step 1: Write failing state-machine tests**

Cover these transitions:

```text
idle -> requestingPermission -> listening
listening -> transcribing -> resolving -> resolved
resolving -> choosingCandidate
resolving -> clarifying
microphone/ASR/network/malformed-response -> infrastructureError
```

Also test:

- resolved/candidate/clarification never use `errorMessage`;
- a fake ASR elapsed time of 4.5 seconds leaves only 0.5 seconds for the repository;
- a repository that never completes exits by the total five-second deadline and does not continue spinning;
- `reset`, second recording, page disposal, or user confirmation invalidates a late response;
- only a candidate from the current resolution can become `selectedCandidate`;
- a clarification option with `selectCandidate` selects that response candidate; retry starts a new recording; keyboard returns to idle without modifying the answer.

Use an injected deadline value and fake elapsed durations; do not make unit tests sleep five real seconds.

- [ ] **Step 2: Write a failing recognizer timing test**

Extend final result callbacks with optional processing metadata:

```dart
typedef SpeechFormulaResultCallback = void Function(
  String words, {
  required bool isFinal,
  Duration? processingElapsed,
});
```

The local SenseVoice recognizer must measure from the beginning of stop/capture finalization through WAV encoding and ASR completion, then pass that duration with the final transcript. Browser recognition may omit it because the browser driver does not expose a trustworthy stop-origin timestamp.

- [ ] **Step 3: Run controller and recognizer tests and observe compile/behavior failures**

```powershell
flutter test test/features/practice_assessment/speech_formula_controller_test.dart test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart test/features/practice_assessment/platform_speech_formula_recognizer_web_test.dart
```

- [ ] **Step 4: Implement the explicit state and deadline model**

Use:

```dart
enum SpeechFormulaStatus {
  idle,
  requestingPermission,
  listening,
  transcribing,
  resolving,
  resolved,
  choosingCandidate,
  clarifying,
  infrastructureError,
}
```

`SpeechFormulaState` stores transcript, current resolution, selected candidate ID, and infrastructure message. The controller has an injectable `totalDeadline`, defaulting to five seconds. On a final transcript:

```dart
final remaining = totalDeadline - (processingElapsed ?? Duration.zero);
if (remaining <= Duration.zero) {
  _showInfrastructureError(_deadlineMessage, transcript);
  return;
}
final resolution = await repository
    .resolve(text: transcript, timeout: remaining)
    .timeout(remaining);
```

Map outcomes exactly: `resolved` -> `resolved`, `candidates` -> `choosingCandidate`, `clarification` -> `clarifying`. Continue using `_operationId` to isolate late completions. `stopListening` sets `transcribing` before awaiting the recognizer and does not overwrite a final callback that already moved to `resolving`.

- [ ] **Step 5: Budget SenseVoice inside the five-second total**

In `createPlatformSpeechFormulaRecognizer`, construct the local client with:

```dart
SenseVoiceAsrClient(
  baseUrl: senseVoiceBaseUrl,
  timeout: const Duration(milliseconds: 1800),
)
```

Keep the client constructor default unchanged for independent callers and existing tests. The local recognizer stopwatch includes capture stop and ASR; it never fabricates model confidence.

- [ ] **Step 6: Run all affected state/cancellation tests and analysis**

```powershell
flutter test test/features/practice_assessment/speech_formula_controller_test.dart test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart test/features/practice_assessment/platform_speech_formula_recognizer_web_test.dart test/features/practice_assessment/sensevoice_asr_client_test.dart
dart analyze lib/features/practice_assessment/core/spoken_formula.dart lib/features/practice_assessment/application/speech_formula_controller.dart lib/features/practice_assessment/adapters/local_sensevoice_speech_formula_recognizer.dart lib/features/practice_assessment/adapters/platform_speech_formula_recognizer_web.dart
```

Expected: PASS.

- [ ] **Step 7: Commit the deadline state machine**

```powershell
git add lib/features/practice_assessment/core/spoken_formula.dart lib/features/practice_assessment/adapters/local_sensevoice_speech_formula_recognizer.dart lib/features/practice_assessment/adapters/platform_speech_formula_recognizer_web.dart lib/features/practice_assessment/application/speech_formula_controller.dart test/features/practice_assessment/local_sensevoice_speech_formula_recognizer_test.dart test/features/practice_assessment/platform_speech_formula_recognizer_web_test.dart test/features/practice_assessment/speech_formula_controller_test.dart
git commit -m "feat(practice): enforce spoken formula resolution deadline"
```

---

### Task 8: Render Formula Candidates, Reverse Speech, and Clarification as Success UI

**Files:**

- Modify: `lib/features/practice_assessment/presentation/practice_formula_voice_panel.dart`
- Modify: `lib/features/practice_assessment/presentation/math_answer_field.dart`
- Modify: `test/features/practice_assessment/practice_formula_voice_panel_test.dart`
- Modify: `test/features/practice_assessment/math_answer_field_test.dart`

- [ ] **Step 1: Write failing widget tests for the three successful outcomes**

Tests must assert:

- `resolved`: formula and `反向朗读：…` display; nothing is inserted before the user taps `插入公式`.
- `choosingCandidate`: two or three cards each display their own formula and reverse speech; the insert button remains disabled until the user explicitly selects one.
- `clarifying`: displays the concrete question/focus and clickable actions in neutral purple styling, with no red error copy and no generic “换一种说法”.
- selecting a candidate and inserting calls `onInsert` exactly once with the selected candidate LaTeX;
- retry and cancel preserve the existing operation-generation isolation;
- 375px width has no overflow and long formula/reverse speech can scroll or wrap;
- `infrastructureError` preserves the transcript and leaves the formula keyboard available.

- [ ] **Step 2: Run widget tests and observe failures against the old preview/error UI**

```powershell
flutter test test/features/practice_assessment/practice_formula_voice_panel_test.dart test/features/practice_assessment/math_answer_field_test.dart
```

- [ ] **Step 3: Implement outcome-specific presentation**

Split private widgets by responsibility:

```text
_ResolvedFormula
_CandidatePicker
_ClarificationPrompt
_InfrastructureError
_ProgressMessage
```

Use stable keys:

```text
practice-formula-voice-resolved
practice-formula-voice-candidates
practice-formula-voice-candidate-<id>
practice-formula-voice-spoken-back-<id>
practice-formula-voice-clarification
practice-formula-voice-clarification-<option-id>
practice-formula-voice-infrastructure-error
```

Formula cards call `controller.selectCandidate(candidate.id)`. The insert callback reads only `state.selectedCandidate?.latex`, then resets. Clarification options delegate to `controller.answerClarification(option)`. Never infer a formula in the widget.

- [ ] **Step 4: Run affected widgets, composition tests, and analysis**

```powershell
flutter test test/features/practice_assessment/practice_formula_voice_panel_test.dart test/features/practice_assessment/math_answer_field_test.dart test/features/practice_assessment/practice_spoken_formula_composition_test.dart
dart analyze lib/main.dart test/features/practice_assessment
```

Expected: PASS.

- [ ] **Step 5: Commit the outcome UI**

```powershell
git add lib/features/practice_assessment/presentation/practice_formula_voice_panel.dart lib/features/practice_assessment/presentation/math_answer_field.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart test/features/practice_assessment/math_answer_field_test.dart
git commit -m "feat(practice): show spoken formula candidates and clarification"
```

---

### Task 9: Add Repeatable Phase-One Benchmarks and End-to-End Contract Tests

**Files:**

- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\scripts\benchmark-spoken-formula-resolution.ts`
- Modify: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\package.json`
- Create: `D:\ywkeji\Uniprism\worktrees\spoken-formula-resilience-backend\tests\unit\practiceFormulaResolutionBenchmark.test.ts`
- Create: `test/features/practice_assessment/spoken_formula_resolution_end_to_end_test.dart`
- Create: `docs/qa/spoken-formula-resolution-phase-one-report.md`

- [ ] **Step 1: Write a failing backend benchmark gate**

For all ten hard cases, call `resolveLocalSpokenFormula` with deterministic IDs and assert:

```ts
expect(summary).toMatchObject({
  total: 10,
  actionableRate: 1,
  expectedTop3Rate: 1,
  genericFailureCount: 0,
  cloudCallCount: 0,
});
expect(summary.p95Ms).toBeLessThan(100);
```

Unit tests use an injected monotonic clock for deterministic behavior. The separate CLI benchmark uses real `performance.now()` and reports P50/P95/max without writing transcripts or formulas to its output.

- [ ] **Step 2: Implement the benchmark CLI and script**

Add:

```json
"qa:spoken-formula-resolution": "tsx scripts/benchmark-spoken-formula-resolution.ts"
```

CLI output contains only:

```json
{
  "fixtureVersion": 1,
  "total": 10,
  "resolved": 10,
  "candidates": 0,
  "clarifications": 0,
  "expectedTop3Rate": 1,
  "genericFailureCount": 0,
  "cloudCallCount": 0,
  "p50Ms": 0,
  "p95Ms": 0,
  "maxMs": 0
}
```

The shown zero timings are the schema shape, not hard-coded results; populate them from observed durations. Exit non-zero unless all ten are actionable, expected formula is in Top-3, generic failures/cloud calls are zero, and P95 is below 100ms.

- [ ] **Step 3: Add a Flutter contract-to-insert integration test**

Use `MockClient` to return one resolved and one ambiguous response through the real `PracticeApiClient` + `RemoteSpokenFormulaRepository` + `SpeechFormulaController` + `PracticeFormulaVoicePanel`. Assert the real endpoint path, reverse speech display, explicit selection, and single insertion. This test must not use `DemoSpokenFormulaRepository`.

- [ ] **Step 4: Run the focused benchmark and integration tests**

Backend:

```powershell
npm test -- --run tests/unit/practiceFormulaResolutionBenchmark.test.ts
npm run qa:spoken-formula-resolution
```

Frontend:

```powershell
flutter test test/features/practice_assessment/spoken_formula_resolution_end_to_end_test.dart
```

Expected: PASS; retain the measured P50/P95/max for the QA report.

- [ ] **Step 5: Perform a real local audio smoke test**

Start the existing local SenseVoice service on port 8000, backend on port 3000, and Flutter Web on port 5175 with:

```powershell
flutter run -d chrome --web-port 5175 --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=SPOKEN_FORMULA_ASR_MODE=sensevoiceLocal --dart-define=SENSEVOICE_BASE_URL=http://127.0.0.1:8000
```

Speak at least these three phrases:

1. `求函数 x 的三次方加二 x 在 x 等于二处的二阶导数`
2. `x 趋近于零时根号下一加 x 再减一整体除以 x 的极限`
3. `负二的平方`

Verify real microphone input, visible ASR transcript, correct resolved/candidate state, reverse speech, manual confirmation, and stop-to-actionable duration at or below five seconds. Do not save audio.

- [ ] **Step 6: Write the QA report with observed evidence**

The report must include commit IDs, OS/CPU, SenseVoice mode, fixture version, backend P50/P95/max, three real-audio observed durations and outcomes, test commands/results, and explicit statements that phase one does not establish 95% production accuracy and that MiniMax is not used by the new endpoint. Do not include audio, raw HTTP bodies, access tokens, or user identity.

- [ ] **Step 7: Commit benchmarks and evidence**

Backend:

```powershell
git add scripts/benchmark-spoken-formula-resolution.ts package.json tests/unit/practiceFormulaResolutionBenchmark.test.ts
git commit -m "test(practice): benchmark local spoken formula resolution"
```

Frontend:

```powershell
git add test/features/practice_assessment/spoken_formula_resolution_end_to_end_test.dart docs/qa/spoken-formula-resolution-phase-one-report.md
git commit -m "test(practice): verify spoken formula resolution flow"
```

---

### Task 10: Run Full Verification and Prepare Branch Integration

**Files:**

- Verify all changed files in both isolated worktrees.
- Do not modify the dirty original backend checkout during verification.

- [ ] **Step 1: Invoke verification-before-completion and inspect diffs**

Run in each worktree:

```powershell
git status --short --branch
git diff --check
git log --oneline --decorate -10
```

Review for raw transcripts/LaTeX in logs, new cloud imports in V2, generic mathematical failure copy, 70-second formula timeout, unvalidated candidate insertion, and unrelated changes.

- [ ] **Step 2: Run the complete backend quality gates**

```powershell
npm test -- --run tests/unit/practiceFormulaResolutionContracts.test.ts tests/unit/practiceFormulaCandidateAudit.test.ts tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts tests/unit/practiceFormulaLocalParser.test.ts tests/unit/practiceFormulaLocalResolutionService.test.ts tests/unit/practiceSpokenFormulaResolutionRoute.test.ts tests/unit/practiceSpokenFormulaResolutionNextRoute.test.ts tests/unit/practiceFormulaResolutionBenchmark.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts tests/unit/practiceFormulaConfiguredConverter.test.ts
npm run typecheck
npm run lint
npm run build
npm run qa:spoken-formula-resolution
```

Expected: all pass. If repository-wide lint/build exposes a pre-existing unrelated failure, capture exact output and still prove every changed-file/focused gate passes.

- [ ] **Step 3: Run the complete frontend quality gates**

```powershell
flutter test test/features/practice_assessment
dart analyze lib/main.dart test
flutter build web --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=SPOKEN_FORMULA_ASR_MODE=sensevoiceLocal --dart-define=SENSEVOICE_BASE_URL=http://127.0.0.1:8000
```

Expected: all pass.

- [ ] **Step 4: Verify contract and privacy invariants with searches**

Backend:

```powershell
rg -n "configuredConverter|MiniMax|resolveSpokenFormulaModelCall|localModel" lib/practice-formula/localResolutionService.ts lib/practice-formula/resolutionHttp.ts app/api/practice/formulas/resolve-spoken-text/route.ts
rg -n "recognizedText|normalizedText|latex|ast|modelOutput" lib/practice-formula/localResolutionService.ts
```

Expected: first search has no matches. Review the second search manually: response construction is allowed; logger payloads must contain none of those fields.

Frontend:

```powershell
rg -n "70|from-spoken-text|换一种说法|公式转换失败" lib/features/practice_assessment test/features/practice_assessment
```

Expected: no production matches for the legacy timeout/path/generic math-failure copy. Test descriptions may mention forbidden copy only to assert it is absent.

- [ ] **Step 5: Request code review and resolve only evidence-backed findings**

Invoke `superpowers:requesting-code-review`. If review feedback arrives, invoke `superpowers:receiving-code-review` before changing code. Rerun the affected focused tests after each accepted fix, then rerun Steps 2–4.

- [ ] **Step 6: Use finishing-a-development-branch for integration choices**

Invoke `superpowers:finishing-a-development-branch`. Present frontend and backend commits separately. Do not merge/cherry-pick into the dirty backend checkout automatically. Integration into `feature/dialogue-exploration-1-2-backend` must wait until its owning worktree is clean or the user explicitly chooses a safe integration method. Likewise, integrate the frontend feature branch into its intended app branch only through the finishing workflow.

- [ ] **Step 7: Final handoff**

Report:

1. User-visible result and the exact test URL/configuration.
2. Frontend and backend commits/files.
3. Confirmation that V2 is local CPU ASR + local deterministic parser and makes zero MiniMax calls.
4. Test/build/benchmark evidence, including real measured P50/P95 and stop-to-actionable observations.
5. Privacy/data impact: no new database, no audio persistence, anonymous metrics only.
6. Known limitations: ten difficult cases are not a 95% production claim; broader 200-text/50-audio benchmarking, consented data, local small model and MathLex/MathCAT experiments remain later phases.
