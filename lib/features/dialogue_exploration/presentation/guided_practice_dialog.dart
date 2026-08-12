import 'package:flutter/material.dart';

import '../adapters/guided_teaching_flow_dto.dart';

/// 学生尚未提交的独立作答；只保存输入草稿，不包含本地判题结论。
final class GuidedPracticeDraft {
  const GuidedPracticeDraft({required this.reasoning, required this.answer});

  final String reasoning;
  final String answer;
}

/// 展示服务端指定的迁移情境，并在网络失败时保留学生草稿以便幂等重试。
final class GuidedPracticeDialog extends StatefulWidget {
  const GuidedPracticeDialog({
    super.key,
    required this.practice,
    required this.onSubmit,
    required this.onRetry,
  });

  final RemoteGuidedPractice practice;
  final Future<bool> Function(GuidedPracticeDraft draft) onSubmit;
  final Future<bool> Function() onRetry;

  @override
  State<GuidedPracticeDialog> createState() => _GuidedPracticeDialogState();
}

final class _GuidedPracticeDialogState extends State<GuidedPracticeDialog> {
  final _reasoningController = TextEditingController();
  final _answerController = TextEditingController();
  var _isSubmitting = false;
  var _canRetry = false;

  @override
  void initState() {
    super.initState();
    _reasoningController.addListener(_refreshDraftAvailability);
    _answerController.addListener(_refreshDraftAvailability);
  }

  @override
  void dispose() {
    _reasoningController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  bool get _hasCompleteDraft =>
      _reasoningController.text.trim().isNotEmpty &&
      _answerController.text.trim().isNotEmpty;

  void _refreshDraftAvailability() {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_hasCompleteDraft) return;
    setState(() {
      _isSubmitting = true;
      _canRetry = false;
    });
    final accepted = await widget.onSubmit(
      GuidedPracticeDraft(
        reasoning: _reasoningController.text,
        answer: _answerController.text,
      ),
    );
    if (!mounted) return;
    if (accepted) {
      Navigator.pop(context);
      return;
    }
    // 控制器保留首次请求的幂等键；这里不能重新提交新的作答操作。
    setState(() {
      _isSubmitting = false;
      _canRetry = true;
    });
  }

  Future<void> _retry() async {
    if (_isSubmitting || !_canRetry) return;
    setState(() => _isSubmitting = true);
    final accepted = await widget.onRetry();
    if (!mounted) return;
    if (accepted) {
      Navigator.pop(context);
      return;
    }
    setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _isSubmitting || !_hasCompleteDraft;
    return PopScope(
      canPop: _canRetry && !_isSubmitting,
      child: AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(widget.practice.title)),
            if (_canRetry)
              IconButton(
                key: const ValueKey('guided-practice-close-button'),
                tooltip: '关闭练习',
                onPressed: _isSubmitting
                    ? null
                    : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.practice.prompt),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('guided-practice-reasoning-input'),
                  controller: _reasoningController,
                  maxLines: 3,
                  enabled: !_isSubmitting,
                  decoration: InputDecoration(
                    labelText: widget.practice.reasoningLabel,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('guided-practice-answer-input'),
                  controller: _answerController,
                  enabled: !_isSubmitting,
                  decoration: InputDecoration(
                    labelText: widget.practice.answerLabel,
                  ),
                ),
                if (_canRetry) ...[
                  const SizedBox(height: 12),
                  const Text('提交暂未完成，已保留你的作答，可以重试。'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_canRetry)
            FilledButton(
              key: const ValueKey('guided-practice-retry-button'),
              onPressed: _isSubmitting ? null : _retry,
              child: const Text('重试提交'),
            )
          else
            FilledButton(
              key: const ValueKey('guided-practice-submit-button'),
              onPressed: disabled ? null : _submit,
              child: const Text('提交我的判断'),
            ),
        ],
      ),
    );
  }
}
