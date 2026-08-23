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
    final emittedExplorationGoals = <int>{};
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
            goalStatus: _goalStatus(snapshot, architecture, goalIndex),
            depth: 0,
            kind: 'GOAL',
          ),
        );
        lastGoalIndex = goalIndex;
      }

      if (_isExplorationActivityBoard(board) && board.goalIndex != null) {
        final goalIndex = board.goalIndex!;
        if (emittedExplorationGoals.add(goalIndex)) {
          final group = _visibleExplorationBoardsForGoal(
            snapshot,
            architecture,
            goalIndex,
            activeBoardId,
          );
          final representative = _explorationRepresentative(
            group,
            activeBoardId,
          );
          if (representative != null) {
            // 素材、动手互动和练习虽由不同教学板承载，但学生完成的是同一段探索。
            // 侧栏只保留一个入口，点击后仍会按板归属读取完整内容，避免跨 Goal 串台。
            entries.add(
              TeachingModeHistoryEntry(
                label: explorationSegmentLabel(group),
                boardId: representative.id,
                nodeId: representative.nodeIds.isNotEmpty
                    ? representative.nodeIds.first
                    : null,
                isActive: group.any(
                  (item) => item.id == activeBoardId || item.isActive,
                ),
                isCompleted: group.every((item) {
                  final itemIndex = architecture.boards.indexOf(item);
                  return _isBoardCompleted(
                    architecture,
                    item,
                    boardIndex: itemIndex,
                    activeBoardIndex: activeBoardIndex,
                  );
                }),
                depth: 1,
                kind: 'INTERACTION',
              ),
            );
          }
        }
        continue;
      }

      final displayLabel = _studentBoardLabel(
        board,
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

  /// 学生端把“看例子—动手判断—完成练习”视为同一段连续任务。
  /// 后端仍保留细粒度 TeachingBoard，以便每条对话和补救分支准确归属。
  static bool _isExplorationActivityBoard(RemoteTeachingBoardSnapshot board) {
    return switch (board.kind) {
      'EXAMPLE' || 'INTERACTION' || 'CHECK' || 'SUPPORT_BRANCH' => true,
      _ => false,
    };
  }

  static List<RemoteTeachingBoardSnapshot> _visibleExplorationBoardsForGoal(
    RemoteLearningSessionSnapshot snapshot,
    RemoteTeachingArchitectureSnapshot architecture,
    int goalIndex,
    String? activeBoardId,
  ) {
    return architecture.boards
        .where(
          (board) =>
              board.goalIndex == goalIndex &&
              _isExplorationActivityBoard(board) &&
              _isStudentVisibleBoard(snapshot, board, activeBoardId),
        )
        .toList(growable: false);
  }

  static RemoteTeachingBoardSnapshot? _explorationRepresentative(
    List<RemoteTeachingBoardSnapshot> boards,
    String? activeBoardId,
  ) {
    if (boards.isEmpty) return null;
    return boards
            .where((board) => board.id == activeBoardId || board.isActive)
            .firstOrNull ??
        boards.where((board) => board.kind == 'INTERACTION').firstOrNull ??
        boards.where((board) => board.kind == 'EXAMPLE').firstOrNull ??
        boards.first;
  }

  /// 学生看到的是一个由互动主导的连续任务，例子和练习只作为该任务内的前后步骤。
  static String explorationSegmentLabel(
    Iterable<RemoteTeachingBoardSnapshot> boards,
  ) {
    final boardList = boards.toList(growable: false);
    final interaction = boardList
        .where((board) => board.kind == 'INTERACTION')
        .firstOrNull;
    final source = interaction ?? boardList.firstOrNull;
    if (source == null) return '互动与练习';
    final label = _sanitizeLabel(source.label);
    if (label.isEmpty || _looksLikeDevLabel(label)) return '互动与练习';
    return '互动与练习：$label';
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
    RemoteLearningSessionSnapshot snapshot,
    RemoteTeachingArchitectureSnapshot architecture,
    int goalIndex,
  ) {
    final boardsForGoal = architecture.boards
        .where((board) => board.goalIndex == goalIndex)
        .toList(growable: false);
    if (boardsForGoal.isEmpty) return 'pending';
    final scheduler = snapshot.processSchedulerState;
    if (scheduler != null) {
      // Goal 是否“当前”只能由课程调度器决定；旧 CHECK 画板仍存在不代表旧 Goal
      // 仍在学习，否则跨入下一 Goal 后会同时出现两个“当前学习”。
      if (goalIndex == scheduler.currentGoalIndex &&
          scheduler.currentPhase != RemoteTeachingPhase.goalComplete) {
        return 'ongoing';
      }
      final schedulerStatus = goalIndex < scheduler.goalStatuses.length
          ? scheduler.goalStatuses[goalIndex]
          : RemoteLessonGoalStatus.unknown;
      if (schedulerStatus == RemoteLessonGoalStatus.mastered ||
          goalIndex < scheduler.currentGoalIndex) {
        return 'completed';
      }
      return 'pending';
    }

    final activeGoalIndex = architecture
        .boardById(_resolvedActiveBoardId(architecture))
        ?.goalIndex;
    if (activeGoalIndex == goalIndex) return 'ongoing';
    if (activeGoalIndex != null && goalIndex < activeGoalIndex) {
      return 'completed';
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

  /// 返回学生在同一学习段中应连续看到的教学板。
  /// 只按同一 Goal 的显式归属聚合，不能依赖时间相邻，避免回看追问混入其他知识点。
  static List<RemoteTeachingBoardSnapshot> viewingBoardsFor(
    RemoteLearningSessionSnapshot snapshot,
    String boardId,
  ) {
    final architecture = snapshot.teachingArchitecture;
    final focusBoard = architecture?.boardById(boardId);
    if (architecture == null || focusBoard == null) return const [];
    if (!_isExplorationActivityBoard(focusBoard) ||
        focusBoard.goalIndex == null) {
      return [focusBoard];
    }
    final boards = _visibleExplorationBoardsForGoal(
      snapshot,
      architecture,
      focusBoard.goalIndex!,
      _resolvedActiveBoardId(architecture),
    );
    return List.unmodifiable(boards.isEmpty ? [focusBoard] : boards);
  }

  static List<IntroChatMessage> messagesForBoard(
    RemoteLearningSessionSnapshot snapshot,
    String boardId, {
    String? trailingTeacherPrompt,
    String? modeSelectionPrompt,
    bool appendModePrompt = false,
    RemoteTeachingFlow? liveTeachingFlow,
    bool includeRevisitThreads = true,
  }) {
    return messagesForBoards(
      snapshot,
      [boardId],
      trailingTeacherPrompt: trailingTeacherPrompt,
      modeSelectionPrompt: modeSelectionPrompt,
      appendModePrompt: appendModePrompt,
      liveTeachingFlow: liveTeachingFlow,
      includeRevisitThreads: includeRevisitThreads,
    );
  }

  /// 聚合一个连续学习段的对话；每个节点仍必须由其 TeachingBoard 显式持有。
  static List<IntroChatMessage> messagesForBoards(
    RemoteLearningSessionSnapshot snapshot,
    Iterable<String> boardIds, {
    String? trailingTeacherPrompt,
    String? modeSelectionPrompt,
    bool appendModePrompt = false,
    RemoteTeachingFlow? liveTeachingFlow,
    bool includeRevisitThreads = true,
  }) {
    final architecture = snapshot.teachingArchitecture;
    final requestedBoardIds = boardIds.toSet();
    final boards = architecture?.boards
        .where((board) => requestedBoardIds.contains(board.id))
        .toList(growable: false);
    if (boards == null || boards.isEmpty) {
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

    final activeBoardId = _resolvedActiveBoardId(architecture!);
    final isActive = boards.any(
      (board) => board.id == activeBoardId || board.isActive,
    );
    final messages = <IntroChatMessage>[];
    final practiceByAnswerNodeId = <String, RemoteLearningPracticeNode>{};
    final renderedPracticePromptIds = <String>{};
    final boardNodes = nodesForBoards(snapshot, boards);
    final mainBoardNodes = boardNodes
        .where((node) => node.conversationThreadKind != 'REVISIT')
        .toList(growable: false);

    for (final board in boards) {
      final practice = practiceForBoard(snapshot, board);
      if (practice == null) continue;
      for (final nodeId in board.nodeIds) {
        final node = snapshot.nodeById(nodeId);
        if (node?.conversationThreadKind != 'REVISIT' &&
            node?.question.trim().isNotEmpty == true) {
          practiceByAnswerNodeId.putIfAbsent(nodeId, () => practice);
        }
      }
    }

    for (final node in mainBoardNodes) {
      final practice = practiceByAnswerNodeId[node.id];
      if (practice != null && renderedPracticePromptIds.add(practice.id)) {
        // 练习的题干来自 TeachingBoard 关联的结构化练习，而不是学生回答节点；
        // 回看时必须先补回题干，避免只看到学生答案而失去作答语境。
        messages.add(
          IntroChatMessage.teacher(_practiceDialoguePrompt(practice)),
        );
      }
      messages.addAll(IntroChatMessage.fromSingleNode(node));
    }

    final conceptBoards = boards
        .where((board) => board.kind == 'CONCEPT')
        .toList(growable: false);
    if (messages.isEmpty &&
        conceptBoards.isNotEmpty &&
        conceptBoards.length == boards.length) {
      // 早期会话只持久化了知识结构，没有把概念讲解复制成聊天 turn；
      // 回看时使用服务端保存的知识摘要还原真实学习记录，不能再展示成空白页。
      final conceptRecord = _conceptLearningRecord(conceptBoards);
      if (conceptRecord.isNotEmpty) {
        messages.add(IntroChatMessage.teacher(conceptRecord));
      }
    }

    final processedPracticeIds = <String>{};
    for (final board in boards) {
      if (board.practiceAttemptIds.isNotEmpty) {
        final practiceAttemptId = board.practiceAttemptIds.first;
        if (processedPracticeIds.add(practiceAttemptId)) {
          final hasStudentLine = board.nodeIds.any((nodeId) {
            final node = snapshot.nodeById(nodeId);
            return node?.conversationThreadKind != 'REVISIT' &&
                node?.question.trim().isNotEmpty == true;
          });
          if (!hasStudentLine) {
            final branch = architecture.branches
                .where(
                  (item) => item.triggerPracticeAttemptId == practiceAttemptId,
                )
                .firstOrNull;
            final practiceNode = practiceForBoard(snapshot, board);
            if (practiceNode != null &&
                renderedPracticePromptIds.add(practiceNode.id)) {
              messages.add(
                IntroChatMessage.teacher(_practiceDialoguePrompt(practiceNode)),
              );
            }
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
                !messages.any(
                  (line) => line.isTeacher && line.text == feedback,
                )) {
              messages.add(IntroChatMessage.teacherCorrection(feedback));
            }
          }
        }
      }

      if (board.branchId != null) {
        final branch = architecture.branches
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
      }
    }

    final activeBoard = boards
        .where((board) => board.id == activeBoardId || board.isActive)
        .firstOrNull;
    if (activeBoard?.branchId == null && isActive && liveTeachingFlow != null) {
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

    if (includeRevisitThreads) {
      // 回访发生在主教学和素材操作之后，展示时统一追加到底部，不能按创建时间插回原课堂中间。
      messages.addAll(_revisitMessagesFromNodes(boardNodes));
    }

    return List.unmodifiable(messages);
  }

  /// 返回指定历史学习段的回访线程；页面将它放在原问答与素材快照之后。
  static List<IntroChatMessage> revisitMessagesForBoards(
    RemoteLearningSessionSnapshot snapshot,
    Iterable<String> boardIds,
  ) {
    final architecture = snapshot.teachingArchitecture;
    if (architecture == null) return const [];
    final requestedBoardIds = boardIds.toSet();
    final boards = architecture.boards
        .where((board) => requestedBoardIds.contains(board.id))
        .toList(growable: false);
    if (boards.isEmpty) return const [];
    return _revisitMessagesFromNodes(nodesForBoards(snapshot, boards));
  }

  static List<IntroChatMessage> _revisitMessagesFromNodes(
    Iterable<RemoteLearningNode> nodes,
  ) {
    final threads = <String, List<RemoteLearningNode>>{};
    for (final node in nodes) {
      if (node.conversationThreadKind != 'REVISIT') continue;
      final explicitId = node.conversationThreadId?.trim();
      final threadId = explicitId?.isNotEmpty == true
          ? explicitId!
          : 'revisit-${node.conversationAnchorNodeId ?? node.id}';
      threads.putIfAbsent(threadId, () => <RemoteLearningNode>[]).add(node);
    }

    final messages = <IntroChatMessage>[];
    for (final (index, threadNodes) in threads.values.indexed) {
      messages.add(IntroChatMessage.threadHeader('回访对话 #${index + 1}'));
      for (final node in threadNodes) {
        messages.addAll(IntroChatMessage.fromSingleNode(node));
      }
    }
    return List.unmodifiable(messages);
  }

  /// 历史画板只读取服务端明确归属的节点及其素材节点。
  /// 不能按时间窗兜底：学生可以在进入后续 Goal 后回到旧节点追问，时间相邻不等于属于同一画板。
  static List<RemoteLearningNode> nodesForBoard(
    RemoteLearningSessionSnapshot snapshot,
    RemoteTeachingBoardSnapshot board,
  ) {
    return nodesForBoards(snapshot, [board]);
  }

  /// 多板合并仅做展示层聚合；节点集合仍来自每一张板的显式 nodeIds 和素材归属。
  static List<RemoteLearningNode> nodesForBoards(
    RemoteLearningSessionSnapshot snapshot,
    Iterable<RemoteTeachingBoardSnapshot> boards,
  ) {
    final nodeIds = <String>{};
    for (final board in boards) {
      nodeIds.addAll(board.nodeIds);
      for (final material in materialsForBoard(snapshot, board)) {
        nodeIds.add(material.nodeId);
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

  /// 将结构化题干投影进对话时间线，使“题目 → 作答 → 反馈”成为可回看的完整单元。
  static String _practiceDialoguePrompt(RemoteLearningPracticeNode practice) {
    final title = practice.title.trim();
    final prompt = practice.prompt.trim();
    final purpose = practice.purpose.trim();
    final header = title.isEmpty ? '本题任务' : '练习题：$title';
    if (purpose.isEmpty) return '$header\n$prompt';
    return '$header\n$prompt\n\n请围绕：$purpose 作答。';
  }

  static String _conceptLearningRecord(
    Iterable<RemoteTeachingBoardSnapshot> boards,
  ) {
    final summaries = <String>{};
    final names = <String>{};
    for (final board in boards) {
      summaries.addAll(
        board.knowledgeNodeSummaries
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
      );
      names.addAll(
        board.knowledgeNodeNames
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
      );
    }
    if (summaries.isNotEmpty) {
      return '概念学习记录\n${summaries.map((item) => '• $item').join('\n')}';
    }
    if (names.isNotEmpty) {
      return '概念学习记录\n这一阶段学习了：${names.join('、')}。';
    }
    return '';
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
    RemoteTeachingBoardSnapshot? parentBoard,
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
      'SUPPORT_BRANCH' when parentBoard?.kind == 'CHECK' =>
        '练习 · ${_boardCoreLabel(parentBoard!)}',
      'SUPPORT_BRANCH' => '练习 · ${_studentBoardLabel(board)}',
      'INTERACTION' => '互动 · $label',
      'CONCEPT' => '概念 · $label',
      'EXAMPLE' => '例子 · $label',
      _ => label,
    };
  }

  static String _boardCoreLabel(RemoteTeachingBoardSnapshot board) {
    final normalized = _sanitizeLabel(board.label);
    return normalized.isNotEmpty && !_looksLikeDevLabel(normalized)
        ? normalized
        : _fallbackBoardLabel(board);
  }
}

extension _BoardIterableHelpers<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
