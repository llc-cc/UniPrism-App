import 'package:flutter/material.dart';

import '../adapters/teaching_architecture_dto.dart';

const _ink = Color(0xFF1F2937);
const _muted = Color(0xFF6F6977);

/// 补救画板：针对薄弱知识点给出讲解与轻量互动。
final class ClassroomRemediationPanel extends StatelessWidget {
  const ClassroomRemediationPanel({
    super.key,
    required this.topic,
    required this.feedback,
    this.repairFocus,
    this.readOnly = false,
    this.onQuickAnswer,
  });

  final String topic;
  final String feedback;
  final String? repairFocus;
  final bool readOnly;
  final Future<void> Function(String answer)? onQuickAnswer;

  factory ClassroomRemediationPanel.fromBranch({
    required RemoteTeachingBranchRecord branch,
    required List<String> knowledgeNodeNames,
    bool readOnly = false,
    Future<void> Function(String answer)? onQuickAnswer,
  }) {
    final topic = knowledgeNodeNames.isNotEmpty
        ? knowledgeNodeNames.first
        : '薄弱知识点';
    return ClassroomRemediationPanel(
      topic: topic,
      feedback: branch.feedback,
      repairFocus: branch.repairFocus,
      readOnly: readOnly,
      onQuickAnswer: onQuickAnswer,
    );
  }

  String get _conceptExplanation {
    final focus = repairFocus?.trim();
    if (focus != null && focus.isNotEmpty) return focus;
    if (topic.contains('无序')) {
      return '无序性：集合中的元素不考虑顺序。例如 {1,2,3} 与 {3,2,1} 表示同一个集合。';
    }
    if (topic.contains('确定')) {
      return '确定性：给定集合后，任意对象是否属于该集合必须能明确判断，标准不能模糊。';
    }
    return feedback;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('classroom-remediation-panel'),
      margin: const EdgeInsets.only(left: 44, right: 8, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEA580C),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  topic,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '针对性补救',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _conceptExplanation,
            style: const TextStyle(height: 1.55, color: _ink, fontSize: 14),
          ),
          if (!readOnly && onQuickAnswer != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '互动练习',
                    style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '判断：{a, b, c} 与 {c, a, b} 是否相等？',
                    style: TextStyle(height: 1.45, color: _ink),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        key: const ValueKey('remediation-quick-yes'),
                        onPressed: () => onQuickAnswer!(
                          '是，它们相等，因为集合具有无序性，元素相同即可。',
                        ),
                        child: const Text('是，相等'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('remediation-quick-no'),
                        onPressed: () => onQuickAnswer!(
                          '不是，我还需要再想想无序性和元素是否相同。',
                        ),
                        child: const Text('还不确定'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (readOnly)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '已完成的补救记录，可在上方对话区回看讲解过程。',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
