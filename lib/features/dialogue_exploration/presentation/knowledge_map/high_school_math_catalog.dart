/// 高中数学知识图谱中的单个三级知识点。
final class MathKnowledgePoint {
  const MathKnowledgePoint({
    required this.id,
    required this.title,
    required this.summary,
  });

  final String id;
  final String title;
  final String summary;
}

/// 高中数学知识图谱中的二级主题分支。
final class MathKnowledgeTheme {
  const MathKnowledgeTheme({
    required this.id,
    required this.title,
    this.expectedPointCount,
    this.points = const [],
  });

  final String id;
  final String title;
  final int? expectedPointCount;
  final List<MathKnowledgePoint> points;

  int get pointCount => expectedPointCount ?? points.length;
}

/// 高中数学知识图谱中的一级模块；未接入模块仍保留统计用于总览。
final class MathKnowledgeModule {
  const MathKnowledgeModule({
    required this.id,
    required this.title,
    required this.pointCount,
    required this.branchCount,
    this.themes = const [],
  });

  final String id;
  final String title;
  final int pointCount;
  final int branchCount;
  final List<MathKnowledgeTheme> themes;

  bool get hasExplorationData => themes.isNotEmpty;
}

/// App 实验页使用的高中数学目录快照，数据来自本地知识图谱而非网络接口。
abstract final class HighSchoolMathCatalog {
  static const modules = <MathKnowledgeModule>[
    MathKnowledgeModule(
      id: 'A',
      title: '预备知识与不等式',
      pointCount: 8,
      branchCount: 2,
      themes: [
        MathKnowledgeTheme(
          id: 'A1',
          title: '集合与常用逻辑用语',
          points: [
            MathKnowledgePoint(
              id: 'A1.1',
              title: '集合的概念与表示',
              summary: '理解集合、元素及常用表示方法，能够判断元素与集合的关系。',
            ),
            MathKnowledgePoint(
              id: 'A1.2',
              title: '集合间的基本关系',
              summary: '识别子集、真子集与集合相等，并用包含关系描述集合。',
            ),
            MathKnowledgePoint(
              id: 'A1.3',
              title: '集合的基本运算',
              summary: '使用交集、并集和补集处理集合之间的组合关系。',
            ),
            MathKnowledgePoint(
              id: 'A1.4',
              title: '充分条件与必要条件',
              summary: '根据命题之间的推出关系判断充分性与必要性。',
            ),
            MathKnowledgePoint(
              id: 'A1.5',
              title: '全称量词与存在量词',
              summary: '理解全称命题、存在性命题及其否定方式。',
            ),
          ],
        ),
        MathKnowledgeTheme(
          id: 'A2',
          title: '等式与不等式',
          points: [
            MathKnowledgePoint(
              id: 'A2.1',
              title: '等式与不等式的性质',
              summary: '掌握等式和不等式在变形过程中的基本规则与成立条件。',
            ),
            MathKnowledgePoint(
              id: 'A2.2',
              title: '基本不等式',
              summary: '理解基本不等式及取等条件，并用于求最值和证明。',
            ),
            MathKnowledgePoint(
              id: 'A2.3',
              title: '一元二次不等式与分式不等式',
              summary: '结合函数图象、零点和符号区间求解常见不等式。',
            ),
          ],
        ),
      ],
    ),
    MathKnowledgeModule(
      id: 'B',
      title: '函数',
      pointCount: 17,
      branchCount: 3,
      themes: [
        MathKnowledgeTheme(
          id: 'B1',
          title: '函数的概念与基本性质',
          points: [
            MathKnowledgePoint(
              id: 'B1.1',
              title: '函数的概念与三要素',
              summary: '从定义域、对应关系和值域三个要素理解函数。',
            ),
            MathKnowledgePoint(
              id: 'B1.2',
              title: '函数的表示与分段函数',
              summary: '使用解析式、图象和表格表示函数，并理解分段定义。',
            ),
            MathKnowledgePoint(
              id: 'B1.3',
              title: '函数的单调性与最值',
              summary: '从区间上的变化趋势判断单调性并研究最值。',
            ),
            MathKnowledgePoint(
              id: 'B1.4',
              title: '函数的奇偶性',
              summary: '利用定义域对称与函数值关系判断奇函数和偶函数。',
            ),
            MathKnowledgePoint(
              id: 'B1.5',
              title: '函数的对称性',
              summary: '识别函数图象的轴对称、中心对称及其代数表达。',
            ),
            MathKnowledgePoint(
              id: 'B1.6',
              title: '函数的周期性',
              summary: '理解周期函数的定义、最小正周期及图象重复规律。',
            ),
            MathKnowledgePoint(
              id: 'B1.7',
              title: '类周期函数',
              summary: '研究满足缩放或递推关系的函数及其重复结构。',
            ),
          ],
        ),
        MathKnowledgeTheme(
          id: 'B2',
          title: '幂函数、指数函数与对数函数',
          points: [
            MathKnowledgePoint(
              id: 'B2.1',
              title: '指数运算与指数函数',
              summary: '掌握指数运算规则及指数函数的图象和性质。',
            ),
            MathKnowledgePoint(
              id: 'B2.2',
              title: '对数运算与对数函数',
              summary: '掌握对数运算规则及对数函数的图象和性质。',
            ),
            MathKnowledgePoint(
              id: 'B2.3',
              title: '幂函数',
              summary: '比较常见幂函数在不同指数下的定义域和图象特征。',
            ),
            MathKnowledgePoint(
              id: 'B2.4',
              title: '指数式与对数式的大小比较',
              summary: '利用单调性、换底和构造函数比较指对数式大小。',
            ),
            MathKnowledgePoint(
              id: 'B2.5',
              title: '二次函数的图象与性质',
              summary: '结合开口、对称轴和顶点研究二次函数的整体性质。',
            ),
          ],
        ),
        MathKnowledgeTheme(
          id: 'B3',
          title: '函数的图象与应用',
          points: [
            MathKnowledgePoint(
              id: 'B3.1',
              title: '函数的图象与图象变换',
              summary: '通过平移、伸缩和对称变换理解函数图象之间的关系。',
            ),
            MathKnowledgePoint(
              id: 'B3.2',
              title: '函数的零点与方程的根',
              summary: '把方程根的问题转化为函数零点或图象交点问题。',
            ),
            MathKnowledgePoint(
              id: 'B3.3',
              title: '复合（嵌套）函数',
              summary: '分析函数复合后的定义域、对应关系与性质传递。',
            ),
            MathKnowledgePoint(
              id: 'B3.4',
              title: '抽象函数',
              summary: '根据给定性质、方程和结构推导未显式给出解析式的函数。',
            ),
            MathKnowledgePoint(
              id: 'B3.5',
              title: '函数模型及其应用',
              summary: '选择合适的函数模型描述实际变化并解释模型结果。',
            ),
          ],
        ),
      ],
    ),
    MathKnowledgeModule(
      id: 'C',
      title: '导数及其应用',
      pointCount: 15,
      branchCount: 3,
      themes: [
        MathKnowledgeTheme(id: 'C1', title: '导数的概念与运算', expectedPointCount: 3),
        MathKnowledgeTheme(id: 'C2', title: '导数与函数的性质', expectedPointCount: 4),
        MathKnowledgeTheme(id: 'C3', title: '导数的综合应用', expectedPointCount: 8),
      ],
    ),
    MathKnowledgeModule(
      id: 'D',
      title: '三角函数与解三角形',
      pointCount: 20,
      branchCount: 4,
      themes: [
        MathKnowledgeTheme(
          id: 'D1',
          title: '三角函数的概念与公式',
          expectedPointCount: 4,
        ),
        MathKnowledgeTheme(id: 'D2', title: '三角恒等变换', expectedPointCount: 5),
        MathKnowledgeTheme(
          id: 'D3',
          title: '三角函数的图象与性质',
          expectedPointCount: 3,
        ),
        MathKnowledgeTheme(id: 'D4', title: '解三角形', expectedPointCount: 8),
      ],
    ),
    MathKnowledgeModule(
      id: 'E',
      title: '平面向量与复数',
      pointCount: 11,
      branchCount: 3,
      themes: [
        MathKnowledgeTheme(
          id: 'E1',
          title: '平面向量的概念与线性运算',
          expectedPointCount: 4,
        ),
        MathKnowledgeTheme(id: 'E2', title: '平面向量的数量积', expectedPointCount: 5),
        MathKnowledgeTheme(id: 'E3', title: '复数', expectedPointCount: 2),
      ],
    ),
    MathKnowledgeModule(
      id: 'F',
      title: '数列',
      pointCount: 20,
      branchCount: 3,
      themes: [
        MathKnowledgeTheme(id: 'F1', title: '等差数列与等比数列', expectedPointCount: 6),
        MathKnowledgeTheme(
          id: 'F2',
          title: '数列的通项与求和方法',
          expectedPointCount: 7,
        ),
        MathKnowledgeTheme(id: 'F3', title: '数列的综合与创新', expectedPointCount: 7),
      ],
    ),
    MathKnowledgeModule(
      id: 'G',
      title: '立体几何与空间向量',
      pointCount: 21,
      branchCount: 4,
      themes: [
        MathKnowledgeTheme(id: 'G1', title: '空间几何体', expectedPointCount: 6),
        MathKnowledgeTheme(
          id: 'G2',
          title: '空间点、直线、平面的位置关系',
          expectedPointCount: 4,
        ),
        MathKnowledgeTheme(
          id: 'G3',
          title: '空间角与距离（几何法）',
          expectedPointCount: 5,
        ),
        MathKnowledgeTheme(id: 'G4', title: '空间向量与立体几何', expectedPointCount: 6),
      ],
    ),
    MathKnowledgeModule(
      id: 'H',
      title: '平面解析几何',
      pointCount: 24,
      branchCount: 4,
      themes: [
        MathKnowledgeTheme(id: 'H1', title: '直线与圆', expectedPointCount: 3),
        MathKnowledgeTheme(
          id: 'H2',
          title: '圆锥曲线的定义与方程',
          expectedPointCount: 5,
        ),
        MathKnowledgeTheme(id: 'H3', title: '圆锥曲线的几何性质', expectedPointCount: 7),
        MathKnowledgeTheme(
          id: 'H4',
          title: '直线与圆锥曲线的位置关系',
          expectedPointCount: 9,
        ),
      ],
    ),
    MathKnowledgeModule(
      id: 'I',
      title: '概率、统计与计数原理',
      pointCount: 21,
      branchCount: 4,
      themes: [
        MathKnowledgeTheme(id: 'I1', title: '计数原理', expectedPointCount: 6),
        MathKnowledgeTheme(id: 'I2', title: '概率', expectedPointCount: 5),
        MathKnowledgeTheme(id: 'I3', title: '随机变量及其分布', expectedPointCount: 6),
        MathKnowledgeTheme(id: 'I4', title: '统计', expectedPointCount: 4),
      ],
    ),
  ];
}
