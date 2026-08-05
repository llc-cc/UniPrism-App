import '../core/exploration_models.dart';
import '../core/exploration_ports.dart';
import '../mastery/student_mastery.dart';

/// 按关键词和掌握档位返回确定性结果，便于首版演示和自动化验收。
final class MockExplorationGateway implements ExplorationGateway {
  MockExplorationGateway({this.delay = const Duration(milliseconds: 300)});

  static const inappropriateTestInput = '[不适宜测试输入]';
  static const strategyVersion = 'mock-exploration-v1';

  final Duration delay;

  @override
  Future<ExplorationTurnResponse> reply(ExplorationTurnRequest request) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final question = request.question.trim();
    if (question == inappropriateTestInput) {
      throw const ExplorationInputRejectedException('这个内容不适合在学习探索中继续。');
    }
    if (_containsAny(question, const ['泛函', '微分几何', '大学'])) {
      return _response(
        request,
        answer: '这超出当前学段。可以先记住：更高阶工具仍然在描述函数整体结构，但这里不调用超出知识边界的素材。',
        followUp: '在当前学段里，顶点式成立需要哪些代数条件？',
        boundary: ExplorationInputBoundary.aboveStage,
        intent: ExplorationIntent.clarifyBoundary,
      );
    }
    if (_containsAny(question, const ['天气', '吃饭', '明星'])) {
      return _response(
        request,
        answer: '这个问题和当前二次函数主线没有直接关系，我先把它标成支线，你可以随时回到顶点问题。',
        followUp: '回到主线时，你想先检查顶点结论的哪个成立条件？',
        boundary: ExplorationInputBoundary.unrelated,
        intent: ExplorationIntent.exploreSideBranch,
        sideBranch: true,
      );
    }
    return _routeTeaching(request);
  }

  ExplorationTurnResponse _routeTeaching(ExplorationTurnRequest request) {
    final question = request.question;
    if (_containsAny(question, const ['参数 a', 'a 改变', '开口'])) {
      return _response(
        request,
        answer: 'a 的绝对值控制抛物线收拢的速度，符号控制开口方向。你可以拖动 a，观察顶点位置并不会因此移动。',
        followUp: '当 a 的符号变化时，函数最值为什么也会变化？',
        intent: ExplorationIntent.extendReasoning,
        materialIds: const ['quadratic-interactive', 'quadratic-video'],
      );
    }
    if (_containsAny(question, const ['一般式', '顶点式', '配方'])) {
      return _response(
        request,
        answer: '把 x² 和一次项配成完全平方，就能把横向位置 h 与纵向位置 k 直接读出来。',
        followUp: '配方时同时加上又减去同一个量，依据是什么？',
        intent: ExplorationIntent.extendReasoning,
        materialIds: const ['quadratic-formula', 'quadratic-interactive'],
      );
    }
    if (_containsAny(question, const ['最值', '最大', '最小'])) {
      return _response(
        request,
        answer: '顶点是抛物线方向发生转换的位置；开口向上时它给出最小值，向下时给出最大值。',
        followUp: '把顶点当作最值点，需要满足哪个定义域条件？',
        intent: ExplorationIntent.clarifyBoundary,
        materialIds: const ['quadratic-figure', 'quadratic-formula'],
      );
    }
    if (_containsAny(question, const ['平移', 'h 和 k'])) {
      return _response(
        request,
        answer: 'h 改变横向位置，k 改变纵向位置；式子里的 x-h 为零时，横坐标正好是 h。',
        followUp: '为什么 x-h 中的负号会让图像向 h 的方向平移？',
        intent: ExplorationIntent.extendReasoning,
        materialIds: const ['quadratic-interactive', 'quadratic-figure'],
      );
    }
    if (_containsAny(question, const ['现实', '有什么用', '应用'])) {
      return _response(
        request,
        answer: '抛物线可以描述抛射轨迹、反射结构和“先增加后减少”的收益变化。顶点对应这些场景里的极值时刻。',
        followUp: '把现实过程近似成二次函数，需要哪些成立条件？',
        intent: ExplorationIntent.connectApplication,
        materialIds: const ['quadratic-video', 'quadratic-figure'],
      );
    }
    return switch (request.masteryLevel) {
      StudentMasteryLevel.unknown => _response(
        request,
        answer: '先不假设你已经掌握。你可以先指出图像上你认为的顶点，我再根据这个判断选择解释方式。',
        followUp: '你判断一个点是顶点时，使用了什么依据？',
        intent: ExplorationIntent.probePriorKnowledge,
        materialIds: const ['quadratic-figure'],
      ),
      StudentMasteryLevel.weak => _response(
        request,
        answer: '先把顶点看成抛物线转向的那个点。拖动图像时，这个点决定曲线能达到的最高或最低位置。',
        followUp: '把这个点称为最值点，需要满足什么条件？',
        intent: ExplorationIntent.repairPrerequisite,
        materialIds: const ['quadratic-figure', 'quadratic-interactive'],
      ),
      StudentMasteryLevel.developing => _response(
        request,
        answer: '顶点式把横向位置 h、纵向位置 k 与图像直接对应起来；配方就是把一般式转换成这种可读形式。',
        followUp: '从一般式配成完全平方时，每一步的依据是什么？',
        intent: ExplorationIntent.clarifyBoundary,
        materialIds: const ['quadratic-formula', 'quadratic-interactive'],
      ),
      StudentMasteryLevel.strong => _response(
        request,
        answer: '从 y=a(x-h)²+k 出发，平方项在 x=h 时达到边界值 0，所以函数值落在 k；a 的符号决定这是下界还是上界。',
        followUp: '这个推导成立时，a 与定义域需要满足什么条件？',
        intent: ExplorationIntent.extendReasoning,
        materialIds: const ['quadratic-formula', 'quadratic-figure'],
      ),
    };
  }

  ExplorationTurnResponse _response(
    ExplorationTurnRequest request, {
    required String answer,
    required String followUp,
    required ExplorationIntent intent,
    ExplorationInputBoundary boundary = ExplorationInputBoundary.inScope,
    List<String> materialIds = const [],
    bool sideBranch = false,
  }) {
    // 即使 Mock 路由配置错误，也在输出边界再次裁剪，模拟正式服务端的素材白名单校验。
    final safeMaterials = materialIds
        .where(request.allowedMaterialIds.contains)
        .take(2)
        .toSet();
    return ExplorationTurnResponse(
      answer: answer,
      followUpQuestion: followUp,
      boundary: boundary,
      intent: intent,
      materialIds: safeMaterials,
      isSideBranchSuggested: sideBranch,
      strategyVersion: strategyVersion,
    );
  }

  static bool _containsAny(String value, List<String> candidates) {
    return candidates.any(value.contains);
  }
}
