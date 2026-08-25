# Local Spoken-Math Parser Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parse high-frequency Chinese high-school math speech locally into the existing Math AST and call MiniMax only when deterministic parsing cannot produce one safe, complete, unambiguous result.

**Architecture:** A longest-match normalizer converts controlled Chinese math phrases into typed tokens while retaining source spans. A complete-consumption recursive-descent parser builds the existing Math AST, reports ambiguity/unsupported reasons internally, and never emits raw LaTeX. `convertSpokenFormula` renders validated local AST first and reaches the existing MiniMax AST path only for non-local results; both paths share the same validation and deterministic LaTeX boundary.

**Tech Stack:** Next.js backend, TypeScript, Zod, Vitest, existing Math AST V1 and KaTeX safety guard, MiniMax M2.7 as low-confidence fallback.

**Spec:** `D:\dev\Uniprism\uniprism_app\docs\superpowers\specs\2026-08-25-local-sensevoice-spoken-formula-design.md`

## Global Constraints

- Read and follow `D:\dev\Uniprism\uniprism_app\docs\DEVELOPMENT_CODE_STANDARD.md` before code changes.
- Start from backend commit `aed6844` or its verified descendant on `feature/spoken-formula-math-ast-backend` and use an isolated worktree created through `superpowers:using-git-worktrees`.
- Target integration branch remains `feature/dialogue-exploration-1-2-backend` in the shared backend repository.
- Keep the public `POST /api/practice/formulas/from-spoken-text` request and response shape unchanged.
- Never let the local parser produce raw LaTeX; every result must pass existing Math AST limits, deterministic rendering, and final LaTeX safety validation.
- Local high confidence requires complete token consumption, one structure, no unknown fragment, and no heuristic repair.
- Send only low-confidence Chinese transcript text to MiniMax; never send audio, answer history, or unrelated user data.
- If MiniMax is unconfigured or unavailable, return a recoverable service error and preserve the transcript on the Flutter side; never guess a formula.
- Do not log the original transcript, generated AST, or full formula. Log only route, stable reason code, attempts, and latency.
- Do not add a local 1.7B language model in this plan.
- Frontend compatibility tests run after backend completion even when no Flutter production file changes.

---

## File Structure

Backend worktree rooted at `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend` or the new isolated execution worktree:

- `lib/practice-formula/spokenMathTokens.ts`: closed token and local-result types plus safe reason codes.
- `lib/practice-formula/spokenMathNormalizer.ts`: longest-match phrase scanner, Chinese number parsing, source-span retention, and complete unknown-fragment reporting.
- `lib/practice-formula/spokenMathParser.ts`: deterministic recursive-descent parser and special high-school structures.
- `lib/practice-formula/conversionCandidate.ts`: shared AST validation, deterministic rendering, candidate deduplication, and public conversion construction.
- `lib/practice-formula/converter.ts`: local-first orchestration and MiniMax fallback only.
- `tests/unit/practiceFormulaSpokenMathNormalizer.test.ts`: lexical and normalization contract.
- `tests/unit/practiceFormulaLocalParser.test.ts`: local AST/LaTeX golden cases, ambiguity, and rejection.
- `tests/unit/practiceSpokenFormula.test.ts`: route selection, privacy, error propagation, and existing MiniMax behavior.
- Existing route tests: public protocol compatibility.

No database, migration, persistence, or audio endpoint is introduced.

---

### Task 1: Closed token protocol and complete-consumption normalizer

**Files:**
- Create: `lib/practice-formula/spokenMathTokens.ts`
- Create: `lib/practice-formula/spokenMathNormalizer.ts`
- Create: `tests/unit/practiceFormulaSpokenMathNormalizer.test.ts`

**Interfaces:**
- Produces: `normalizeSpokenMath(text: string): NormalizedSpokenMath`.
- Produces: `parseChineseSpokenNumber(text: string): string | null`.
- Produces token union `SpokenMathToken` with source `start`/`end` offsets.
- Produces stable `LocalParseReason`: `empty | unknown_fragment | invalid_number | unsupported_scope | ambiguous_scope | trailing_tokens | invalid_structure`.

- [ ] **Step 1: Define the failing normalization table**

Create `practiceFormulaSpokenMathNormalizer.test.ts` with table-driven cases:

```ts
import { describe, expect, it } from 'vitest';
import { normalizeSpokenMath, parseChineseSpokenNumber } from '@/lib/practice-formula/spokenMathNormalizer';

describe('parseChineseSpokenNumber', () => {
  it.each([
    ['零', '0'], ['二', '2'], ['十', '10'], ['十二', '12'],
    ['二十', '20'], ['二十三', '23'], ['一百零二', '102'],
    ['三点一四', '3.14'], ['负三', '-3'],
  ])('normalizes %s', (spoken, expected) => {
    expect(parseChineseSpokenNumber(spoken)).toBe(expected);
  });
  it.each(['两百百', '一点点', '负', '十点'])('rejects %s', (spoken) => {
    expect(parseChineseSpokenNumber(spoken)).toBeNull();
  });
});

describe('normalizeSpokenMath', () => {
  it('uses longest phrases and preserves source spans', () => {
    const result = normalizeSpokenMath('x 的平方减三 x 加二');
    expect(result.unknownFragments).toEqual([]);
    expect(result.tokens.map(({ kind, value }) => ({ kind, value }))).toEqual([
      { kind: 'symbol', value: 'x' },
      { kind: 'postfixPower', value: '2' },
      { kind: 'binary', value: 'subtract' },
      { kind: 'number', value: '3' },
      { kind: 'symbol', value: 'x' },
      { kind: 'binary', value: 'add' },
      { kind: 'number', value: '2' },
    ]);
    expect(result.normalizedText).toBe('x的平方减3x加2');
  });

  it('does not silently drop an unknown phrase', () => {
    const result = normalizeSpokenMath('x 随便来一下 二');
    expect(result.unknownFragments).toEqual([
      expect.objectContaining({ text: '随便来一下' }),
    ]);
  });
});
```

- [ ] **Step 2: Run the normalizer test and verify RED**

Run:

```powershell
npm test -- --run tests/unit/practiceFormulaSpokenMathNormalizer.test.ts
```

Expected: FAIL because the modules do not exist.

- [ ] **Step 3: Define the closed token and result types**

Create `spokenMathTokens.ts` with exact types:

```ts
import type { MathAstNode, MathFunctionName, RelationOperator } from './mathAst';

type SourceSpan = { start: number; end: number };

export type SpokenMathToken = SourceSpan & (
  | { kind: 'number'; value: string }
  | { kind: 'symbol'; value: string }
  | { kind: 'constant'; value: 'pi' | 'e' | 'infinity' }
  | { kind: 'binary'; value: 'add' | 'subtract' | 'multiply' | 'divide' | 'power' }
  | { kind: 'relation'; value: RelationOperator }
  | { kind: 'conjunction'; value: 'and' }
  | { kind: 'function'; value: MathFunctionName }
  | { kind: 'postfixPower'; value: string }
  | { kind: 'root' }
  | { kind: 'subscript' }
  | { kind: 'leftParen' }
  | { kind: 'rightParen' }
  | { kind: 'comma' }
  | { kind: 'whole' }
  | { kind: 'from' }
  | { kind: 'to' }
  | { kind: 'intervalStyle'; value: 'open' | 'closed' | 'leftOpenRightClosed' | 'leftClosedRightOpen' }
  | { kind: 'setOpen' }
  | { kind: 'setClose' }
);

export type UnknownFragment = SourceSpan & { text: string };

export type NormalizedSpokenMath = {
  source: string;
  normalizedText: string;
  tokens: SpokenMathToken[];
  unknownFragments: UnknownFragment[];
};

export type LocalParseReason =
  | 'empty' | 'unknown_fragment' | 'invalid_number'
  | 'unsupported_scope' | 'ambiguous_scope'
  | 'trailing_tokens' | 'invalid_structure';

export type LocalSpokenMathParseResult =
  | { status: 'parsed'; normalizedText: string; primary: MathAstNode; alternatives: []; warnings: [] }
  | { status: 'ambiguous'; normalizedText: string; primary: MathAstNode; alternatives: MathAstNode[]; warnings: string[]; reason: 'ambiguous_scope' }
  | { status: 'unsupported'; normalizedText: string; reason: Exclude<LocalParseReason, 'ambiguous_scope'> };

export type LocalSpokenMathParser = (text: string) => LocalSpokenMathParseResult;
```

- [ ] **Step 4: Implement longest-match scanning with an explicit lexicon**

`spokenMathNormalizer.ts` scans left-to-right and chooses the longest matching phrase. The lexicon must contain these exact mappings:

| Spoken phrase | Token |
|---|---|
| `的二次方`, `的平方`, `平方` | `postfixPower(2)` |
| `的三次方`, `立方` | `postfixPower(3)` |
| `加上`, `加` | `binary(add)` |
| `减去`, `减` | `binary(subtract)` |
| `乘以`, `乘上`, `乘` | `binary(multiply)` |
| `整体除以`, `除以`, `除` | `whole? + binary(divide)` preserving whether `整体` appeared |
| `小于等于`, `不大于` | `relation(lte)` |
| `大于等于`, `不小于` | `relation(gte)` |
| `不等于` | `relation(neq)` |
| `等于`, `小于`, `大于`, `属于` | `eq`, `lt`, `gt`, `in` |
| `并且`, `且` | `conjunction(and)` |
| `正弦`, `余弦`, `正切`, `余切`, `自然对数`, `常用对数` | `sin`, `cos`, `tan`, `cot`, `ln`, `lg` |
| `根号下`, `平方根` | `root` |
| `下标` | `subscript` |
| `负` | unary-position `binary(subtract)` |
| `左括号`, `右括号` | explicit parentheses |
| `集合左括号`, `集合右括号` | `setOpen`, `setClose` |
| `从`, `到` | `from`, `to` |
| `开区间`, `闭区间`, `左开右闭区间`, `左闭右开区间` | matching `intervalStyle` |
| `圆周率`, `派`, `π` | `constant(pi)` |
| `无穷大`, `无穷` | `constant(infinity)` |
| `艾克斯`, `x`, `X` | `symbol(x)` |
| `歪`, `y`, `Y` | `symbol(y)` |

ASCII letters `a-z` become lowercase symbols. Arabic integers/finite decimals and valid Chinese spoken numbers become `number`. Whitespace and punctuation `，。！？、` are separators, not unknown fragments. The possessive particle `的` may be ignored only immediately before `平方`, `立方`, `次方`, `对数`, or a recognized structural phrase; elsewhere it becomes an unknown fragment.

Merge consecutive unknown characters into one `UnknownFragment`, preserving source offsets. Build `normalizedText` from recognized mathematical lexemes and normalized numeric values, not by copying unknown text.

- [ ] **Step 5: Run tests, add edge cases, and commit Task 1**

Add tests for longest-match `小于等于` versus `小于`, uppercase symbol lowering, punctuation, `π`, `艾克斯`, and source offsets. Run:

```powershell
npm test -- --run tests/unit/practiceFormulaSpokenMathNormalizer.test.ts
npm run typecheck
```

Expected: all normalizer tests pass and TypeScript exits 0.

Commit:

```powershell
git add lib/practice-formula/spokenMathTokens.ts lib/practice-formula/spokenMathNormalizer.ts tests/unit/practiceFormulaSpokenMathNormalizer.test.ts
git commit -m "feat(practice): normalize spoken math locally"
```

---

### Task 2: Complete-consumption arithmetic and relation parser

**Files:**
- Create: `lib/practice-formula/spokenMathParser.ts`
- Create: `tests/unit/practiceFormulaLocalParser.test.ts`

**Interfaces:**
- Consumes: `normalizeSpokenMath` and existing `MathAstNode` types.
- Produces: `parseSpokenMathLocally(text: string): LocalSpokenMathParseResult`.
- Produces internal parser methods `parseRelation`, `parseAdditive`, `parseMultiplicative`, `parsePower`, `parseUnary`, and `parsePrimary`.

- [ ] **Step 1: Write failing arithmetic and relation golden tests**

Create helper constructors `n`, `s`, and `binary` in the test and assert exact ASTs for:

```ts
it.each([
  ['x 的平方减三 x 加二', 'x^{2}-3x+2'],
  ['二 x 加一', '2x+1'],
  ['左括号 x 加一右括号乘 x 减一', String.raw`\left(x+1\right)\cdot x-1`],
  ['x 加一整体除以 x 减一', String.raw`\frac{x+1}{x-1}`],
  ['零小于 x 并且 x 小于等于一', String.raw`0<x\leq1`],
  ['负 x 加二', '-x+2'],
])('parses %s', (spoken, latex) => {
  const result = parseSpokenMathLocally(spoken);
  expect(result.status).toBe('parsed');
  if (result.status !== 'parsed') return;
  assertMathAstCandidateLimits([result.primary]);
  expect(renderMathAstToLatex(result.primary)).toBe(latex);
});
```

Also reject incomplete expressions `x 加`, mismatched parentheses, unknown fragments, two adjacent operators, and any trailing token.

- [ ] **Step 2: Run parser tests and verify RED**

Run: `npm test -- --run tests/unit/practiceFormulaLocalParser.test.ts`

Expected: FAIL because `spokenMathParser.ts` does not exist.

- [ ] **Step 3: Implement recursive-descent precedence**

Use this grammar exactly:

```text
relation       := additive (relationOp additive)+ | additive
additive       := multiplicative ((add | subtract) multiplicative)*
multiplicative := power ((multiply | divide) power | implicitProduct power)*
power          := unary ((power unary) | postfixPower)*
unary          := (add | subtract) unary | primary
primary        := number | symbol | constant | leftParen relation rightParen
```

Rules:

- implicit product is allowed only for `number→symbol`, `number→function`, `number→leftParen`, `symbol→symbol`, or `rightParen→symbol`; other adjacency is unsupported;
- exponentiation is right-associative;
- postfix power is converted to a `binary(power, base, number)` node;
- a relation chain becomes `relationChain` with `operands.length === operators.length + 1`;
- the spoken conjunction `并且` is accepted only between two adjacent comparisons sharing the middle operand, such as `0<x 并且 x<=1`; it is normalized into one relation chain and rejected for unrelated operands;
- `整体除以` is handled before generic precedence by splitting at the single top-level marker, parsing the complete left and right substrings independently, and producing `binary(divide)`;
- parsing succeeds only when the cursor reaches the final token and `unknownFragments` is empty.

Do not perform algebraic simplification. Preserve `x+x` as addition and explicit parentheses as a `group` node.

- [ ] **Step 4: Detect the negative-power scope ambiguity**

For the exact structural pattern `negative number + postfixPower`, including `负二的平方`, return:

```ts
{
  status: 'ambiguous',
  normalizedText: '负2的平方',
  primary: power(group(negate(number('2'))), number('2')),
  alternatives: [negate(power(number('2'), number('2')))],
  warnings: ['负号是否属于平方底数存在歧义，请确认。'],
  reason: 'ambiguous_scope',
}
```

Explicit `左括号负二右括号的平方` is parsed locally without ambiguity. The parser must not choose either meaning silently.

- [ ] **Step 5: Run arithmetic tests and commit Task 2**

Run:

```powershell
npm test -- --run tests/unit/practiceFormulaSpokenMathNormalizer.test.ts tests/unit/practiceFormulaLocalParser.test.ts
npm run typecheck
```

Expected: all tests pass; TypeScript exits 0.

Commit:

```powershell
git add lib/practice-formula/spokenMathParser.ts tests/unit/practiceFormulaLocalParser.test.ts
git commit -m "feat(practice): parse spoken arithmetic locally"
```

---

### Task 3: Roots, functions, logarithms, subscripts, intervals, and finite sets

**Files:**
- Modify: `lib/practice-formula/spokenMathNormalizer.ts`
- Modify: `lib/practice-formula/spokenMathParser.ts`
- Modify: `tests/unit/practiceFormulaSpokenMathNormalizer.test.ts`
- Modify: `tests/unit/practiceFormulaLocalParser.test.ts`

**Interfaces:**
- Extends only the closed token union already defined; no raw-text AST node is introduced.
- Preserves `parseSpokenMathLocally` signature and complete-consumption requirement.

- [ ] **Step 1: Add failing high-school structure cases**

Add golden tests:

```ts
it.each([
  ['根号下 x 加一', String.raw`\sqrt{x+1}`],
  ['正弦 x 加余弦 x', String.raw`\sin\left(x\right)+\cos\left(x\right)`],
  ['自然对数 x', String.raw`\ln\left(x\right)`],
  ['以二为底 x 的对数', String.raw`\log_{2}\left(x\right)`],
  ['x 下标一加 x 下标二', 'x_{1}+x_{2}'],
  ['x 属于从零到一的闭区间', String.raw`x\in\left[0,1\right]`],
  ['x 属于从零到一的左开右闭区间', String.raw`x\in\left(0,1\right]`],
  ['集合左括号一逗号二逗号三集合右括号', String.raw`\left\{1,2,3\right\}`],
])('parses advanced phrase %s', (spoken, latex) => {
  const result = parseSpokenMathLocally(spoken);
  expect(result.status).toBe('parsed');
  if (result.status === 'parsed') {
    expect(renderMathAstToLatex(result.primary)).toBe(latex);
  }
});
```

Add rejection tests for root with an empty radicand, log without base/argument, more than 12 set items, interval without both endpoints, and unsupported `根号下 x 加一然后再加二` scope wording.

- [ ] **Step 2: Run advanced cases and verify RED**

Run: `npm test -- --run tests/unit/practiceFormulaLocalParser.test.ts`

Expected: the new advanced cases fail.

- [ ] **Step 3: Implement special structures before generic expression parsing**

Apply these deterministic patterns in order:

1. `以 <complete expression> 为底 <complete expression> 的对数` → `function(log, base, args)`;
2. `从 <expression> 到 <expression> 的 <interval style> 区间` → `interval`;
3. `集合左括号 <comma-separated expressions> 集合右括号` → `set` with at most 12 items;
4. a leading `根号下` consumes the entire remaining complete expression as `root.radicand`;
5. prefix functions consume one primary/power expression unless explicit parentheses define a larger argument;
6. `subscript` binds tighter than postfix power and consumes exactly one number or symbol.

The special-pattern parser must return `unsupported_scope` when a scope boundary cannot be proven. It may not drop words such as `然后`, `里面`, or `那个` to force a parse.

- [ ] **Step 4: Prove all local ASTs satisfy existing safety limits**

For every parsed golden case, call both:

```ts
assertMathAstCandidateLimits([result.primary]);
assertSafeFormulaLatex(renderMathAstToLatex(result.primary));
```

Add a generated 13-item set and a 17-level parenthesis/root nesting case; both must return `unsupported` before rendering.

- [ ] **Step 5: Run tests and commit Task 3**

Run:

```powershell
npm test -- --run tests/unit/practiceFormulaSpokenMathNormalizer.test.ts tests/unit/practiceFormulaLocalParser.test.ts tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts
npm run typecheck
```

Expected: all named tests pass.

Commit:

```powershell
git add lib/practice-formula/spokenMathNormalizer.ts lib/practice-formula/spokenMathParser.ts tests/unit/practiceFormulaSpokenMathNormalizer.test.ts tests/unit/practiceFormulaLocalParser.test.ts
git commit -m "feat(practice): cover common spoken math structures"
```

---

### Task 4: Shared conversion candidate boundary

**Files:**
- Create: `lib/practice-formula/conversionCandidate.ts`
- Modify: `lib/practice-formula/converter.ts`
- Modify: `tests/unit/practiceSpokenFormula.test.ts`

**Interfaces:**
- Produces: `buildSpokenFormulaConversion(input: { recognizedText: string; normalizedText: string; status: 'ok' | 'ambiguous'; primary: MathAstNode; alternatives: MathAstNode[]; warnings: string[] }): SpokenFormulaConversion`.
- Consumes: existing AST limits, renderer, and LaTeX guard.
- Keeps: MiniMax repair behavior and public conversion contract.

- [ ] **Step 1: Write failing shared-boundary tests**

Add tests proving both local and model candidates:

- reject an AST over depth/node limits;
- reject unsafe/unrenderable candidates;
- deduplicate rendered candidates while preserving order;
- require at least two distinct rendered candidates for `ambiguous`;
- return no more than two alternatives;
- preserve `recognizedText` and safe `normalizedText`.

Use this direct happy-path assertion:

```ts
expect(buildSpokenFormulaConversion({
  recognizedText: 'x 的平方',
  normalizedText: 'x的平方',
  status: 'ok',
  primary: { type: 'binary', op: 'power', left: symbol('x'), right: number('2') },
  alternatives: [],
  warnings: [],
})).toEqual({
  recognizedText: 'x 的平方',
  normalizedText: 'x的平方',
  latex: 'x^{2}',
  alternatives: [],
  warnings: [],
});
```

- [ ] **Step 2: Run focused tests and verify RED**

Run: `npm test -- --run tests/unit/practiceSpokenFormula.test.ts`

Expected: FAIL because `conversionCandidate.ts` does not exist and converter still owns rendering.

- [ ] **Step 3: Extract the single candidate-to-public boundary**

Move the current sequence from `converter.ts` into `buildSpokenFormulaConversion`:

```ts
assertMathAstCandidateLimits([input.primary, ...input.alternatives]);
const rendered = [input.primary, ...input.alternatives]
  .map(renderMathAstToLatex)
  .map(assertSafeFormulaLatex);
const uniqueRendered = [...new Set(rendered)];
if (input.status === 'ambiguous' && uniqueRendered.length < 2) {
  throw new CandidateValidationError('歧义结果缺少不同候选。');
}
return {
  recognizedText: input.recognizedText,
  normalizedText: input.normalizedText,
  latex: uniqueRendered[0],
  alternatives: uniqueRendered.slice(1, 3),
  warnings: input.warnings,
};
```

Export a typed `CandidateValidationError` from the new module so the MiniMax repair loop can still distinguish candidate-contract failures from upstream availability failures. Do not broaden repair to `ApiError` or arbitrary exceptions.

- [ ] **Step 4: Re-run all existing model AST tests**

Run:

```powershell
npm test -- --run tests/unit/practiceSpokenFormula.test.ts tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts
npm run typecheck
```

Expected: all existing MiniMax, repair, security, ambiguity, and derivative tests remain green.

- [ ] **Step 5: Commit Task 4**

```powershell
git add lib/practice-formula/conversionCandidate.ts lib/practice-formula/converter.ts tests/unit/practiceSpokenFormula.test.ts
git commit -m "refactor(practice): share formula candidate validation"
```

---

### Task 5: Local-first router and MiniMax text-only fallback

**Files:**
- Modify: `lib/practice-formula/converter.ts`
- Modify: `tests/unit/practiceSpokenFormula.test.ts`
- Modify: `tests/unit/practiceSpokenFormulaRoute.test.ts`
- Modify: `tests/unit/practiceSpokenFormulaNextRoute.test.ts`

**Interfaces:**
- Extends `ConvertOptions` with `localParser?: LocalSpokenMathParser`.
- Defaults `localParser` to `parseSpokenMathLocally` in production.
- Calls `callModel` only after local result `unsupported` or `ambiguous`.

- [ ] **Step 1: Write failing route-selection tests**

Add these exact cases:

```ts
it('returns a high-confidence local formula without calling MiniMax', async () => {
  let modelCalls = 0;
  const result = await convertSpokenFormula(
    { text: 'x 的平方减三 x 加二', locale: 'zh-CN' },
    { callModel: async () => { modelCalls += 1; throw new Error('must not call'); } },
  );
  expect(result.latex).toBe('x^{2}-3x+2');
  expect(modelCalls).toBe(0);
});

it('sends only the transcript to MiniMax after local unsupported', async () => {
  const requests: Array<{ text: string; system: string }> = [];
  await convertSpokenFormula(
    { text: '从 k 等于一加到 n 的 k 平方', locale: 'zh-CN' },
    {
      localParser: () => ({
        status: 'unsupported', normalizedText: '从k等于1加到n的k平方', reason: 'unsupported_scope',
      }),
      callModel: async ({ text, system }) => {
        requests.push({ text, system });
        return astReply();
      },
    },
  );
  expect(requests).toHaveLength(1);
  expect(requests[0].text).toBe('从 k 等于一加到 n 的 k 平方');
  expect(JSON.stringify(requests[0])).not.toContain('audio');
});
```

Also test local ambiguity falls back, local invalid AST is treated as a local miss rather than returned, MiniMax unconfigured preserves `SERVICE_UNAVAILABLE`, and a local hit succeeds when `LEARNING_AI_PROVIDER` and all MiniMax keys are absent.

- [ ] **Step 2: Run route tests and verify RED**

Run:

```powershell
npm test -- --run tests/unit/practiceSpokenFormula.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts
```

Expected: local-first assertions fail because every valid request currently calls MiniMax.

- [ ] **Step 3: Implement local-first orchestration**

Immediately after input validation:

```ts
const localStartedAt = performance.now();
const local = (options.localParser ?? parseSpokenMathLocally)(parsedInput.data.text);
if (local.status === 'parsed') {
  try {
    const conversion = buildSpokenFormulaConversion({
      recognizedText: parsedInput.data.text,
      normalizedText: local.normalizedText,
      status: 'ok',
      primary: local.primary,
      alternatives: [],
      warnings: [],
    });
    logger.info('practice.spoken-formula.route', {
      route: 'local',
      latencyMs: Math.round(performance.now() - localStartedAt),
    });
    return conversion;
  } catch {
    logger.warn('practice.spoken-formula.local-rejected', {
      reason: 'invalid_structure',
    });
  }
}

logger.info('practice.spoken-formula.route', {
  route: 'minimax',
  reason: local.status === 'parsed' ? 'invalid_structure' : local.reason,
});
```

Then execute the unchanged two-attempt MiniMax AST loop. The log object may not include `text`, `normalizedText`, AST, rendered LaTeX, or model content.

For existing tests whose purpose is specifically MiniMax repair/contract behavior, inject a shared `forceModelRoute` parser returning `unsupported`. This keeps each test explicit instead of relying on an expression that happens not to be locally supported.

- [ ] **Step 4: Prove public route compatibility and no-cloud local operation**

In both route test files, issue an authenticated/local test request for `x 的平方减三 x 加二` with MiniMax environment variables removed. Assert HTTP 200 and the unchanged response:

```json
{
  "ok": true,
  "data": {
    "recognizedText": "x 的平方减三 x 加二",
    "normalizedText": "x的平方减3x加2",
    "latex": "x^{2}-3x+2",
    "alternatives": [],
    "warnings": []
  }
}
```

For an unsupported phrase with no MiniMax configuration, assert the established 503 envelope; do not return a fabricated formula or raw local parser reason to the client.

- [ ] **Step 5: Run tests and commit Task 5**

Run:

```powershell
npm test -- --run tests/unit/practiceFormulaSpokenMathNormalizer.test.ts tests/unit/practiceFormulaLocalParser.test.ts tests/unit/practiceSpokenFormula.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts
npm run typecheck
npm run lint
```

Expected: all named tests, typecheck, and lint pass. If full lint has unrelated pre-existing failures, capture exact files and run ESLint on only changed practice-formula files; do not report full lint as passing.

Commit:

```powershell
git add lib/practice-formula/converter.ts tests/unit/practiceSpokenFormula.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts
git commit -m "feat(practice): route spoken formulas local first"
```

---

### Task 6: Versioned local parser acceptance corpus and final integration

**Files:**
- Create: `tests/fixtures/practice-spoken-formula-local-v1.json`
- Create: `tests/unit/practiceFormulaLocalAcceptance.test.ts`
- Create: `docs/operations/SPOKEN_FORMULA_LOCAL_PARSER_ACCEPTANCE.md`
- Verify frontend files without production edits.

**Interfaces:**
- Produces: versioned JSON cases with `id`, `spoken`, `expectedRoute`, `expectedLatex`, and optional `expectedAlternatives`.
- Produces: reproducible local coverage and exact-match report.

- [ ] **Step 1: Add the 30-case acceptance corpus**

The fixture must contain exactly 30 cases grouped as:

- 8 arithmetic/polynomial cases;
- 4 fraction/root cases;
- 5 relation/interval cases;
- 5 function/log cases;
- 4 subscript/set cases;
- 4 ambiguity/unsupported cases.

Include the ten phrases from the local SenseVoice Web plan. Mark `负二的平方` as `minimax`, not `local`, because local ambiguity is low confidence. Mark summation, derivative-at-point, piecewise, and conversational wording as `minimax` for V1 unless they are explicitly implemented and proven by Task 3 tests.

- [ ] **Step 2: Write the failing corpus runner**

The test loads JSON and for each case:

- calls `parseSpokenMathLocally`;
- asserts `parsed` only for `expectedRoute=local`;
- validates/renders the AST and compares exact LaTeX;
- asserts non-local cases never return `parsed`;
- calculates local route count and requires at least 20 of 30 cases while keeping all expected local exact matches correct.

No network or MiniMax key is used in this test.

- [ ] **Step 3: Run the corpus and fix only explicit grammar gaps**

Run:

```powershell
npm test -- --run tests/unit/practiceFormulaLocalAcceptance.test.ts
```

Expected first run: FAIL for any corpus wording not yet represented in the lexicon. Add only explicit synonyms supported by a new table row and unit test; do not add generic filler dropping or fuzzy string correction.

Re-run until the 30-case expected routes and exact LaTeX all pass.

- [ ] **Step 4: Run complete backend and frontend compatibility gates**

Backend:

```powershell
npm test -- --run tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts tests/unit/practiceFormulaSpokenMathNormalizer.test.ts tests/unit/practiceFormulaLocalParser.test.ts tests/unit/practiceFormulaLocalAcceptance.test.ts tests/unit/practiceSpokenFormula.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts
npm run typecheck
npm run lint
```

Frontend from `D:\dev\Uniprism\uniprism_app`:

```powershell
flutter test test/features/practice_assessment/spoken_formula_repository_test.dart test/features/practice_assessment/speech_formula_controller_test.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart test/features/practice_assessment/practice_spoken_formula_composition_test.dart test/features/practice_assessment/math_answer_field_test.dart
```

Expected: all selected backend and Flutter tests pass.

- [ ] **Step 5: Write the acceptance report**

`SPOKEN_FORMULA_LOCAL_PARSER_ACCEPTANCE.md` records:

- commit and fixture version;
- exact local coverage count out of 30;
- local exact-match count and percentage;
- cases deliberately routed to MiniMax and their stable reason codes;
- confirmation that no audio or transcript content appears in application logs;
- known unsupported structures;
- the next data threshold for considering a local Math AST model.

- [ ] **Step 6: Commit corpus/report and verify branch history**

Commit:

```powershell
git add tests/fixtures/practice-spoken-formula-local-v1.json tests/unit/practiceFormulaLocalAcceptance.test.ts docs/operations/SPOKEN_FORMULA_LOCAL_PARSER_ACCEPTANCE.md
git commit -m "test(practice): benchmark local spoken math coverage"
```

Verify:

```powershell
git status --short
git diff --check aed6844..HEAD
git log --oneline aed6844..HEAD
```

Expected: isolated backend worktree clean and only the named parser, converter, test, and documentation files changed.

- [ ] **Step 7: Integrate into the requested backend branch**

In the shared backend checkout, first verify none of the changed paths are dirty. Fast-forward or merge the completed implementation branch into `feature/dialogue-exploration-1-2-backend` without staging unrelated work. Re-run the focused backend tests and typecheck from the actual target branch before reporting completion.

The phase is complete only when high-confidence corpus cases succeed with all MiniMax environment variables removed and unsupported cases visibly fall back or return the safe recoverable service error.
