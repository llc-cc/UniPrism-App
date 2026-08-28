# 练习公式键盘分类面板 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建参考图式的分类公式面板，并补齐高中数学、物理与单位的受控 LaTeX 键位。

**Architecture:** 新建键位目录文件，集中声明八个类别、公式键和编辑动作；现有 `PracticeFormulaKeyboard` 缩减为分类状态、响应式布局和按键渲染。桌面使用左分类/中公式/右数字三栏，窄屏改为分类横向滚动并纵向排列两个四列网格。

**Tech Stack:** Flutter、`math_keyboard`、`flutter_math_fork`、Flutter Widget Test

## Global Constraints

- 继续使用 `MathFieldEditingController`，不改变草稿、提交或后端协议。
- `=` 只存在于“常用”类别，右侧数字区不得重复出现。
- 所有按键产生静态受控 LaTeX，不能由显示文字动态拼命令。
- 375px 与桌面宽度都不得出现布局溢出。
- 只提交本任务文件，保护工作区其他未提交改动。

---

### Task 1: 可审计的公式键位目录

**Files:**
- Create: `lib/features/practice_assessment/presentation/practice_formula_key_catalog.dart`
- Create: `test/features/practice_assessment/practice_formula_key_catalog_test.dart`

**Interfaces:**
- Produces: `PracticeFormulaKeyboardCategory`、`PracticeFormulaKeySpec`、`practiceFormulaCategoryLabels`、`practiceFormulaCategoryKeys`、`practiceFormulaNumericKeys`
- `PracticeFormulaKeySpec.action` 接收 `MathFieldEditingController` 并写入受控 LaTeX。

- [ ] **Step 1: 写目录完整性与 LaTeX 行为的失败测试**

测试八个类别恰好为 `common/structures/symbols/functions/greek/physics/units/more`；符号页前六项为 `less-equal, greater-equal, not-equal, in, union, intersection`；全目录只有一个 `equals`；希腊页包含 `alpha beta gamma theta pi`。直接执行 `alpha`、`vector-force`、`unit-metre` 动作，分别断言 `\alpha`、`\vec{F}`、`5\,\mathrm{m}`。

- [ ] **Step 2: 运行目录测试并确认 RED**

```powershell
flutter test test/features/practice_assessment/practice_formula_key_catalog_test.dart
```

Expected: FAIL，因为目录文件和公开类型尚不存在。

- [ ] **Step 3: 实现键位目录**

创建公开枚举和键位规格：

```dart
enum PracticeFormulaKeyboardCategory {
  common, structures, symbols, functions, greek, physics, units, more,
}

final class PracticeFormulaKeySpec {
  const PracticeFormulaKeySpec(
    this.id,
    this.label,
    this.semanticLabel,
    this.action, {
    this.isTexLabel = false,
  });
}
```

从旧文件迁移分式、根式、上下限与光标槽位动作，补充希腊、物理、单位、逻辑和数集键。单位动作读取当前 LaTeX，仅当前内容以数字或右花括号结尾时前置 `\,`。

- [ ] **Step 4: 运行目录测试并确认 GREEN**

```powershell
flutter test test/features/practice_assessment/practice_formula_key_catalog_test.dart
```

Expected: PASS。

---

### Task 2: 参考图式响应式键盘

**Files:**
- Modify: `lib/features/practice_assessment/presentation/practice_formula_keyboard.dart`
- Modify: `test/features/practice_assessment/practice_formula_keyboard_test.dart`
- Test: `test/features/practice_assessment/math_answer_field_test.dart`

**Interfaces:**
- Consumes: Task 1 的键位目录与 `PracticeFormulaKeyboard(controller, onDone)`。
- Produces: 稳定测试 key：`practice-formula-category-<id>`、`practice-formula-category-rail`、`practice-formula-auxiliary-pad-<id>`、`practice-formula-numeric-pad`。

- [ ] **Step 1: 写桌面三栏与右侧五行的失败测试**

在 1100px 宽度断言分类栏在公式区左侧、数字区在公式区右侧；断言右侧五行依次为 `more-shortcut/previous/next/delete`、`7/8/9/divide`、`4/5/6/multiply`、`1/2/3/minus`、`0/decimal/plus/done`；断言页面中只有一个 `equals`。

- [ ] **Step 2: 写分类切换、窄屏和确认行为的失败测试**

点击希腊分类后断言 `alpha beta gamma theta pi` 可见；点击符号分类后断言前排六个高频符号的位置先于 `parallel/perpendicular/degree`；375px 下切换所有分类均无异常；点击 `done` 只调用一次 `onDone`。

- [ ] **Step 3: 运行键盘测试并确认 RED**

```powershell
flutter test test/features/practice_assessment/practice_formula_keyboard_test.dart
```

Expected: FAIL，因为旧键盘仍使用顶部三个标签和底部操作栏。

- [ ] **Step 4: 实现桌面和窄屏布局**

桌面端使用：

```dart
Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    SizedBox(width: 68, child: categoryRail),
    const VerticalDivider(width: 18),
    Expanded(child: auxiliaryGrid),
    const VerticalDivider(width: 18),
    SizedBox(width: 320, child: numericControlGrid),
  ],
)
```

窄屏将分类栏替换为横向 `SingleChildScrollView`，随后显示两个四列网格。确认键使用黄色强调色；选中分类使用品牌紫色；`abc` 切换 `more`。

- [ ] **Step 5: 运行目标测试并确认 GREEN**

```powershell
flutter test test/features/practice_assessment/practice_formula_key_catalog_test.dart test/features/practice_assessment/practice_formula_keyboard_test.dart test/features/practice_assessment/math_answer_field_test.dart
```

Expected: PASS，且没有 overflow 或异步异常。

- [ ] **Step 6: 运行完整验证并构建无缓存 Web**

```powershell
flutter test
flutter analyze lib/main.dart lib/features/practice_assessment test
flutter build web --debug --pwa-strategy=none --dart-define=APP_ENV=development --dart-define=ENABLE_DEVELOPER_TOOLS=true --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=PRACTICE_ASSESSMENT_REMOTE=false
```

Expected: 全部 exit 0；在新端口启动 `build/web` 并打开第 12 题测试。

- [ ] **Step 7: 只提交任务文件**

```powershell
git add lib/features/practice_assessment/presentation/practice_formula_key_catalog.dart lib/features/practice_assessment/presentation/practice_formula_keyboard.dart test/features/practice_assessment/practice_formula_key_catalog_test.dart test/features/practice_assessment/practice_formula_keyboard_test.dart
git commit -m "feat(practice): redesign categorized formula keyboard"
```
