import 'package:flutter/material.dart';

import '../adapters/guided_teaching_flow_dto.dart';
import '../adapters/remote_exploration_dto.dart';
import 'intro_chat_messages.dart';

const _muted = Color(0xFF6F6977);

/// 章节入口与服务端引导阶段共用：真实 AI 寒暄互动，再展示 DesignArena 选项。
final class TeachingModeSelectionStage extends StatefulWidget {
  const TeachingModeSelectionStage({
    super.key,
    required this.topicLabel,
    required this.options,
    required this.submitting,
    required this.onSelect,
    required this.mobile,
    this.historyEntries = const [],
    this.onHistoryTap,
    this.messages = const [],
    this.modePrompt,
    this.showOptions = false,
    this.onSendMessage,
    this.showReplyBar = true,
    this.teacherTyping = false,
    this.initializing = false,
    this.guidedPanel,
    this.classroomBottomBar,
    this.selectedHistoryNodeId,
    this.selectedHistoryBoardId,
    this.onBoardTap,
    this.boardPanelTitle,
    this.emptyConversationLabel,
    this.isReviewingHistory = false,
    this.onReturnToCurrent,
    this.onFunctionAreaATap,
  });

  final String topicLabel;
  final List<RemoteTeachingModeOption> options;
  final bool submitting;
  final void Function(String skill) onSelect;
  final bool mobile;
  final List<TeachingModeHistoryEntry> historyEntries;
  final void Function(String nodeId)? onHistoryTap;
  final List<IntroChatMessage> messages;
  final String? modePrompt;

  /// 为 true 时展示底部三选项。
  final bool showOptions;
  final Future<void> Function(String text)? onSendMessage;
  final bool showReplyBar;

  /// 仅在等待服务端生成回复时为 true，避免输出完成后仍显示「正在输入」。
  final bool teacherTyping;
  final bool initializing;

  /// 当前节点上的教学/练习/补救面板（仅最新节点展示）。
  final Widget? guidedPanel;

  /// 课堂底部操作条（开始验证 / 我完成了 等）。
  final Widget? classroomBottomBar;
  final String? selectedHistoryNodeId;
  final String? selectedHistoryBoardId;
  final void Function(String boardId)? onBoardTap;
  final String? boardPanelTitle;
  final String? emptyConversationLabel;
  final bool isReviewingHistory;
  final VoidCallback? onReturnToCurrent;

  /// 功能区 A 由页面层注入导航，侧栏只负责呈现入口。
  final VoidCallback? onFunctionAreaATap;

  @override
  State<TeachingModeSelectionStage> createState() =>
      _TeachingModeSelectionStageState();
}

final class _TeachingModeSelectionStageState
    extends State<TeachingModeSelectionStage> {
  var _sidebarCollapsed = false;
  final _replyController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant TeachingModeSelectionStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focusChanged =
        widget.selectedHistoryBoardId != oldWidget.selectedHistoryBoardId ||
        widget.selectedHistoryNodeId != oldWidget.selectedHistoryNodeId;
    if (focusChanged) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncScrollAfterFocusChange(),
      );
    } else if (widget.messages.length > oldWidget.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _syncScrollAfterFocusChange() {
    if (!_scrollController.hasClients) return;
    // 历史画板从第一句开始回放；返回当前学习时则定位到最新对话。
    final position = _scrollController.position;
    _scrollController.jumpTo(
      widget.isReviewingHistory
          ? position.minScrollExtent
          : position.maxScrollExtent,
    );
  }

  Future<void> _onUserSend([String? preset]) async {
    final text = (preset ?? _replyController.text).trim();
    if (text.isEmpty || widget.submitting || widget.onSendMessage == null) {
      return;
    }
    _replyController.clear();
    await widget.onSendMessage!(text);
  }

  bool get _canReply =>
      widget.showReplyBar &&
      !widget.showOptions &&
      widget.onSendMessage != null;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('teaching-mode-selection-stage'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_sidebarCollapsed)
          ModeSelectionSidebar(
            entries: widget.historyEntries,
            onHistoryTap: widget.onHistoryTap,
            onBoardTap: widget.onBoardTap,
            mobile: widget.mobile,
            onCollapse: () => setState(() => _sidebarCollapsed = true),
            selectedBoardId: widget.selectedHistoryBoardId,
            selectedNodeId: widget.selectedHistoryNodeId,
            onFunctionAreaATap: widget.onFunctionAreaATap,
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_sidebarCollapsed)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _sidebarCollapsed = false),
                      icon: const Icon(Icons.menu_rounded, size: 18),
                      label: const Text('展开历史与功能区'),
                    ),
                  ),
                ),
              if (widget.isReviewingHistory)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.mobile ? 12 : 20,
                    8,
                    widget.mobile ? 12 : 20,
                    0,
                  ),
                  child: _HistoryReviewBanner(
                    onReturnToCurrent: widget.onReturnToCurrent,
                  ),
                ),
              if (widget.boardPanelTitle != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.mobile ? 12 : 20,
                    widget.isReviewingHistory ? 6 : 8,
                    widget.mobile ? 12 : 20,
                    0,
                  ),
                  child: _ClassroomBoardHeader(title: widget.boardPanelTitle!),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _IntroChatPanel(
                        controller: _scrollController,
                        messages: widget.messages,
                        mobile: widget.mobile,
                        initializing: widget.initializing,
                        teacherTyping: widget.teacherTyping,
                        emptyLabel: widget.emptyConversationLabel,
                      ),
                    ),
                    if (widget.guidedPanel != null) widget.guidedPanel!,
                  ],
                ),
              ),
              if (_canReply)
                _IntroReplyBar(
                  controller: _replyController,
                  submitting: widget.submitting,
                  onSend: _onUserSend,
                ),
              if (widget.showOptions)
                ModeSelectionChoiceRow(
                  options: widget.options,
                  submitting: widget.submitting,
                  onSelect: widget.onSelect,
                  mobile: widget.mobile,
                ),
              if (widget.classroomBottomBar != null) widget.classroomBottomBar!,
            ],
          ),
        ),
      ],
    );
  }
}

final class _IntroChatPanel extends StatelessWidget {
  const _IntroChatPanel({
    required this.controller,
    required this.messages,
    required this.mobile,
    required this.initializing,
    required this.teacherTyping,
    this.emptyLabel,
  });

  final ScrollController controller;
  final List<IntroChatMessage> messages;
  final bool mobile;
  final bool initializing;
  final bool teacherTyping;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(mobile ? 12 : 20, 12, mobile ? 12 : 20, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: messages.isEmpty && !teacherTyping
          ? Center(
              child: Text(
                initializing
                    ? 'AI 老师正在赶来…'
                    : (emptyLabel?.trim().isNotEmpty == true
                          ? emptyLabel!.trim()
                          : '跟 AI 老师打个招呼，开始这节课吧'),
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            )
          : ListView.separated(
              controller: controller,
              itemCount: messages.length + (teacherTyping ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index >= messages.length) {
                  return const _TeacherTypingIndicator();
                }
                final line = messages[index];
                if (line.isThreadHeader) {
                  return _ConversationThreadHeader(label: line.text);
                }
                if (line.isTeacher) {
                  if (line.isModePrompt) {
                    return TeacherModePromptBanner(prompt: line.text);
                  }
                  if (line.isCorrectionFeedback) {
                    return _TeacherCorrectionBubble(text: line.text);
                  }
                  return _TeacherChatBubble(text: line.text);
                }
                return _StudentChatBubble(text: line.text);
              },
            ),
    );
  }
}

final class _ConversationThreadHeader extends StatelessWidget {
  const _ConversationThreadHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFD8D3E3))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B5B95),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFD8D3E3))),
      ],
    );
  }
}

/// 历史回访独立放在原教学问答和素材快照之后，避免学生误以为它属于当时的主线课堂。
final class HistoricalRevisitTranscript extends StatelessWidget {
  const HistoricalRevisitTranscript({super.key, required this.messages});

  final List<IntroChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('historical-revisit-transcript'),
      margin: const EdgeInsets.only(left: 44, right: 8, bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8CBFF), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, line) in messages.indexed) ...[
            if (index > 0) const SizedBox(height: 10),
            if (line.isThreadHeader)
              _ConversationThreadHeader(label: line.text)
            else if (line.isTeacher && line.isCorrectionFeedback)
              _TeacherCorrectionBubble(text: line.text)
            else if (line.isTeacher)
              _TeacherChatBubble(text: line.text)
            else
              _StudentChatBubble(text: line.text),
          ],
        ],
      ),
    );
  }
}

final class _TeacherTypingIndicator extends StatelessWidget {
  const _TeacherTypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withValues(alpha: .15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        const SizedBox(width: 8),
        const Text('AI 老师正在思考…', style: TextStyle(color: _muted, fontSize: 12)),
      ],
    );
  }
}

final class _TeacherChatBubble extends StatelessWidget {
  const _TeacherChatBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.school_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Color(0xFF1E3A5F),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _TeacherCorrectionBubble extends StatelessWidget {
  const _TeacherCorrectionBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.feedback_outlined,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Color(0xFF991B1B),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 回看态与真实学习进度并存；明确提示可避免用户误以为历史画板仍能继续提交。
final class _HistoryReviewBanner extends StatelessWidget {
  const _HistoryReviewBanner({required this.onReturnToCurrent});

  final VoidCallback? onReturnToCurrent;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('history-review-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, color: Color(0xFFB45309), size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '正在回看历史画板，当前学习进度不会改变。',
              style: TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton.icon(
            key: const ValueKey('return-to-current-board'),
            onPressed: onReturnToCurrent,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('返回当前学习'),
          ),
        ],
      ),
    );
  }
}

final class _ClassroomBoardHeader extends StatelessWidget {
  const _ClassroomBoardHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.dashboard_customize_outlined,
            size: 18,
            color: Color(0xFF2563EB),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: Color(0xFF1E3A8A),
            ),
          ),
        ],
      ),
    );
  }
}

final class _StudentChatBubble extends StatelessWidget {
  const _StudentChatBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFDBEAFE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF93C5FD)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            height: 1.4,
            color: Color(0xFF1E3A8A),
          ),
        ),
      ),
    );
  }
}

final class _IntroReplyBar extends StatelessWidget {
  const _IntroReplyBar({
    required this.controller,
    required this.submitting,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool submitting;
  final void Function([String? preset]) onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8E4EE))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                label: const Text('你好老师'),
                onPressed: submitting ? null : () => onSend('你好老师'),
              ),
              ActionChip(
                label: const Text('我还不太懂'),
                onPressed: submitting ? null : () => onSend('我还不太懂'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !submitting,
                  textInputAction: TextInputAction.send,
                  onSubmitted: submitting ? null : (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: '写下你的想法，跟 AI 老师聊几句…',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: submitting ? null : () => onSend(),
                child: const Text('发送'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class TeachingModeHistoryEntry {
  const TeachingModeHistoryEntry({
    required this.label,
    this.nodeId,
    this.boardId,
    this.isActive = false,
    this.isCompleted = false,
    this.depth = 0,
    this.kind,
    this.isSectionHeader = false,
    this.isGoalHeader = false,
    this.goalStatus,
  });

  final String label;
  final String? nodeId;
  final String? boardId;
  final bool isActive;
  final bool isCompleted;
  final int depth;
  final String? kind;
  final bool isSectionHeader;
  final bool isGoalHeader;

  /// `ongoing` | `completed` | `pending`
  final String? goalStatus;
}

/// 章节入口默认选路文案；寒暄本身由服务端会话 turn 驱动。
abstract final class TeachingModeOptionCatalog {
  static List<RemoteTeachingModeOption> forTopic(String topic) {
    final label = topic.trim().isEmpty ? '这个概念' : topic.trim();
    return [
      RemoteTeachingModeOption(
        skill: 'MORE_EXAMPLES',
        label: '多看几个例子',
        icon: '📚',
        description: '我想多看几个关于$label的例子，我还不太懂',
      ),
      RemoteTeachingModeOption(
        skill: 'INTERACTIVE_EXPLORATION',
        label: '动手判断 ∈/∉',
        icon: '🎮',
        description: '我想玩一个跟$label有关的小互动',
      ),
      RemoteTeachingModeOption(
        skill: 'CONCEPT_HISTORY',
        label: '了解概念由来',
        icon: '🕰',
        description: '我想听听「$label」这个概念是怎么来的',
      ),
    ];
  }

  static List<TeachingModeHistoryEntry> fromChapterPhases(
    LearningChapterOverviewSnapshot chapter,
  ) {
    return [
      for (final phase in chapter.phases)
        TeachingModeHistoryEntry(label: phase.title),
    ];
  }

  static List<TeachingModeHistoryEntry> fromSessionPath(
    List<RemoteLearningNode> path,
  ) {
    return [
      for (final node in path)
        TeachingModeHistoryEntry(label: node.question, nodeId: node.id),
    ];
  }

  static List<RemoteTeachingModeOption> optionsForChapter(
    LearningChapterOverviewSnapshot chapter,
    String topic,
  ) {
    return chapter.entryGuidance?.designArenaOptions ?? forTopic(topic);
  }

  static String modePromptForChapter(
    LearningChapterOverviewSnapshot chapter,
    String topic,
  ) {
    return chapter.entryGuidance?.modePromptFor(topic) ??
        '关于「${topic.trim().isEmpty ? '本节课内容' : topic.trim()}」，你希望 AI 老师接下来怎么带你学？';
  }
}

typedef _SidebarGoalSection = ({
  TeachingModeHistoryEntry header,
  List<TeachingModeHistoryEntry> children,
});

/// 以“开场—教学目标—教学节点”的结构展示本节课学习地图。
final class ModeSelectionSidebar extends StatefulWidget {
  const ModeSelectionSidebar({
    super.key,
    required this.entries,
    required this.mobile,
    this.onBoardTap,
    this.onHistoryTap,
    this.onCollapse,
    this.selectedBoardId,
    this.selectedNodeId,
    this.onFunctionAreaATap,
  });

  final List<TeachingModeHistoryEntry> entries;
  final void Function(String boardId)? onBoardTap;
  final void Function(String nodeId)? onHistoryTap;
  final bool mobile;
  final VoidCallback? onCollapse;
  final String? selectedBoardId;
  final String? selectedNodeId;
  final VoidCallback? onFunctionAreaATap;

  static const _functionAreas = [
    (
      icon: Icons.grid_view_rounded,
      label: '功能区A · 数学实验',
      color: Color(0xFF3B82F6),
    ),
    (icon: Icons.menu_book_rounded, label: '功能区B', color: Color(0xFF8B5CF6)),
    (icon: Icons.bar_chart_rounded, label: '功能区C', color: Color(0xFF22C55E)),
    (icon: Icons.star_rounded, label: '功能区D', color: Color(0xFFF59E0B)),
  ];

  @override
  State<ModeSelectionSidebar> createState() => _ModeSelectionSidebarState();

  static bool _isSelected(
    TeachingModeHistoryEntry entry,
    String? selectedBoardId,
    String? selectedNodeId,
  ) {
    return entry.boardId == selectedBoardId ||
        (entry.boardId == null &&
            entry.nodeId != null &&
            entry.nodeId == selectedNodeId) ||
        (entry.isActive && selectedBoardId == null && selectedNodeId == null);
  }

  static Color _entryBackground(
    TeachingModeHistoryEntry entry,
    String? selectedBoardId,
    String? selectedNodeId,
  ) {
    if (_isSelected(entry, selectedBoardId, selectedNodeId)) {
      return const Color(0xFFE8F0FF);
    }
    if (entry.isActive) return const Color(0xFFF3F7FF);
    if (entry.kind == 'SUPPORT_BRANCH') {
      return const Color(0xFFFFF7ED);
    }
    return Colors.white;
  }

  static Color _entryIconColor(
    TeachingModeHistoryEntry entry,
    String? selectedBoardId,
    String? selectedNodeId,
  ) {
    if (_isSelected(entry, selectedBoardId, selectedNodeId)) {
      return const Color(0xFF1D4ED8);
    }
    return switch (entry.kind) {
      'CONCEPT' => const Color(0xFFF59E0B),
      'INTERACTION' => const Color(0xFF8B5CF6),
      'CHECK' => const Color(0xFF2563EB),
      'SUPPORT_BRANCH' => const Color(0xFFEA580C),
      'EXAMPLE' => const Color(0xFF64748B),
      _ => const Color(0xFF64748B),
    };
  }

  static IconData _entryIcon(String? kind) {
    return switch (kind) {
      'OPENING' => Icons.waving_hand_outlined,
      'MODE_SELECTION' => Icons.alt_route_rounded,
      'CONCEPT' => Icons.lightbulb_outline_rounded,
      'INTERACTION' => Icons.extension_outlined,
      'EXAMPLE' => Icons.search_rounded,
      'CHECK' => Icons.edit_note_rounded,
      'SUPPORT_BRANCH' => Icons.support_agent_rounded,
      _ => Icons.circle_outlined,
    };
  }
}

final class _ModeSelectionSidebarState extends State<ModeSelectionSidebar> {
  String? _expandedGoalLabel;
  String? _lastActiveGoalLabel;
  String? _lastSelectedGoalLabel;

  @override
  void initState() {
    super.initState();
    _lastActiveGoalLabel = _activeGoalLabel(widget.entries);
    _lastSelectedGoalLabel = _selectedGoalLabel(widget.entries);
    final goalSections = _goalSections(widget.entries);
    _expandedGoalLabel =
        _lastSelectedGoalLabel ??
        _lastActiveGoalLabel ??
        (goalSections.isEmpty ? null : goalSections.first.header.label);
  }

  @override
  void didUpdateWidget(covariant ModeSelectionSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeGoalLabel = _activeGoalLabel(widget.entries);
    final selectedGoalLabel = _selectedGoalLabel(widget.entries);
    if (selectedGoalLabel != null &&
        selectedGoalLabel != _lastSelectedGoalLabel) {
      _expandedGoalLabel = selectedGoalLabel;
    } else if (activeGoalLabel != _lastActiveGoalLabel &&
        (_expandedGoalLabel == null ||
            _expandedGoalLabel == _lastActiveGoalLabel)) {
      // 正常推进时跟随新的 Goal；明确回看旧 Goal 时保留用户展开选择。
      _expandedGoalLabel = activeGoalLabel;
    }
    _lastActiveGoalLabel = activeGoalLabel;
    _lastSelectedGoalLabel = selectedGoalLabel;
  }

  List<_SidebarGoalSection> _goalSections(
    List<TeachingModeHistoryEntry> entries,
  ) {
    final sections = <_SidebarGoalSection>[];
    TeachingModeHistoryEntry? header;
    var children = <TeachingModeHistoryEntry>[];
    for (final entry in entries) {
      if (entry.isGoalHeader || entry.isSectionHeader) {
        if (header != null) {
          sections.add((header: header, children: List.unmodifiable(children)));
        }
        header = entry;
        children = [];
      } else if (header != null) {
        children.add(entry);
      }
    }
    if (header != null) {
      sections.add((header: header, children: List.unmodifiable(children)));
    }
    return List.unmodifiable(sections);
  }

  List<TeachingModeHistoryEntry> _openingEntries(
    List<TeachingModeHistoryEntry> entries,
  ) {
    return entries
        .takeWhile((entry) => !entry.isGoalHeader && !entry.isSectionHeader)
        .toList(growable: false);
  }

  String? _activeGoalLabel(List<TeachingModeHistoryEntry> entries) {
    for (final section in _goalSections(entries)) {
      if (section.header.goalStatus == 'ongoing' ||
          section.children.any((entry) => entry.isActive)) {
        return section.header.label;
      }
    }
    return null;
  }

  String? _selectedGoalLabel(List<TeachingModeHistoryEntry> entries) {
    for (final section in _goalSections(entries)) {
      if (section.children.any(
        (entry) => ModeSelectionSidebar._isSelected(
          entry,
          widget.selectedBoardId,
          widget.selectedNodeId,
        ),
      )) {
        return section.header.label;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final openingEntries = _openingEntries(widget.entries);
    final goalSections = _goalSections(widget.entries);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: widget.mobile ? 236 : 272,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(right: BorderSide(color: Color(0xFFE8E4EE))),
        ),
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onCollapse != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: '收起侧边栏',
                    onPressed: widget.onCollapse,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  children: [
                    Container(
                      key: const ValueKey('lesson-map-card'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFDCE8FF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.auto_stories_outlined,
                                size: 18,
                                color: Color(0xFF3B82F6),
                              ),
                              SizedBox(width: 7),
                              Text(
                                '本节课',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '查看老师带你完成的学习路径',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                          if (openingEntries.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _openingStage(openingEntries),
                          ],
                          for (final section in goalSections) ...[
                            const SizedBox(height: 10),
                            _goalSection(section),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFE8E4EE)),
                    const SizedBox(height: 6),
                    for (final area in ModeSelectionSidebar._functionAreas)
                      InkWell(
                        onTap: area.label.startsWith('功能区A')
                            ? widget.onFunctionAreaATap
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: area.color.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  area.icon,
                                  size: 18,
                                  color: area.color,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  area.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, size: 18),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _openingStage(List<TeachingModeHistoryEntry> entries) {
    final isCompleted = entries.every((entry) => entry.isCompleted);
    return Container(
      key: const ValueKey('lesson-opening-stage'),
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isCompleted ? Icons.check_circle : Icons.play_circle_outline,
                size: 15,
                color: isCompleted
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF3B82F6),
              ),
              const SizedBox(width: 6),
              const Text(
                '开场',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final entry in entries) _entryTile(entry, compact: true),
        ],
      ),
    );
  }

  Widget _goalSection(_SidebarGoalSection section) {
    final isExpanded = _expandedGoalLabel == section.header.label;
    final status = section.header.goalStatus ?? 'pending';
    final isCurrent = status == 'ongoing';
    return Container(
      key: ValueKey('goal-section-${section.header.label}'),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFFF8FBFF) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrent ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('goal-header-${section.header.label}'),
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                _expandedGoalLabel = isExpanded ? null : section.header.label;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 17,
                    color: const Color(0xFF475569),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      section.header.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  if (section.header.goalStatus != null)
                    _GoalStatusBadge(status: section.header.goalStatus!),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFE8EEF7)),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
              child: Column(
                children: [
                  for (final entry in section.children) _entryTile(entry),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _entryTile(TeachingModeHistoryEntry entry, {bool compact = false}) {
    final isExample = entry.kind == 'EXAMPLE';
    final isActive = entry.isActive;
    final leftIndent = compact
        ? 8.0
        : (entry.depth * (isExample ? 9 : 7)).toDouble();
    final onTap = entry.boardId != null && widget.onBoardTap != null
        ? () => widget.onBoardTap!(entry.boardId!)
        : entry.nodeId == null || widget.onHistoryTap == null
        ? null
        : () => widget.onHistoryTap!(entry.nodeId!);
    return Padding(
      padding: EdgeInsets.only(bottom: 3, left: leftIndent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isActive)
            Container(
              width: 3,
              height: compact ? 22 : 28,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          Expanded(
            child: Material(
              color: ModeSelectionSidebar._entryBackground(
                entry,
                widget.selectedBoardId,
                widget.selectedNodeId,
              ),
              borderRadius: BorderRadius.circular(7),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(7),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 5 : 6,
                    vertical: compact ? 4 : (isExample ? 4 : 6),
                  ),
                  child: Row(
                    children: [
                      _EntryStatusIcon(
                        entry: entry,
                        selectedBoardId: widget.selectedBoardId,
                        selectedNodeId: widget.selectedNodeId,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: Icon(
                          ModeSelectionSidebar._entryIcon(entry.kind),
                          size: isExample || compact ? 12 : 14,
                          color: ModeSelectionSidebar._entryIconColor(
                            entry,
                            widget.selectedBoardId,
                            widget.selectedNodeId,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isExample || compact ? 10.5 : 11,
                            height: 1.3,
                            fontWeight: isActive
                                ? FontWeight.w800
                                : isExample
                                ? FontWeight.w400
                                : FontWeight.w600,
                            color: isActive
                                ? const Color(0xFF1D4ED8)
                                : isExample
                                ? const Color(0xFF64748B)
                                : const Color(0xFF334155),
                          ),
                        ),
                      ),
                      if (isActive)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text(
                            '当前',
                            style: TextStyle(
                              color: Color(0xFF2563EB),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _GoalStatusBadge extends StatelessWidget {
  const _GoalStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status) {
      'ongoing' => ('当前学习', const Color(0xFF15803D), const Color(0xFFDCFCE7)),
      'completed' => ('已完成', const Color(0xFF1D4ED8), const Color(0xFFDBEAFE)),
      _ => ('未开始', const Color(0xFF64748B), const Color(0xFFF1F5F9)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

final class _EntryStatusIcon extends StatelessWidget {
  const _EntryStatusIcon({
    required this.entry,
    required this.selectedBoardId,
    required this.selectedNodeId,
  });

  final TeachingModeHistoryEntry entry;
  final String? selectedBoardId;
  final String? selectedNodeId;

  @override
  Widget build(BuildContext context) {
    final selected = ModeSelectionSidebar._isSelected(
      entry,
      selectedBoardId,
      selectedNodeId,
    );
    if (entry.isActive) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Icon(
          Icons.radio_button_checked,
          size: 14,
          color: selected ? const Color(0xFF2563EB) : const Color(0xFF93C5FD),
        ),
      );
    }
    if (entry.isCompleted) {
      return const Padding(
        padding: EdgeInsets.only(right: 6),
        child: Icon(Icons.check_circle, size: 14, color: Color(0xFF22C55E)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Icon(
        Icons.circle_outlined,
        size: 12,
        color: selected ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1),
      ),
    );
  }
}

final class TeacherModePromptBanner extends StatelessWidget {
  const TeacherModePromptBanner({super.key, required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('teaching-mode-teacher-prompt'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEAF4FF), Color(0xFFF5FAFF)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD6E8FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              prompt,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.45,
                color: Color(0xFF1E3A5F),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFBFDBFE),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.school_rounded,
              size: 36,
              color: Color(0xFF2563EB),
            ),
          ),
        ],
      ),
    );
  }
}

final class ModeSelectionChoiceRow extends StatelessWidget {
  const ModeSelectionChoiceRow({
    super.key,
    required this.options,
    required this.submitting,
    required this.onSelect,
    required this.mobile,
  });

  final List<RemoteTeachingModeOption> options;
  final bool submitting;
  final void Function(String skill) onSelect;
  final bool mobile;

  static const _palettes = [
    (accent: Color(0xFF3B82F6), soft: Color(0xFFEAF4FF)),
    (accent: Color(0xFF8B5CF6), soft: Color(0xFFF3EEFF)),
    (accent: Color(0xFF22C55E), soft: Color(0xFFEAFBF3)),
    (accent: Color(0xFFF59E0B), soft: Color(0xFFFFF8E6)),
  ];

  static const _optionLetters = ['A', 'B', 'C', 'D'];

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          '当前目标没有可选模式，AI 老师将直接进入必需的教学环节。',
          style: TextStyle(color: _muted),
          textAlign: TextAlign.center,
        ),
      );
    }

    final cards = [
      for (final (index, option) in options.indexed)
        ModeSelectionChoiceCard(
          option: option,
          optionLetter:
              _optionLetters[index.clamp(0, _optionLetters.length - 1)],
          palette: _palettes[index.clamp(0, _palettes.length - 1)],
          disabled: submitting,
          onTap: submitting ? null : () => onSelect(option.skill),
        ),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(mobile ? 12 : 20, 8, mobile ? 12 : 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8E4EE))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (submitting)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '正在按你的选择安排下一步内容…',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          if (mobile)
            Column(
              children: [
                for (final card in cards) ...[card, const SizedBox(height: 10)],
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, card) in cards.indexed) ...[
                  if (index > 0) const SizedBox(width: 14),
                  Expanded(child: card),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

final class ModeSelectionChoiceCard extends StatelessWidget {
  const ModeSelectionChoiceCard({
    super.key,
    required this.option,
    required this.optionLetter,
    required this.palette,
    required this.disabled,
    required this.onTap,
  });

  final RemoteTeachingModeOption option;
  final String optionLetter;
  final ({Color accent, Color soft}) palette;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.65 : 1,
      child: Material(
        color: Colors.white,
        elevation: 1,
        shadowColor: palette.accent.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: ValueKey('teaching-mode-option-${option.skill}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.soft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                  child: Column(
                    children: [
                      Text(option.icon, style: const TextStyle(fontSize: 36)),
                      const SizedBox(height: 12),
                      Text(
                        option.description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accent,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(17),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '选项$optionLetter',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        option.label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .92),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
