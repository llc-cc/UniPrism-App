import 'package:flutter/material.dart';

import '../adapters/guided_teaching_flow_dto.dart';
import 'guided_practice_dialog.dart';

const _ink = Color(0xFF1F2937);
const _muted = Color(0xFF6F6977);

/// 页面内嵌的作答区域，替代弹窗式练习，贴近设计稿「练习画板」。
final class InlinePracticeAnswerPanel extends StatefulWidget {
  const InlinePracticeAnswerPanel({
    super.key,
    required this.practice,
    required this.onSubmit,
    this.readOnly = false,
    this.isConsolidation = false,
    this.submitting = false,
  });

  final RemoteGuidedPractice practice;
  final Future<bool> Function(GuidedPracticeDraft draft) onSubmit;
  final bool readOnly;
  final bool isConsolidation;
  final bool submitting;

  @override
  State<InlinePracticeAnswerPanel> createState() =>
      _InlinePracticeAnswerPanelState();
}

final class _InlinePracticeAnswerPanelState
    extends State<InlinePracticeAnswerPanel> {
  final _reasoningController = TextEditingController();
  String? _selectedChoice;
  var _isSubmitting = false;

  static const _choiceOptions = {
    'set-same-collection-v1': [
      ('是同一个集合', '是同一个集合'),
      ('不是同一个集合', '不是同一个集合'),
    ],
  };

  @override
  void dispose() {
    _reasoningController.dispose();
    super.dispose();
  }

  List<(String label, String value)>? get _choices =>
      _choiceOptions[widget.practice.id];

  bool get _hasCompleteDraft {
    final reasoning = _reasoningController.text.trim();
    if (reasoning.isEmpty) return false;
    if (_choices != null) return _selectedChoice != null;
    return true;
  }

  String get _answerValue => _selectedChoice ?? _reasoningController.text.trim();

  Future<void> _submit() async {
    if (widget.readOnly || _isSubmitting || !_hasCompleteDraft) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.onSubmit(
        GuidedPracticeDraft(
          reasoning: _reasoningController.text,
          answer: _answerValue,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled =
        widget.readOnly || _isSubmitting || widget.submitting || !_hasCompleteDraft;
    final title = widget.isConsolidation ? '巩固作答区域' : '作答区域';
    final reasoningLength = _reasoningController.text.length;

    return Container(
      key: const ValueKey('inline-practice-answer-panel'),
      margin: const EdgeInsets.only(left: 44, right: 8, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.practice.prompt,
            style: const TextStyle(height: 1.5, color: _ink, fontSize: 14),
          ),
          const SizedBox(height: 14),
          Text(
            widget.practice.reasoningLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('inline-practice-reasoning-input'),
            controller: _reasoningController,
            maxLines: 3,
            maxLength: 200,
            readOnly: widget.readOnly,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '例如：因为两个集合元素完全相同，且集合具有无序性…',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              counterText: '$reasoningLength/200',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.practice.answerLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          if (_choices != null)
            Column(
              children: [
                for (final (label, value) in _choices!)
                  RadioListTile<String>(
                    key: ValueKey('inline-practice-choice-$value'),
                    value: value,
                    groupValue: _selectedChoice,
                    onChanged: widget.readOnly
                        ? null
                        : (next) => setState(() => _selectedChoice = next),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                  ),
              ],
            )
          else
            TextField(
              key: const ValueKey('inline-practice-answer-input'),
              readOnly: widget.readOnly,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '在这里写出你的结论',
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
              ),
            ),
          if (!widget.readOnly) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey('inline-practice-submit-button'),
                onPressed: disabled ? null : _submit,
                icon: _isSubmitting || widget.submitting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(widget.isConsolidation ? '提交巩固作答' : '提交作答'),
              ),
            ),
          ],
          if (widget.readOnly)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '这是历史练习记录，可在上方对话区查看当时作答。',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
