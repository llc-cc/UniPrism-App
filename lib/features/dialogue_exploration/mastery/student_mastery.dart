import '../core/exploration_models.dart';

/// 学生对单个知识原子的掌握档位；unknown 不得被当作“中等”处理。
enum StudentMasteryLevel { unknown, weak, developing, strong }

/// 某一时刻可追溯的学生知识掌握快照。
final class StudentMasterySnapshot {
  StudentMasterySnapshot({
    required this.atomId,
    required this.level,
    required List<String> recentEvidence,
    required List<String> misconceptionTags,
    required List<ExplorationMaterialKind> preferredMaterialKinds,
    required this.observedAt,
    required this.source,
  }) : recentEvidence = List.unmodifiable(recentEvidence),
       misconceptionTags = List.unmodifiable(misconceptionTags),
       preferredMaterialKinds = List.unmodifiable(preferredMaterialKinds);

  final String atomId;
  final StudentMasteryLevel level;
  final List<String> recentEvidence;
  final List<String> misconceptionTags;
  final List<ExplorationMaterialKind> preferredMaterialKinds;
  final DateTime observedAt;
  final String source;
}

/// 读取学生掌握证据；首版用 Mock，后续由 M2/M3 事件聚合实现。
abstract interface class StudentMasteryRepository {
  Future<List<StudentMasterySnapshot>> availableProfiles(String atomId);
}
