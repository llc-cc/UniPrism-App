import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:math_keyboard/math_keyboard.dart';
// math_keyboard 的公开 controller 方法暴露了 TeXArg，但主入口没有转出该类型。
// ignore: implementation_imports
import 'package:math_keyboard/src/foundation/node.dart';

enum PracticeFormulaKeyboardTab { common, functions, relations }

/// 基于 math_keyboard 编辑树的两区式公式键盘。
///
/// 数字区始终保持四行四列，辅助区才随标签切换，避免响应式重排破坏学生的
/// 键位记忆；按键只生成受控 LaTeX，不改变练习草稿和后端协议。
final class PracticeFormulaKeyboard extends StatefulWidget {
  const PracticeFormulaKeyboard({
    super.key,
    required this.controller,
    required this.onDone,
  });

  final MathFieldEditingController controller;
  final VoidCallback onDone;

  @override
  State<PracticeFormulaKeyboard> createState() =>
      _PracticeFormulaKeyboardState();
}

final class _PracticeFormulaKeyboardState
    extends State<PracticeFormulaKeyboard> {
  static const double _wideLayoutBreakpoint = 720;
  PracticeFormulaKeyboardTab _tab = PracticeFormulaKeyboardTab.common;

  List<_FormulaKey> get _auxiliaryKeys => switch (_tab) {
    PracticeFormulaKeyboardTab.common => _commonKeys,
    PracticeFormulaKeyboardTab.functions => _functionKeys,
    PracticeFormulaKeyboardTab.relations => _relationKeys,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('practice-formula-keyboard'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFDCE1EA),
        border: Border.all(color: const Color(0xFFC6CDD9)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tabBar(),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= _wideLayoutBreakpoint) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _auxiliaryPad(isWide: true)),
                    const SizedBox(width: 12),
                    SizedBox(width: 360, child: _numericPad(isWide: true)),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _auxiliaryPad(isWide: false),
                  const SizedBox(height: 10),
                  _numericPad(isWide: false),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          _actionRow(),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Row(
      children: [
        Expanded(
          child: _tabButton(PracticeFormulaKeyboardTab.common, '123', 'common'),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _tabButton(
            PracticeFormulaKeyboardTab.functions,
            '函数',
            'functions',
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _tabButton(
            PracticeFormulaKeyboardTab.relations,
            '符号',
            'relations',
          ),
        ),
      ],
    );
  }

  Widget _tabButton(PracticeFormulaKeyboardTab tab, String label, String id) {
    final selected = _tab == tab;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label 键盘页',
      child: TextButton(
        key: ValueKey('practice-formula-tab-$id'),
        onPressed: () => setState(() => _tab = tab),
        style: TextButton.styleFrom(
          foregroundColor: selected ? Colors.white : const Color(0xFF3F4652),
          backgroundColor: selected
              ? const Color(0xFF6B23FF)
              : const Color(0xFFF4F6F9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _auxiliaryPad({required bool isWide}) {
    return GridView.count(
      key: ValueKey('practice-formula-auxiliary-pad-${_tab.name}'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isWide ? 5 : 4,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: isWide ? 1.45 : 1.34,
      children: [for (final key in _auxiliaryKeys) _keyButton(key)],
    );
  }

  Widget _numericPad({required bool isWide}) {
    return GridView.count(
      key: const ValueKey('practice-formula-numeric-pad'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: isWide ? 1.45 : 1.4,
      children: [for (final key in _numericKeys) _keyButton(key)],
    );
  }

  Widget _keyButton(_FormulaKey key) {
    return Semantics(
      button: true,
      label: key.semanticLabel,
      child: FilledButton(
        key: ValueKey('practice-formula-key-${key.id}'),
        onPressed: () => key.action(widget.controller),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          foregroundColor: const Color(0xFF252932),
          backgroundColor: const Color(0xFFFAFBFD),
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFC8CFDA)),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: key.isTexLabel
              ? Math.tex(
                  key.label,
                  mathStyle: MathStyle.text,
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Text(
                  key.label,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _actionRow() {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            id: 'previous',
            icon: Icons.chevron_left_rounded,
            label: '光标左移',
            onPressed: widget.controller.goBack,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _actionButton(
            id: 'next',
            icon: Icons.chevron_right_rounded,
            label: '光标右移',
            onPressed: _goNext,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _actionButton(
            id: 'delete',
            icon: Icons.backspace_outlined,
            label: '退格',
            onPressed: () => widget.controller.goBack(deleteMode: true),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _actionButton(
            id: 'done',
            icon: Icons.keyboard_return_rounded,
            label: '确认',
            onPressed: widget.onDone,
            emphasized: true,
          ),
        ),
      ],
    );
  }

  void _goNext() {
    widget.controller.goNext();
    final node = widget.controller.currentNode;
    final position = node.courserPosition;
    // math_keyboard 将上下限保存为相邻的下标和上标节点。退出下标后光标
    // 位于两者之间，因此再前进一步，让学生一次点击即可进入上限槽位。
    final previous = position > 0 ? node.children[position - 1] : null;
    // 当前编辑树会把 Cursor 放在 children[position]，真正的右侧节点位于
    // position + 1；不能把 cursor 当成上标节点，否则数字会落在两者之间。
    final next = position + 1 < node.children.length
        ? node.children[position + 1]
        : null;
    if (previous is TeXFunction &&
        next is TeXFunction &&
        previous.expression.endsWith('_') &&
        next.expression == '^') {
      widget.controller.goNext();
    }
  }

  Widget _actionButton({
    required String id,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool emphasized = false,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: IconButton.filled(
        key: ValueKey('practice-formula-key-$id'),
        onPressed: onPressed,
        tooltip: label,
        style: IconButton.styleFrom(
          foregroundColor: emphasized ? Colors.white : const Color(0xFF252932),
          backgroundColor: emphasized
              ? const Color(0xFF6B23FF)
              : const Color(0xFFAAB4C4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: Icon(icon),
      ),
    );
  }
}

typedef _FormulaAction = void Function(MathFieldEditingController controller);

final class _FormulaKey {
  const _FormulaKey(
    this.id,
    this.label,
    this.semanticLabel,
    this.action, {
    this.isTexLabel = false,
  });

  final String id;
  final String label;
  final String semanticLabel;
  final _FormulaAction action;
  final bool isTexLabel;
}

_FormulaAction _leaf(String value) =>
    (controller) => controller.addLeaf(value);

_FormulaAction _function(String command) =>
    (controller) => controller.addFunction(command, const [TeXArg.parentheses]);

void _insertAbsoluteValue(MathFieldEditingController controller) {
  // math_keyboard 没有成对定界符节点；使用受控的 left/right 叶子并把
  // 光标移回中间，既生成合法 LaTeX，也不会允许注入任意命令。
  controller.addLeaf(r'\left|');
  controller.addLeaf(r'\right|');
  controller.goBack();
}

void _insertExponential(MathFieldEditingController controller) {
  controller.addLeaf('e');
  controller.addFunction('^', const [TeXArg.braces]);
}

void _insertBoundedOperator(
  MathFieldEditingController controller,
  String command,
) {
  controller.addFunction('${command}_', const [TeXArg.braces]);
  controller.goNext();
  controller.addFunction('^', const [TeXArg.braces]);
  // 默认回到下限；操作行会把“一次右移”补偿为直接进入上限。
  controller.goBack();
  controller.goBack();
}

final List<_FormulaKey> _numericKeys = <_FormulaKey>[
  _FormulaKey('7', '7', '数字 7', _leaf('7')),
  _FormulaKey('8', '8', '数字 8', _leaf('8')),
  _FormulaKey('9', '9', '数字 9', _leaf('9')),
  _FormulaKey('divide', '÷', '除号', _leaf(r'\div ')),
  _FormulaKey('4', '4', '数字 4', _leaf('4')),
  _FormulaKey('5', '5', '数字 5', _leaf('5')),
  _FormulaKey('6', '6', '数字 6', _leaf('6')),
  _FormulaKey('multiply', '×', '乘号', _leaf(r'\times ')),
  _FormulaKey('1', '1', '数字 1', _leaf('1')),
  _FormulaKey('2', '2', '数字 2', _leaf('2')),
  _FormulaKey('3', '3', '数字 3', _leaf('3')),
  _FormulaKey('minus', '−', '减号', _leaf('-')),
  _FormulaKey('0', '0', '数字 0', _leaf('0')),
  _FormulaKey('decimal', '.', '小数点', _leaf('.')),
  _FormulaKey('equals', '=', '等号', _leaf('=')),
  _FormulaKey('plus', '+', '加号', _leaf('+')),
];

final List<_FormulaKey> _commonKeys = <_FormulaKey>[
  _FormulaKey('left-paren', '(', '左括号', _leaf('(')),
  _FormulaKey('right-paren', ')', '右括号', _leaf(')')),
  _FormulaKey(
    'fraction',
    r'\frac{\Box}{\Box}',
    '插入分式',
    (controller) =>
        controller.addFunction(r'\frac', const [TeXArg.braces, TeXArg.braces]),
    isTexLabel: true,
  ),
  _FormulaKey(
    'square',
    r'\Box^2',
    '插入平方',
    (controller) => controller.addFunction('^2', const [TeXArg.braces]),
    isTexLabel: true,
  ),
  _FormulaKey(
    'power',
    r'\Box^{\Box}',
    '插入任意次幂',
    (controller) => controller.addFunction('^', const [TeXArg.braces]),
    isTexLabel: true,
  ),
  _FormulaKey(
    'sqrt',
    r'\sqrt{\Box}',
    '插入平方根',
    (controller) => controller.addFunction(r'\sqrt', const [TeXArg.braces]),
    isTexLabel: true,
  ),
  _FormulaKey('pi', 'π', '圆周率', _leaf(r'\pi ')),
  _FormulaKey('e', 'e', '自然常数 e', _leaf('e')),
];

final List<_FormulaKey> _functionKeys = <_FormulaKey>[
  _FormulaKey('x', 'x', '变量 x', _leaf('x')),
  _FormulaKey('y', 'y', '变量 y', _leaf('y')),
  _FormulaKey('z', 'z', '变量 z', _leaf('z')),
  _FormulaKey('a', 'a', '变量 a', _leaf('a')),
  _FormulaKey('b', 'b', '变量 b', _leaf('b')),
  _FormulaKey('c', 'c', '变量 c', _leaf('c')),
  _FormulaKey('n', 'n', '变量 n', _leaf('n')),
  _FormulaKey(
    'subscript',
    r'\Box_{\Box}',
    '插入下标',
    (controller) => controller.addFunction('_', const [TeXArg.braces]),
    isTexLabel: true,
  ),
  _FormulaKey('absolute', '|x|', '插入绝对值', _insertAbsoluteValue),
  _FormulaKey('sin', 'sin', '正弦函数', _function(r'\sin')),
  _FormulaKey('cos', 'cos', '余弦函数', _function(r'\cos')),
  _FormulaKey('tan', 'tan', '正切函数', _function(r'\tan')),
  _FormulaKey('log', 'log', '对数函数', _function(r'\log')),
  _FormulaKey('ln', 'ln', '自然对数函数', _function(r'\ln')),
  _FormulaKey('exp', r'e^{\Box}', '指数函数', _insertExponential, isTexLabel: true),
  _FormulaKey(
    'limit',
    r'\lim_{\Box}',
    '插入极限下标',
    (controller) => controller.addFunction(r'\lim_', const [TeXArg.braces]),
    isTexLabel: true,
  ),
  _FormulaKey(
    'sum',
    r'\sum_{\Box}^{\Box}',
    '插入求和上下限',
    (controller) => _insertBoundedOperator(controller, r'\sum'),
    isTexLabel: true,
  ),
  _FormulaKey(
    'integral',
    r'\int_{\Box}^{\Box}',
    '插入积分上下限',
    (controller) => _insertBoundedOperator(controller, r'\int'),
    isTexLabel: true,
  ),
];

final List<_FormulaKey> _relationKeys = <_FormulaKey>[
  _FormulaKey('less', '<', '小于', _leaf('<')),
  _FormulaKey('greater', '>', '大于', _leaf('>')),
  _FormulaKey('less-equal', '≤', '小于等于', _leaf(r'\le ')),
  _FormulaKey('greater-equal', '≥', '大于等于', _leaf(r'\ge ')),
  _FormulaKey('relation-equals', '=', '等于', _leaf('=')),
  _FormulaKey('not-equal', '≠', '不等于', _leaf(r'\ne ')),
  _FormulaKey('approx', '≈', '约等于', _leaf(r'\approx ')),
  _FormulaKey('plus-minus', '±', '正负号', _leaf(r'\pm ')),
  _FormulaKey('in', '∈', '属于', _leaf(r'\in ')),
  _FormulaKey('not-in', '∉', '不属于', _leaf(r'\notin ')),
  _FormulaKey('subset', '⊂', '真子集', _leaf(r'\subset ')),
  _FormulaKey('subset-equal', '⊆', '子集或相等', _leaf(r'\subseteq ')),
  _FormulaKey('union', '∪', '并集', _leaf(r'\cup ')),
  _FormulaKey('intersection', '∩', '交集', _leaf(r'\cap ')),
  _FormulaKey('empty-set', '∅', '空集', _leaf(r'\emptyset ')),
  _FormulaKey('infinity', '∞', '无穷', _leaf(r'\infty ')),
  _FormulaKey('parallel', '∥', '平行', _leaf(r'\parallel ')),
  _FormulaKey('perpendicular', '⊥', '垂直', _leaf(r'\perp ')),
  _FormulaKey('degree', '°', '角度', _leaf(r'^{\circ}')),
  _FormulaKey('arrow', '→', '趋向', _leaf(r'\to ')),
];
