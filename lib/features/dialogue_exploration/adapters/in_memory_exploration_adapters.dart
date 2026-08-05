import '../core/exploration_ports.dart';
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
