# Practice V2 Shadow Assessment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Flutter App 的真实作答在后端生成版本化 V2 Shadow 判断，同时保持学生、正式画像和管理端的数据边界。

**Architecture:** 保留现有 V1 学生提交与正式画像事务；提交时用同一输入运行 V2，将单次七维 Shadow 嵌入 attempt 内部 facts JSON。学生 DTO 和管理端均不读取真实 Shadow；管理端继续用模拟 Gold 调试同一 Engine。

**Tech Stack:** Flutter/Dart、Next.js、TypeScript、Prisma JSON、Vitest。

## Global Constraints

- 不新增数据库迁移，不改变 V1 维度、判断规则或画像公式；仅允许修正同题多次提交的事件分窗归属。
- 完整答案与过程只供后端 Engine 使用；V2 Shadow 不进入任何新增网络响应。
- Shadow 与 Benchmark 必须调用同一 `assessAttemptCognitionV2`。
- 不重复保存答案或过程；幂等重复请求不重复写入。
- 新增模块、异步流程与安全边界使用简洁中文注释。

---

### Task 1: V2 可重放边界（已完成）

**Files:**
- Create: backend `lib/practice-assessment/benchmark/realAttemptReplay.ts`
- Test: backend `tests/unit/practiceRealAttemptReplay.test.ts`

**Interfaces:**
- Produces: 内部 V2 历史重放与测试工具；不注册网络路由。

- [x] TDD 实现 V2 历史重放、稳定排序、事件切窗与跨会话画像演算。
- [x] 独立审查并修复全部 Important。

### Task 2: 提交时 V2 Shadow

**Files:**
- Modify: backend `lib/practice-assessment/contracts.ts`
- Modify: backend `lib/practice-assessment/sessionService.ts`
- Test: backend `tests/unit/practiceSessionService.test.ts`

**Interfaces:**
- Consumes: `assessAttemptCognitionV2` 与现有 `assessmentInput`。
- Produces: attempt facts 内部 `cognitionV2Shadow`；`toStudentAttempt` 输出保持不变。

- [ ] 写失败测试：提交保存 V2 Shadow、学生响应不含 Shadow、幂等重试不重复写入。
- [ ] 运行测试并确认因 Shadow 缺失失败。
- [ ] 运行 V2 并把版本化 Shadow 随 V1 facts 同事务保存。
- [ ] 同题第二次及以后提交只汇总上一次 `submittedAt` 之后的事件，避免旧提示和旧修改污染当次证据。
- [ ] 运行测试、typecheck 和定向 lint。
- [ ] 提交 `feat(practice): capture cognition v2 shadow assessments`。

### Task 3: 管理端模拟实验室边界

**Files:**
- Modify: backend `tests/unit/practiceBenchmarkAdminPage.test.ts`

**Interfaces:**
- Consumes: 现有静态 Benchmark 与自定义模拟场景。
- Produces: 测试保证管理端保持 Gold/Actual/Evidence，且没有真实作答接口。

- [ ] 写或收紧边界测试。
- [ ] 运行页面测试；如现状不满足，最小修改管理端文案。
- [ ] 提交 `test(admin): keep benchmark isolated from real attempts`。

### Task 4: App 远程行为入口与文档

**Files:**
- Modify: `docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md`
- Test: `test/widget_test.dart`
- Test: `test/features/practice_assessment/practice_session_controller_test.dart`

**Interfaces:**
- Consumes: Developer Tools、RemotePracticeRepository 和事件记录器。
- Produces: 可复现的 Flutter Web 真实行为测试流程。

- [ ] 收紧测试：远程入口存在，答案/过程变化与提交事件进入记录链。
- [ ] 运行 Flutter 测试；仅按失败点最小修复。
- [ ] 更新远程启动命令、Mock/Remote 横幅和 App→后端→管理端模拟调试说明。
- [ ] 提交 `docs(practice): document app behavior shadow flow`。

### Task 5: 全链路验证

**Files:**
- Modify: backend `docs/PRACTICE_ASSESSMENT_V1_OPERATIONS.md`

**Interfaces:**
- Produces: 第一版操作说明与验证证据。

- [ ] 运行全部 practice Vitest、TypeScript、定向 ESLint 与生产构建。
- [ ] 运行 Flutter practice 测试和相关 analyze。
- [ ] 如本地数据库可用，做 App 远程提交和后端 Shadow 写入冒烟；否则明确记录未执行项。
- [ ] 更新运维文档并提交。
