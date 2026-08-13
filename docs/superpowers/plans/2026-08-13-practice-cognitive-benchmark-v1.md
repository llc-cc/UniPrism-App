# Practice Cognitive Benchmark V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an admin-only, deterministic benchmark that compares the real practice assessment engines with independent `gold-v1` annotations for 19 questions, 190 behavior cases, and 12 long-term learner trajectories.

**Architecture:** Add a `cognition-v2` engine namespace beside the unchanged production V1 contracts. Load immutable JSON Gold through strict schemas, replay it through production difficulty plus V2 evidence/profile engines, and expose stage-aware results through authenticated admin APIs and a debug dashboard. The runner is pure in-memory and never writes student data or Gold.

**Tech Stack:** Next.js 16 App Router, React 18, TypeScript 5 strict mode, Zod 4, Vitest 4, Tailwind CSS, lucide-react.

## Global Constraints

- Use `gold-v1`, `cognition-rule-v2`, and `ability-profile-v2` as exact version identifiers.
- Keep V1 student APIs, Prisma profile rows, and Flutter contracts unchanged.
- Gold contains exactly 19 question difficulty rows, 190 explicit attempt rows, and 12 learner trajectories.
- Only `OBSERVED` observations may have a `0..4` band; all other statuses must have `band: null`.
- Admin scenario execution is memory-only, length-bounded, authenticated, and excluded from application logs.
- Gold files are read-only at runtime; no API may mutate them.
- New substantive modules, async flows, safety branches, and state transitions require concise Chinese comments.
- Stage failures use `BLOCKED_BY_UPSTREAM` to avoid double-counting one root cause.
- Run relevant Vitest tests, TypeScript typecheck, Next.js build, and a browser smoke test before handoff.

---

### Task 0: Preserve the existing practice migration fix

**Files:**
- Modify/commit existing: `prisma/migrations/20260813_practice_participant_identity_uniqueness/migration.sql`
- Modify/commit existing: `tests/unit/practiceAssessmentMigration.test.ts`

**Interfaces:**
- Consumes: current practice participant migration and its source-level regression test.
- Produces: a clean committed backend baseline before Benchmark work starts.

- [ ] **Step 1: Run the focused migration regression test**

Run: `npm test -- --run tests/unit/practiceAssessmentMigration.test.ts`

Expected: PASS, including the MySQL-safe index order assertion.

- [ ] **Step 2: Review only the two existing diffs**

Run: `git diff -- prisma/migrations/20260813_practice_participant_identity_uniqueness/migration.sql tests/unit/practiceAssessmentMigration.test.ts`

Expected: the unique-index migration drops the conflicting ordinary index before adding the unique key; no unrelated file appears.

- [ ] **Step 3: Commit the verified fix**

```powershell
git add -- prisma/migrations/20260813_practice_participant_identity_uniqueness/migration.sql tests/unit/practiceAssessmentMigration.test.ts
git commit -m "fix(practice): make participant identity migration deployable"
```

### Task 1: Define the isolated cognition V2 contracts

**Files:**
- Create: `lib/practice-assessment/cognition-v2/contracts.ts`
- Test: `tests/unit/practiceCognitionV2Contracts.test.ts`

**Interfaces:**
- Consumes: V1 `AttemptFacts`, `AttemptOutcome`, `EvidenceStatus`, `HintLevel`, and `QuestionDifficultyProfile` types.
- Produces: `COGNITION_DIMENSIONS`, `CognitionDimension`, `CognitionObservationV2`, `CognitionAssessmentV2`, `CognitionProfileV2`, and strict Zod schemas.

- [ ] **Step 1: Write failing contract invariants**

Test all seven exact dimensions (`READ`, `COMP`, `REPR`, `STRAT`, `CALC`, `PROOF`, `CHECK`), reject an eighth/legacy value, reject `OBSERVED` with `null`, reject insufficient/not-applicable with a number, and accept a valid nullable observation.

- [ ] **Step 2: Run the contract test and verify RED**

Run: `npm test -- --run tests/unit/practiceCognitionV2Contracts.test.ts`

Expected: FAIL because `cognition-v2/contracts.ts` does not exist.

- [ ] **Step 3: Implement strict V2 contracts**

Define the version constants, seven-dimension tuple, observation schema, assessment result, profile maturity, profile shape, scenario input, and `ProfileDirection = 'UP' | 'DOWN' | 'UNCHANGED'`. Add Chinese comments explaining V1 isolation and null-band safety.

- [ ] **Step 4: Run the contract test and verify GREEN**

Run: `npm test -- --run tests/unit/practiceCognitionV2Contracts.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/practice-assessment/cognition-v2/contracts.ts tests/unit/practiceCognitionV2Contracts.test.ts
git commit -m "feat(practice): define cognition v2 contracts"
```

### Task 2: Implement V2 evidence and profile engines

**Files:**
- Create: `lib/practice-assessment/cognition-v2/evidenceEngine.ts`
- Create: `lib/practice-assessment/cognition-v2/profileUpdater.ts`
- Test: `tests/unit/practiceCognitionV2Evidence.test.ts`
- Test: `tests/unit/practiceCognitionV2Profile.test.ts`

**Interfaces:**
- Consumes: `AttemptAssessmentInput`, `extractAttemptFacts(input)`, question rubric steps and V2 contracts.
- Produces: `assessAttemptCognitionV2(input): CognitionAssessmentV2`, `createEmptyCognitionProfileV2(dimension)`, and `updateCognitionProfileV2(input)`.

- [ ] **Step 1: Write failing evidence tests for the hard cases**

Cover correct/no-process, wrong/no-process, complete/correct, partial process, independent correction, nudge correction, solution-hint correction, calculation slip, concept contradiction, and not-applicable dimensions. Assert that answer correctness alone never fabricates COMP/REPR/STRAT/PROOF and that CHECK distinguishes independent from prompted correction.

- [ ] **Step 2: Run evidence tests and verify RED**

Run: `npm test -- --run tests/unit/practiceCognitionV2Evidence.test.ts`

Expected: FAIL because the V2 evidence engine does not exist.

- [ ] **Step 3: Implement the minimal deterministic evidence engine**

Map rubric V1 step evidence to V2 through an explicit step-dimension projection: READING→READ, UNDERSTANDING→COMP, TECHNIQUE→STRAT, CALCULATION→CALC, REASONING→PROOF, expression-only evidence does not create a top-level observation, and representation evidence comes only from explicit representation/construction step semantics. CHECK consumes correction, validation, boundary, and hint facts. Preserve evidence status before any band calculation.

- [ ] **Step 4: Run evidence tests and verify GREEN**

Run: `npm test -- --run tests/unit/practiceCognitionV2Evidence.test.ts`

Expected: PASS.

- [ ] **Step 5: Write failing profile tests**

Assert zero update for insufficient/not-applicable evidence, first observed update, same-question repeat weight `0.25`, CHECK correction evidence exemption only when independent, cross-family maturity, `displayBand: null` before evidence, deterministic updates, and direction calculation.

- [ ] **Step 6: Run profile tests and verify RED**

Run: `npm test -- --run tests/unit/practiceCognitionV2Profile.test.ts`

Expected: FAIL because the updater does not exist.

- [ ] **Step 7: Implement the profile updater**

Use bounded theta, information, uncertainty, structure-family coverage, evidence counts, maturity thresholds, difficulty parameters per V2 dimension, and repeat attenuation. Keep floating-point details internal; expose bands and direction helpers for benchmark comparison.

- [ ] **Step 8: Run both engine tests and verify GREEN**

Run: `npm test -- --run tests/unit/practiceCognitionV2Evidence.test.ts tests/unit/practiceCognitionV2Profile.test.ts`

Expected: PASS.

- [ ] **Step 9: Commit**

```powershell
git add -- lib/practice-assessment/cognition-v2/evidenceEngine.ts lib/practice-assessment/cognition-v2/profileUpdater.ts tests/unit/practiceCognitionV2Evidence.test.ts tests/unit/practiceCognitionV2Profile.test.ts
git commit -m "feat(practice): add cognition v2 assessment engines"
```

### Task 3: Add versioned Gold schemas and independent fixtures

**Files:**
- Create: `lib/practice-assessment/benchmark/goldSchemas.ts`
- Create: `lib/practice-assessment/benchmark/goldLoader.ts`
- Create: `data/practice-benchmark/gold-v1/manifest.json`
- Create: `data/practice-benchmark/gold-v1/question-difficulty-gold.json`
- Create: `data/practice-benchmark/gold-v1/attempt-cases-gold.json`
- Create: `data/practice-benchmark/gold-v1/student-trajectories-gold.json`
- Test: `tests/unit/practiceBenchmarkGold.test.ts`

**Interfaces:**
- Consumes: `demoPracticePaper` only for cross-reference validation; it must not source expected difficulty or expected evidence.
- Produces: `loadPracticeBenchmarkGold(): PracticeBenchmarkGold` and typed immutable Gold records.

- [ ] **Step 1: Write failing loader tests**

Assert exact counts `19/190/12`, ten behavior categories per question, unique IDs, valid question/step references, explicit expectations, correct null-band invariants, fixed provenance `INDEPENDENT_HUMAN_BASELINE`, and rejection of `ENGINE_GENERATED` provenance.

- [ ] **Step 2: Run loader tests and verify RED**

Run: `npm test -- --run tests/unit/practiceBenchmarkGold.test.ts`

Expected: FAIL because schemas, loader, and fixtures do not exist.

- [ ] **Step 3: Implement strict Gold schemas and loader**

Use Zod `.strict()` schemas, resolve files from `process.cwd()/data/practice-benchmark/gold-v1`, deep-freeze parsed data, and perform cross-file/catalog validations with actionable error messages. Do not import difficulty, evidence, or profile engines from the loader.

- [ ] **Step 4: Author 19 independent difficulty rows**

For each question, explicitly record all six `0..4` dimensions and a concise annotation reason per dimension. Review values against the problem statement and step graph, not the existing `question.difficulty` output.

- [ ] **Step 5: Author 190 explicit behavior rows**

Expand all 19 × 10 rows in checked-in JSON. Each row stores input, expected outcome, fact constraints, seven expected statuses/band ranges, profile directions, and evidence-count deltas. Inputs may cite catalog rubric step IDs; expected values must be independently authored.

- [ ] **Step 6: Author 12 explicit learner trajectories**

Each trajectory references 5–10 behavior case IDs across multiple question structure families and declares final status/band/maturity/evidence/coverage constraints.

- [ ] **Step 7: Run loader tests and verify GREEN**

Run: `npm test -- --run tests/unit/practiceBenchmarkGold.test.ts`

Expected: PASS and print/assert counts `19/190/12`.

- [ ] **Step 8: Commit**

```powershell
git add -- lib/practice-assessment/benchmark/goldSchemas.ts lib/practice-assessment/benchmark/goldLoader.ts data/practice-benchmark/gold-v1 tests/unit/practiceBenchmarkGold.test.ts
git commit -m "test(practice): add independent benchmark gold v1"
```

### Task 4: Build the stage-aware comparator and benchmark runner

**Files:**
- Create: `lib/practice-assessment/benchmark/goldComparator.ts`
- Create: `lib/practice-assessment/benchmark/benchmarkMetrics.ts`
- Create: `lib/practice-assessment/benchmark/benchmarkRunner.ts`
- Create: `lib/practice-assessment/benchmark/customScenarioRunner.ts`
- Test: `tests/unit/practiceBenchmarkComparator.test.ts`
- Test: `tests/unit/practiceBenchmarkRunner.test.ts`

**Interfaces:**
- Consumes: loaded Gold, `calculateQuestionDifficulty`, `extractAttemptFacts`, `assessAttemptCognitionV2`, and `updateCognitionProfileV2`.
- Produces: `runPracticeBenchmark(): PracticeBenchmarkReport` and `runCustomPracticeScenario(input): CustomScenarioReport`.

- [ ] **Step 1: Write failing comparator tests**

Use small hand-built Gold/Actual pairs to test per-dimension deviation, MAE, within-one rate, allowed band ranges, fact must/must-not constraints, profile directions, and `BLOCKED_BY_UPSTREAM` behavior.

- [ ] **Step 2: Run comparator tests and verify RED**

Run: `npm test -- --run tests/unit/practiceBenchmarkComparator.test.ts`

Expected: FAIL because comparator modules do not exist.

- [ ] **Step 3: Implement comparator and metric aggregation**

Calculate denominator-safe rates, retain every deviation for debugging, and apply the exact quality thresholds from the spec. Hard invariants and quality targets are separate result groups.

- [ ] **Step 4: Run comparator tests and verify GREEN**

Run: `npm test -- --run tests/unit/practiceBenchmarkComparator.test.ts`

Expected: PASS.

- [ ] **Step 5: Write failing full-runner tests**

Assert deterministic repeat runs, report counts, all ten behaviors represented, individual stage outputs present, no database imports/writes, 12 trajectory results, version identifiers, and custom scenario validation/execution.

- [ ] **Step 6: Run runner tests and verify RED**

Run: `npm test -- --run tests/unit/practiceBenchmarkRunner.test.ts`

Expected: FAIL because the runner does not exist.

- [ ] **Step 7: Implement replay and custom scenario runners**

Catch exceptions per case/stage, continue other cases, mark downstream blocked after upstream mismatch, and compute profile snapshots after every trajectory attempt. The custom runner uses the same production V2 path but never imports repositories or Prisma.

- [ ] **Step 8: Run Benchmark tests and verify GREEN**

Run: `npm test -- --run tests/unit/practiceBenchmarkComparator.test.ts tests/unit/practiceBenchmarkRunner.test.ts`

Expected: PASS; quality targets may be red only if represented honestly in report data, while hard invariants must pass.

- [ ] **Step 9: Commit**

```powershell
git add -- lib/practice-assessment/benchmark/goldComparator.ts lib/practice-assessment/benchmark/benchmarkMetrics.ts lib/practice-assessment/benchmark/benchmarkRunner.ts lib/practice-assessment/benchmark/customScenarioRunner.ts tests/unit/practiceBenchmarkComparator.test.ts tests/unit/practiceBenchmarkRunner.test.ts
git commit -m "feat(practice): add cognitive benchmark runner"
```

### Task 5: Expose authenticated read-only admin APIs

**Files:**
- Create: `app/api/admin/practice-benchmark/route.ts`
- Create: `app/api/admin/practice-benchmark/scenarios/route.ts`
- Test: `tests/unit/practiceBenchmarkRoutes.test.ts`

**Interfaces:**
- Consumes: `requireAdminSession`, `runPracticeBenchmark`, `customScenarioInputSchema`, and `runCustomPracticeScenario`.
- Produces: authenticated GET report and POST one-off scenario response using existing `withApiHandler`/`ok` response conventions.

- [ ] **Step 1: Write failing route tests**

Mock auth and runners. Assert GET requires admin, POST requires admin, malformed/oversized inputs return 400, valid inputs call the runner exactly once, responses have `Cache-Control: no-store`, and neither route imports Prisma/repository code.

- [ ] **Step 2: Run route tests and verify RED**

Run: `npm test -- --run tests/unit/practiceBenchmarkRoutes.test.ts`

Expected: FAIL because routes do not exist.

- [ ] **Step 3: Implement GET and POST routes**

Use Node runtime and force dynamic rendering. Add an in-process GET cache keyed by Gold, cognition, difficulty, and catalog versions; never cache POST. Validate before running and do not log scenario payloads.

- [ ] **Step 4: Run route tests and verify GREEN**

Run: `npm test -- --run tests/unit/practiceBenchmarkRoutes.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add -- app/api/admin/practice-benchmark/route.ts app/api/admin/practice-benchmark/scenarios/route.ts tests/unit/practiceBenchmarkRoutes.test.ts
git commit -m "feat(admin): expose practice benchmark APIs"
```

### Task 6: Build the Benchmark Debug admin page and entry

**Files:**
- Create: `app/admin/practice-benchmark/page.tsx`
- Create: `app/admin/practice-benchmark/PracticeBenchmarkDashboardClient.tsx`
- Create: `app/admin/practice-benchmark/components/BenchmarkSummary.tsx`
- Create: `app/admin/practice-benchmark/components/DifficultyReview.tsx`
- Create: `app/admin/practice-benchmark/components/AttemptCaseReview.tsx`
- Create: `app/admin/practice-benchmark/components/CustomScenarioPanel.tsx`
- Create: `app/admin/practice-benchmark/components/TrajectoryReview.tsx`
- Modify: `app/admin/users/page.tsx`
- Test: `tests/unit/practiceBenchmarkAdminPage.test.ts`

**Interfaces:**
- Consumes: server-loaded `PracticeBenchmarkReport` and POST scenario endpoint.
- Produces: `/admin/practice-benchmark` with overview, difficulty, behavior, custom scenario, and trajectory workspaces plus a discoverable admin entry.

- [ ] **Step 1: Write failing admin page tests**

Source-level/render tests assert admin auth, route entry, five workspace labels, Gold/Actual terminology, `证据不足`, 190-case filters, error/empty/loading states, a manual refresh control, custom scenario fields, and no mutation/upload controls for Gold.

- [ ] **Step 2: Run page tests and verify RED**

Run: `npm test -- --run tests/unit/practiceBenchmarkAdminPage.test.ts`

Expected: FAIL because page components and link do not exist.

- [ ] **Step 3: Implement the server page shell**

Reuse `auth`, `isAdminRole`, and existing unauthorized styling. Load the initial report on the server and pass only the report DTO to the client dashboard.

- [ ] **Step 4: Implement focused dashboard components**

Add responsive tabs/cards/tables, dimension labels, pass/fail badges, exact Gold/Actual deviations, question/behavior/stage/status filters, expandable pipeline detail, per-attempt trajectory snapshots, and safe error handling. Keep API/parsing in the dashboard client, not presentation components.

- [ ] **Step 5: Implement custom scenario interaction**

Bound answer/reasoning inputs, select question/hint/timeline/attempt behavior, POST once per click, show pending/error/result states, and retain user input after a failed request. Do not use local persistence.

- [ ] **Step 6: Add the admin navigation entry**

Add a clearly labeled `能力判断测试台` link from the existing admin users page without changing unrelated navigation.

- [ ] **Step 7: Run page tests and verify GREEN**

Run: `npm test -- --run tests/unit/practiceBenchmarkAdminPage.test.ts`

Expected: PASS.

- [ ] **Step 8: Commit**

```powershell
git add -- app/admin/practice-benchmark app/admin/users/page.tsx tests/unit/practiceBenchmarkAdminPage.test.ts
git commit -m "feat(admin): add cognitive benchmark debug page"
```

### Task 7: Complete regression, build, and browser validation

**Files:**
- Modify only if verification finds scoped defects: Benchmark files from Tasks 1–6.
- Update: `docs/PRACTICE_ASSESSMENT_BACKEND_HANDOFF.md`
- Update in Flutter repository: `docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md`

**Interfaces:**
- Consumes: complete Benchmark V1 implementation.
- Produces: verified test instructions, known limits, and a locally running admin page for product review.

- [ ] **Step 1: Run all practice and Benchmark unit tests**

Run: `npm test -- --run tests/unit/practiceAssessment*.test.ts tests/unit/practiceCognitionV2*.test.ts tests/unit/practiceBenchmark*.test.ts`

Expected: PASS.

- [ ] **Step 2: Run type checking**

Run: `npm run typecheck`

Expected: PASS with no TypeScript errors introduced by this feature.

- [ ] **Step 3: Run production build**

Run: `npm run build`

Expected: PASS and list both admin Benchmark API routes and page route.

- [ ] **Step 4: Run a clean Benchmark report smoke command**

Run: `npx tsx -e "import { runPracticeBenchmark } from './lib/practice-assessment/benchmark/benchmarkRunner'; const report = runPracticeBenchmark(); console.log(JSON.stringify({counts: report.counts, hardInvariantsPass: report.summary.hardInvariantsPass, qualityTargetsPass: report.summary.qualityTargetsPass}, null, 2));"`

Expected: counts are `19/190/12`, hard invariants pass, and quality target status matches the admin page.

- [ ] **Step 5: Start the backend and open the admin page**

Run: `npm run dev`, sign in with an admin account, and visit `http://localhost:3000/admin/practice-benchmark`.

Expected: all five workspaces render; filters and details work; a custom scenario returns a result; browser console has no errors.

- [ ] **Step 6: Update handoff documentation**

Document paths, versions, commands, admin URL, exact testing steps, the demonstration-content disclaimer, V1/V2 isolation, and any red quality metrics without weakening thresholds.

- [ ] **Step 7: Run final diff and status audit**

Run: `git diff --check` and `git status --short` in both repositories.

Expected: no whitespace errors; unrelated pre-existing changes remain untouched and unstaged.

- [ ] **Step 8: Commit verification documentation**

```powershell
git add -- docs/PRACTICE_ASSESSMENT_BACKEND_HANDOFF.md
git commit -m "docs(practice): document benchmark testing"
```

In the Flutter repository, stage only the corresponding handoff update and this plan if still uncommitted.
