import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:math_keyboard/math_keyboard.dart';

import 'practice_formula_key_catalog.dart';

/// 初高中数学与物理公式键盘。
///
/// 桌面端把二级目录折叠在左侧所属一级分类下，窄屏则放在横向一级栏下一行。
/// 键位只消费目录元数据和受控插入策略，不改变练习草稿与后端的 LaTeX 字符串协议。
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
  // LayoutBuilder 位于 1px 边框和 10px 水平内边距内，698px 内容对应 720px 外宽。
  static const double _wideContentBreakpoint = 698;
  static const int _pageSize = 20;

  PracticeFormulaPrimaryCategory _primaryCategory =
      PracticeFormulaPrimaryCategory.common;
  PracticeFormulaSection _section = PracticeFormulaSection.lettersAndNumbers;
  bool _sectionsExpanded = true;
  bool _uppercaseLetters = false;
  int _pageIndex = 0;
  PracticeFormulaKeySpec? _hoveredKey;

  bool get _isAlphabet => _section == PracticeFormulaSection.lettersAndNumbers;

  List<PracticeFormulaKeySpec> get _sectionKeys =>
      practiceFormulaKeysForSection(
        _section,
        uppercaseLetters: _uppercaseLetters,
      );

  int get _pageCount => math.max(1, (_sectionKeys.length / _pageSize).ceil());

  bool get _hasPages => !_isAlphabet && _sectionKeys.length > _pageSize;

  List<PracticeFormulaKeySpec> get _visibleKeys {
    if (!_hasPages) return _sectionKeys;
    final start = _pageIndex * _pageSize;
    final end = math.min(start + _pageSize, _sectionKeys.length);
    return _sectionKeys.sublist(start, end);
  }

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth >= _wideContentBreakpoint
                    ? _wideKeyboard(constraints.maxWidth)
                    : _narrowKeyboard(),
          ),
          if (_hoveredKey case final hovered? when hovered.usage.isNotEmpty) ...[
            const SizedBox(height: 8),
            _keyTooltipCard(hovered),
          ],
        ],
      ),
    );
  }

  Widget _wideKeyboard(double maxWidth) {
    final numericWidth = (maxWidth * 0.34).clamp(300.0, 360.0);
    return Row(
      key: const ValueKey('practice-formula-wide-layout'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 112, child: _verticalPrimaryRail()),
        const SizedBox(width: 8),
        _verticalSeparator(),
        const SizedBox(width: 10),
        Expanded(child: _contentPad(isWide: true)),
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
        _horizontalPrimaryRail(),
        if (_sectionsExpanded) ...[
          const SizedBox(height: 6),
          _horizontalSectionPanel(),
        ],
        const SizedBox(height: 10),
        _contentPad(isWide: false),
        const SizedBox(height: 10),
        const Divider(height: 1, color: Color(0xFFCCD3DF)),
        const SizedBox(height: 10),
        _numericControlPad(isWide: false),
      ],
    );
  }

  Widget _verticalSeparator() =>
      Container(width: 1, height: 320, color: const Color(0xFFCCD3DF));

  Widget _verticalPrimaryRail() {
    return Column(
      key: const ValueKey('practice-formula-navigation-rail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final primary in PracticeFormulaPrimaryCategory.values) ...[
          _primaryButton(primary, compact: true),
          if (primary == _primaryCategory && _sectionsExpanded) ...[
            const SizedBox(height: 4),
            _verticalSectionPanel(),
          ],
          if (primary != PracticeFormulaPrimaryCategory.values.last)
            const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _horizontalPrimaryRail() {
    return SingleChildScrollView(
      key: const ValueKey('practice-formula-primary-scroll'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final primary in PracticeFormulaPrimaryCategory.values) ...[
            SizedBox(width: 92, child: _primaryButton(primary)),
            if (primary != PracticeFormulaPrimaryCategory.values.last)
              const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }

  Widget _verticalSectionPanel() {
    final sections = practiceFormulaSectionsByPrimary[_primaryCategory]!;
    return Padding(
      key: const ValueKey('practice-formula-section-panel'),
      padding: const EdgeInsets.only(left: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in sections) ...[
            _sectionButton(section, compact: true),
            if (section != sections.last) const SizedBox(height: 3),
          ],
        ],
      ),
    );
  }

  Widget _horizontalSectionPanel() {
    final sections = practiceFormulaSectionsByPrimary[_primaryCategory]!;
    return SingleChildScrollView(
      key: const ValueKey('practice-formula-section-panel'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final section in sections) ...[
            SizedBox(width: 118, child: _sectionButton(section)),
            if (section != sections.last) const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }

  Widget _primaryButton(
    PracticeFormulaPrimaryCategory primary, {
    bool compact = false,
  }) {
    final selected = primary == _primaryCategory;
    return _navigationButton(
      key: ValueKey('practice-formula-primary-${primary.name}'),
      label: practiceFormulaPrimaryLabels[primary]!,
      semanticLabel:
          '${practiceFormulaPrimaryLabels[primary]} 一级分类，${selected && _sectionsExpanded ? '已展开' : '已收起'}',
      selected: selected,
      compact: compact,
      expanded: selected && _sectionsExpanded,
      trailingIcon: selected && _sectionsExpanded
          ? Icons.expand_more_rounded
          : Icons.chevron_right_rounded,
      onPressed: () => _handlePrimaryPressed(primary),
    );
  }

  Widget _sectionButton(
    PracticeFormulaSection section, {
    bool compact = false,
  }) {
    return _navigationButton(
      key: ValueKey('practice-formula-section-${section.name}'),
      label: practiceFormulaSectionLabels[section]!,
      semanticLabel: '${practiceFormulaSectionLabels[section]} 二级标签',
      selected: section == _section,
      compact: compact,
      secondary: true,
      onPressed: () => _selectSection(section),
    );
  }

  Widget _navigationButton({
    required Key key,
    required String label,
    required String semanticLabel,
    required bool selected,
    required bool compact,
    required VoidCallback onPressed,
    IconData? trailingIcon,
    bool secondary = false,
    bool? expanded,
  }) {
    // 二级标签视觉保持紧凑，但实际触控热区不低于 44px，兼顾窄屏操作。
    final minimumHeight = secondary ? 44.0 : (compact ? 34.0 : 38.0);
    return Semantics(
      button: true,
      selected: selected,
      expanded: expanded,
      label: semanticLabel,
      child: TextButton(
        key: key,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: Size(0, minimumHeight),
          tapTargetSize: secondary
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          foregroundColor: selected ? Colors.white : const Color(0xFF3F4652),
          backgroundColor: selected
              ? const Color(0xFF6B23FF)
              : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: trailingIcon == null ? 12 : 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 2),
              Icon(trailingIcon, size: 16),
            ],
          ],
        ),
      ),
    );
  }

  void _handlePrimaryPressed(PracticeFormulaPrimaryCategory primary) {
    if (primary == _primaryCategory) {
      // 收起导航只影响目录可见性，不能重置学生当前标签与分页位置。
      setState(() => _sectionsExpanded = !_sectionsExpanded);
      return;
    }
    setState(() {
      _primaryCategory = primary;
      _section = practiceFormulaSectionsByPrimary[primary]!.first;
      // 一级分类改变后必须回到首标签首屏，避免沿用其他目录的越界页码。
      _pageIndex = 0;
      _sectionsExpanded = true;
    });
  }

  void _selectSection(PracticeFormulaSection section) {
    if (section == _section && _pageIndex == 0) return;
    setState(() {
      _section = section;
      // 各标签长度不同，切换时统一复位，保证分页状态始终有效。
      _pageIndex = 0;
    });
  }

  Widget _contentPad({required bool isWide}) {
    final keys = _visibleKeys;
    return Column(
      key: ValueKey('practice-formula-content-${_section.name}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        GridView.count(
          key: ValueKey('practice-formula-section-grid-${_section.name}'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: _isAlphabet ? 7 : 4,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          mainAxisExtent: _isAlphabet ? (isWide ? 48 : 44) : (isWide ? 56 : 48),
          children: [
            if (_isAlphabet)
              _textActionButton(
                id: 'uppercase',
                label: '⇧ 大写',
                semanticLabel: '切换大写字母',
                onPressed: _toggleUppercaseLetters,
                selected: _uppercaseLetters,
              ),
            for (final key in keys) _formulaKeyButton(key),
          ],
        ),
        if (_hasPages) ...[const SizedBox(height: 6), _paginationControls()],
      ],
    );
  }

  Widget _paginationControls() {
    return SizedBox(
      key: const ValueKey('practice-formula-page-controls'),
      height: 34,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const ValueKey('practice-formula-page-previous'),
            onPressed: _pageIndex > 0
                ? () => _selectPage(_pageIndex - 1)
                : null,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: '上一页',
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          SizedBox(
            key: const ValueKey('practice-formula-page-indicator'),
            width: 52,
            child: Text(
              '${_pageIndex + 1}/$_pageCount',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            key: const ValueKey('practice-formula-page-next'),
            onPressed: _pageIndex + 1 < _pageCount
                ? () => _selectPage(_pageIndex + 1)
                : null,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: '下一页',
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  void _selectPage(int pageIndex) {
    if (pageIndex == _pageIndex || pageIndex < 0 || pageIndex >= _pageCount) {
      return;
    }
    setState(() => _pageIndex = pageIndex);
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
      mainAxisExtent: isWide ? 56 : 48,
      children: [
        _textActionButton(
          id: 'more-shortcut',
          label: 'abc',
          semanticLabel: '打开完整字母键盘',
          onPressed: _handleAlphabetShortcut,
          selected:
              _primaryCategory == PracticeFormulaPrimaryCategory.common &&
              _isAlphabet,
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
          onPressed: () => goToNextPracticeFormulaSlot(widget.controller),
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

  void _handleAlphabetShortcut() {
    if (_primaryCategory == PracticeFormulaPrimaryCategory.common &&
        _isAlphabet &&
        _pageIndex == 0 &&
        _sectionsExpanded) {
      return;
    }
    setState(() {
      _primaryCategory = PracticeFormulaPrimaryCategory.common;
      _section = PracticeFormulaSection.lettersAndNumbers;
      _pageIndex = 0;
      _sectionsExpanded = true;
    });
  }

  void _toggleUppercaseLetters() {
    setState(() => _uppercaseLetters = !_uppercaseLetters);
  }

  Widget _formulaKeyButton(PracticeFormulaKeySpec key) {
    return Semantics(
      button: true,
      label: key.semanticLabel,
      child: MouseRegion(
        onEnter: (_) {
          if (key.usage.isNotEmpty) {
            setState(() => _hoveredKey = key);
          }
        },
        onExit: (_) {
          setState(() => _hoveredKey = null);
        },
        child: FilledButton(
          key: ValueKey('practice-formula-key-${key.id}'),
          onPressed: () => key.insert(widget.controller),
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

  Widget _keyTooltipCard(PracticeFormulaKeySpec key) {
    return Material(
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        key: const ValueKey('practice-formula-key-tooltip'),
        width: 240,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE8EBF0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: key.isTexLabel
                      ? Math.tex(
                          key.label,
                          mathStyle: MathStyle.text,
                          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                        )
                      : Text(
                          key.label,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    key.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B23FF),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFEEF0F5)),
            const SizedBox(height: 8),
            Text(
              key.usage,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF595959),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
