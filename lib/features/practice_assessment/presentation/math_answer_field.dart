import 'package:flutter/material.dart';
import 'package:math_keyboard/math_keyboard.dart';

import 'practice_formula_config.dart';
import 'practice_formula_keyboard.dart';

/// 填空题的可排版数学输入框；对外只暴露 LaTeX 字符串，不泄漏编辑器内部树。
final class MathAnswerField extends StatefulWidget {
  const MathAnswerField({
    super.key,
    required this.questionId,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.controller,
  });

  final String questionId;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  /// 允许测试或上层复用控制器；只有组件自行创建时才负责销毁。
  final MathFieldEditingController? controller;

  @override
  State<MathAnswerField> createState() => _MathAnswerFieldState();
}

final class _MathAnswerFieldState extends State<MathAnswerField> {
  late MathFieldEditingController _controller;
  late bool _ownsController;
  late final FocusNode _focusNode;
  bool _isSynchronizingExternalValue = false;
  String _lastAcceptedValue = '';
  String? _formatError;
  bool _isKeyboardVisible = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? MathFieldEditingController();
    _focusNode = FocusNode(debugLabel: 'practice_math_${widget.questionId}');
    _focusNode.addListener(_handleFocusChanged);
    _synchronizeExternalValue(widget.value);
  }

  @override
  void didUpdateWidget(covariant MathAnswerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final oldController = _controller;
      final ownedOldController = _ownsController;
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? MathFieldEditingController();
      if (ownedOldController) oldController.dispose();
      _lastAcceptedValue = '';
    }
    if (widget.value != _lastAcceptedValue ||
        oldWidget.questionId != widget.questionId) {
      _synchronizeExternalValue(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus || !widget.enabled || _isKeyboardVisible) return;
    setState(() => _isKeyboardVisible = true);
  }

  void _finishEditing() {
    _focusNode.unfocus();
    setState(() => _isKeyboardVisible = false);
  }

  void _synchronizeExternalValue(String value) {
    _isSynchronizingExternalValue = true;
    try {
      if (value.isEmpty) {
        if (!_controller.isEmpty) _controller.clear();
      } else {
        _controller.updateValue(TeXParser(value).parse());
      }
      _lastAcceptedValue = value;
      _formatError = null;
    } catch (_) {
      // 恢复失败时保留上层原始草稿并显示错误，不能静默清空学生答案。
      _lastAcceptedValue = value;
      _formatError = '该公式暂时无法排版，请修改后重试。';
    } finally {
      _isSynchronizingExternalValue = false;
    }
  }

  void _handleChanged(String value) {
    if (_isSynchronizingExternalValue) return;
    if (value.length > practiceFormulaAnswerMaxLength) {
      setState(() {
        _formatError = '公式不能超过 $practiceFormulaAnswerMaxLength 个字符。';
      });
      return;
    }
    if (_formatError != null) {
      setState(() {
        _formatError = null;
      });
    }
    _lastAcceptedValue = value;
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '数学公式答案',
      textField: true,
      child: Column(
        key: const ValueKey('practice-math-answer-field'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IgnorePointer(
            ignoring: !widget.enabled,
            child: MathField(
              key: const ValueKey('practice-math-answer-input'),
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: MathKeyboardType.expression,
              variables: practiceFormulaVariables,
              // 默认键盘颜色与键位均为包内硬编码；App 使用下方受控浅色键盘。
              opensKeyboard: false,
              decoration: InputDecoration(
                labelText: '填写数学答案',
                hintText: '点击此处输入分数、根式或公式',
                filled: true,
                fillColor: widget.enabled
                    ? Colors.white
                    : const Color(0xFFF1EFF5),
                enabled: widget.enabled,
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF6B23FF), width: 2),
                ),
              ),
              onChanged: _handleChanged,
              onSubmitted: (_) => _finishEditing(),
            ),
          ),
          if (_formatError case final message?) ...[
            const SizedBox(height: 6),
            Text(
              message,
              key: const ValueKey('practice-math-answer-error'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
          if (_isKeyboardVisible && widget.enabled)
            PracticeFormulaKeyboard(
              controller: _controller,
              onDone: _finishEditing,
            ),
        ],
      ),
    );
  }
}
