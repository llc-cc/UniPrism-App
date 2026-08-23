import '../adapters/remote_exploration_dto.dart';

/// 章节入口 / 选路前寒暄区展示的单条对话。
final class IntroChatMessage {
  const IntroChatMessage({
    required this.text,
    required this.isTeacher,
    this.isModePrompt = false,
    this.isCorrectionFeedback = false,
    this.isThreadHeader = false,
  });

  factory IntroChatMessage.teacher(String text, {bool isModePrompt = false}) {
    return IntroChatMessage(
      text: text,
      isTeacher: true,
      isModePrompt: isModePrompt,
    );
  }

  factory IntroChatMessage.teacherCorrection(String text) {
    return IntroChatMessage(
      text: text,
      isTeacher: true,
      isCorrectionFeedback: true,
    );
  }

  factory IntroChatMessage.student(String text) {
    return IntroChatMessage(text: text, isTeacher: false);
  }

  factory IntroChatMessage.threadHeader(String text) {
    return IntroChatMessage(text: text, isTeacher: true, isThreadHeader: true);
  }

  final String text;
  final bool isTeacher;
  final bool isModePrompt;
  final bool isCorrectionFeedback;
  final bool isThreadHeader;

  /// 从服务端会话路径投影聊天行；寒暄与选路前引导均走真实 turn 数据。
  static List<IntroChatMessage> fromSessionPath(
    List<RemoteLearningNode> path, {
    String? trailingTeacherPrompt,
    String? modeSelectionPrompt,
    bool appendModePrompt = false,
  }) {
    if (path.length == 1) {
      return fromSingleNode(
        path.first,
        trailingTeacherPrompt: trailingTeacherPrompt,
        modeSelectionPrompt: modeSelectionPrompt,
        appendModePrompt: appendModePrompt,
      );
    }

    final messages = <IntroChatMessage>[];
    for (final (index, node) in path.indexed) {
      messages.addAll(
        fromSingleNode(node, includeFollowUp: index == path.length - 1),
      );
    }

    final trailing = (trailingTeacherPrompt ?? '').trim();
    if (_shouldAppendTrailing(messages, trailing)) {
      messages.add(IntroChatMessage.teacher(trailing));
    }

    if (appendModePrompt) {
      final prompt = (modeSelectionPrompt ?? '').trim();
      if (prompt.isNotEmpty &&
          !messages.any((line) => line.isModePrompt && line.text == prompt)) {
        messages.add(IntroChatMessage.teacher(prompt, isModePrompt: true));
      }
    }

    return List.unmodifiable(messages);
  }

  /// 只展示单个节点画板内的对话，不包含其他节点内容。
  static List<IntroChatMessage> fromSingleNode(
    RemoteLearningNode node, {
    bool includeFollowUp = true,
    String? trailingTeacherPrompt,
    String? modeSelectionPrompt,
    bool appendModePrompt = false,
  }) {
    final messages = <IntroChatMessage>[];
    final question = node.question.trim();
    if (question.isNotEmpty) {
      messages.add(IntroChatMessage.student(question));
    }
    final answer = node.answer.trim();
    if (answer.isNotEmpty) {
      messages.add(IntroChatMessage.teacher(answer));
    }
    if (includeFollowUp) {
      final followUp = node.followUpQuestion.trim();
      if (followUp.isNotEmpty) {
        messages.add(IntroChatMessage.teacher(followUp));
      }
    }

    final trailing = (trailingTeacherPrompt ?? '').trim();
    if (_shouldAppendTrailing(messages, trailing)) {
      messages.add(IntroChatMessage.teacher(trailing));
    }

    if (appendModePrompt) {
      final prompt = (modeSelectionPrompt ?? '').trim();
      if (prompt.isNotEmpty &&
          !messages.any((line) => line.isModePrompt && line.text == prompt)) {
        messages.add(IntroChatMessage.teacher(prompt, isModePrompt: true));
      }
    }

    return List.unmodifiable(messages);
  }

  static bool _shouldAppendTrailing(
    List<IntroChatMessage> messages,
    String trailing,
  ) {
    if (trailing.isEmpty) return false;
    for (var index = messages.length - 1; index >= 0; index--) {
      final line = messages[index];
      if (!line.isTeacher) break;
      if (line.text == trailing) return false;
    }
    return true;
  }
}
