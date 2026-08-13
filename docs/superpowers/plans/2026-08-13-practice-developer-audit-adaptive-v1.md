# Practice Developer Audit and Adaptive Rule V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有练习 Benchmark 管理端中提供题目难度、模拟/真实作答内部判断的统一审查，并提供可解释的规则选题预览。

**Architecture:** 真实作答由后端只读重放服务生成脱敏审查投影，模拟案例继续使用内存 Runner；两者共享 Cognition V2 Engine。规则选题是独立纯函数，读取题目元数据、手工/画像能力和历史摘要，返回稳定得分明细；管理端只负责输入和展示。

**Tech Stack:** Next.js 16、React 18、TypeScript、Zod、Prisma、Vitest、React Test Renderer。

## Global Constraints

- 不新增数据库表，不改变学生 DTO，不修改 V1 正式画像公式。
- 真实作答网络 DTO 禁止答案、过程、参与者、会话、邮箱、手机号和 token 字段。
- V2 继续保持 Shadow；Adaptive V1 只在管理端预览，不改变 Flutter App 正式题序。
- `null` 能力表示证据不足，不能按 0 档处理。
- 所有新模块、异步流程和数据安全白名单使用简洁中文注释。
- 保留前后端两个仓库现有未提交文件，不覆盖或提交无关改动。

---

### Task 1: 真实作答脱敏审查投影和管理员 API

**Files:**
- Create: backend `lib/practice-assessment/benchmark/realAttemptAudit.ts`
- Create: backend `app/api/admin/practice-benchmark/real-attempts/route.ts`
- Test: backend `tests/unit/practiceRealAttemptAudit.test.ts`
- Test: backend `tests/unit/practiceRealAttemptRoutes.test.ts`

**Interfaces:**
- Consumes: `RealAttemptReplayService.listRecentRealAttempts(limit)` 和 `replayRealAttempt(attemptId)`。
- Produces: `listRecentAttemptAuditRefs(limit)` 与 `getRealAttemptAudit(attemptId)`；HTTP `GET ?limit=20` 或 `GET ?attemptId=<id>`。

- [ ] **Step 1: 写审查投影失败测试**

```ts
const audit = projectRealAttemptAudit(replayResult);
expect(audit.target.behavior).toEqual({
  attemptNumber: 2,
  previousOutcome: 'INCORRECT',
  hintLevels: [],
  answerChangeCount: 1,
  reasoningChangeCount: 1,
  questionRevisitCount: 0,
  timelineQuality: 'VALID',
});
expect(JSON.stringify(audit)).not.toMatch(/answerSnapshot|reasoningSnapshot|sessionId|participant/i);
expect(audit.target.observations).toHaveProperty('CHECK');
```

- [ ] **Step 2: 运行 RED**

Run: `npm test -- --run tests/unit/practiceRealAttemptAudit.test.ts`

Expected: FAIL，因为 `realAttemptAudit.ts` 尚不存在。

- [ ] **Step 3: 实现白名单投影**

```ts
export function projectRealAttemptAudit(result: RealAttemptReplayResult): RealAttemptAuditDto;

export class RealAttemptAuditService {
  listRecentAttemptAuditRefs(limit: number): Promise<RealAttemptAuditRefDto[]>;
  getRealAttemptAudit(attemptId: string): Promise<RealAttemptAuditDto | null>;
}
```

列表仅返回 attemptId、questionId、attemptNumber、outcome、submittedAt；详情只返回难度、行为摘要、facts、七维 observations、画像变化和算法版本。

- [ ] **Step 4: 运行投影 GREEN**

Run: `npm test -- --run tests/unit/practiceRealAttemptAudit.test.ts`

Expected: PASS。

- [ ] **Step 5: 写路由 RED 测试**

断言管理员认证先执行、limit 被限制到 1～50、非法 attemptId 被拒绝、404 不回退、响应 `cache-control=no-store`，且网络 JSON 不包含禁止字段。

- [ ] **Step 6: 实现 GET 路由并运行 GREEN**

Run: `npm test -- --run tests/unit/practiceRealAttemptRoutes.test.ts`

Expected: PASS。

- [ ] **Step 7: 提交 Task 1**

```powershell
git add lib/practice-assessment/benchmark/realAttemptAudit.ts app/api/admin/practice-benchmark/real-attempts/route.ts tests/unit/practiceRealAttemptAudit.test.ts tests/unit/practiceRealAttemptRoutes.test.ts
git commit -m "feat(practice): expose redacted attempt audits to admins"
```

### Task 2: 管理端真实作答审查区域

**Files:**
- Create: backend `app/admin/practice-benchmark/components/RealAttemptAuditPanel.tsx`
- Modify: backend `app/admin/practice-benchmark/PracticeBenchmarkDashboardClient.tsx`
- Test: backend `tests/unit/practiceBenchmarkAdminPage.test.ts`

**Interfaces:**
- Consumes: `/api/admin/practice-benchmark/real-attempts?limit=20` 和 `?attemptId=`。
- Produces: `真实作答审查` Tab，显示脱敏行为、六维难度、判题 facts、七维证据和画像快照。

- [ ] **Step 1: 写页面 RED 测试**

渲染 Dashboard、点击“真实作答审查”、加载列表并选择 attempt；断言出现“答案修改”“证据不足”“CHECK”“画像变化”，且组件不渲染答案或过程原文。

- [ ] **Step 2: 运行 RED**

Run: `npm test -- --run tests/unit/practiceBenchmarkAdminPage.test.ts`

Expected: FAIL，因为 Tab 和组件尚不存在。

- [ ] **Step 3: 实现组件**

组件独立维护 loading/error/empty/selected 状态；错误时保留最近一次成功详情，数据库不可用时不影响其他 Tab。

- [ ] **Step 4: 运行 GREEN 并提交**

Run: `npm test -- --run tests/unit/practiceBenchmarkAdminPage.test.ts`

```powershell
git add app/admin/practice-benchmark/PracticeBenchmarkDashboardClient.tsx app/admin/practice-benchmark/components/RealAttemptAuditPanel.tsx tests/unit/practiceBenchmarkAdminPage.test.ts
git commit -m "feat(admin): review redacted practice attempts"
```

### Task 3: 统一模拟判断审查

**Files:**
- Modify: backend `lib/practice-assessment/benchmark/customScenarioRunner.ts`
- Modify: backend `app/admin/practice-benchmark/components/CustomScenarioPanel.tsx`
- Test: backend `tests/unit/practiceBenchmarkRunner.test.ts`
- Test: backend `tests/unit/practiceBenchmarkAdminPage.test.ts`

**Interfaces:**
- Consumes: 现有 `runCustomPracticeScenario`、Question Difficulty Gold 和 V2 assessment。
- Produces: 自定义场景结果中的 `difficultyReview`、facts、rubric、七维 evidence 和完整 before/after 画像。

- [ ] **Step 1: 写 Runner RED 测试**

```ts
expect(result.difficultyReview).toMatchObject({
  actual: { algorithmVersion: 'difficulty-rule-v1' },
  expected: { questionId: input.questionId },
});
expect(result.assessment.facts.matchedStepIds).toEqual(expect.any(Array));
expect(result.profileChanges.CHECK).toHaveProperty('before');
```

- [ ] **Step 2: 运行 RED、实现最小 Runner 扩展、运行 GREEN**

Run: `npm test -- --run tests/unit/practiceBenchmarkRunner.test.ts`

- [ ] **Step 3: 写页面 RED 并实现同页六区块**

页面依次显示题目六维 Gold/Actual、输入行为、判题、事实、七维证据、画像变化；非观察维度显示“证据不足/不适用”，不得显示 0 档。

- [ ] **Step 4: 运行 GREEN 并提交**

Run: `npm test -- --run tests/unit/practiceBenchmarkAdminPage.test.ts tests/unit/practiceBenchmarkRunner.test.ts`

```powershell
git add lib/practice-assessment/benchmark/customScenarioRunner.ts app/admin/practice-benchmark/components/CustomScenarioPanel.tsx tests/unit/practiceBenchmarkRunner.test.ts tests/unit/practiceBenchmarkAdminPage.test.ts
git commit -m "feat(admin): unify practice judgment review"
```

### Task 4: 规则选题纯引擎

**Files:**
- Create: backend `lib/practice-assessment/adaptive/contracts.ts`
- Create: backend `lib/practice-assessment/adaptive/questionDemand.ts`
- Create: backend `lib/practice-assessment/adaptive/ruleSelector.ts`
- Test: backend `tests/unit/practiceAdaptiveRuleSelector.test.ts`

**Interfaces:**
- Produces: `recommendPracticeQuestions(input: AdaptiveSelectionInput): AdaptiveSelectionResult`。
- Output: `ruleVersion='adaptive-rule-v1'`、targetBucket、ranked candidates、scoreBreakdown、reasons、risks。

- [ ] **Step 1: 写 RED 测试**

覆盖：知识过滤；REPR=1.9 时优先接近2.2的题；`null` 不等于0；近期同题/同结构受惩罚；迁移题加分；十题周期为6/2/2；相同输入稳定；同分按题号/id。

- [ ] **Step 2: 运行 RED**

Run: `npm test -- --run tests/unit/practiceAdaptiveRuleSelector.test.ts`

Expected: FAIL，因为 selector 不存在。

- [ ] **Step 3: 实现契约和需求派生**

```ts
export const ADAPTIVE_RULE_VERSION = 'adaptive-rule-v1' as const;
export const QUESTION_DEMAND_VERSION = 'derived-demand-v1' as const;
export function deriveQuestionCognitionDemand(question: DemoPracticeQuestion): Record<CognitionDimension, number>;
```

- [ ] **Step 4: 实现五层评分和稳定排序**

单项分数保持可解释；分桶优先级由 `(sequencePosition - 1) % 10` 决定；没有候选时记录 fallbackReason。

- [ ] **Step 5: 运行 GREEN 并提交**

Run: `npm test -- --run tests/unit/practiceAdaptiveRuleSelector.test.ts`

```powershell
git add lib/practice-assessment/adaptive tests/unit/practiceAdaptiveRuleSelector.test.ts
git commit -m "feat(practice): rank questions with adaptive rules"
```

### Task 5: 规则选题管理端预览

**Files:**
- Create: backend `app/api/admin/practice-benchmark/adaptive-preview/route.ts`
- Create: backend `app/admin/practice-benchmark/components/AdaptiveRulePreview.tsx`
- Modify: backend `app/admin/practice-benchmark/PracticeBenchmarkDashboardClient.tsx`
- Test: backend `tests/unit/practiceAdaptiveRoutes.test.ts`
- Test: backend `tests/unit/practiceBenchmarkAdminPage.test.ts`

**Interfaces:**
- Consumes: `recommendPracticeQuestions` 和19题演示目录。
- Produces: 管理员 POST 预览 API 与“规则选题” Tab。

- [ ] **Step 1: 写路由 RED 测试**

断言同源、管理员、Zod 限制、七维 nullable 输入和 `no-store`。

- [ ] **Step 2: 实现路由并运行 GREEN**

Run: `npm test -- --run tests/unit/practiceAdaptiveRoutes.test.ts`

- [ ] **Step 3: 写页面 RED 测试**

输入 REPR=1.9、当前知识点和历史结构，提交后断言展示目标分桶、Top 候选、总分、七项分解、推荐理由和风险。

- [ ] **Step 4: 实现预览组件并运行 GREEN**

Run: `npm test -- --run tests/unit/practiceBenchmarkAdminPage.test.ts`

- [ ] **Step 5: 提交 Task 5**

```powershell
git add app/api/admin/practice-benchmark/adaptive-preview/route.ts app/admin/practice-benchmark/components/AdaptiveRulePreview.tsx app/admin/practice-benchmark/PracticeBenchmarkDashboardClient.tsx tests/unit/practiceAdaptiveRoutes.test.ts tests/unit/practiceBenchmarkAdminPage.test.ts
git commit -m "feat(admin): preview adaptive practice ranking"
```

### Task 6: 全量验证与测试说明

**Files:**
- Modify: backend `docs/PRACTICE_ASSESSMENT_V1_OPERATIONS.md`
- Modify: frontend `docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md`

**Interfaces:**
- Produces: 开发人员可重复执行的 App、后端和管理端测试步骤。

- [ ] **Step 1: 运行练习相关回归**

Run: `npm test -- --run tests/unit/practice*.test.ts`

Expected: 0 failures。

- [ ] **Step 2: 运行类型和定向 lint**

Run: `npm run typecheck`

Run: `npx eslint lib/practice-assessment app/admin/practice-benchmark app/api/admin/practice-benchmark tests/unit/practice*.test.ts`

- [ ] **Step 3: 运行生产构建**

Run: `npm run build`

- [ ] **Step 4: 运行 Flutter 相关回归**

Run: `flutter test test/features/practice_assessment test/widget_test.dart`

Run: `dart analyze lib/main.dart lib/developer_tools.dart lib/features/practice_assessment test/features/practice_assessment test/widget_test.dart`

- [ ] **Step 5: 更新说明并提交**

文档明确：App 产生真实行为；管理端模拟审查总是可用；真实审查依赖练习表和管理员登录；Adaptive 仅预览；当前题目为演示题。

```powershell
git add docs/PRACTICE_ASSESSMENT_V1_OPERATIONS.md
git commit -m "docs(practice): explain audit and adaptive preview"
```

```powershell
git add docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md
git commit -m "docs(practice): hand off developer audit testing"
```
