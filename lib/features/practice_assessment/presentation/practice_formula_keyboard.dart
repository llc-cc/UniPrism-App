import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:math_keyboard/math_keyboard.dart';
// math_keyboard 的公开 controller 方法暴露了节点类型，但主入口没有转出。
// ignore: implementation_imports
import 'package:math_keyboard/src/foundation/node.dart';

import 'practice_formula_key_catalog.dart';

/// 高中数学与物理公式键盘。
///
/// 桌面端采用“分类栏 + 公式区 + 数字控制区”，窄屏将分类栏横置并纵向排列
/// 两个四列键区；所有按键动作来自受控目录，不改变练习草稿和后端协议。
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
  PracticeFormulaKeyboardCategory _category =
      PracticeFormulaKeyboardCategory.common;

  List<PracticeFormulaKeySpec> get _categoryKeys =>
      practiceFormulaCategoryKeys[_category]!;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('practice-formula-keyboard'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F9),
        border: Border.all(color: const Color(0xFFD3D9E4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _wideLayoutBreakpoint) {
            return _wideKeyboard(constraints.maxWidth);
          }
          return _narrowKeyboard();
        },
      ),
    );
  }

  Widget _wideKeyboard(double maxWidth) {
    final numericWidth = (maxWidth * 0.34).clamp(300.0, 360.0);
    return Row(
      key: const ValueKey('practice-formula-wide-layout'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 68, child: _verticalCategoryRail()),
        const SizedBox(width: 8),
        _verticalSeparator(),
        const SizedBox(width: 10),
        Expanded(child: _auxiliaryPad(isWide: true)),
        const SizedBox(width: 10),
        _verticalSeparator(),
        const SizedBox(width: 10),
        SizedBox(width: numericWidth, child: _numericControlPad(isWide: true)),
      ],
    );
  }

  Widget _narrowKeyboard() {
    return Column(
      key: const ValueKey('practice-formula-narrow-layout'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _horizontalCategoryRail(),
        const SizedBox(height: 10),
        _auxiliaryPad(isWide: false),
        const SizedBox(height: 10),
        const Divider(height: 1, color: Color(0xFFCCD3DF)),
        const SizedBox(height: 10),
        _numericControlPad(isWide: false),
      ],
    );
  }

  Widget _verticalSeparator() =>
      Container(width: 1, height: 320, color: const Color(0xFFCCD3DF));

  Widget _verticalCategoryRail() {
    return Column(
      key: const ValueKey('practice-formula-category-rail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final category in PracticeFormulaKeyboardCategory.values) ...[
          _categoryButton(category, isCompact: true),
          if (category != PracticeFormulaKeyboardCategory.values.last)
            const SizedBox(height: 3),
        ],
      ],
    );
  }

  Widget _horizontalCategoryRail() {
    return SingleChildScrollView(
      key: const ValueKey('practice-formula-category-scroll'),
      scrollDirection: Axis.horizontal,
      child: Row(
        key: const ValueKey('practice-formula-category-rail'),
        children: [
          for (final category in PracticeFormulaKeyboardCategory.values) ...[
            SizedBox(width: 66, child: _categoryButton(category)),
            if (category != PracticeFormulaKeyboardCategory.values.last)
              const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }

  Widget _categoryButton(
    PracticeFormulaKeyboardCategory category, {
    bool isCompact = false,
  }) {
    final selected = category == _category;
    final label = practiceFormulaCategoryLabels[category]!;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label 公式分类',
      child: TextButton(
        key: ValueKey('practice-formula-category-${category.name}'),
        onPressed: () => _selectCategory(category),
        style: TextButton.styleFrom(
          minimumSize: Size(0, isCompact ? 34 : 38),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          foregroundColor: selected ? Colors.white : const Color(0xFF3F4652),
          backgroundColor: selected
              ? const Color(0xFF6B23FF)
              : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  void _selectCategory(PracticeFormulaKeyboardCategory category) {
    if (category == _category) return;
    setState(() => _category = category);
  }

  Widget _auxiliaryPad({required bool isWide}) {
    return GridView.count(
      key: ValueKey('practice-formula-auxiliary-pad-${_category.name}'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      // 窄屏需同时容纳公式区和五行数字区，稍压缩键高避免挡住题干。
      childAspectRatio: isWide ? 1.55 : 1.58,
      children: [for (final key in _categoryKeys) _formulaKeyButton(key)],
    );
  }

  Widget _numericControlPad({required bool isWide}) {
    final numericKeys = practiceFormulaNumericKeys;
    return GridView.count(
      key: const ValueKey('practice-formula-numeric-pad'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: isWide ? 1.45 : 1.58,
      children: [
        _textActionButton(
          id: 'more-shortcut',
          label: 'abc',
          semanticLabel: '打开更多字母与逻辑符号',
          onPressed: () =>
              _selectCategory(PracticeFormulaKeyboardCategory.more),
          selected: _category == PracticeFormulaKeyboardCategory.more,
        ),
        _iconActionButton(
          id: 'previous',
          icon: Icons.chevron_left_rounded,
          label: '光标左移',
          onPressed: widget.controller.goBack,
        ),
        _iconActionButton(
          id: 'next',
          icon: Icons.chevron_right_rounded,
          label: '光标右移',
          onPressed: _goNext,
        ),
        _iconActionButton(
          id: 'delete',
          icon: Icons.backspace_outlined,
          label: '退格',
          onPressed: () => widget.controller.goBack(deleteMode: true),
        ),
        for (final key in numericKeys.take(12)) _formulaKeyButton(key),
        _formulaKeyButton(numericKeys[12]),
        _formulaKeyButton(numericKeys[13]),
        _formulaKeyButton(numericKeys[14]),
        _textActionButton(
          id: 'done',
          label: '确认',
          semanticLabel: '确认公式输入',
          onPressed: widget.onDone,
          emphasized: true,
        ),
      ],
    );
  }

  Widget _formulaKeyButton(PracticeFormulaKeySpec key) {
    return Semantics(
      button: true,
      label: key.semanticLabel,
      child: FilledButton(
        key: ValueKey('practice-formula-key-${key.id}'),
        onPressed: () => key.action(widget.controller),
        style: _keyButtonStyle(),
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

  Widget _iconActionButton({
    required String id,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: FilledButton(
        key: ValueKey('practice-formula-key-$id'),
        onPressed: onPressed,
        style: _keyButtonStyle(backgroundColor: const Color(0xFFE3E7EF)),
        child: Icon(icon, size: 22),
      ),
    );
  }

  Widget _textActionButton({
    required String id,
    required String label,
    required String semanticLabel,
    required VoidCallback onPressed,
    bool emphasized = false,
    bool selected = false,
  }) {
    final backgroundColor = emphasized
        ? const Color(0xFFFFC928)
        : selected
        ? const Color(0xFF8A66D9)
        : const Color(0xFFE3E7EF);
    final foregroundColor = selected ? Colors.white : const Color(0xFF252932);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: FilledButton(
        key: ValueKey('practice-formula-key-$id'),
        onPressed: onPressed,
        style: _keyButtonStyle(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  ButtonStyle _keyButtonStyle({
    Color backgroundColor = const Color(0xFFFAFBFD),
    Color foregroundColor = const Color(0xFF252932),
  }) {
    return FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFC8CFDA)),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  void _goNext() {
    widget.controller.goNext();
    final node = widget.controller.currentNode;
    final position = node.courserPosition;
    final previous = position > 0 ? node.children[position - 1] : null;
    final next = position + 1 < node.children.length
        ? node.children[position + 1]
        : null;
    // 上下限是相邻节点，跳出下限后再前进一步才能进入上限槽位。
    if (previous is TeXFunction &&
        next is TeXFunction &&
        previous.expression.endsWith('_') &&
        next.expression == '^') {
      widget.controller.goNext();
    }
  }
}
