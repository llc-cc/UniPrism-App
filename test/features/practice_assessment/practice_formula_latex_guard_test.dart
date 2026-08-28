import 'package:flutter_test/flutter_test.dart';
import 'package:math_keyboard/math_keyboard.dart';
import 'package:uniprism_app/features/practice_assessment/presentation/practice_formula_latex_guard.dart';

void main() {
  test('允许初版语音公式使用的数学命令', () {
    for (final latex in <String>[
      r'x^2+2x+1',
      r'\sqrt{x+1}',
      r'\frac{1}{2}mv^2',
      r'\int_0^1x^2\,dx',
      r'x\to\infty',
    ]) {
      expect(
        validatePracticeFormulaLatex(latex).isValid,
        isTrue,
        reason: latex,
      );
    }
  });

  test('拒绝宏定义、外部资源和未知命令', () {
    for (final latex in <String>[
      r'\def\x{1}',
      r'\newcommand{\x}{1}',
      r'\includegraphics{x}',
      r'\href{x}{y}',
      r'\unknown{x}',
    ]) {
      expect(
        validatePracticeFormulaLatex(latex).isValid,
        isFalse,
        reason: latex,
      );
    }
  });

  test('在当前光标插入通过校验的公式而不覆盖两侧内容', () {
    final controller = MathFieldEditingController()
      ..addLeaf('a')
      ..addLeaf('b')
      ..goBack();
    addTearDown(controller.dispose);

    insertValidatedPracticeFormulaLatex(controller, r'\frac{1}{2}');

    expect(
      controller.currentEditingValue(placeholderWhenEmpty: false),
      r'a\frac{1}{2}b',
    );
  });

  test('无效候选抛错且不修改原公式', () {
    final controller = MathFieldEditingController()..addLeaf('x');
    addTearDown(controller.dispose);

    expect(
      () => insertValidatedPracticeFormulaLatex(
        controller,
        r'\includegraphics{x}',
      ),
      throwsArgumentError,
    );
    expect(controller.currentEditingValue(placeholderWhenEmpty: false), 'x');
  });
}
