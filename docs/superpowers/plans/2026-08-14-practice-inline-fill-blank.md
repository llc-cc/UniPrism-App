# 练习填空题内嵌公式答案框 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将填空题数学答案直接编辑并排版在题干下划线位置，同时复用现有键盘、草稿和提交链路。

**Architecture:** `MathAnswerField` 继续独占 `MathFieldEditingController`、格式校验和键盘显隐；新增可选题干参数，将题干按首个连续下划线拆分，并把紧凑 `MathField` 放在前后文本之间。`_QuestionCard` 对填空题不再先绘制完整题干再绘制大型输入框，而是一次性调用内嵌模式。

**Tech Stack:** Flutter、`math_keyboard`、Flutter Widget Test

## Global Constraints

- 第一版只支持当前题库的单空填空题。
- 草稿和接口继续使用单个 LaTeX 字符串，不修改 Controller、Repository 或后端协议。
- 没有连续下划线时在题干后追加紧凑答案框，不能阻断作答。
- 只修改练习模块文件，并保护工作区中其他未提交改动。

---

### Task 1: 题干内嵌数学答案编辑器

**Files:**
- Modify: `test/features/practice_assessment/math_answer_field_test.dart`
- Modify: `test/features/practice_assessment/practice_assessment_lab_page_test.dart`
- Modify: `lib/features/practice_assessment/presentation/math_answer_field.dart`
- Modify: `lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart`

**Interfaces:**
- Consumes: `MathAnswerField(questionId, value, enabled, onChanged, controller)` 与 `PracticeQuestion.prompt`
- Produces: 新增可选参数 `String? prompt`；`prompt != null` 时输出题干前文、内嵌公式框和题干后文，LaTeX 仍通过 `ValueChanged<String> onChanged` 返回。

- [ ] **Step 1: 写题干内嵌布局的失败测试**

在 `math_answer_field_test.dart` 构造：

```dart
MathAnswerField(
  questionId: 'q12',
  prompt: '双曲线的离心率为______。',
  value: '',
  enabled: true,
  onChanged: values.add,
)
```

断言 `practice-fill-blank-prompt-before`、`practice-math-answer-input`、`practice-fill-blank-prompt-after` 各一个，完整的 `______` 文本不存在；再点击输入框并通过公式键盘输入 `3/2`，断言回调得到 LaTeX 且键盘位于内嵌行下方。

- [ ] **Step 2: 写页面不再渲染重复答案框的失败测试**

进入第 12 题，断言只存在一个 `practice-math-answer-input`，题干的下划线不再作为普通文本显示，点击输入框后 `practice-formula-keyboard` 出现。

- [ ] **Step 3: 运行目标测试并确认 RED**

Run:

```powershell
flutter test test/features/practice_assessment/math_answer_field_test.dart test/features/practice_assessment/practice_assessment_lab_page_test.dart
```

Expected: FAIL，原因是 `MathAnswerField` 尚无 `prompt` 参数和题干片段 key。

- [ ] **Step 4: 实现最小内嵌模式**

在 `MathAnswerField` 增加：

```dart
final String? prompt;
```

用 `RegExp(r'_{3,}')` 只拆分首个占位符；内嵌模式使用 `Wrap(crossAxisAlignment: WrapCrossAlignment.center)` 依次绘制前文、受限宽度的现有 `MathField` 和后文。答案框宽度按 LaTeX 长度在 88–260 像素间调整。无占位符时把全部题干作为前文，答案框追加在末尾。键盘仍作为外层 `Column` 的后续子项，因此保持页面宽度。

在 `_QuestionCard` 中：填空题跳过原来的独立 `Text(question.prompt)`，改为调用：

```dart
MathAnswerField(
  questionId: question.id,
  prompt: question.prompt,
  value: draft.answer,
  enabled: !isSubmitting,
  onChanged: onAnswer,
)
```

- [ ] **Step 5: 运行目标测试并确认 GREEN**

Run:

```powershell
flutter test test/features/practice_assessment/math_answer_field_test.dart test/features/practice_assessment/practice_assessment_lab_page_test.dart
```

Expected: PASS，且没有 overflow 或异步异常。

- [ ] **Step 6: 运行练习模块回归、分析与 Web 构建**

Run:

```powershell
flutter test test/features/practice_assessment
flutter analyze lib/features/practice_assessment test/features/practice_assessment
flutter build web --debug --dart-define=APP_ENV=development --dart-define=ENABLE_DEVELOPER_TOOLS=true --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=PRACTICE_ASSESSMENT_REMOTE=false
```

Expected: 全部 exit 0；随后重启 5174 静态服务并打开 `/#/practice-assessment-lab` 手工检查第 12–14 题。

- [ ] **Step 7: 只提交本任务文件**

```powershell
git add lib/features/practice_assessment/presentation/math_answer_field.dart lib/features/practice_assessment/presentation/practice_assessment_lab_page.dart test/features/practice_assessment/math_answer_field_test.dart test/features/practice_assessment/practice_assessment_lab_page_test.dart docs/superpowers/plans/2026-08-14-practice-inline-fill-blank.md
git commit -m "feat(practice): embed fill blank answer in prompt"
```
