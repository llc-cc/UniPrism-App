# Spoken Formula Math AST Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace model-authored LaTeX in the high-school spoken-formula flow with a versioned, validated Math AST that the backend deterministically renders to safe LaTeX without changing the Flutter API contract.

**Architecture:** Browser `speech_to_text` continues to produce the final Chinese transcript. MiniMax M2.7 returns `astVersion: 1` and one to three controlled AST candidates; the backend validates shape and complexity, renders each AST through a pure TypeScript serializer, then runs the existing LaTeX/KaTeX guard before returning the unchanged public response. Implementation work happens in an isolated backend worktree and is fast-forwarded into `feature/dialogue-exploration-1-2-backend` only after all checks pass.

**Tech Stack:** Next.js 16, TypeScript, Zod 4, KaTeX, Vitest, Flutter/Dart, `speech_to_text`, `flutter_math_fork`

**Spec:** `docs/superpowers/specs/2026-08-25-spoken-formula-math-ast-design.md`

## Global Constraints

- Backend repository: `D:\ywkeji\Uniprism\UniPrism_New-main`; integration branch: `feature/dialogue-exploration-1-2-backend`.
- Backend isolated worktree: `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend`; implementation branch: `feature/spoken-formula-math-ast-backend` based on commit `95cd685`.
- Frontend repository: `D:\dev\Uniprism\uniprism_app`; no production Flutter file changes are planned in this feature.
- Keep `POST /api/practice/formulas/from-spoken-text` request and response fields unchanged.
- Keep browser `speech_to_text`; do not add audio upload, server ASR, handwriting, image recognition, model training, database tables, or persisted transcripts.
- Model output must not contain raw LaTeX or a generic raw/text escape node.
- Use strict Zod objects, maximum AST depth 16, maximum 128 nodes per candidate, maximum 256 nodes across candidates, and maximum two alternatives.
- All final formula candidates must pass `assertSafeFormulaLatex`; never fall back to accepting model-authored LaTeX.
- Preserve unrelated dirty files in both repositories; stage and commit only the exact files named by each task.
- Add concise Chinese comments for exported modules, recursive validation, async repair decisions, and security boundaries; do not comment obvious assignments.

---

### Task 1: Versioned Math AST schema and complexity auditor

**Files:**
- Create: `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend\lib\practice-formula\mathAst.ts`
- Create: `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend\tests\unit\practiceFormulaMathAst.test.ts`

**Interfaces:**
- Produces: `MathAstNode`, `mathAstNodeSchema`, `parseMathAstNode(input: unknown): MathAstNode`, `assertMathAstCandidateLimits(candidates: readonly MathAstNode[]): void`.
- Consumed by: Task 2 renderer and Task 3 MiniMax output contract/converter.

- [ ] **Step 1: Create the isolated backend worktree**

Invoke `superpowers:using-git-worktrees`, verify that the target directory is absent or safe, then create the implementation branch from the known clean feature commit:

```powershell
git -C D:\ywkeji\Uniprism\UniPrism_New-main worktree add -b feature/spoken-formula-math-ast-backend D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend 95cd685
```

Verify:

```powershell
git -C D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend status --short --branch
```

Expected: branch `feature/spoken-formula-math-ast-backend` with no working-tree changes.

- [ ] **Step 2: Write failing AST schema and boundary tests**

Create `tests/unit/practiceFormulaMathAst.test.ts` with real schema parsing and limit checks. The test must name the production behavior that would make it fail: removing strict parsing, depth counting, candidate counting, or semantic checks.

```ts
import { describe, expect, it } from 'vitest';
import {
  assertMathAstCandidateLimits,
  parseMathAstNode,
  type MathAstNode,
} from '@/lib/practice-formula/mathAst';

const symbol = (name: string): MathAstNode => ({ type: 'symbol', name });
const number = (value: string): MathAstNode => ({ type: 'number', value });

describe('Math AST V1', () => {
  it('accepts nested high-school algebra without a raw LaTeX escape', () => {
    const node = parseMathAstNode({
      type: 'binary',
      op: 'power',
      left: symbol('x'),
      right: number('2'),
    });
    expect(node).toEqual({
      type: 'binary',
      op: 'power',
      left: symbol('x'),
      right: number('2'),
    });
  });

  it.each([
    { type: 'raw', latex: String.raw`\\href{x}{y}` },
    { type: 'symbol', name: String.raw`\\alpha` },
    { type: 'number', value: 'NaN' },
    { type: 'binary', op: 'execute', left: number('1'), right: number('2') },
    { type: 'number', value: '1', extra: '<script>' },
  ])('rejects unknown or unsafe node data: %o', (input) => {
    expect(() => parseMathAstNode(input)).toThrow();
  });

  it('rejects a candidate deeper than 16 nodes', () => {
    let node: MathAstNode = number('1');
    for (let index = 0; index < 17; index += 1) {
      node = { type: 'unary', op: 'negate', operand: node };
    }
    expect(() => assertMathAstCandidateLimits([node])).toThrow(/深度/);
  });

  it('rejects more than 256 nodes across all candidates', () => {
    const items = Array.from({ length: 127 }, () => number('1'));
    const candidate: MathAstNode = { type: 'set', items };
    expect(() => assertMathAstCandidateLimits([
      candidate,
      candidate,
      number('1'),
    ])).toThrow(/总节点数/);
  });

  it('requires relation-chain operators to match adjacent operands', () => {
    const node = parseMathAstNode({
      type: 'relationChain',
      operands: [number('0'), symbol('x'), number('1')],
      operators: ['lt'],
    });
    expect(() => assertMathAstCandidateLimits([node])).toThrow(/连续关系/);
  });

  it('allows a log base only for the log function', () => {
    const node = parseMathAstNode({
      type: 'function',
      name: 'sin',
      args: [symbol('x')],
      base: number('2'),
    });
    expect(() => assertMathAstCandidateLimits([node])).toThrow(/对数底数/);
  });
});
```

Append this table-driven acceptance test so every V1 node is represented by real input:

```ts
const acceptedFixtures: Array<{ label: string; node: MathAstNode }> = [
  { label: 'constant', node: { type: 'constant', name: 'real' } },
  { label: 'root', node: { type: 'root', radicand: number('2') } },
  { label: 'function', node: { type: 'function', name: 'sin', args: [symbol('x')] } },
  { label: 'call', node: { type: 'call', callee: 'f', args: [symbol('x')] } },
  { label: 'subscript', node: { type: 'subscript', base: symbol('a'), subscript: symbol('n') } },
  { label: 'relation', node: { type: 'relation', op: 'eq', left: symbol('x'), right: number('1') } },
  { label: 'relationChain', node: { type: 'relationChain', operands: [number('0'), symbol('x'), number('1')], operators: ['lt', 'lte'] } },
  { label: 'group', node: { type: 'group', style: 'parentheses', body: symbol('x') } },
  { label: 'tuple', node: { type: 'tuple', items: [number('1'), number('2')] } },
  { label: 'set', node: { type: 'set', items: [number('1'), number('2')] } },
  { label: 'setBuilder', node: { type: 'setBuilder', variable: symbol('x'), condition: { type: 'relation', op: 'gt', left: symbol('x'), right: number('0') } } },
  { label: 'interval', node: { type: 'interval', left: number('0'), right: number('1'), leftClosed: false, rightClosed: true } },
  { label: 'conditional', node: { type: 'conditional', left: symbol('A'), right: symbol('B') } },
  { label: 'decoration', node: { type: 'decoration', kind: 'angle', body: symbol('A') } },
  { label: 'combinatoric', node: { type: 'combinatoric', kind: 'combination', n: symbol('n'), k: symbol('k') } },
  { label: 'piecewise', node: { type: 'piecewise', cases: [{ expression: symbol('x'), condition: { type: 'relation', op: 'gte', left: symbol('x'), right: number('0') } }], otherwise: { type: 'unary', op: 'negate', operand: symbol('x') } } },
  { label: 'sum', node: { type: 'binder', kind: 'sum', body: symbol('k'), variable: symbol('k'), lower: number('1'), upper: symbol('n') } },
  { label: 'limit', node: { type: 'binder', kind: 'limit', body: { type: 'call', callee: 'f', args: [symbol('x')] }, variable: symbol('x'), target: number('0') } },
  { label: 'derivative', node: { type: 'derivative', expression: { type: 'call', callee: 'f', args: [symbol('x')] }, variable: symbol('x') } },
];

it.each(acceptedFixtures)('accepts $label', ({ node }) => {
  const parsed = parseMathAstNode(node);
  expect(parsed).toEqual(node);
  expect(() => assertMathAstCandidateLimits([parsed])).not.toThrow();
});
```

- [ ] **Step 3: Run the focused test and verify RED**

```powershell
npm test -- --run tests/unit/practiceFormulaMathAst.test.ts
```

Expected: FAIL because `@/lib/practice-formula/mathAst` does not exist. A syntax/import error in the test itself is not an acceptable RED state.

- [ ] **Step 4: Implement the strict recursive schema and auditor**

Create `lib/practice-formula/mathAst.ts`. Define a discriminated TypeScript union with no index signatures, and make every Zod object `.strict()`. The public surface must match:

```ts
export type MathConstantName =
  | 'pi' | 'e' | 'infinity' | 'emptySet'
  | 'natural' | 'integer' | 'rational' | 'real' | 'complex';
export type UnaryOperator =
  | 'positive' | 'negate' | 'absolute' | 'factorial' | 'vector' | 'overline';
export type BinaryOperator =
  | 'add' | 'subtract' | 'multiply' | 'divide' | 'power';
export type RelationOperator =
  | 'eq' | 'neq' | 'lt' | 'lte' | 'gt' | 'gte'
  | 'approx' | 'equivalent' | 'proportional'
  | 'in' | 'notIn' | 'subset' | 'subsetEq' | 'superset' | 'supersetEq'
  | 'perpendicular' | 'parallel';
export type MathFunctionName =
  | 'sin' | 'cos' | 'tan' | 'cot'
  | 'arcsin' | 'arccos' | 'arctan'
  | 'ln' | 'log' | 'lg' | 'exp' | 'max' | 'min';
export type DecorationKind = 'angle' | 'triangle' | 'degree';
export type PiecewiseCase = {
  expression: MathAstNode;
  condition: MathAstNode;
};

export type MathAstNode =
  | { type: 'number'; value: string }
  | { type: 'symbol'; name: string }
  | { type: 'constant'; name: MathConstantName }
  | { type: 'unary'; op: UnaryOperator; operand: MathAstNode }
  | { type: 'binary'; op: BinaryOperator; left: MathAstNode; right: MathAstNode }
  | { type: 'root'; radicand: MathAstNode; degree?: MathAstNode }
  | { type: 'function'; name: MathFunctionName; args: MathAstNode[]; base?: MathAstNode }
  | { type: 'call'; callee: string; args: MathAstNode[] }
  | { type: 'subscript'; base: MathAstNode; subscript: MathAstNode }
  | { type: 'relation'; op: RelationOperator; left: MathAstNode; right: MathAstNode }
  | { type: 'relationChain'; operands: MathAstNode[]; operators: RelationOperator[] }
  | { type: 'group'; style: 'parentheses' | 'brackets' | 'braces'; body: MathAstNode }
  | { type: 'tuple'; items: MathAstNode[] }
  | { type: 'set'; items: MathAstNode[] }
  | { type: 'setBuilder'; variable: MathAstNode; condition: MathAstNode }
  | { type: 'interval'; left: MathAstNode; right: MathAstNode; leftClosed: boolean; rightClosed: boolean }
  | { type: 'conditional'; left: MathAstNode; right: MathAstNode }
  | { type: 'decoration'; kind: DecorationKind; body: MathAstNode }
  | { type: 'combinatoric'; kind: 'arrangement' | 'combination'; n: MathAstNode; k: MathAstNode }
  | { type: 'piecewise'; cases: PiecewiseCase[]; otherwise?: MathAstNode }
  | { type: 'binder'; kind: 'sum' | 'product' | 'limit'; body: MathAstNode; variable?: MathAstNode; lower?: MathAstNode; upper?: MathAstNode; target?: MathAstNode }
  | { type: 'derivative'; expression: MathAstNode; variable: MathAstNode; order?: number };

export const mathAstNodeSchema: z.ZodType<MathAstNode> = z.lazy(
  () => z.union([
    numberSchema,
    symbolSchema,
    constantSchema,
    unarySchema,
    binarySchema,
    rootSchema,
    functionSchema,
    callSchema,
    subscriptSchema,
    relationSchema,
    relationChainSchema,
    groupSchema,
    tupleSchema,
    setSchema,
    setBuilderSchema,
    intervalSchema,
    conditionalSchema,
    decorationSchema,
    combinatoricSchema,
    piecewiseSchema,
    binderSchema,
    derivativeSchema,
  ]),
);

export function parseMathAstNode(input: unknown): MathAstNode {
  return mathAstNodeSchema.parse(input);
}

export function assertMathAstCandidateLimits(
  candidates: readonly MathAstNode[],
): void;
```

Implementation rules:

- number regex: `^(?:0|[1-9]\d*)(?:\.\d+)?$`, maximum 40 characters;
- symbol regex: one ASCII letter or an enum of approved Greek names;
- `constant` enum: `pi`, `e`, `infinity`, `emptySet`, `natural`, `integer`, `rational`, `real`, `complex`;
- collection/function/call items: 1–12 except a finite `set`, which can be empty and has at most 128 items;
- piecewise cases: 1–8; derivative order: 1–5;
- `sum` and `product` require `variable`; `limit` requires `variable` and `target`;
- regular functions take exactly one argument except `max` and `min`, which take 1–12;
- `base` is legal only when `name === 'log'`;
- walk every child exactly once, rejecting depth greater than 16, an individual count greater than 128, or a total count greater than 256.

- [ ] **Step 5: Run focused tests and typecheck**

```powershell
npm test -- --run tests/unit/practiceFormulaMathAst.test.ts
npm run typecheck
```

Expected: all AST tests PASS and TypeScript exits 0.

- [ ] **Step 6: Commit Task 1**

```powershell
git add lib/practice-formula/mathAst.ts tests/unit/practiceFormulaMathAst.test.ts
git commit -m "feat(practice): validate spoken formula math ast"
```

Expected: commit contains exactly the new AST module and its focused test.

---

### Task 2: Deterministic Math AST to LaTeX renderer

**Files:**
- Create: `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend\lib\practice-formula\mathAstLatex.ts`
- Create: `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend\tests\unit\practiceFormulaMathAstLatex.test.ts`
- Modify only if a fixed renderer command is missing: `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend\lib\practice-formula\latexGuard.ts`

**Interfaces:**
- Consumes: validated `MathAstNode` from Task 1.
- Produces: `renderMathAstToLatex(node: MathAstNode): string`.
- Consumed by: Task 3 converter.

- [ ] **Step 1: Write failing renderer golden tests**

Create `tests/unit/practiceFormulaMathAstLatex.test.ts` with helpers `n(value)`, `s(name)`, and exact canonical outputs:

```ts
import { describe, expect, it } from 'vitest';
import { assertSafeFormulaLatex } from '@/lib/practice-formula/latexGuard';
import { renderMathAstToLatex } from '@/lib/practice-formula/mathAstLatex';
import type { MathAstNode } from '@/lib/practice-formula/mathAst';

const n = (value: string): MathAstNode => ({ type: 'number', value });
const s = (name: string): MathAstNode => ({ type: 'symbol', name });

describe('renderMathAstToLatex', () => {
  it('preserves arithmetic precedence and conventional coefficient notation', () => {
    const ast: MathAstNode = {
      type: 'binary', op: 'add',
      left: {
        type: 'binary', op: 'power', left: s('x'), right: n('2'),
      },
      right: {
        type: 'binary', op: 'multiply', left: n('2'), right: s('x'),
      },
    };
    expect(renderMathAstToLatex(ast)).toBe('x^{2}+2x');
  });

  it('adds parentheses when a composite base is raised to a power', () => {
    const ast: MathAstNode = {
      type: 'binary', op: 'power',
      left: { type: 'binary', op: 'add', left: s('x'), right: n('1') },
      right: n('2'),
    };
    expect(renderMathAstToLatex(ast)).toBe('\\left(x+1\\right)^{2}');
  });

  it('renders division as a structural fraction', () => {
    const ast: MathAstNode = {
      type: 'binary', op: 'divide',
      left: { type: 'root', radicand: { type: 'binary', op: 'add', left: s('x'), right: n('1') } },
      right: { type: 'binary', op: 'subtract', left: s('x'), right: n('1') },
    };
    expect(renderMathAstToLatex(ast)).toBe(
      String.raw`\frac{\sqrt{x+1}}{x-1}`,
    );
  });

  it('renders a relation chain without converting it to boolean prose', () => {
    expect(renderMathAstToLatex({
      type: 'relationChain',
      operands: [n('0'), s('x'), n('1')],
      operators: ['lt', 'lte'],
    })).toBe(String.raw`0<x\leq1`);
  });

  it('renders a piecewise function through the fixed cases environment', () => {
    const latex = renderMathAstToLatex({
      type: 'piecewise',
      cases: [{
        expression: { type: 'binary', op: 'power', left: s('x'), right: n('2') },
        condition: { type: 'relation', op: 'gte', left: s('x'), right: n('0') },
      }],
      otherwise: { type: 'unary', op: 'negate', operand: s('x') },
    });
    expect(latex).toBe(String.raw`\begin{cases}x^{2},&x\geq0\\-x,&\text{otherwise}\end{cases}`);
  });

  it('only emits LaTeX accepted by the final safety guard', () => {
    const fixtures: MathAstNode[] = [
      { type: 'constant', name: 'real' },
      { type: 'function', name: 'log', base: n('2'), args: [s('x')] },
      { type: 'combinatoric', kind: 'combination', n: s('n'), k: s('k') },
      { type: 'derivative', expression: { type: 'call', callee: 'f', args: [s('x')] }, variable: s('x') },
    ];
    for (const fixture of fixtures) {
      expect(() => assertSafeFormulaLatex(renderMathAstToLatex(fixture)))
        .not.toThrow();
    }
  });
});
```

Append the following table-driven golden cases for the remaining structures:

```ts
it.each<Array<{ node: MathAstNode; latex: string }>>([
  { node: { type: 'constant', name: 'pi' }, latex: String.raw`\pi` },
  { node: { type: 'constant', name: 'real' }, latex: String.raw`\mathbb{R}` },
  { node: { type: 'symbol', name: 'alpha' }, latex: String.raw`\alpha` },
  { node: { type: 'group', style: 'parentheses', body: s('x') }, latex: String.raw`\left(x\right)` },
  { node: { type: 'group', style: 'brackets', body: s('x') }, latex: String.raw`\left[x\right]` },
  { node: { type: 'group', style: 'braces', body: s('x') }, latex: String.raw`\left\{x\right\}` },
  { node: { type: 'tuple', items: [n('1'), n('2')] }, latex: String.raw`\left(1,2\right)` },
  { node: { type: 'set', items: [n('1'), n('2')] }, latex: String.raw`\left\{1,2\right\}` },
  { node: { type: 'setBuilder', variable: s('x'), condition: { type: 'relation', op: 'gt', left: s('x'), right: n('0') } }, latex: String.raw`\left\{x\mid x>0\right\}` },
  { node: { type: 'interval', left: n('0'), right: n('1'), leftClosed: false, rightClosed: true }, latex: String.raw`\left(0,1\right]` },
  { node: { type: 'conditional', left: s('A'), right: s('B') }, latex: String.raw`A\mid B` },
  { node: { type: 'decoration', kind: 'angle', body: s('A') }, latex: String.raw`\angle A` },
  { node: { type: 'decoration', kind: 'triangle', body: s('A') }, latex: String.raw`\triangle A` },
  { node: { type: 'decoration', kind: 'degree', body: n('30') }, latex: String.raw`30^{\circ}` },
  { node: { type: 'combinatoric', kind: 'arrangement', n: s('n'), k: s('k') }, latex: String.raw`A_{n}^{k}` },
  { node: { type: 'combinatoric', kind: 'combination', n: s('n'), k: s('k') }, latex: String.raw`C_{n}^{k}` },
  { node: { type: 'subscript', base: s('a'), subscript: s('n') }, latex: String.raw`a_{n}` },
  { node: { type: 'unary', op: 'factorial', operand: s('n') }, latex: 'n!' },
  { node: { type: 'unary', op: 'vector', operand: s('a') }, latex: String.raw`\vec{a}` },
  { node: { type: 'unary', op: 'overline', operand: s('A') }, latex: String.raw`\overline{A}` },
  { node: { type: 'binder', kind: 'sum', body: s('k'), variable: s('k'), lower: n('1'), upper: s('n') }, latex: String.raw`\sum_{k=1}^{n}k` },
  { node: { type: 'binder', kind: 'product', body: s('k'), variable: s('k'), lower: n('1'), upper: s('n') }, latex: String.raw`\prod_{k=1}^{n}k` },
  { node: { type: 'binder', kind: 'limit', body: { type: 'call', callee: 'f', args: [s('x')] }, variable: s('x'), target: n('0') }, latex: String.raw`\lim_{x\to0}f\left(x\right)` },
  { node: { type: 'derivative', expression: { type: 'call', callee: 'f', args: [s('x')] }, variable: s('x'), order: 2 }, latex: String.raw`\frac{d^{2}}{dx^{2}}f\left(x\right)` },
  { node: { type: 'binary', op: 'power', left: { type: 'group', style: 'parentheses', body: { type: 'unary', op: 'negate', operand: n('2') } }, right: n('2') }, latex: String.raw`\left(-2\right)^{2}` },
  { node: { type: 'unary', op: 'negate', operand: { type: 'binary', op: 'power', left: n('2'), right: n('2') } }, latex: String.raw`-2^{2}` },
])('renders $latex', ({ node, latex }) => {
  expect(renderMathAstToLatex(node)).toBe(latex);
});

const relationLatex = {
  eq: '=', neq: String.raw`\neq`, lt: '<', lte: String.raw`\leq`,
  gt: '>', gte: String.raw`\geq`, approx: String.raw`\approx`,
  equivalent: String.raw`\equiv`, proportional: String.raw`\propto`,
  in: String.raw`\in`, notIn: String.raw`\notin`, subset: String.raw`\subset`,
  subsetEq: String.raw`\subseteq`, superset: String.raw`\supset`,
  supersetEq: String.raw`\supseteq`, perpendicular: String.raw`\perp`,
  parallel: String.raw`\parallel`,
} as const;

it.each(Object.entries(relationLatex))('renders relation %s', (op, latex) => {
  expect(renderMathAstToLatex({
    type: 'relation', op: op as keyof typeof relationLatex,
    left: s('x'), right: s('y'),
  })).toBe(`x${latex}y`);
});

const functionLatex = {
  sin: String.raw`\sin\left(x\right)`, cos: String.raw`\cos\left(x\right)`,
  tan: String.raw`\tan\left(x\right)`, cot: String.raw`\cot\left(x\right)`,
  arcsin: String.raw`\arcsin\left(x\right)`, arccos: String.raw`\arccos\left(x\right)`,
  arctan: String.raw`\arctan\left(x\right)`, ln: String.raw`\ln\left(x\right)`,
  lg: String.raw`\lg\left(x\right)`, exp: String.raw`\exp\left(x\right)`,
  max: String.raw`\max\left(x\right)`, min: String.raw`\min\left(x\right)`,
} as const;

it.each(Object.entries(functionLatex))('renders function %s', (name, latex) => {
  expect(renderMathAstToLatex({
    type: 'function', name: name as keyof typeof functionLatex, args: [s('x')],
  })).toBe(latex);
});

it('renders logarithm base structurally', () => {
  expect(renderMathAstToLatex({
    type: 'function', name: 'log', base: n('2'), args: [s('x')],
  })).toBe(String.raw`\log_{2}\left(x\right)`);
});
```

- [ ] **Step 2: Run the renderer test and verify RED**

```powershell
npm test -- --run tests/unit/practiceFormulaMathAstLatex.test.ts
```

Expected: FAIL because `mathAstLatex.ts` does not exist.

- [ ] **Step 3: Implement precedence-aware deterministic rendering**

Create `lib/practice-formula/mathAstLatex.ts` with a private precedence enum and a recursive renderer that never accepts unknown strings as commands:

```ts
import type { MathAstNode } from './mathAst';

const enum Precedence {
  Relation = 1,
  Add = 2,
  Multiply = 3,
  Unary = 4,
  Power = 5,
  Atom = 6,
}

type RenderedNode = { latex: string; precedence: Precedence };

/** 将已审核 AST 稳定序列化为受控 LaTeX；不执行化简或模型调用。 */
export function renderMathAstToLatex(node: MathAstNode): string {
  return renderNode(node).latex;
}

function renderNode(node: MathAstNode): RenderedNode {
  switch (node.type) {
    case 'number':
      return { latex: node.value, precedence: Precedence.Atom };
    case 'constant':
      return { latex: constantLatex[node.name], precedence: Precedence.Atom };
    default: {
      const neverNode: never = node;
      throw new Error(`未实现的 Math AST 节点：${JSON.stringify(neverNode)}`);
    }
  }
}
```

Implement the switch using this complete canonical mapping; each row is one explicit case and the exhaustive default remains after them:

| Node | Canonical LaTeX | Precedence |
|---|---|---|
| `number` | validated `value` | Atom |
| `symbol` | ASCII letter or static Greek-command map | Atom |
| `constant` | static map for `pi/e/infinity/emptySet/natural/integer/rational/real/complex` | Atom |
| `unary.positive/negate` | sign plus child; wrap child only below Unary | Unary |
| `unary.absolute` | `\left|child\right|` | Atom |
| `unary.factorial` | `child!` | Unary |
| `unary.vector/overline` | fixed command with braced child | Atom |
| `binary.add/subtract` | `left+right` / `left-right`; subtraction wraps a right child at Add precedence | Add |
| `binary.multiply` | concatenate only safe coefficient/symbol pairs, otherwise `left\cdot right` | Multiply |
| `binary.divide` | `\frac{left}{right}` | Atom |
| `binary.power` | `base^{exponent}`; non-atom base gets `\left(...\right)` | Power |
| `root` | `\sqrt{radicand}` or `\sqrt[degree]{radicand}` | Atom |
| `function` | static command, optional log subscript, `\left(args\right)` | Atom |
| `call` | validated one-letter callee plus `\left(args\right)` | Atom |
| `subscript` | `base_{subscript}` | Power |
| `relation` | static relation map between children | Relation |
| `relationChain` | operands interleaved with the static relation map | Relation |
| `group` | fixed matching `\left`/`\right` delimiters | Atom |
| `tuple` | `\left(item,...\right)` | Atom |
| `set` | `\left\{item,...\right\}` | Atom |
| `setBuilder` | `\left\{variable\mid condition\right\}` | Atom |
| `interval` | delimiters derived only from `leftClosed/rightClosed` | Atom |
| `conditional` | `left\mid right` | Relation |
| `decoration.angle/triangle` | fixed command plus child | Atom |
| `decoration.degree` | `child^{\circ}` | Power |
| `combinatoric` | fixed `A` or `C` with `_{n}^{k}` | Atom |
| `piecewise` | fixed `cases` rows; optional else row uses literal `\text{otherwise}` | Atom |
| `binder.sum/product` | fixed command, structured lower `variable=lower`, upper, then body | Atom |
| `binder.limit` | `\lim_{variable\to target}` then body | Atom |
| `derivative` | first-order `\frac{d}{dvariable}` or matching higher-order superscripts | Atom |

Parenthesize only when child precedence would change meaning. Multiplication may omit `\cdot` only for unambiguous coefficient/symbol or adjacent symbol notation; all other products emit `\cdot`. Use only the static command/operator maps proven by the golden tests. No model-authored text reaches an environment or command name.

If a generated command is absent from `latexGuard.ts`, add only that named command to `allowedCommands` and prove it with the final guard fixture. Do not broaden the whitelist with a generic pattern.

- [ ] **Step 4: Run focused renderer and AST tests**

```powershell
npm test -- --run tests/unit/practiceFormulaMathAstLatex.test.ts tests/unit/practiceFormulaMathAst.test.ts
npm run typecheck
```

Expected: all focused tests PASS and TypeScript exits 0.

- [ ] **Step 5: Commit Task 2**

```powershell
git add lib/practice-formula/mathAstLatex.ts lib/practice-formula/latexGuard.ts tests/unit/practiceFormulaMathAstLatex.test.ts
git commit -m "feat(practice): render validated math ast to latex"
```

Before committing, omit `latexGuard.ts` from `git add` if it did not change.

---

### Task 3: MiniMax AST contract and converter integration

**Files:**
- Modify: `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend\lib\practice-formula\contracts.ts`
- Modify: `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend\lib\practice-formula\prompt.ts`
- Modify: `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend\lib\practice-formula\converter.ts`
- Modify: `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend\tests\unit\practiceSpokenFormula.test.ts`
- Verify unchanged: `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend\tests\unit\practiceSpokenFormulaRoute.test.ts`
- Verify unchanged: `D:\ywkeji\Uniprism\uniprism_worktrees\spoken-formula-math-ast-backend\tests\unit\practiceSpokenFormulaNextRoute.test.ts`

**Interfaces:**
- Consumes: `mathAstNodeSchema`, `assertMathAstCandidateLimits`, and `renderMathAstToLatex` from Tasks 1–2.
- Produces internally: strict `SpokenFormulaModelOutput` with `astVersion: 1`, `primary: MathAstNode | null`, and `alternatives: MathAstNode[]`.
- Preserves publicly: `SpokenFormulaConversion` with `recognizedText`, `normalizedText`, `latex`, `alternatives: string[]`, and `warnings`.

- [ ] **Step 1: Replace direct-LaTeX fixtures with failing AST fixtures**

Update `tests/unit/practiceSpokenFormula.test.ts` so the flexible wording test returns:

```ts
return JSON.stringify({
  astVersion: 1,
  status: 'ok',
  normalizedText: 'x的平方加2x加1',
  primary: {
    type: 'binary', op: 'add',
    left: {
      type: 'binary', op: 'add',
      left: { type: 'binary', op: 'power', left: { type: 'symbol', name: 'x' }, right: { type: 'number', value: '2' } },
      right: { type: 'binary', op: 'multiply', left: { type: 'number', value: '2' }, right: { type: 'symbol', name: 'x' } },
    },
    right: { type: 'number', value: '1' },
  },
  alternatives: [],
  warnings: [],
});
```

Assert the unchanged public result with canonical backend LaTeX:

```ts
expect(result).toEqual({
  recognizedText: '先把 x 自乘，再加上它的两倍，最后加一',
  normalizedText: 'x的平方加2x加1',
  latex: 'x^{2}+2x+1',
  alternatives: [],
  warnings: [],
});
expect(receivedSystem).toContain('"astVersion":1');
expect(receivedSystem).not.toContain('"latex"');
```

Rewrite every existing model fixture to use AST. Add these security/contract tests:

```ts
it('repairs one raw-LaTeX model response before accepting AST', async () => {
  const replies = [
    JSON.stringify({
      astVersion: 1,
      status: 'ok',
      normalizedText: '根号x',
      primary: { type: 'raw', latex: String.raw`\href{x}{y}` },
      alternatives: [],
      warnings: [],
    }),
    JSON.stringify({
      astVersion: 1,
      status: 'ok',
      normalizedText: '根号x',
      primary: { type: 'root', radicand: { type: 'symbol', name: 'x' } },
      alternatives: [],
      warnings: [],
    }),
  ];
  let calls = 0;
  const result = await convertSpokenFormula(
    { text: '开根号 x', locale: 'zh-CN' },
    { callModel: async () => replies[calls++] },
  );
  expect(result.latex).toBe(String.raw`\sqrt{x}`);
  expect(calls).toBe(2);
});

it('rejects an ambiguous response without a distinct rendered candidate', async () => {
  const repeated = { type: 'symbol', name: 'x' };
  await expect(convertSpokenFormula(
    { text: '一个有歧义的 x', locale: 'zh-CN' },
    { callModel: async () => JSON.stringify({
      astVersion: 1,
      status: 'ambiguous',
      normalizedText: 'x',
      primary: repeated,
      alternatives: [repeated],
      warnings: ['请确认。'],
    }) },
  )).rejects.toMatchObject({ code: 'LLM_INVALID_JSON' });
});
```

Retain the existing locale rejection and MiniMax availability propagation tests.

- [ ] **Step 2: Run converter tests and verify RED**

```powershell
npm test -- --run tests/unit/practiceSpokenFormula.test.ts
```

Expected: FAIL because the current contract still requires `latex` and strips/ignores AST candidates.

- [ ] **Step 3: Replace the internal model-output contract**

In `contracts.ts`, keep `spokenFormulaInputSchema` and the exported public `SpokenFormulaConversion` unchanged. Replace only `spokenFormulaModelOutputSchema`:

```ts
export const spokenFormulaModelOutputSchema = z.object({
  astVersion: z.literal(1),
  status: z.enum(['ok', 'ambiguous', 'unsupported']),
  normalizedText: z.string().trim().min(1).max(300),
  primary: mathAstNodeSchema.nullable(),
  alternatives: z.array(mathAstNodeSchema).max(2),
  warnings: z.array(z.string().trim().min(1).max(160)).max(3),
}).strict();

export type SpokenFormulaModelOutput = z.infer<
  typeof spokenFormulaModelOutputSchema
>;
```

Add a Chinese module comment explaining that the AST contract is internal and the Flutter response remains LaTeX for compatibility.

- [ ] **Step 4: Rewrite the MiniMax system and repair prompts for AST V1**

In `prompt.ts`, require a single strict JSON object with `astVersion: 1`, enumerate every node/operator/function from the spec, and include three complete examples:

1. flexible polynomial → nested `binary` AST;
2. “负二的平方” → distinct primary/alternative ASTs;
3. piecewise function → `piecewise` with structured conditions.

The prompt must state:

```text
不得输出 latex、raw、HTML、Markdown、URL、解释性前后缀或协议之外字段。
status=unsupported 时 primary 必须为 null 且 alternatives 必须为空。
status=ambiguous 时 alternatives 至少包含一个与 primary 结构语义不同的候选。
```

Keep `buildSpokenFormulaRepairPrompt(text, reason)` but change its last sentence to require Math AST V1 JSON rather than generic JSON.

- [ ] **Step 5: Integrate validation, rendering, deduplication, and one repair**

In `converter.ts`, replace `candidate.latex` handling with this sequence:

```ts
const candidate = parseCandidate(content);
assertModelStatusContract(candidate);
if (candidate.status === 'unsupported') {
  throw badRequest('暂时无法可靠理解这条高中数学表达，请换一种说法。');
}

const astCandidates = [candidate.primary!, ...candidate.alternatives];
assertMathAstCandidateLimits(astCandidates);
const rendered = astCandidates
  .map(renderMathAstToLatex)
  .map(assertSafeFormulaLatex);
const uniqueRendered = [...new Set(rendered)];
if (candidate.status === 'ambiguous' && uniqueRendered.length < 2) {
  throw new Error('歧义结果缺少不同候选');
}

return {
  recognizedText: parsedInput.data.text,
  normalizedText: candidate.normalizedText,
  latex: uniqueRendered[0],
  alternatives: uniqueRendered.slice(1, 3),
  warnings: candidate.warnings,
};
```

Implement `assertModelStatusContract` so `ok/ambiguous` require `primary`, `unsupported` requires `primary === null` and no alternatives, and `ambiguous` requires at least one alternative before rendering. Keep the current repair loop and its rule that only model-format/AST/render failures are repaired; `ApiError` values other than `LLM_INVALID_JSON` must continue to propagate immediately.

- [ ] **Step 6: Run converter and route regression tests**

```powershell
npm test -- --run tests/unit/practiceSpokenFormula.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts
npm run typecheck
```

Expected: all spoken-formula and route tests PASS; TypeScript exits 0; the route response shape remains unchanged.

- [ ] **Step 7: Commit Task 3**

```powershell
git add lib/practice-formula/contracts.ts lib/practice-formula/prompt.ts lib/practice-formula/converter.ts tests/unit/practiceSpokenFormula.test.ts
git commit -m "feat(practice): convert spoken math through ast"
```

Expected: route files and Flutter files are not part of this commit.

---

### Task 4: Full verification, real MiniMax smoke, and target-branch integration

**Files:**
- Verify backend worktree files from Tasks 1–3.
- Verify frontend tests without modifying production files.
- Integrate commits into `D:\ywkeji\Uniprism\UniPrism_New-main` branch `feature/dialogue-exploration-1-2-backend`.

**Interfaces:**
- Consumes: completed backend implementation branch and unchanged Flutter public contract.
- Produces: verified target backend branch plus a running local test page.

- [ ] **Step 1: Run complete backend quality gates in the isolated worktree**

```powershell
npm test -- --run tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts tests/unit/practiceSpokenFormula.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts
npm run typecheck
npm run lint
```

Expected: all named tests PASS, typecheck exits 0, and ESLint exits 0. If full lint reports an unrelated pre-existing failure, record the exact file and also run ESLint against only the changed backend files; do not describe the full lint as passing.

- [ ] **Step 2: Start the worktree backend on port 3001**

```powershell
npm run dev -- -p 3001
```

Expected: Next.js reports ready at `http://localhost:3001`. Use this separate port so the existing port-3000 developer session is not interrupted.

- [ ] **Step 3: Run real MiniMax acceptance requests**

For each transcript below, send UTF-8 JSON to `http://localhost:3001/api/practice/formulas/from-spoken-text` with `Origin: http://localhost:5175`:

```json
{"text":"先把 x 自乘，再加上它的两倍，最后加一","locale":"zh-CN"}
{"text":"负二的平方","locale":"zh-CN"}
{"text":"根号下 x 加一整体除以 x 减一","locale":"zh-CN"}
{"text":"零小于 x 并且 x 小于等于一","locale":"zh-CN"}
{"text":"f x 等于，当 x 大于等于零时是 x 平方，否则是负 x","locale":"zh-CN"}
{"text":"从 k 等于一加到 n 的 k 平方","locale":"zh-CN"}
{"text":"函数 x 的三次方在 x 等于二处的导数","locale":"zh-CN"}
```

For each response, verify HTTP 200 except a genuinely unsupported expression, `ok: true`, non-empty `latex`, no raw AST in the public response, at most two alternatives, and CORS origin `http://localhost:5175`. Specifically verify that “负二的平方” exposes two distinct candidates rather than hiding the scope ambiguity.

- [ ] **Step 4: Run Flutter compatibility regression tests**

From `D:\dev\Uniprism\uniprism_app`:

```powershell
flutter test test/features/practice_assessment/spoken_formula_repository_test.dart test/features/practice_assessment/speech_formula_controller_test.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart test/features/practice_assessment/practice_spoken_formula_composition_test.dart
```

Expected: all selected tests PASS with no production Flutter changes.

- [ ] **Step 5: Build the Web test page against the verified backend contract**

```powershell
flutter build web --dart-define=APP_ENV=development --dart-define=ENABLE_DEVELOPER_TOOLS=true --dart-define=API_BASE_URL=http://localhost:3001 --dart-define=PRACTICE_ASSESSMENT_REMOTE=false --dart-define=PRACTICE_SPOKEN_FORMULA_REMOTE=true
```

Expected: Web build exits 0 and the generated bundle contains `/practice-assessment-lab` and `localhost:3001`.

- [ ] **Step 6: Verify implementation-branch history and exact diff**

```powershell
git status --short
git log --oneline 95cd685..HEAD
git diff --check 95cd685..HEAD
git diff --stat 95cd685..HEAD
```

Expected: the isolated worktree is clean; history contains the three task commits; diff check is empty; only `lib/practice-formula/*` and the named backend tests changed.

- [ ] **Step 7: Fast-forward the requested backend branch**

In `D:\ywkeji\Uniprism\UniPrism_New-main`, first verify that none of the files changed by this plan are dirty:

```powershell
git status --short -- lib/practice-formula tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts tests/unit/practiceSpokenFormula.test.ts
```

Expected: no output. Then integrate without rewriting or staging unrelated changes:

```powershell
git merge --ff-only feature/spoken-formula-math-ast-backend
```

Expected: `feature/dialogue-exploration-1-2-backend` advances by fast-forward and all unrelated dirty files remain untouched.

- [ ] **Step 8: Re-run focused backend tests from the target branch**

```powershell
npm test -- --run tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts tests/unit/practiceSpokenFormula.test.ts tests/unit/practiceSpokenFormulaRoute.test.ts tests/unit/practiceSpokenFormulaNextRoute.test.ts
npm run typecheck
```

Expected: all named tests PASS and typecheck exits 0 from the actual requested backend branch.

- [ ] **Step 9: Open the acceptance page and perform one browser microphone check**

Run the verified backend on port 3000 and the built Flutter Web page on port 5175, then open:

```text
http://localhost:5175/#/practice-assessment-lab
```

Select a fill-blank question, focus the MathField, choose “语音输入公式”, allow microphone access, speak “先把 x 自乘，再加上它的两倍，最后加一”, and verify the preview appears before the answer changes. Confirm insertion once and verify the answer contains the rendered formula exactly once.

- [ ] **Step 10: Report verification and known limits**

Report:

- backend commits integrated into `feature/dialogue-exploration-1-2-backend`;
- focused Vitest count, typecheck result, lint result, Flutter test count, Web build result, and real MiniMax sample outcomes;
- no database/schema/persistence change and no audio storage;
- known limit: browser/OS speech recognition remains the ASR layer and is not equally supported across browsers;
- next feature remains handwriting/whiteboard input reusing the new AST pipeline.
