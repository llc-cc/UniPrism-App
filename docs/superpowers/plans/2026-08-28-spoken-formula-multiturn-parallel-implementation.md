# 语音公式多轮澄清并行实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan with review checkpoints.

**Goal:** 一小时内交付可运行的多轮补充语音 MVP，并让安全 AST 支持二阶行列式。

**Architecture:** Flutter 在控制器内保留累计识别文字，并把补充录音合并后复用现有无状态解析接口；后端扩展澄清动作和受限矩阵/行列式 AST，全程保留原有审计与显式插入边界。前后端以 `continueRecording` 字面量为唯一共享改动点，分别在独立 worktree 开发。

**Tech Stack:** Flutter/Dart、Riverpod/现有状态管理、Next.js/TypeScript、Vitest、Flutter Test、MiniMax Compact AST 适配层。

**Spec:** `docs/superpowers/specs/2026-08-28-spoken-formula-multiturn-clarification-design.md`

## Global Constraints

- 修改前遵守 `docs/DEVELOPMENT_CODE_STANDARD.md`，异步状态和安全边界写简洁中文注释。
- 不读取、输出或提交 `.env.local`；单元测试不得访问真实 MiniMax 网络。
- 不读取或修改冻结隐藏集 `tests/fixtures/practice-spoken-formula-semantic-heldout-v1.json` 和 `tests/unit/practiceFormulaSemanticHeldout.test.ts`。
- 不碰前端 worktree 中用户未跟踪的 `docs/qa/`。
- 不降低 AST、LaTeX、候选审计，不自动插入任何语音候选。

### Task 1: Flutter 协议严格解析 `continueRecording`

**Owner:** Frontend worker

**Files:**

- Modify: `lib/features/practice_assessment/core/spoken_formula.dart`
- Modify: `lib/features/practice_assessment/adapters/remote_spoken_formula_repository.dart`
- Test: `test/features/practice_assessment/spoken_formula_repository_test.dart`

**Step 1: Write the failing test**

在 clarification fixture 中加入 `continueRecording`，断言严格解析得到对应枚举；保留未知 action 必须拒绝的现有测试。

**Step 2: Run test to verify it fails**

Run: `flutter test test/features/practice_assessment/spoken_formula_repository_test.dart`

Expected: 因未知 `continueRecording` 失败。

**Step 3: Write minimal implementation**

新增 Dart 枚举成员并在远端响应严格映射中识别冻结字面量，不改变其他 action 语义。

**Step 4: Run test to verify it passes**

Run: `flutter test test/features/practice_assessment/spoken_formula_repository_test.dart`

Expected: PASS。

### Task 2: Flutter 多轮续录状态机

**Owner:** Frontend worker

**Files:**

- Modify: `lib/features/practice_assessment/application/speech_formula_controller.dart`
- Test: `test/features/practice_assessment/speech_formula_controller_test.dart`

**Step 1: Write failing controller tests**

覆盖：clarification 与客户端 deadline/error 两个入口都能保留首轮文字；补充 final 后按中文逗号合并并重新解析；每轮使用新的 operation；迟到回调隔离；空补充不请求；整段重录清空上下文；最多 3 轮。没有 transcript 的权限/麦克风错误不能续录。

**Step 2: Run test to verify it fails**

Run: `flutter test test/features/practice_assessment/speech_formula_controller_test.dart`

Expected: 缺少续录状态和 action 分支而失败。

**Step 3: Write minimal implementation**

为状态增加累计文字与续录轮数；`continueRecording` 保留上下文启动监听，final 合并后复用 repository；`retryRecording` 完整清空。对异步 operation 边界写中文注释。

**Step 4: Run test to verify it passes**

Run: `flutter test test/features/practice_assessment/speech_formula_controller_test.dart`

Expected: PASS。

### Task 3: Flutter 澄清界面与无障碍入口

**Owner:** Frontend worker

**Files:**

- Modify: `lib/features/practice_assessment/presentation/practice_formula_voice_panel.dart`
- Test: `test/features/practice_assessment/practice_formula_voice_panel_test.dart`

**Step 1: Write failing widget tests**

断言澄清卡和“超时但已有识别文字”的错误卡都显示“继续补充语音”，点击后保留原识别文字；没有文字的基础设施错误不显示该按钮；达到 3 轮后按钮不可再出现；候选仍不会自动插入。

**Step 2: Run test to verify it fails**

Run: `flutter test test/features/practice_assessment/practice_formula_voice_panel_test.dart`

Expected: 找不到续录按钮或状态不保留。

**Step 3: Write minimal implementation**

复用 clarification option 渲染，增加稳定 key 与清晰中文标签；轮数上限由控制器状态决定，不把业务判断塞进 Widget。

**Step 4: Verify frontend slice**

Run: `flutter test test/features/practice_assessment/spoken_formula_repository_test.dart test/features/practice_assessment/speech_formula_controller_test.dart test/features/practice_assessment/practice_formula_voice_panel_test.dart`

Run: `flutter analyze lib/features/practice_assessment test/features/practice_assessment`

Expected: 全部通过。

**Step 5: Commit frontend slice**

```bash
git add lib/features/practice_assessment test/features/practice_assessment
git commit -m "feat(practice): support spoken formula continuation"
```

### Task 4: 后端澄清协议与默认选项

**Owner:** Backend worker

**Files:**

- Modify: `lib/practice-formula/resolutionContracts.ts`
- Modify: `lib/practice-formula/localResolutionService.ts`
- Modify: `lib/practice-formula/resolutionHttp.ts`
- Test: `tests/unit/practiceFormulaResolutionContracts.test.ts`
- Test: `tests/unit/practiceFormulaLocalResolutionService.test.ts`
- Test: `tests/unit/practiceSpokenFormulaResolutionRoute.test.ts`

**Step 1: Write failing tests**

断言 action 合约接受 `continueRecording`；无安全候选与 HTTP 剩余预算不足的 clarification 都返回续录和键盘；有安全候选时仍提供 `selectCandidate`，且所有 candidateId 都属于当前响应。

**Step 2: Run tests to verify they fail**

Run: `npm test -- --run tests/unit/practiceFormulaResolutionContracts.test.ts tests/unit/practiceFormulaLocalResolutionService.test.ts tests/unit/practiceSpokenFormulaResolutionRoute.test.ts`

Expected: 新 action 未定义而失败。

**Step 3: Write minimal implementation**

扩展 action 联合类型和运行时校验；将需要更多语义信息的默认澄清选项改为 `continueRecording`，保留键盘/整段重录安全出口。

**Step 4: Run tests to verify they pass**

重复 Step 2 命令，Expected: PASS。

### Task 5: 受限矩阵/行列式 Canonical 与 Compact AST

**Owner:** Backend worker

**Files:**

- Modify: `lib/practice-formula/mathAst.ts`
- Modify: `lib/practice-formula/compactMathAst.ts`
- Modify: `lib/practice-formula/mathAstJsonSchema.ts`
- Test: `tests/unit/practiceFormulaMathAst.test.ts`
- Test: `tests/unit/practiceFormulaCompactAst.test.ts`
- Test: `tests/unit/practiceFormulaMathAstJsonSchema.test.ts`

**Step 1: Write failing AST tests**

覆盖 2x2 matrix/determinant 解析与 compact 往返；拒绝空行、不等长、1x1、超过 4x4、determinant body 非 matrix。

**Step 2: Run tests to verify they fail**

Run: `npm test -- --run tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaCompactAst.test.ts tests/unit/practiceFormulaMathAstJsonSchema.test.ts`

Expected: 新节点未知而失败。

**Step 3: Write minimal implementation**

按设计增加节点、运行时解析、计数/深度遍历、compact tag 与 JSON Schema；矩阵单元格递归使用既有节点解析器。

**Step 4: Run tests to verify they pass**

重复 Step 2 命令，Expected: PASS。

### Task 6: 行列式渲染、朗读、审计与模型提示

**Owner:** Backend worker

**Files:**

- Modify: `lib/practice-formula/mathAstLatex.ts`
- Modify: `lib/practice-formula/mathAstSpeechZhCn.ts`
- Modify: `lib/practice-formula/candidateAudit.ts`
- Modify: `lib/practice-formula/prompt.ts`
- Modify: `lib/practice-formula/miniMaxCompactAstClient.ts`
- Test: `tests/unit/practiceFormulaMathAstLatex.test.ts`
- Test: `tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts`
- Test: `tests/unit/practiceFormulaCandidateAudit.test.ts`
- Test: `tests/unit/practiceFormulaMiniMaxCompactAstClient.test.ts`

**Step 1: Write failing behavior tests**

用 2x2 AST 断言 `vmatrix` LaTeX、逐行逐单元格反向朗读、审计遍历所有单元格；模型 compact schema/prompt 包含新 tag，非法模型输出仍拒绝。

**Step 2: Run tests to verify they fail**

Run: `npm test -- --run tests/unit/practiceFormulaMathAstLatex.test.ts tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts tests/unit/practiceFormulaCandidateAudit.test.ts tests/unit/practiceFormulaMiniMaxCompactAstClient.test.ts`

Expected: 渲染器/遍历器未覆盖新节点而失败。

**Step 3: Write minimal implementation**

增加受控环境渲染和中文反向朗读；审计递归进入全部单元格；提示中给出一个明确 2x2 示例。不得接受 raw LaTeX。

**Step 4: Add public acceptance test**

在非隐藏公开测试中加入明确槽位语句：`二阶行列式，第一行 x 加一、二 x 减三，第二行 x 减一、x 平方`。若本地解析器无法在时限内安全覆盖，模型客户端 fixture 至少必须返回并审核目标 AST，真实服务由 MiniMax 兜底。

**Step 5: Verify backend slice**

Run: `npm test -- --run tests/unit/practiceFormulaResolutionContracts.test.ts tests/unit/practiceFormulaLocalResolutionService.test.ts tests/unit/practiceFormulaMathAst.test.ts tests/unit/practiceFormulaCompactAst.test.ts tests/unit/practiceFormulaMathAstJsonSchema.test.ts tests/unit/practiceFormulaMathAstLatex.test.ts tests/unit/practiceFormulaMathAstSpeechZhCn.test.ts tests/unit/practiceFormulaCandidateAudit.test.ts tests/unit/practiceFormulaMiniMaxCompactAstClient.test.ts tests/unit/practiceSpokenFormulaResolutionRoute.test.ts`

Run: `npm run typecheck`

Expected: 全部通过。

**Step 6: Commit backend slice**

```bash
git add lib/practice-formula tests/unit
git commit -m "feat(practice): add formula continuation and determinants"
```

### Task 7: C3 集成、审查与回归

**Owner:** Coordinator

**Files:**

- Review both worker commits and changed file sets.
- Integrate backend commit into the branch used by the running API without including ignored secrets or hidden fixtures.

**Step 1: Contract review**

检查前后端字面量完全一致，严格解析未知 action 仍失败；确认 `retryRecording` 清空、`continueRecording` 保留；确认所有新 AST 分支都有穷尽处理。

**Step 2: Focused regression**

运行 Task 3 和 Task 6 的完整验证命令，再运行现有 spoken-formula 相关公开测试（显式排除冻结隐藏测试）。

**Step 3: Build**

Frontend: `flutter build web`

Backend: `npm run build`

Expected: 两边构建成功。

**Step 4: Live smoke test**

重启本地 Web 和 API 后验证：

1. 首轮歧义 -> 继续补充 -> 合并文字可见 -> 返回候选。
2. 明确二阶行列式 -> 返回安全渲染公式或可继续补充的澄清，不出现 raw/半成品 LaTeX。
3. 候选必须由用户点击“插入公式”后才进入答案框。
4. 本地可解析案例不增加 MiniMax 调用；复杂案例在配置可用时走兜底。

**Step 5: Final report**

报告实际修改、命令和结果、公开/隐藏回归边界、尚未覆盖的自然语言变体；不得声称未执行的真实麦克风用例已通过。
