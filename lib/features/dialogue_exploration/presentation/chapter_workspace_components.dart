import 'package:flutter/material.dart';

import '../adapters/remote_exploration_dto.dart';

const _chapterBrand = Color(0xFF6B23FF);
const _chapterInk = Color(0xFF27222D);
const _chapterMuted = Color(0xFF6F6977);

/// 章节总览把学习、练习、复习与知识路线放在同一页面，但不在 UI 内推断真实进度。
final class ChapterOverviewPanel extends StatelessWidget {
  const ChapterOverviewPanel({
    super.key,
    required this.chapter,
    required this.selectedNodeId,
    required this.questionController,
    required this.busy,
    required this.onSelectNode,
    required this.onStartNode,
  });

  final LearningChapterOverviewSnapshot chapter;
  final String? selectedNodeId;
  final TextEditingController questionController;
  final bool busy;
  final ValueChanged<String> onSelectNode;
  final ValueChanged<String> onStartNode;

  @override
  Widget build(BuildContext context) {
    final selected =
        chapter.nodeById(selectedNodeId) ??
        chapter.nodeById(chapter.recommendedNodeId)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ChapterHeader(chapter: chapter),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth >= 760
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth;
              final phaseMinutes =
                  (chapter.estimatedMinutes / chapter.phases.length).ceil();
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: chapter.phases
                    .map(
                      (phase) => SizedBox(
                        width: cardWidth,
                        child: _ChapterPhaseCard(
                          phase: phase,
                          estimatedMinutes: phaseMinutes,
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            '本章知识路线',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            '点击任一节点查看核心问题，再从这里开始探索。',
            style: TextStyle(color: _chapterMuted),
          ),
          const SizedBox(height: 12),
          ChapterKnowledgeTree(
            chapter: chapter,
            selectedNodeId: selected.id,
            onNodeTap: onSelectNode,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF0E8FF), Color(0xFFFFF4E8)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected.title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  selected.description,
                  style: const TextStyle(color: _chapterMuted),
                ),
                const SizedBox(height: 12),
                Text(
                  selected.hookQuestion,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('chapter-free-question'),
                  controller: questionController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: '也可以把这个问题改成你真正想问的内容',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('start-selected-chapter-node'),
                  onPressed: busy ? null : () => onStartNode(selected.id),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: const Text('进入这个知识点'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({required this.chapter});

  final LearningChapterOverviewSnapshot chapter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5DFEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '章节学习工作台',
            style: TextStyle(color: _chapterBrand, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Text(
            chapter.title,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            chapter.description,
            style: const TextStyle(color: _chapterMuted, height: 1.45),
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: chapter.progress.clamp(0, 1),
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 7),
          Text(
            '本章进度 ${(chapter.progress * 100).round()}% · 预计 ${chapter.estimatedMinutes} 分钟',
            style: const TextStyle(fontSize: 12, color: _chapterMuted),
          ),
        ],
      ),
    );
  }
}

final class _ChapterPhaseCard extends StatelessWidget {
  const _ChapterPhaseCard({
    required this.phase,
    required this.estimatedMinutes,
  });

  final LearningChapterPhaseSnapshot phase;
  final int estimatedMinutes;

  @override
  Widget build(BuildContext context) {
    final kind = phase.kind.toLowerCase();
    final icon = switch (phase.kind) {
      'PRACTICE' => Icons.edit_note_rounded,
      'REVIEW' => Icons.history_edu_rounded,
      _ => Icons.school_rounded,
    };
    final status = switch (phase.status) {
      'LOCKED' => '待产生复习内容',
      'IN_PROGRESS' => '进行中',
      _ => '可进入',
    };
    return Container(
      key: ValueKey('chapter-phase-$kind'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE5DFEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _chapterBrand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  phase.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                status,
                style: const TextStyle(fontSize: 11, color: _chapterMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(phase.summary, style: const TextStyle(color: _chapterMuted)),
          const SizedBox(height: 6),
          Text(
            '预计 $estimatedMinutes 分钟',
            style: const TextStyle(
              fontSize: 11,
              color: _chapterBrand,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: phase.progress.clamp(0, 1),
            minHeight: 5,
          ),
        ],
      ),
    );
  }
}

/// 章节知识树是稳定课程结构，点击只改变焦点，不执行会话写操作。
final class ChapterKnowledgeTree extends StatelessWidget {
  const ChapterKnowledgeTree({
    super.key,
    required this.chapter,
    required this.selectedNodeId,
    required this.onNodeTap,
    this.compact = false,
  });

  final LearningChapterOverviewSnapshot chapter;
  final String? selectedNodeId;
  final ValueChanged<String> onNodeTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        key: const ValueKey('chapter-knowledge-tree'),
        children: chapter.nodes.indexed
            .map((entry) => _compactNode(entry.$1, entry.$2))
            .toList(growable: false),
      );
    }
    return Column(
      key: const ValueKey('chapter-knowledge-tree'),
      children: chapter.nodes.indexed
          .map((entry) {
            final (index, node) = entry;
            final selected = node.id == selectedNodeId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                key: ValueKey('chapter-node-${node.id}'),
                onTap: () => onNodeTap(node.id),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFF1EAFF) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? _chapterBrand : const Color(0xFFE5DFEA),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundColor: selected
                            ? _chapterBrand
                            : const Color(0xFFEFEAF7),
                        foregroundColor: selected ? Colors.white : _chapterInk,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              node.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              node.description,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _chapterMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (node.recommended)
                        const Chip(
                          label: Text('推荐'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _compactNode(int index, LearningChapterNodeSnapshot node) {
    final selected = node.id == selectedNodeId;
    final isLast = index == chapter.nodes.length - 1;
    return InkWell(
      key: ValueKey('chapter-node-${node.id}'),
      onTap: () => onNodeTap(node.id),
      borderRadius: BorderRadius.circular(10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  Container(
                    width: selected ? 10 : 8,
                    height: selected ? 10 : 8,
                    decoration: BoxDecoration(
                      color: selected ? _chapterBrand : const Color(0xFF49B984),
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: const Color(0xFFE1DBE9),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFF1EAFF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: selected ? Border.all(color: _chapterBrand) : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        node.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w900
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (node.phase != 'LEARNING')
                      Text(
                        node.phase == 'PRACTICE' ? '练习' : '复习',
                        style: const TextStyle(
                          fontSize: 10,
                          color: _chapterMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
