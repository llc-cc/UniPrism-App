import 'package:flutter/material.dart';

/// 章节加载中占位；寒暄会话创建成功后由 [RemoteLearningSessionPage] 承接。
final class ChapterOverviewPanel extends StatelessWidget {
  const ChapterOverviewPanel({
    super.key,
    required this.busy,
    this.errorMessage,
    required this.onRetry,
  });

  final bool busy;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: busy
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 14),
                      Text('AI 老师正在赶来…'),
                    ],
                  )
                : const Text('正在进入 AI 探索课堂…'),
          ),
        ),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _ChapterEntryError(message: errorMessage!, onRetry: onRetry),
          ),
      ],
    );
  }
}

final class _ChapterEntryError extends StatelessWidget {
  const _ChapterEntryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chapter-entry-error'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECE9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFC23A2B)),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
