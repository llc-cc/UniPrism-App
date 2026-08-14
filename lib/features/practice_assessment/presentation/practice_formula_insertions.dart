import 'dart:ui' show Color;

import 'package:math_keyboard/math_keyboard.dart';
// math_keyboard 尚未公开公式树节点；复杂模板只能在本适配层集中接触内部 API。
// ignore: implementation_imports
import 'package:math_keyboard/src/foundation/node.dart';

import 'practice_formula_key_models.dart';

/// 公式函数参数的外部描述，避免目录直接依赖 math_keyboard 的内部类型。
enum PracticeFormulaArgument { braces, brackets, parentheses }

/// 插入一个不含可编辑槽位的 TeX 叶节点。
final class LeafFormulaInsertion implements PracticeFormulaInsertion {
  const LeafFormulaInsertion(this.value);

  final String value;

  @override
  void apply(MathFieldEditingController controller) =>
      controller.addLeaf(value);
}

/// 插入由 math_keyboard 原生支持的函数模板。
final class FunctionFormulaInsertion implements PracticeFormulaInsertion {
  const FunctionFormulaInsertion(this.command, this.arguments);

  final String command;
  final List<PracticeFormulaArgument> arguments;

  @override
  void apply(MathFieldEditingController controller) {
    controller.addFunction(
      command,
      arguments.map(_toTeXArgument).toList(growable: false),
    );
  }
}

/// 插入一对定界符，并把光标留在定界符之间。
final class PairFormulaInsertion implements PracticeFormulaInsertion {
  const PairFormulaInsertion(this.left, this.right);

  final String left;
  final String right;

  @override
  void apply(MathFieldEditingController controller) {
    controller
      ..addLeaf(left)
      ..addLeaf(right)
      ..goBack();
  }
}

/// 插入已经填好指数的幂，并在完成后回到主表达式。
final class FixedExponentFormulaInsertion implements PracticeFormulaInsertion {
  const FixedExponentFormulaInsertion(this.exponent);

  final String exponent;

  @override
  void apply(MathFieldEditingController controller) {
    final originalNode = controller.currentNode;
    controller.addFunction('^', const <TeXArg>[TeXArg.braces]);
    // 没有底数时 math_keyboard 会拒绝建幂；此时不能误把固定指数写进正文。
    if (identical(controller.currentNode, originalNode)) return;
    controller
      ..addLeaf(exponent)
      ..goNext();
  }
}

/// 插入相邻的上下标，并让学生从下标开始填写。
final class SubSuperscriptFormulaInsertion implements PracticeFormulaInsertion {
  const SubSuperscriptFormulaInsertion();

  @override
  void apply(MathFieldEditingController controller) {
    controller
      ..addFunction('_', const <TeXArg>[TeXArg.braces])
      ..goNext()
      ..addFunction('^', const <TeXArg>[TeXArg.braces])
      ..goBack()
      ..goBack();
  }
}

/// 插入若干可编辑槽位与固定 TeX 片段交错组成的模板。
final class CompositeFormulaInsertion implements PracticeFormulaInsertion {
  const CompositeFormulaInsertion(this.pieces);

  /// n 个槽位由 n + 1 个固定片段围住。
  final List<String> pieces;

  @override
  void apply(MathFieldEditingController controller) {
    assert(pieces.length >= 2, '复合公式至少需要一个可编辑槽位。');
    final parent = controller.currentNode;
    parent.removeCursor();
    final function = _CompositeTeXFunction(parent: parent, pieces: pieces);
    parent.addTeX(function);
    controller.currentNode = function.argNodes.first..setCursor();
    // 公式树的公开控制器没有“插入自定义节点”入口，集中在适配层触发刷新。
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    controller.notifyListeners();
  }
}

/// 插入物理单位；仅在数值或结构后补薄空格，空输入不制造前导间距。
final class UnitFormulaInsertion implements PracticeFormulaInsertion {
  const UnitFormulaInsertion(this.latex);

  final String latex;

  @override
  void apply(MathFieldEditingController controller) {
    final current = controller
        .currentEditingValue(placeholderWhenEmpty: false)
        .replaceAll(' ', '');
    if (RegExp(r'(?:\d|\})$').hasMatch(current)) controller.addLeaf(r'\,');
    controller.addLeaf(latex);
  }
}

/// 将系统输入法产生的普通文本安全写入当前公式光标。
void insertPracticeFormulaText(
  MathFieldEditingController controller,
  String value,
) {
  if (value.isEmpty) return;
  const escapedCharacters = <String, String>{
    r'\': r'\backslash{}',
    '{': r'\{',
    '}': r'\}',
    '%': r'\%',
    '_': r'\_',
    '#': r'\#',
    r'$': r'\$',
    '&': r'\&',
    '^': r'\^{}',
    '~': r'\~{}',
  };
  final escaped = value
      .split('')
      .map((character) => escapedCharacters[character] ?? character)
      .join();
  controller.addLeaf('\\text{$escaped}');
}

TeXArg _toTeXArgument(PracticeFormulaArgument argument) => switch (argument) {
  PracticeFormulaArgument.braces => TeXArg.braces,
  PracticeFormulaArgument.brackets => TeXArg.brackets,
  PracticeFormulaArgument.parentheses => TeXArg.parentheses,
};

/// math_keyboard 原生函数只能把参数依次放在表达式末尾，本节点补足交错片段能力。
final class _CompositeTeXFunction extends TeXFunction {
  _CompositeTeXFunction({required TeXNode parent, required this.pieces})
    : super('', parent, List<TeXArg>.filled(pieces.length - 1, TeXArg.braces));

  final List<String> pieces;

  @override
  String buildString({Color? cursorColor}) {
    final buffer = StringBuffer(pieces.first);
    for (var index = 0; index < argNodes.length; index++) {
      buffer
        ..write(argNodes[index].buildTeXString(cursorColor: cursorColor))
        ..write(pieces[index + 1]);
    }
    return buffer.toString();
  }
}
