import 'package:flutter/material.dart';
import 'package:math_keyboard/math_keyboard.dart';
// math_keyboard 的公开 controller 方法暴露了 TeXArg，但主入口没有转出该类型。
// ignore: implementation_imports
import 'package:math_keyboard/src/foundation/node.dart';

enum PracticeFormulaKeyboardTab { common, functions, relations }

/// 基于 math_keyboard 编辑树的 UniPrism 浅色键盘；键位目录与页面样式由 App 控制。
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
  PracticeFormulaKeyboardTab _tab = PracticeFormulaKeyboardTab.common;

  List<_FormulaKey> get _keys => switch (_tab) {
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
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final columnCount = constraints.maxWidth < 520 ? 5 : 8;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: columnCount,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: constraints.maxWidth < 520 ? 1.28 : 1.45,
                children: [for (final key in _keys) _keyButton(key)],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
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
                  onPressed: widget.controller.goNext,
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
          ),
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
        child: Text(
          key.label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
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
  const _FormulaKey(this.id, this.label, this.semanticLabel, this.action);

  final String id;
  final String label;
  final String semanticLabel;
  final _FormulaAction action;
}

_FormulaAction _leaf(String value) =>
    (controller) => controller.addLeaf(value);

final List<_FormulaKey> _commonKeys = <_FormulaKey>[
  _FormulaKey('7', '7', '数字 7', _leaf('7')),
  _FormulaKey('8', '8', '数字 8', _leaf('8')),
  _FormulaKey('9', '9', '数字 9', _leaf('9')),
  _FormulaKey('plus', '+', '加号', _leaf('+')),
  _FormulaKey('minus', '−', '减号', _leaf('-')),
  _FormulaKey('4', '4', '数字 4', _leaf('4')),
  _FormulaKey('5', '5', '数字 5', _leaf('5')),
  _FormulaKey('6', '6', '数字 6', _leaf('6')),
  _FormulaKey('multiply', '×', '乘号', _leaf(r'\times ')),
  _FormulaKey('divide', '÷', '除号', _leaf(r'\div ')),
  _FormulaKey('1', '1', '数字 1', _leaf('1')),
  _FormulaKey('2', '2', '数字 2', _leaf('2')),
  _FormulaKey('3', '3', '数字 3', _leaf('3')),
  _FormulaKey('equals', '=', '等号', _leaf('=')),
  _FormulaKey('decimal', '.', '小数点', _leaf('.')),
  _FormulaKey('0', '0', '数字 0', _leaf('0')),
  _FormulaKey(
    'fraction',
    'a/b',
    '插入分式',
    (controller) =>
        controller.addFunction(r'\frac', const [TeXArg.braces, TeXArg.braces]),
  ),
  _FormulaKey(
    'square',
    'x²',
    '插入平方',
    (controller) => controller.addFunction('^2', const [TeXArg.braces]),
  ),
  _FormulaKey(
    'sqrt',
    '√',
    '插入平方根',
    (controller) => controller.addFunction(r'\sqrt', const [TeXArg.braces]),
  ),
  _FormulaKey('pi', 'π', '圆周率', _leaf(r'\pi ')),
];

final List<_FormulaKey> _functionKeys = <_FormulaKey>[
  _FormulaKey('x', 'x', '变量 x', _leaf('x')),
  _FormulaKey('y', 'y', '变量 y', _leaf('y')),
  _FormulaKey('z', 'z', '变量 z', _leaf('z')),
  _FormulaKey('n', 'n', '变量 n', _leaf('n')),
  _FormulaKey('e', 'e', '自然常数 e', _leaf('e')),
  _FormulaKey('left-paren', '(', '左括号', _leaf('(')),
  _FormulaKey('right-paren', ')', '右括号', _leaf(')')),
  _FormulaKey(
    'power',
    'xⁿ',
    '插入任意次幂',
    (controller) => controller.addFunction('^', const [TeXArg.braces]),
  ),
  _FormulaKey('absolute', '|x|', '绝对值', (controller) {
    controller.addLeaf('|');
    controller.addLeaf('|');
    controller.goBack();
  }),
  _FormulaKey('sin', 'sin', '正弦', _leaf(r'\sin(')),
  _FormulaKey('cos', 'cos', '余弦', _leaf(r'\cos(')),
  _FormulaKey('tan', 'tan', '正切', _leaf(r'\tan(')),
  _FormulaKey('log', 'log', '对数', _leaf(r'\log(')),
  _FormulaKey('ln', 'ln', '自然对数', _leaf(r'\ln(')),
  _FormulaKey('exp', 'eˣ', '指数函数', _leaf(r'e^')),
];

final List<_FormulaKey> _relationKeys = <_FormulaKey>[
  _FormulaKey('less', '<', '小于', _leaf('<')),
  _FormulaKey('greater', '>', '大于', _leaf('>')),
  _FormulaKey('less-equal', '≤', '小于等于', _leaf(r'\le ')),
  _FormulaKey('greater-equal', '≥', '大于等于', _leaf(r'\ge ')),
  _FormulaKey('not-equal', '≠', '不等于', _leaf(r'\ne ')),
  _FormulaKey('in', '∈', '属于', _leaf(r'\in ')),
  _FormulaKey('not-in', '∉', '不属于', _leaf(r'\notin ')),
  _FormulaKey('subset', '⊂', '子集', _leaf(r'\subset ')),
  _FormulaKey('union', '∪', '并集', _leaf(r'\cup ')),
  _FormulaKey('intersection', '∩', '交集', _leaf(r'\cap ')),
  _FormulaKey('empty-set', '∅', '空集', _leaf(r'\emptyset ')),
  _FormulaKey('infinity', '∞', '无穷', _leaf(r'\infty ')),
  _FormulaKey('plus-minus', '±', '正负号', _leaf(r'\pm ')),
  _FormulaKey('degree', '°', '度数', _leaf(r'^{\circ}')),
  _FormulaKey('parallel', '∥', '平行', _leaf(r'\parallel ')),
];
