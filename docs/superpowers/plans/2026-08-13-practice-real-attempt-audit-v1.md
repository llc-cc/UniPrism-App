# Practice Real Attempt Audit V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Flutter App 产生的真实练习作答可在管理端用 `cognition-rule-v2` 只读重放并解释。

**Architecture:** 保留现有 V1 学生提交和正式画像事务；新增管理员只读查询服务，从持久化答案、过程、题目版本和分段事件重建 V2 输入，按参与者历史演算 V2 画像。管理端新增独立页签消费管理员 API，Flutter 不接触内部审计数据。

**Tech Stack:** Flutter/Dart、Next.js App Router、TypeScript、Prisma、Vitest、React。

## Global Constraints

- 不新增数据库迁移，不改变 V1 学生评分和正式画像写入。
- 管理员 API 才能返回答案、过程、内部事实代码、错误标签和置信度。
- 真实重放与静态 Benchmark 必须调用同一个 `assessAttemptCognitionV2` 和 `updateCognitionProfileV2`。
- 查询最多返回 100 条最近提交，历史结果标记为“当前版本重放”。
- 新增模块、异步流程和安全边界使用简洁中文注释。

---

### Task 1: 真实作答 V2 重放服务

**Files:**
- Create: backend `lib/practice-assessment/benchmark/realAttemptReplay.ts`
- Test: backend `tests/unit/practiceRealAttemptReplay.test.ts`

**Interfaces:**
- Consumes: Prisma 查询结果、`assessAttemptCognitionV2`、`updateCognitionProfileV2`。
- Produces: `listRecentRealAttempts(limit)` 与 `replayRealAttempt(attemptId)`。

- [ ] 写失败测试：按提交时间切分事件、同题 previousOutcome、七维画像顺序演算、未知 attempt 返回 null。
- [ ] 运行测试并确认因服务不存在而失败。
- [ ] 实现最小 Prisma 查询适配和纯重放函数，保持稳定排序。
- [ ] 运行测试并确认通过。
- [ ] 提交 `feat(practice): replay real attempts through cognition v2`。

### Task 2: 管理员真实作答 API

**Files:**
- Create: backend `app/api/admin/practice-benchmark/real-attempts/route.ts`
- Test: backend `tests/unit/practiceRealAttemptRoutes.test.ts`

**Interfaces:**
- Consumes: Task 1 的列表/详情服务。
- Produces: 管理员 GET 列表与详情响应。

- [ ] 写失败测试：管理员成功、未登录 401、limit/attemptId 校验失败。
- [ ] 运行测试并确认路由缺失失败。
- [ ] 实现管理员鉴权、Zod 查询校验与标准信封。
- [ ] 运行路由测试并确认通过。
- [ ] 提交 `feat(admin): expose real practice attempt audit api`。

### Task 3: 管理端真实作答审查页签

**Files:**
- Create: backend `app/admin/practice-benchmark/components/RealAttemptReview.tsx`
- Modify: backend `app/admin/practice-benchmark/PracticeBenchmarkDashboardClient.tsx`
- Modify: backend `app/admin/practice-benchmark/practiceBenchmark.module.css`
- Test: backend `tests/unit/practiceBenchmarkAdminPage.test.ts`

**Interfaces:**
- Consumes: Task 2 API。
- Produces: “真实作答审查”页签及列表、详情、错误/空状态。

- [ ] 写失败测试：源码注册新页签且只调用管理员 real-attempts API。
- [ ] 运行测试并确认失败。
- [ ] 实现延迟加载列表、选择详情和七维审查卡片。
- [ ] 运行页面测试并确认通过。
- [ ] 提交 `feat(admin): review real practice cognition evidence`。

### Task 4: App 远程行为入口确认与说明

**Files:**
- Modify: `docs/PRACTICE_ASSESSMENT_V1_HANDOFF.md`
- Test: `test/widget_test.dart`、`test/features/practice_assessment/practice_session_controller_test.dart`

**Interfaces:**
- Consumes: 现有 Developer Tools、RemotePracticeRepository 和事件记录器。
- Produces: 可复现的 Flutter Web 远程测试步骤。

- [ ] 写或收紧测试：远程入口使用后端仓库，答案/过程变化和提交事件进入既有记录链。
- [ ] 运行相关 Flutter 测试确认现状；若失败，按失败点最小修复。
- [ ] 更新交接文档，明确 Mock/Remote 横幅和启动命令。
- [ ] 运行 Flutter 相关测试。
- [ ] 提交 `docs(practice): document app to admin audit flow`。

### Task 5: 全链路验证

**Files:**
- Modify: backend `docs/PRACTICE_ASSESSMENT_V1_OPERATIONS.md`

**Interfaces:**
- Consumes: 前四项交付。
- Produces: 可执行验收说明和验证证据。

- [ ] 运行新增及全部 practice Vitest。
- [ ] 运行后端 TypeScript、定向 ESLint 与生产构建。
- [ ] 运行 Flutter practice 测试和相关 analyze。
- [ ] 以真实数据库做 App 提交 → 管理端出现 → V2 详情稳定的 HTTP/页面冒烟；若数据库不可用，明确记录未执行项。
- [ ] 更新运维文档并提交 `docs(practice): hand off real attempt audit testing`。
