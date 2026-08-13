# Practice Formula Keyboard Two-Zone Implementation Plan

> **For Codex:** Use `superpowers:executing-plans` to implement this plan task by task with TDD checkpoints.

**Goal:** 将练习填空题键盘改为稳定的两区式布局，并保证数字、运算符、函数与关系符号写入正确、可继续编辑的 LaTeX。

**Architecture:** `MathAnswerField` 继续负责输入框、焦点和草稿回传；`PracticeFormulaKeyboard` 只负责键位目录、响应式布局和编辑树动作。数字区保持固定 4×4，辅助区按标签切换，所有按键通过 `MathFieldEditingController` 修改同一编辑树，不改变后端或草稿协议。

**Tech Stack:** Flutter, `math_keyboard` 0.3.3, `flutter_math_fork`, Flutter widget tests.

---

### Task 1: Lock the keyboard contract with failing widget tests

**Files:**
- Create: `test/features/practice_assessment/practice_formula_keyboard_test.dart`

1. 编写测试，断言 375px 与桌面宽度下数字区均按 `789÷ / 456× / 123− / 0.=+` 四行排列。
2. 编写测试，断言切换“函数”“符号”标签后数字区仍可见。
3. 编写测试，真实点击平方、任意次幂、下标、根式、函数及代表性关系符号，并读取 controller 的无定界符 LaTeX。
4. 运行目标测试并确认因当前统一网格、缺失键位或错误动作而失败。

### Task 2: Implement correct key actions and the two-zone layout

**Files:**
- Modify: `lib/features/practice_assessment/presentation/practice_formula_keyboard.dart`

1. 将键位分为固定数字区和三个辅助目录，补齐 `a/b/c`、下标、约等、子集等于、垂直、极限、求和与积分。
2. 结构键使用 `addFunction` 及 `TeXArg` 创建可导航槽位；普通符号仅写入约定的 LaTeX 命令。
3. 宽屏并排显示辅助区与数字区，窄屏上下堆叠；数字区始终使用固定 4×4 网格。
4. 保持光标左右、退格和确认位于独立操作行，并补充必要的中文边界注释。
5. 格式化代码，运行目标测试直到通过。

### Task 3: Regression, build and handoff

**Files:**
- Modify if necessary: `test/features/practice_assessment/math_answer_field_test.dart`

1. 运行练习公式输入相关测试及整个 `practice_assessment` 测试目录。
2. 运行 `flutter analyze`，确认没有新增静态问题。
3. 使用 Remote 配置重新构建 Flutter Web，并确认 `#/practice-assessment-lab` 可加载新键盘。
4. 仅提交本次键盘相关文件，记录验证结果与已知限制。
