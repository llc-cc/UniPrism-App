import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../adapters/remote_exploration_api.dart';
import '../adapters/remote_exploration_dto.dart';

enum RemoteExplorationStatus {
  idle,
  loadingEntry,
  ready,
  submitting,
  active,
  failed,
  completed,
}

enum RemoteComposerMode { currentPath, continueFromNode, branchFromNode }

/// 远程会话页面只读状态；思维树永远来自服务端完整快照。
final class RemoteExplorationState {
  const RemoteExplorationState({
    required this.status,
    required this.entry,
    required this.snapshot,
    required this.inspectedNodeId,
    required this.composerMode,
    required this.errorMessage,
    required this.memoryCandidateNodeIds,
    required this.canRetry,
  });

  const RemoteExplorationState.idle()
    : status = RemoteExplorationStatus.idle,
      entry = null,
      snapshot = null,
      inspectedNodeId = null,
      composerMode = RemoteComposerMode.currentPath,
      errorMessage = null,
      memoryCandidateNodeIds = const {},
      canRetry = false;

  final RemoteExplorationStatus status;
  final LearningEntrySnapshot? entry;
  final RemoteLearningSessionSnapshot? snapshot;
  final String? inspectedNodeId;
  final RemoteComposerMode composerMode;
  final String? errorMessage;
  final Set<String> memoryCandidateNodeIds;
  final bool canRetry;

  RemoteExplorationState copyWith({
    RemoteExplorationStatus? status,
    LearningEntrySnapshot? entry,
    RemoteLearningSessionSnapshot? snapshot,
    String? inspectedNodeId,
    bool clearInspectedNode = false,
    RemoteComposerMode? composerMode,
    String? errorMessage,
    bool clearError = false,
    Set<String>? memoryCandidateNodeIds,
    bool? canRetry,
  }) {
    return RemoteExplorationState(
      status: status ?? this.status,
      entry: entry ?? this.entry,
      snapshot: snapshot ?? this.snapshot,
      inspectedNodeId: clearInspectedNode
          ? null
          : inspectedNodeId ?? this.inspectedNodeId,
      composerMode: composerMode ?? this.composerMode,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      memoryCandidateNodeIds:
          memoryCandidateNodeIds ?? this.memoryCandidateNodeIds,
      canRetry: canRetry ?? this.canRetry,
    );
  }
}

/// 管理远程 Session 的异步状态、显式节点动作和幂等重试，不在本地合并树。
final class RemoteExplorationSessionController extends ChangeNotifier {
  RemoteExplorationSessionController({required this.api});

  final RemoteExplorationGateway api;
  RemoteExplorationState _state = const RemoteExplorationState.idle();
  Future<void> Function()? _retryOperation;
  var _isDisposed = false;

  RemoteExplorationState get state => _state;

  Future<void> loadEntry(String atomId) async {
    _replace(
      _state.copyWith(
        status: RemoteExplorationStatus.loadingEntry,
        clearError: true,
      ),
    );
    try {
      final entry = await api.getEntry(atomId);
      _replace(
        _state.copyWith(status: RemoteExplorationStatus.ready, entry: entry),
      );
    } catch (error) {
      _fail(error, () => loadEntry(atomId));
    }
  }

  Future<void> start({String? directionId, String? question}) async {
    final entry = _state.entry;
    if (entry == null) throw StateError('Learning Entry 尚未加载');
    final key = _traceId('create');
    Future<void> operation() async {
      _submitting();
      try {
        final snapshot = await api.createSession(
          atomId: entry.atomId,
          scenarioId: _scenarioId(entry.atomId),
          directionId: directionId,
          question: question,
          idempotencyKey: key,
        );
        _acceptSnapshot(snapshot);
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<void> restoreLatest() async {
    try {
      final snapshot = await api.restoreLatest();
      if (snapshot != null) _acceptSnapshot(snapshot);
    } catch (error) {
      _fail(error, restoreLatest);
    }
  }

  /// 选中节点只改变本地检查视图，绝不触发支线、回溯或服务端写入。
  void inspectNode(String nodeId) {
    if (_state.snapshot?.nodeById(nodeId) == null) return;
    _replace(
      _state.copyWith(
        inspectedNodeId: nodeId,
        composerMode: RemoteComposerMode.currentPath,
        clearError: true,
      ),
    );
  }

  void prepareContinueFromInspected() {
    _requireInspectedNode();
    _replace(
      _state.copyWith(composerMode: RemoteComposerMode.continueFromNode),
    );
  }

  void prepareBranchFromInspected() {
    _requireInspectedNode();
    _replace(_state.copyWith(composerMode: RemoteComposerMode.branchFromNode));
  }

  void cancelPreparedAction() {
    _replace(_state.copyWith(composerMode: RemoteComposerMode.currentPath));
  }

  Future<void> submitQuestion(String question) async {
    final normalized = question.trim();
    if (normalized.isEmpty) return;
    final snapshot = _requireSnapshot();
    final mode = _state.composerMode;
    final parentId = mode == RemoteComposerMode.currentPath
        ? null
        : _requireInspectedNode().id;
    final key = _traceId(
      mode == RemoteComposerMode.branchFromNode ? 'branch' : 'turn',
    );
    Future<void> operation() async {
      _submitting();
      try {
        final updated = mode == RemoteComposerMode.branchFromNode
            ? await api.createBranch(
                sessionId: snapshot.session.id,
                parentNodeId: parentId!,
                question: normalized,
                idempotencyKey: key,
              )
            : await api.submitTurn(
                sessionId: snapshot.session.id,
                question: normalized,
                parentNodeId: parentId,
                idempotencyKey: key,
              );
        _acceptSnapshot(updated);
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<void> backtrackToInspected() async {
    final snapshot = _requireSnapshot();
    final target = _requireInspectedNode();
    final key = _traceId('backtrack');
    Future<void> operation() async {
      _submitting();
      try {
        _acceptSnapshot(
          await api.backtrack(
            sessionId: snapshot.session.id,
            targetNodeId: target.id,
            idempotencyKey: key,
          ),
        );
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<void> convertInspectedToMemory() async {
    final snapshot = _requireSnapshot();
    final node = _requireInspectedNode();
    final key = _traceId('memory');
    Future<void> operation() async {
      _submitting();
      try {
        await api.createMemoryCandidate(
          sessionId: snapshot.session.id,
          nodeId: node.id,
          idempotencyKey: key,
        );
        _retryOperation = null;
        _replace(
          _state.copyWith(
            status: RemoteExplorationStatus.active,
            memoryCandidateNodeIds: {..._state.memoryCandidateNodeIds, node.id},
            canRetry: false,
            clearError: true,
          ),
        );
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<void> complete(String reflection) async {
    final normalized = reflection.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(reflection, 'reflection', '复述不能为空');
    }
    final snapshot = _requireSnapshot();
    final key = _traceId('complete');
    Future<void> operation() async {
      _submitting();
      try {
        _acceptSnapshot(
          await api.complete(
            sessionId: snapshot.session.id,
            reflection: normalized,
            idempotencyKey: key,
          ),
        );
      } catch (error) {
        _fail(error, operation);
      }
    }

    await operation();
  }

  Future<String> exportTree() => api.exportTree(_requireSnapshot().session.id);

  Future<void> retry() async {
    final operation = _retryOperation;
    if (operation != null) await operation();
  }

  RemoteLearningNode _requireInspectedNode() {
    return _state.snapshot?.nodeById(_state.inspectedNodeId) ??
        (throw StateError('请先选择一个思维树节点'));
  }

  RemoteLearningSessionSnapshot _requireSnapshot() {
    return _state.snapshot ?? (throw StateError('学习会话尚未开始'));
  }

  void _submitting() {
    _replace(
      _state.copyWith(
        status: RemoteExplorationStatus.submitting,
        clearError: true,
      ),
    );
  }

  void _acceptSnapshot(RemoteLearningSessionSnapshot snapshot) {
    _retryOperation = null;
    _replace(
      _state.copyWith(
        status: snapshot.session.status == 'COMPLETED'
            ? RemoteExplorationStatus.completed
            : RemoteExplorationStatus.active,
        snapshot: snapshot,
        clearInspectedNode: true,
        composerMode: RemoteComposerMode.currentPath,
        clearError: true,
        canRetry: false,
      ),
    );
  }

  void _fail(Object error, Future<void> Function() retryOperation) {
    _retryOperation = retryOperation;
    _replace(
      _state.copyWith(
        status: RemoteExplorationStatus.failed,
        errorMessage: error is RemoteExplorationException
            ? error.message
            : '操作失败，请重试。',
        canRetry: true,
      ),
    );
  }

  void _replace(RemoteExplorationState next) {
    _state = next;
    if (!_isDisposed) notifyListeners();
  }

  static String _scenarioId(String atomId) {
    if (atomId == 'inequality-proof') return 'practice';
    if (atomId == 'coffee-business-model') return 'public-demo';
    return 'teaching';
  }

  static String _traceId(String prefix) {
    final entropy = math.Random().nextInt(0x7fffffff).toRadixString(16);
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$entropy';
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
