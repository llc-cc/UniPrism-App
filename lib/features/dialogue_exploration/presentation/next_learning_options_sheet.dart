import 'package:flutter/material.dart';

import '../adapters/guided_teaching_flow_dto.dart';

/// 已掌握后由服务端授权的下一学习方向；组件不自行解锁或创建会话。
final class NextLearningOptionsSheet extends StatelessWidget {
  const NextLearningOptionsSheet({
    super.key,
    required this.options,
    required this.busy,
    required this.errorMessage,
    required this.onContinue,
    required this.onRetry,
    required this.onFinish,
  });

  final List<RemoteNextLearningOption> options;
  final bool busy;
  final String? errorMessage;
  final ValueChanged<RemoteNextLearningOption> onContinue;
  final VoidCallback onRetry;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('next-learning-options'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '接下来想学什么？',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (options.isEmpty)
          const Text('当前暂无已审核的进阶方向')
        else
          ...options.map(
            (option) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(option.relation),
                      Text(option.difficultyReason),
                      Text('预计 ${option.estimatedMinutes} 分钟'),
                      const SizedBox(height: 8),
                      FilledButton(
                        key: ValueKey('next-learning-${option.atomId}'),
                        onPressed:
                            busy ||
                                errorMessage != null ||
                                !option.prerequisitesSatisfied
                            ? null
                            : () => onContinue(option),
                        child: Text(
                          option.prerequisitesSatisfied ? '继续学习' : '暂未解锁',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(errorMessage!),
          const SizedBox(height: 6),
          FilledButton(
            key: const ValueKey('next-learning-retry-button'),
            onPressed: busy ? null : onRetry,
            child: const Text('重试'),
          ),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy ? null : onFinish,
            child: const Text('先结束'),
          ),
        ),
      ],
    );
  }
}
