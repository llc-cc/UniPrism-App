import '../core/exploration_models.dart';
import '../core/exploration_ports.dart';

/// 1.1 尚未接入时使用的少量可审计内容，覆盖 1.2 三个演示场景。
final class MockExplorationContentRepository
    implements ExplorationContentRepository {
  static final List<ExplorationScenario> _scenarios = List.unmodifiable([
    ExplorationScenario(
      id: 'teaching-negative-multiplication',
      title: '负数乘法：为什么负负得正',
      kind: ExplorationScenarioKind.teaching,
      atomId: 'negative-multiplication',
      openingPrompt: '为什么两个负数相乘会得到正数？',
      seedQuestions: const ['为什么两个负数相乘会得到正数？', '负号可以表示什么？', '连续两次取相反数会怎样？'],
      allowedMaterialIds: const {},
    ),
    ExplorationScenario(
      id: 'teaching-quadratic',
      title: '二次函数：顶点为什么在这里',
      kind: ExplorationScenarioKind.teaching,
      atomId: 'quadratic-vertex',
      openingPrompt: '二次函数的顶点为什么在这里？',
      seedQuestions: const [
        '二次函数的顶点为什么在这里？',
        '参数 a 改变时图像会怎样？',
        '一般式怎么变成顶点式？',
        '顶点和最值有什么关系？',
        '平移为什么会改变 h 和 k？',
        '二次函数在现实中有什么用？',
      ],
      allowedMaterialIds: const {
        'quadratic-figure',
        'quadratic-video',
        'quadratic-interactive',
        'quadratic-formula',
      },
    ),
    ExplorationScenario(
      id: 'practice-inequality',
      title: '证明不等式：验证、诊断与回退',
      kind: ExplorationScenarioKind.practice,
      atomId: 'inequality-proof',
      openingPrompt: '证明：当 x > 0 时，x + 1/x ≥ 2。',
      seedQuestions: const ['我想直接用柯西不等式，可以吗？', '这一步需要满足什么条件？', '能不能用基本不等式？'],
      allowedMaterialIds: const {'inequality-figure', 'inequality-formula'},
    ),
    ExplorationScenario(
      id: 'demo-coffee-business-model',
      title: 'Business model：咖啡店怎么赚钱',
      kind: ExplorationScenarioKind.publicDemo,
      atomId: 'business-model-unit-economics',
      openingPrompt: '一家咖啡店怎么赚钱？',
      seedQuestions: const [
        '收入从哪里来？',
        '最大的成本是什么？',
        '价格应该怎么定？',
        '渠道会改变什么？',
        '护城河可能是什么？',
        '怎样计算一杯咖啡的单位经济模型？',
      ],
      allowedMaterialIds: const {
        'business-model-figure',
        'business-model-interactive',
        'business-model-formula',
      },
    ),
  ]);

  static final List<ExplorationMaterial> _materials = List.unmodifiable([
    ExplorationMaterial(
      id: 'quadratic-figure',
      atomId: 'quadratic-vertex',
      kind: ExplorationMaterialKind.figure,
      title: '抛物线与顶点',
      payload: const {'a': 1.0, 'h': 0.0, 'k': 0.0},
    ),
    ExplorationMaterial(
      id: 'quadratic-video',
      atomId: 'quadratic-vertex',
      kind: ExplorationMaterialKind.video,
      title: '参数变化过程（模拟视频）',
      payload: const {'durationSeconds': 18},
    ),
    ExplorationMaterial(
      id: 'quadratic-interactive',
      atomId: 'quadratic-vertex',
      kind: ExplorationMaterialKind.interactive,
      title: '拖动 a、h、k',
      payload: const {'a': 1.0, 'h': 0.0, 'k': 0.0},
    ),
    ExplorationMaterial(
      id: 'quadratic-formula',
      atomId: 'quadratic-vertex',
      kind: ExplorationMaterialKind.formula,
      title: '一般式到顶点式',
      payload: const {'formula': 'y = a(x-h)² + k'},
    ),
    ExplorationMaterial(
      id: 'inequality-figure',
      atomId: 'inequality-proof',
      kind: ExplorationMaterialKind.figure,
      title: 'x 与 1/x 的变化',
      payload: const {'domain': 'x > 0'},
    ),
    ExplorationMaterial(
      id: 'inequality-formula',
      atomId: 'inequality-proof',
      kind: ExplorationMaterialKind.formula,
      title: '基本不等式的成立条件',
      payload: const {'formula': 'a + b ≥ 2√(ab), a,b ≥ 0'},
    ),
    ExplorationMaterial(
      id: 'business-model-figure',
      atomId: 'business-model-unit-economics',
      kind: ExplorationMaterialKind.figure,
      title: '收入与成本画布',
      payload: const {
        'columns': ['收入', '固定成本', '变动成本'],
      },
    ),
    ExplorationMaterial(
      id: 'business-model-interactive',
      atomId: 'business-model-unit-economics',
      kind: ExplorationMaterialKind.interactive,
      title: '调整客单价与销量',
      payload: const {'price': 28.0, 'dailyOrders': 120.0},
    ),
    ExplorationMaterial(
      id: 'business-model-formula',
      atomId: 'business-model-unit-economics',
      kind: ExplorationMaterialKind.formula,
      title: '单杯贡献毛利',
      payload: const {'formula': '售价 - 单杯变动成本'},
    ),
  ]);

  @override
  Future<List<ExplorationScenario>> loadScenarios() async => _scenarios;

  @override
  Future<List<ExplorationMaterial>> loadMaterials(Set<String> ids) async {
    return List.unmodifiable(
      _materials.where((material) => ids.contains(material.id)),
    );
  }

  @override
  Future<Set<String>> allowedMaterialIds(String atomId) async {
    return Set.unmodifiable(
      _scenarios
          .where((scenario) => scenario.atomId == atomId)
          .expand((scenario) => scenario.allowedMaterialIds),
    );
  }

  @override
  Future<List<String>> validateFixtures() async {
    final issues = <String>[];
    final scenarioIds = <String>{};
    final materialIds = <String>{};
    for (final scenario in _scenarios) {
      if (!scenarioIds.add(scenario.id)) {
        issues.add('duplicate_scenario:${scenario.id}');
      }
    }
    for (final material in _materials) {
      if (!materialIds.add(material.id)) {
        issues.add('duplicate_material:${material.id}');
      }
    }
    for (final scenario in _scenarios) {
      for (final materialId in scenario.allowedMaterialIds) {
        final material = _materials
            .where((candidate) => candidate.id == materialId)
            .firstOrNull;
        if (material == null) {
          issues.add('missing_material:${scenario.id}:$materialId');
        } else if (material.atomId != scenario.atomId) {
          issues.add('outside_atom:${scenario.id}:$materialId');
        }
      }
    }
    return List.unmodifiable(issues);
  }
}
