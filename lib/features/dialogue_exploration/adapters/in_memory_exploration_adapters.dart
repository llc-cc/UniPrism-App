import '../core/exploration_ports.dart';
import '../core/exploration_outputs.dart';
import '../practice/practice_diagnosis.dart';

/// 仅用于实验室会话的掌握证据收集器，退出模块后随依赖一起释放。
final class InMemoryMasteryEvidenceSink implements MasteryEvidenceSink {
  final Map<String, MasteryEvidence> _items = {};

  List<MasteryEvidence> get items => List.unmodifiable(_items.values);

  @override
  Future<void> write(MasteryEvidence evidence) async {
    // 事件 ID 幂等可防止重复点击把一次确认记录成多次证据。
    _items.putIfAbsent(evidence.id, () => evidence);
  }
}

/// 进程内思维过程图仓库；用于验证保存和导出，不跨实验室生命周期。
final class InMemoryExplorationTraceRepository
    implements ExplorationTraceRepository {
  final Map<String, ExplorationTraceRecord> _items = {};

  List<ExplorationTraceRecord> get items => List.unmodifiable(_items.values);

  @override
  Future<void> save(ExplorationTraceRecord record) async {
    _items[record.id] = record;
  }
}

/// 进程内 M2 候选输出；相同稳定 ID 不会重复创建。
final class InMemoryMemoryCandidateSink implements MemoryCandidateSink {
  final Map<String, ExplorationMemoryCandidate> _items = {};

  List<ExplorationMemoryCandidate> get items => List.unmodifiable(_items.values);

  @override
  Future<String> upsert(ExplorationMemoryCandidate candidate) async {
    _items.putIfAbsent(candidate.id, () => candidate);
    return candidate.id;
  }
}
