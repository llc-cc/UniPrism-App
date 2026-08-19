import '../adapters/guided_teaching_flow_dto.dart';
import '../adapters/remote_exploration_dto.dart';
import '../adapters/teaching_architecture_dto.dart';
import 'intro_chat_messages.dart';
import 'teaching_mode_selection_stage.dart';

/// 将服务端 TeachingBoard 投影为分层侧边栏节点与画板内完整对话。
abstract final class ClassroomBoardCatalog {
  static List<TeachingModeHistoryEntry> historyEntries(
    RemoteLearningSessionSnapshot snapshot,
  ) {
    final architecture = snapshot.teachingArchitecture;
    if (architecture != null && architecture.boards.isNotEmpty) {
      final isModeSelectionIntro =
          snapshot.processSchedulerState?.currentPhase ==
              RemoteTeachingPhase.modeSelection &&
          snapshot.studentGuidance?.showModeSelection == false;
      return _hierarchicalBoardEntries(
        snapshot,
        architecture,
        isModeSelectionIntro: isModeSelectionIntro,
      );
    }
    return _synthesizedFallbackEntries(snapshot);
  }

  static List<TeachingModeHistoryEntry> _hierarchicalBoardEntries(
    RemoteLearningSessionSnapshot snapshot,
    RemoteTeachingArchitectureSnapshot architecture, {
    required bool isModeSelectionIntro,
  }) {
    final entries = <TeachingModeHistoryEntry>[];
    int? lastGoalIndex;
    final repairCountByGoal = <int, int>{};
    final activeBoardId = _resolvedActiveBoardId(architecture);
    final activeBoardIndex = architecture.boards.indexWhere(
      (board) => board.id == activeBoardId,
    );

    for (final (index, board) in architecture.boards.indexed) {
      if (!_isStudentVisibleBoard(snapshot, board, activeBoardId)) continue;
      final isSessionLevel =
          board.kind == 'OPENING' || board.kind == 'MODE_SELECTION';
      if (!isSessionLevel &&
          board.goalIndex != null &&
          board.goalIndex != lastGoalIndex) {
        final goalIndex = board.goalIndex!;
        entries.add(
          TeachingModeHistoryEntry(
            label: _goalHeaderLabel(board.goalId, goalIndex),
            isGoalHeader: true,
            goalStatus: _goalStatus(architecture, goalIndex),
            depth: 0,
            kind: 'GOAL',
          ),
        );
        lastGoalIndex = goalIndex;
      }

      final repairIndex =
          board.kind == 'SUPPORT_BRANCH' && board.goalIndex != null
          ? () {
              final goalIdx = board.goalIndex!;
              repairCountByGoal[goalIdx] =
                  (repairCountByGoal[goalIdx] ?? 0) + 1;
              return repairCountByGoal[goalIdx];
            }()
          : null;
      final displayLabel = _studentBoardLabel(
        board,
        repairIndex: repairIndex,
        isModeSelectionIntro: isModeSelectionIntro && board.id == activeBoardId,
      );
      entries.add(
        TeachingModeHistoryEntry(
          label: displayLabel,
          boardId: board.id,
          nodeId: board.nodeIds.isNotEmpty ? board.nodeIds.first : null,
          isActive: board.id == activeBoardId,
          isCompleted: _isBoardCompleted(
            architecture,
            board,
            boardIndex: index,
            activeBoardIndex: activeBoardIndex,
          ),
          depth: _boardDepth(board),
          kind: board.kind,
        ),
      );
    }

    return List.unmodifiable(entries);
  }

  static bool _isStudentVisibleBoard(
    RemoteLearningSessionSnapshot snapshot,
    RemoteTeachingBoardSnapshot board,
    String? activeBoardId,
  ) {
    if (board.kind != 'EXAMPLE' && board.kind != 'INTERACTION') return true;
    if (board.id == activeBoardId) return true;
    // 素材可能已被教师调度器预生成；没有任何事件时不代表学生真正看到或完成过。
    return materialsForBoard(
      snapshot,
      board,
    ).any((material) => material.hasRecordedInteraction);
  }

  static String _goalHeaderLabel(String? goalId, int goalIndex) {
    final title = switch (goalId) {
      'G1' => '集合定义与三大特性',
      'G2' => '列举法与描述法',
      'G3' => '常用数集符号',
      _ => switch (goalIndex) {
        0 => '集合与元素',
        1 => '集合的表示',
        _ => '本节学习',
      },
    };
    final prefix = goalId ?? 'G${goalIndex + 1}';
    return '$prefix · $title';
  }

  static String? _goalStatus(
    RemoteTeachingArchitectureSnapshot architecture,
    int goalIndex,
  ) {
    final boardsForGoal = architecture.boards
        .where((board) => board.goalIndex == goalIndex)
        .toList(growable: false);
    if (boardsForGoal.isEmpty) return 'pending';
    final activeGoalIndex = architecture
        .boardById(_resolvedActiveBoardId(architecture))
        ?.goalIndex;
    if (activeGoalIndex == goalIndex) return 'ongoing';
    if (activeGoalIndex != null && goalIndex < activeGoalIndex) {
      return 'completed';
    }
    if (boardsForGoal.every((board) => !board.isActive)) {
      final lastBoard = boardsForGoal.last;
      if (lastBoard.kind == 'CHECK' || lastBoard.kind == 'SUPPORT_BRANCH') {
        return 'ongoing';
      }
    }
    return 'pending';
  }

  static bool _isBoardCompleted(
    RemoteTeachingArchitectureSnapshot architecture,
    RemoteTeachingBoardSnapshot board, {
    required int boardIndex,
    required int activeBoardIndex,
  }) {
    if (board.id == _resolvedActiveBoardId(architecture)) return false;
    if (board.kind == 'CHECK' && board.practiceAttemptIds.isNotEmpty) {
      final openedRepair = architecture.branches.any(
        (branch) =>
            branch.closedAt == null &&
            board.practiceAttemptIds.contains(branch.triggerPracticeAttemptId),
      );
      // 检测失败后进入补救分支时，原检测只能标记为“待复测”，不能因位于当前画板之前而误显示完成。
      if (openedRepair) return false;
    }
    if (activeBoardIndex >= 0 && boardIndex < activeBoardIndex) return true;
    if (board.kind == 'SUPPORT_BRANCH' && board.branchId != null) {
      final branch = architecture.branches
          .where((item) => item.id == board.branchId)
          .firstOrNull;
      return branch?.closedAt != null;
    }
    return false;
  }

  static String? _resolvedActiveBoardId(
    RemoteTeachingArchitectureSnapshot architecture,
  ) {
    final declaredId = architecture.activeBoardId;
    if (declaredId != null && architecture.boardById(declaredId) != null) {
      return declaredId;
    }
    // 兼容旧快照：新协议以 activeBoardId 为准，缺失时才回退到画板自身的活动标记。
    return architecture.boards
        .where((board) => board.isActive)
        .map((board) => board.id)
        .firstOrNull;
  }

  static List<TeachingModeHistoryEntry> _synthesizedFallbackEntries(
    RemoteLearningSessionSnapshot snapshot,
  ) {
    final proc = snapshot.processSchedulerState;
    final goalIndex = proc?.currentGoalIndex ?? 0;
    final entries = <TeachingModeHistoryEntry>[
      const TeachingModeHistoryEntry(
        label: '寒暄 · 了解基础',
        depth: 0,
        kind: 'OPENING',
      ),
    ];

    if (snapshot.nodes.length > 1) {
      entries.add(
        const TeachingModeHistoryEntry(
          label: '学习方式',
          depth: 0,
          kind: 'MODE_SELECTION',
        ),
      );
    }

    entries.add(
      TeachingModeHistoryEntry(
        label: _studentSectionLabel(goalIndex, null),
        isSectionHeader: true,
        depth: 0,
        kind: 'SECTION',
      ),
    );

    final phase = proc?.currentPhase;
    if (phase == RemoteTeachingPhase.extraSupport) {
      entries.add(
        const TeachingModeHistoryEntry(
          label: '老师辅导',
          depth: 2,
          kind: 'SUPPORT_BRANCH',
          isActive: true,
        ),
      );
    } else if (phase == RemoteTeachingPhase.understandingCheck ||
        snapshot.teachingFlow?.stage == RemoteTeachingStage.focus) {
      entries.add(
        const TeachingModeHistoryEntry(
          label: '练一练',
          depth: 1,
          kind: 'CHECK',
          isActive: true,
        ),
      );
    } else {
      entries.add(
        const TeachingModeHistoryEntry(
          label: '概念梳理',
          depth: 1,
          kind: 'CONCEPT',
          isActive: true,
        ),
      );
    }

    return List.unmodifiable(entries);
  }

  static String _studentSectionLabel(int goalIndex, String? goalId) {
    return switch (goalId) {
      'G1' => '集合与元素',
      'G2' => '集合的表示',
      _ => switch (goalIndex) {
        0 => '集合与元素',
        1 => '集合的表示',
        _ => '本节学习',
      },
    };
  }

  static String _studentBoardLabel(
    RemoteTeachingBoardSnapshot board, {
    int? repairIndex,
    bool isModeSelectionIntro = false,
  }) {
    final normalized = _sanitizeLabel(board.label);
    final coreLabel = normalized.isNotEmpty && !_looksLikeDevLabel(normalized)
        ? normalized
        : _fallbackBoardLabel(board);

    return switch (board.kind) {
      'OPENING' => '寒暄 · 了解基础',
      'MODE_SELECTION' when isModeSelectionIntro => '寒暄 · 了解基础',
      'MODE_SELECTION' => '学习方式',
      'CONCEPT' => coreLabel.startsWith('概念') ? coreLabel : '概念：$coreLabel',
      'INTERACTION' => coreLabel.startsWith('互动') ? coreLabel : '互动：$coreLabel',
      'EXAMPLE' => coreLabel.startsWith('例子') ? coreLabel : '例子：$coreLabel',
      'CHECK' => coreLabel.startsWith('练习') ? coreLabel : '练习：$coreLabel',
      'SUPPORT_BRANCH' =>
        repairIndex != null
            ? '老师帮助 #$repairIndex'
            : (board.knowledgeNodeNames.isNotEmpty
                  ? '老师帮助 · ${board.knowledgeNodeNames.first}'
                  : '老师帮助'),
      _ => coreLabel,
    };
  }

  static String _fallbackBoardLabel(RemoteTeachingBoardSnapshot board) {
    return switch (board.kind) {
      'OPENING' => '寒暄 · 了解基础',
      'MODE_SELECTION' => '学习方式',
      'CONCEPT' => '概念梳理',
      'INTERACTION' =>
        board.knowledgeNodeNames.isNotEmpty
            ? board.knowledgeNodeNames.first
            : '动手试一试',
      'EXAMPLE' =>
        board.knowledgeNodeNames.isNotEmpty
            ? board.knowledgeNodeNames.first
            : '看一看例子',
      'CHECK' =>
        board.knowledgeNodeNames.isNotEmpty
            ? board.knowledgeNodeNames.first
            : '练一练',
      'SUPPORT_BRANCH' =>
        board.knowledgeNodeNames.isNotEmpty
            ? board.knowledgeNodeNames.first
            : '老师辅导',
      _ => '学习',
    };
  }

  static String _sanitizeLabel(String label) {
    return label
        .replaceAll(RegExp(r'^G\d+\s*[·.]?\s*'), '')
        .replaceAll(RegExp(r'^概念[：:]\s*'), '')
        .replaceAll(RegExp(r'^练习[：:]\s*'), '')
        .replaceAll(RegExp(r'^互动[：:]\s*'), '')
        .replaceAll(RegExp(r'^例子[：:]\s*'), '')
        .replaceAll(RegExp(r'^补救#\d+'), '老师辅导')
        .replaceAll(RegExp(r'set-[a-z0-9-]+', caseSensitive: false), '')
        .trim();
  }

  static bool _looksLikeDevLabel(String label) {
    if (label.isEmpty) return true;
    if (RegExp(r'^G\d+').hasMatch(label)) return true;
    if (RegExp(r'set-[a-z0-9-]+', caseSensitive: false).hasMatch(label)) {
      return true;
    }
    if (label == 'OPENING' ||
        label == 'MODE_SELECTION' ||
        label == 'CONCEPT' ||
        label == 'CHECK' ||
        label == 'SUPPORT_BRANCH') {
      return true;
    }
    return false;
  }

  static int _boardDepth(RemoteTeachingBoardSnapshot board) {
    return switch (board.kind) {
      'OPENING' || 'MODE_SELECTION' => 0,
      'EXAMPLE' || 'SUPPORT_BRANCH' => 2,
      _ => 1,
    };
  }

  static String? boardIdForNode(
    RemoteLearningSessionSnapshot snapshot,
    String nodeId,
  ) {
    final architecture = snapshot.teachingArchitecture;
    if (architecture == null) return null;
    for (final board in architecture.boards.reversed) {
      if (board.nodeIds.contains(nodeId)) return board.id;
    }
    return null;
  }

  static String? resolveFocusBoardId(
    RemoteLearningSessionSnapshot snapshot,
    String? inspectedBoardId,
  ) {
    final architecture = snapshot.teachingArchitecture;
    if (architecture == null || architecture.boards.isEmpty) return null;
    if (inspectedBoardId != null &&
        architecture.boardById(inspectedBoardId) != null) {
      return inspectedBoardId;
    }
    return architecture.activeBoardId ?? architecture.boards.last.id;
  }

  static List<IntroChatMessage> messagesForBoard(
    RemoteLearningSessionSnapshot snapshot,
    String boardId, {
    String? trailingTeacherPrompt,
    String? modeSelectionPrompt,
    bool appendModePrompt = false,
    RemoteTeachingFlow? liveTeachingFlow,
  }) {
    final architecture = snapshot.teachingArchitecture;
    final board = architecture?.boardById(boardId);
    if (board == null) {
      final nodeId = snapshot.currentNodeId;
      if (nodeId == null) return const [];
      return messagesForNode(
        snapshot,
        nodeId,
        trailingTeacherPrompt: trailingTeacherPrompt,
        modeSelectionPrompt: modeSelectionPrompt,
        appendModePrompt: appendModePrompt,
        liveTeachingFlow: liveTeachingFlow,
      );
    }

    final isActive = board.isActive;
    final messages = <IntroChatMessage>[];

    for (final node in nodesForBoard(snapshot, board)) {
      messages.addAll(IntroChatMessage.fromSingleNode(node));
    }

    if (board.practiceAttemptIds.isNotEmpty) {
      final hasStudentLine = board.nodeIds.any((nodeId) {
        final node = snapshot.nodeById(nodeId);
        return node?.question.trim().isNotEmpty == true;
      });
      if (!hasStudentLine) {
        final branch = architecture?.branches
            .where(
              (item) =>
                  item.triggerPracticeAttemptId ==
                  board.practiceAttemptIds.first,
            )
            .firstOrNull;
        final practiceNode = board.practiceId == null
            ? null
            : snapshot.learningGraph?.practice
                  .where((item) => item.id == board.practiceId)
                  .firstOrNull;
        final triggerText = branch?.triggerStudentText?.trim();
        if (triggerText != null && triggerText.isNotEmpty) {
          for (final line
              in triggerText
                  .split('\n')
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)) {
            messages.add(IntroChatMessage.student(line));
          }
        } else if (practiceNode != null) {
          final reasoning = practiceNode.latestReasoning?.trim();
          final answer = practiceNode.latestAnswer?.trim();
          if (reasoning != null && reasoning.isNotEmpty) {
            messages.add(IntroChatMessage.student(reasoning));
          }
          if (answer != null && answer.isNotEmpty && answer != reasoning) {
            messages.add(IntroChatMessage.student('结论：$answer'));
          }
        }
        final practiceFeedback = practiceNode?.feedback?.trim();
        final feedback = practiceFeedback?.isNotEmpty == true
            ? practiceFeedback
            : branch?.feedback.trim();
        if (feedback != null &&
            feedback.isNotEmpty &&
            board.kind == 'CHECK' &&
            !messages.any((line) => line.isTeacher && line.text == feedback)) {
          messages.add(IntroChatMessage.teacherCorrection(feedback));
        }
      }
    }

    if (board.branchId != null) {
      final branch = architecture!.branches
          .where((item) => item.id == board.branchId)
          .firstOrNull;
      if (branch != null) {
        if (branch.feedback.trim().isNotEmpty &&
            !messages.any(
              (line) => line.isTeacher && line.text == branch.feedback.trim(),
            )) {
          messages.add(
            IntroChatMessage.teacherCorrection(branch.feedback.trim()),
          );
        }
        final repair = branch.repairFocus?.trim();
        if (repair != null && repair.isNotEmpty) {
          messages.add(IntroChatMessage.teacher('这次重点看这里：$repair'));
        }
      }
    } else if (isActive && liveTeachingFlow != null) {
      messages.addAll(_liveFlowMessages(snapshot, liveTeachingFlow));
    }

    if (isActive) {
      final trailing = (trailingTeacherPrompt ?? '').trim();
      if (trailing.isNotEmpty &&
          !messages.any((line) => line.isTeacher && line.text == trailing)) {
        messages.add(IntroChatMessage.teacher(trailing));
      }
      if (appendModePrompt) {
        final prompt = (modeSelectionPrompt ?? '').trim();
        if (prompt.isNotEmpty &&
            !messages.any((line) => line.isModePrompt && line.text == prompt)) {
          messages.add(IntroChatMessage.teacher(prompt, isModePrompt: true));
        }
      }
    }

    return List.unmodifiable(messages);
  }

  /// 历史画板优先读取服务端显式 nodeIds；旧快照缺失归属时，再用素材关联节点和画板时间窗补齐。
  /// 补齐只影响只读展示，不回写会话，也不把同一轮对话重复投影成新节点。
  static List<RemoteLearningNode> nodesForBoard(
    RemoteLearningSessionSnapshot snapshot,
    RemoteTeachingBoardSnapshot board,
  ) {
    final nodeIds = <String>{...board.nodeIds};
    for (final material in materialsForBoard(snapshot, board)) {
      nodeIds.add(material.nodeId);
    }

    final boards = snapshot.teachingArchitecture?.boards ?? const [];
    final boardIndex = boards.indexWhere((item) => item.id == board.id);
    final openedAt = DateTime.tryParse(board.openedAt);
    final nextOpenedAt = boardIndex >= 0 && boardIndex + 1 < boards.length
        ? DateTime.tryParse(boards[boardIndex + 1].openedAt)
        : null;
    if (openedAt != null) {
      for (final node in snapshot.nodes) {
        final createdAt = DateTime.tryParse(node.createdAt);
        if (createdAt == null || createdAt.isBefore(openedAt)) continue;
        if (nextOpenedAt != null && !createdAt.isBefore(nextOpenedAt)) {
          continue;
        }
        nodeIds.add(node.id);
      }
    }

    final nodes =
        snapshot.nodes
            .where((node) => nodeIds.contains(node.id))
            .toList(growable: false)
          ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return List.unmodifiable(nodes);
  }

  static List<RemoteLearningMaterial> materialsForBoard(
    RemoteLearningSessionSnapshot snapshot,
    RemoteTeachingBoardSnapshot board,
  ) {
    final usageIds = board.materialUsageIds.toSet();
    if (usageIds.isEmpty) return const [];
    return List.unmodifiable(
      snapshot.materials.where((material) => usageIds.contains(material.id)),
    );
  }

  static RemoteLearningPracticeNode? practiceForBoard(
    RemoteLearningSessionSnapshot snapshot,
    RemoteTeachingBoardSnapshot board,
  ) {
    final practiceId = board.practiceId;
    if (practiceId == null) return null;
    for (final practice in snapshot.learningGraph?.practice ?? const []) {
      if (practice.id == practiceId) return practice;
    }
    return null;
  }

  static List<IntroChatMessage> messagesForNode(
    RemoteLearningSessionSnapshot snapshot,
    String focusNodeId, {
    String? trailingTeacherPrompt,
    String? modeSelectionPrompt,
    bool appendModePrompt = false,
    RemoteTeachingFlow? liveTeachingFlow,
  }) {
    final boardId = boardIdForNode(snapshot, focusNodeId);
    if (boardId != null) {
      return messagesForBoard(
        snapshot,
        boardId,
        trailingTeacherPrompt: trailingTeacherPrompt,
        modeSelectionPrompt: modeSelectionPrompt,
        appendModePrompt: appendModePrompt,
        liveTeachingFlow: liveTeachingFlow,
      );
    }

    final node = snapshot.nodeById(focusNodeId);
    if (node == null) return const [];

    final isCurrent = focusNodeId == snapshot.currentNodeId;
    final messages = IntroChatMessage.fromSingleNode(
      node,
      trailingTeacherPrompt: isCurrent ? trailingTeacherPrompt : null,
      modeSelectionPrompt: isCurrent ? modeSelectionPrompt : null,
      appendModePrompt: isCurrent && appendModePrompt,
    );

    if (!isCurrent || liveTeachingFlow == null) {
      return messages;
    }

    final flowMessages = _liveFlowMessages(snapshot, liveTeachingFlow);
    if (flowMessages.isEmpty) return messages;

    return List.unmodifiable([...messages, ...flowMessages]);
  }

  static List<IntroChatMessage> _liveFlowMessages(
    RemoteLearningSessionSnapshot snapshot,
    RemoteTeachingFlow flow,
  ) {
    final feedback = flow.feedback?.trim();
    final repairFocus = flow.repairFocus?.trim();
    final proc = snapshot.processSchedulerState?.currentPhase;
    final lines = <IntroChatMessage>[];

    if (feedback != null && feedback.isNotEmpty) {
      final isCorrection =
          flow.explorationAct == RemoteGuidedExplorationAct.practiceRepair ||
          proc == RemoteTeachingPhase.extraSupport;
      lines.add(
        isCorrection
            ? IntroChatMessage.teacherCorrection(feedback)
            : IntroChatMessage.teacher(feedback),
      );
    }

    if (repairFocus != null &&
        repairFocus.isNotEmpty &&
        repairFocus != feedback &&
        (flow.explorationAct == RemoteGuidedExplorationAct.practiceRepair ||
            proc == RemoteTeachingPhase.extraSupport)) {
      lines.add(IntroChatMessage.teacher('这次重点看这里：$repairFocus'));
    }

    if (flow.stage == RemoteTeachingStage.dialogue &&
        flow.explorationAct == RemoteGuidedExplorationAct.practiceRepair) {
      final prompt = flow.currentAction.prompt.trim();
      if (prompt.isNotEmpty && prompt != feedback && prompt != repairFocus) {
        lines.add(IntroChatMessage.teacher(prompt));
      }
    }

    return lines;
  }

  static String boardPanelTitle(
    RemoteTeachingBoardSnapshot board, {
    bool isModeSelectionIntro = false,
  }) {
    final normalized = _sanitizeLabel(board.label);
    final label = normalized.isNotEmpty && !_looksLikeDevLabel(normalized)
        ? normalized
        : _fallbackBoardLabel(board);
    return switch (board.kind) {
      'OPENING' => '课前交流',
      'MODE_SELECTION' when isModeSelectionIntro => '课前交流',
      'MODE_SELECTION' => '选择学习方式',
      'CHECK' => '练习 · $label',
      'SUPPORT_BRANCH' => _studentBoardLabel(board),
      'INTERACTION' => '互动 · $label',
      'CONCEPT' => '概念 · $label',
      'EXAMPLE' => '例子 · $label',
      _ => label,
    };
  }
}

extension _BoardIterableHelpers<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
