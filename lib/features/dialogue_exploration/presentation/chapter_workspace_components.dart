import 'package:flutter/material.dart';

import '../adapters/remote_exploration_dto.dart';
import 'student_learning_narrative.dart';

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
    required this.directTeacherQuestionController,
    required this.busy,
    required this.errorMessage,
    required this.onRetry,
    required this.onSelectNode,
    required this.onStartNode,
    required this.onStartDirectQuestion,
  });

  final LearningChapterOverviewSnapshot chapter;
  final String? selectedNodeId;
  final TextEditingController questionController;
  final TextEditingController directTeacherQuestionController;
  final bool busy;
  final String? errorMessage;
  final VoidCallback onRetry;
  final ValueChanged<String> onSelectNode;
  final void Function(String nodeId, String? question) onStartNode;
  final ValueChanged<String> onStartDirectQuestion;

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
          _StudentMissionHero(
            chapter: chapter,
            node: selected,
            controller: questionController,
            busy: busy,
            onStart: () => onStartNode(selected.id, questionController.text),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 14),
            _ChapterEntryError(message: errorMessage!, onRetry: onRetry),
          ],
          const SizedBox(height: 14),
          _ChapterLearningJourneyStrip(phases: chapter.phases),
          const SizedBox(height: 12),
          _ChapterQuestionSwitcher(
            chapter: chapter,
            selectedNodeId: selected.id,
            busy: busy,
            onNodeTap: onSelectNode,
            onStart: (nodeId) => onStartNode(nodeId, null),
          ),
          const SizedBox(height: 12),
          _DirectAiTeacherEntry(
            controller: directTeacherQuestionController,
            busy: busy,
            onStart: onStartDirectQuestion,
          ),
        ],
      ),
    );
  }
}

/// 首屏只呈现一个当前学习任务，避免章节信息和多个开始入口分散学生注意力。
final class _StudentMissionHero extends StatelessWidget {
  const _StudentMissionHero({
    required this.chapter,
    required this.node,
    required this.controller,
    required this.busy,
    required this.onStart,
  });

  final LearningChapterOverviewSnapshot chapter;
  final LearningChapterNodeSnapshot node;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('student-mission-hero'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4EEFF), Color(0xFFFFF8EF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8C5FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '今天想弄懂什么？',
                style: TextStyle(
                  color: _chapterBrand,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  chapter.title,
                  style: const TextStyle(fontSize: 12, color: _chapterMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            node.hookQuestion,
            style: const TextStyle(
              fontSize: 30,
              height: 1.22,
              fontWeight: FontWeight.w900,
              color: _chapterInk,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            node.description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: _chapterMuted,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '先说说你的问题或想法',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          TextField(
            key: const ValueKey('chapter-free-question'),
            controller: controller,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            onSubmitted: busy ? null : (_) => onStart(),
            decoration: InputDecoration(
              hintText: '例如：我想知道为什么配平只能调整系数……',
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.92),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFD9D0E5)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey('chapter-enter-selected-node'),
              onPressed: busy ? null : onStart,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('和 AI 老师聊一聊'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 会话创建失败后仍保留章节上下文，并在原入口旁给出可执行的重试，避免学生误以为节点不可进入。
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

/// 学习旅程只提供方向感，不重复展示每阶段摘要、时长与进度条。
final class _ChapterLearningJourneyStrip extends StatelessWidget {
  const _ChapterLearningJourneyStrip({required this.phases});

  final List<LearningChapterPhaseSnapshot> phases;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chapter-learning-journey-strip'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5DFEA)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 640;
          final children = phases.indexed
              .map((entry) => _ChapterJourneyStep(phase: entry.$2))
              .toList(growable: false);
          if (!horizontal) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children
                  .expand(
                    (child) => [
                      child,
                      if (child != children.last) const SizedBox(height: 10),
                    ],
                  )
                  .toList(growable: false),
            );
          }
          return Row(
            children: children.indexed
                .expand(
                  (entry) => [
                    Expanded(child: entry.$2),
                    if (entry.$1 < children.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: Color(0xFFB8AFC3),
                        ),
                      ),
                  ],
                )
                .toList(growable: false),
          );
        },
      ),
    );
  }
}

final class _ChapterJourneyStep extends StatelessWidget {
  const _ChapterJourneyStep({required this.phase});

  final LearningChapterPhaseSnapshot phase;

  @override
  Widget build(BuildContext context) {
    final kind = phase.kind.toLowerCase();
    final icon = switch (phase.kind) {
      'PRACTICE' => Icons.touch_app_outlined,
      'REVIEW' => Icons.auto_stories_outlined,
      _ => Icons.lightbulb_outline_rounded,
    };
    return Semantics(
      label:
          '${StudentLearningNarrative.chapterPhaseTitle(phase.kind)}，${StudentLearningNarrative.chapterPhaseStatus(phase.status)}',
      child: Row(
        key: ValueKey('chapter-phase-$kind'),
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFF0E8FF),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: _chapterBrand),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  StudentLearningNarrative.chapterPhaseTitle(phase.kind),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  StudentLearningNarrative.chapterPhaseStatus(phase.status),
                  style: const TextStyle(fontSize: 11, color: _chapterMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 课程路线默认折叠；学生主动换题时才展开完整节点，避免目录先于问题出现。
final class _ChapterQuestionSwitcher extends StatelessWidget {
  const _ChapterQuestionSwitcher({
    required this.chapter,
    required this.selectedNodeId,
    required this.busy,
    required this.onNodeTap,
    required this.onStart,
  });

  final LearningChapterOverviewSnapshot chapter;
  final String selectedNodeId;
  final bool busy;
  final ValueChanged<String> onNodeTap;
  final ValueChanged<String> onStart;

  @override
  Widget build(BuildContext context) {
    final selected = chapter.nodeById(selectedNodeId)!;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5DFEA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const ValueKey('chapter-question-switcher'),
        leading: const Icon(Icons.swap_horiz_rounded, color: _chapterBrand),
        title: const Text(
          '想换一个问题？',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '当前：${selected.title}',
          style: const TextStyle(fontSize: 12, color: _chapterMuted),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        children: [
          ChapterKnowledgeTree(
            chapter: chapter,
            selectedNodeId: selectedNodeId,
            onNodeTap: onNodeTap,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey('chapter-enter-switched-node'),
              onPressed: busy ? null : () => onStart(selected.id),
              icon: const Icon(Icons.science_outlined),
              label: Text('从「${selected.title}」开始探索'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 独立问题仍然可用，但默认收起，避免它与当前课程任务形成两个并列主入口。
final class _DirectAiTeacherEntry extends StatelessWidget {
  const _DirectAiTeacherEntry({
    required this.controller,
    required this.busy,
    required this.onStart,
  });

  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onStart;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xB3FFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5DFEA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const ValueKey('direct-ai-teacher-entry'),
        leading: const Icon(Icons.chat_bubble_outline_rounded),
        title: const Text(
          '想问完全不同的问题？',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text(
          '展开后可以直接问 AI 老师',
          style: TextStyle(fontSize: 12, color: _chapterMuted),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            key: const ValueKey('direct-ai-teacher-question'),
            controller: controller,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: '例如：为什么天空是蓝色？',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey('direct-ai-teacher-start'),
              onPressed: busy ? null : () => onStart(controller.text),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('带着这个问题出发'),
            ),
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
