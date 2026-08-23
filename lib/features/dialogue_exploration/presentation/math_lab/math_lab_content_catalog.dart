/// 数学实验的交互类型；不同知识结构必须对应不同操作机制。
enum MathLabKind { formulaDerivation, derivative, probability, setModeling }

/// 从本地北师大版资料包中人工核对后接入的首批实验元数据。
final class MathLabChallenge {
  const MathLabChallenge({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.volume,
    required this.section,
    required this.sourceFile,
  });

  final MathLabKind kind;
  final String title;
  final String subtitle;
  final String volume;
  final String section;
  final String sourceFile;
}

abstract final class MathLabContentCatalog {
  static const sourceRoot = r'D:\资料\北师大版高中数学资料包';
  static const sourceFileCount = 2539;
  static const sourceVolumeCount = 4;
  static const detectedTopicCount = 15;

  static const challenges = <MathLabChallenge>[
    MathLabChallenge(
      kind: MathLabKind.formulaDerivation,
      title: '公式推导工坊',
      subtitle: '倒序配对、组装恒等式、迁移应用',
      volume: '选择性必修二',
      section: '1.2.2 等差数列的前 n 项和',
      sourceFile:
          r'04 选择性必修二\06 学案\1.2.2等差数列的前n项和 学案（2份打包）\1.2.2.1等差数列的前n项和(一).docx',
    ),
    MathLabChallenge(
      kind: MathLabKind.derivative,
      title: '切线追踪协议',
      subtitle: '拖动切点，锁定目标斜率与切线',
      volume: '选择性必修二',
      section: '2.2 导数的几何意义',
      sourceFile:
          r'04 选择性必修二\01课件+学案（同步）\2.2.2　导数的几何意义(课件(共61张PPT)+学案（含答案）)\§2 2.2　导数的几何意义.docx',
    ),
    MathLabChallenge(
      kind: MathLabKind.probability,
      title: '样本空间引擎',
      subtitle: '构造基本事件，再用随机模拟验证',
      volume: '必修一',
      section: '7.2.1 古典概型',
      sourceFile:
          r'01 必修一\02 课件+教案+学案\01 课件+教案+学案\第七章 概率（课件+学案+教案）（24份打包）\北师大版（2019）数学必修第一册：7.2.1《古典概型》学案.docx',
    ),
    MathLabChallenge(
      kind: MathLabKind.setModeling,
      title: '集合约束建模',
      subtitle: '调节交集参数，让全部条件同时成立',
      volume: '必修一',
      section: '1.1.3 集合的基本运算',
      sourceFile:
          r'01 必修一\02 课件+教案+学案\01 课件+教案+学案\第一章 预备知识（课件+学案+教案）（29份打包）\北师大版（2019）数学必修第一册：1.1.3《集合的基本运算》学案.docx',
    ),
  ];
}
