import 'package:flutter_math_fork/flutter_math.dart';
import 'package:math_keyboard/math_keyboard.dart';

import 'practice_formula_config.dart';

/// 语音候选的前端安全检查结果；服务端恢复后仍需保留这层纵深防护。
final class PracticeFormulaLatexValidation {
  const PracticeFormulaLatexValidation._({
    required this.isValid,
    this.errorMessage,
  });

  const PracticeFormulaLatexValidation.valid() : this._(isValid: true);

  const PracticeFormulaLatexValidation.invalid(String message)
    : this._(isValid: false, errorMessage: message);

  final bool isValid;
  final String? errorMessage;
}

const Set<String> _allowedCommands = <String>{
  'frac',
  'sqrt',
  'int',
  'sum',
  'lim',
  'to',
  'infty',
  'cdot',
  'times',
  'div',
  'left',
  'right',
  'mathrm',
  'sin',
  'cos',
  'tan',
  'ln',
  'log',
  'pi',
  'theta',
  'alpha',
  'beta',
  'gamma',
  'Delta',
  'Omega',
  'partial',
  'nabla',
};

PracticeFormulaLatexValidation validatePracticeFormulaLatex(String latex) {
  final value = latex.trim();
  if (value.isEmpty) {
    return const PracticeFormulaLatexValidation.invalid('公式内容不能为空。');
  }
  if (value.length > practiceFormulaAnswerMaxLength) {
    return const PracticeFormulaLatexValidation.invalid('公式内容过长。');
  }
  for (final match in RegExp(r'\\([A-Za-z]+)').allMatches(value)) {
    if (!_allowedCommands.contains(match.group(1))) {
      return const PracticeFormulaLatexValidation.invalid('公式包含初版不支持的命令。');
    }
  }
  if (!_hasBalancedDelimiters(value)) {
    return const PracticeFormulaLatexValidation.invalid('公式括号结构不完整。');
  }
  try {
    if (Math.tex(value).parseError != null) {
      return const PracticeFormulaLatexValidation.invalid('公式暂时无法排版。');
    }
  } catch (_) {
    return const PracticeFormulaLatexValidation.invalid('公式暂时无法排版。');
  }
  return const PracticeFormulaLatexValidation.valid();
}

/// 校验成功后把候选作为原子表达式插入当前光标，失败时不得部分修改答案。
void insertValidatedPracticeFormulaLatex(
  MathFieldEditingController controller,
  String latex,
) {
  final validation = validatePracticeFormulaLatex(latex);
  if (!validation.isValid) {
    throw ArgumentError.value(latex, 'latex', validation.errorMessage);
  }
  controller.addLeaf(latex.trim());
}

bool _hasBalancedDelimiters(String value) {
  final stack = <String>[];
  const pairs = <String, String>{')': '(', ']': '[', '}': '{'};
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    if (character == '(' || character == '[' || character == '{') {
      stack.add(character);
      continue;
    }
    final expected = pairs[character];
    if (expected == null) continue;
    if (stack.isEmpty || stack.removeLast() != expected) return false;
  }
  return stack.isEmpty;
}
