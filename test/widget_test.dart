import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/main.dart';

Future<void> pumpAtSize(WidgetTester tester, Size size, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pump();
}

void expectOnlyNetworkImageExceptions(WidgetTester tester) {
  Object? pendingException;
  while ((pendingException = tester.takeException()) != null) {
    expect(pendingException, isA<NetworkImageLoadException>());
  }
}

void main() {
  test('persona card snapshot parses the backend response', () {
    final snapshot = PersonaCardSnapshot.fromJson({
      'state': 'completed',
      'codeTag': 'IA',
      'title': '探索型创造者',
      'cardImagePath': '/images/persona/ia.png',
      'summary': '报告已完成',
      'reportId': 'report-1',
    });

    expect(snapshot.isUnlocked, isTrue);
    expect(snapshot.hasCompletedReport, isTrue);
    expect(snapshot.title, '探索型创造者');
    expect(snapshot.reportId, 'report-1');
  });

  test('report task parses backend progress and completed content', () {
    final task = ReportTaskData.fromJson({
      'exists': true,
      'reportId': 'report-2',
      'status': 'completed',
      'queued': false,
      'workflowProgress': {
        'title': '组织专业建议',
        'description': '正在整理推荐方向',
        'percent': 88,
      },
      'report': {
        'majorRecommendations': {
          'majors': [
            {'name': '数学与应用数学'},
          ],
        },
      },
    });

    expect(task.isCompleted, isTrue);
    expect(task.reportId, 'report-2');
    expect(task.progress.percent, 88);
    expect(task.report?['majorRecommendations'], isA<Map>());
  });

  test('agent reply keeps source cards and confirmation separate', () {
    final reply = AgentChatReply.fromJson({
      'conversationId': 'conversation-1',
      'text': '找到两条内容，并生成订阅预览。',
      'cards': [
        {
          'id': 'content-1',
          'title': '人工智能专业体验',
          'excerpt': '授权摘要',
          'source': {
            'id': 'source-1',
            'name': '授权来源',
            'url': 'https://example.com/content-1',
          },
          'contentType': 'major_experience',
          'recommendationReason': '与你的兴趣相关',
          'publishedAt': '2026-07-22T10:00:00+08:00',
        },
      ],
      'pendingAction': {
        'type': 'create_subscription',
        'previewId': 'preview-1',
        'requiresConfirmation': true,
        'subscription': {
          'name': 'AI 专业探索',
          'topics': ['人工智能'],
          'sourceScope': ['authorized'],
          'contentScope': ['major_experience'],
          'frequency': 'daily',
          'pushTime': '20:00',
          'quietHours': ['22:00', '07:30'],
          'maxItems': 3,
        },
      },
    });

    expect(reply.cards.single.source.name, '授权来源');
    expect(reply.subscriptionDraft?.previewId, 'preview-1');
    expect(reply.subscriptionDraft?.pushTime, '20:00');
  });

  test('content acquisition metadata keeps pending task identity', () {
    final result = UnifiedContentAnswerResult.fromJson({
      'answer': {
        'answer': '正在后台补充资料',
        'keyPoints': ['已转后台'],
        'confidence': 'low',
        'caveat': '等待真实资料',
        'model': 'not-called',
        'usedFallback': true,
      },
      'sourceSummary': {'success': 0, 'failed': 0, 'itemCount': 0},
      'selectedSources': [],
      'acquisition': {
        'jobId': 'acq-11111111111111111111111111111111',
        'status': 'pending',
        'merged': true,
        'foregroundWaitMs': 8000,
      },
    });

    expect(result.acquisition?.isPending, isTrue);
    expect(result.acquisition?.merged, isTrue);
    expect(result.acquisition?.foregroundWaitMs, 8000);
  });

  test('Zhihu content test result keeps AI plan and real source separate', () {
    final result = ZhihuContentTestResult.fromJson({
      'provider': 'zhihu-official-open-platform',
      'userQuestion': '人工智能专业就业前景',
      'searchQuery': '人工智能专业 就业前景',
      'queryPlan': {
        'intentSummary': '了解专业就业方向',
        'matchedInterests': ['人工智能', '就业'],
        'model': 'deepseek-v4-flash',
      },
      'retrievedAt': '2026-07-23T08:00:00.000Z',
      'items': [
        {
          'id': 'answer-1',
          'title': '人工智能专业毕业后能做什么？',
          'contentText': '知乎官方接口返回的内容摘要。',
          'url': 'https://www.zhihu.com/question/1/answer/1',
          'contentType': 'Answer',
          'authorName': '知乎作者',
          'editTime': '2026-07-22T08:00:00.000Z',
          'commentCount': 8,
          'voteUpCount': 42,
          'rankingScore': 0.98,
        },
      ],
    });

    expect(result.searchQuery, '人工智能专业 就业前景');
    expect(result.model, 'deepseek-v4-flash');
    expect(result.matchedInterests, ['人工智能', '就业']);
    expect(result.items.single.title, '人工智能专业毕业后能做什么？');
    expect(result.items.single.voteUpCount, 42);
  });

  test('math course page keeps backend native-content routing fields', () {
    final page = MathCoursePageData.fromJson({
      'id': 'analysis-strict-limit',
      'stageIndex': 1,
      'stageTitle': 'Part 2：数学课程介绍',
      'kind': 'web-experience',
      'title': '极限的严格定义',
      'navTitle': '严格定义',
      'webPageId': 'analysis-strict-limit',
      'courseId': 'analysis',
    });

    expect(page.hasNativeContent, isTrue);
    expect(page.webPageId, 'analysis-strict-limit');
    expect(page.stageIndex, 1);
  });

  testWidgets('app login opens directly on the SMS form', (tester) async {
    await pumpAtSize(tester, const Size(360, 720), const AppLoginPage());

    expect(find.text('手机号登录'), findsOneWidget);
    expect(find.text('请输入手机号'), findsOneWidget);
    expect(find.text('6 位验证码'), findsOneWidget);
    expect(find.text('收不到验证码？'), findsOneWidget);
    expect(find.text('登录并继续'), findsOneWidget);
    expect(find.text('开发环境模拟手机号'), findsNothing);
    expect(find.byKey(const ValueKey('simulated-phone-login')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('main shell keeps four phone tabs fixed at the bottom', (
    tester,
  ) async {
    var selectedIndex = 0;
    await pumpAtSize(
      tester,
      const Size(320, 568),
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Text('selected-$selectedIndex'),
          bottomNavigationBar: AppBottomNavigationBar(
            selectedIndex: selectedIndex,
            onSelected: (index) => setState(() => selectedIndex = index),
          ),
        ),
      ),
    );

    expect(find.text('兴趣探索'), findsOneWidget);
    expect(find.text('专业体验'), findsOneWidget);
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.byKey(const ValueKey('main-tab-3')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('main-tab-3')));
    await tester.pump();

    expect(find.text('selected-3'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('home opens the knowledge forest from a visible entry', (
    tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 1600), const HomePage());

    // HomePage 的远程装饰图在 Widget 测试环境固定返回 400；该异常与导航行为无关。
    expectOnlyNetworkImageExceptions(tester);

    final knowledgeEntry = find.byKey(
      const ValueKey('knowledge-forest-home-entry'),
    );
    expect(knowledgeEntry, findsOneWidget);

    await tester.tap(knowledgeEntry);
    await tester.pumpAndSettle();

    expect(find.text('我的知识森林'), findsOneWidget);
    expectOnlyNetworkImageExceptions(tester);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('home collapses diagnostics into one developer tools entry', (
    tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 2400), const HomePage());
    expectOnlyNetworkImageExceptions(tester);

    expect(
      find.byKey(const ValueKey('developer-tools-home-entry')),
      findsOneWidget,
    );
    expect(find.text('真实内容入库预览'), findsNothing);
    expect(find.text('推荐专业 × 知乎真实性测试'), findsNothing);
    expect(find.text('推荐专业 × GitHub真实性测试'), findsNothing);
    expect(find.text('推荐专业 × Agent统一回答测试'), findsNothing);
    expect(find.text('报告生成通知测试'), findsNothing);
    expect(find.text('横屏贪吃蛇'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('developer tools page keeps every existing diagnostic entry', (
    tester,
  ) async {
    await pumpAtSize(
      tester,
      const Size(390, 1000),
      const DeveloperToolsPage(recommendedMajors: ['人工智能'], interests: ['创造']),
    );

    expect(find.text('真实内容入库预览'), findsOneWidget);
    expect(find.text('高中数学知识图谱'), findsOneWidget);
    expect(find.text('推荐专业 × 知乎真实性测试'), findsOneWidget);
    expect(find.text('推荐专业 × GitHub真实性测试'), findsOneWidget);
    expect(find.text('推荐专业 × Agent统一回答测试'), findsOneWidget);
    expect(find.text('报告生成通知测试'), findsOneWidget);
    expect(find.text('横屏贪吃蛇'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('developer tools opens the 1.2 dialogue exploration lab', (
    tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 1000), const DeveloperToolsPage());

    final entry = find.byKey(
      const ValueKey('developer-tool-dialogue-exploration'),
    );
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('1.2 AI 探索课堂'), findsOneWidget);
  });

  testWidgets('popular major cards are display-only', (tester) async {
    await pumpAtSize(
      tester,
      const Size(390, 844),
      Scaffold(body: PopularMajorCard(card: HomeMajorCard.lockedCards.first)),
    );

    final firstCardTitle = find.text('待解锁TOP1');
    expect(firstCardTitle, findsOneWidget);
    expect(
      find.ancestor(of: firstCardTitle, matching: find.byType(InkWell)),
      findsNothing,
    );

    await tester.tap(firstCardTitle);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('developer tools opens the high school math knowledge map', (
    tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 1000), const DeveloperToolsPage());

    final entry = find.byKey(const ValueKey('developer-tool-knowledge-map'));
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('高中数学知识点总览'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('profile login button opens the named login route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {'/login': (_) => const AppLoginPage()},
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => openAppLogin(context),
              child: const Text('打开登录'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('打开登录'));
    await tester.pumpAndSettle();

    expect(find.text('手机号登录'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('privacy gate blocks app content until consent', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/terms': (_) =>
              const LegalDocumentPage(type: LegalDocumentType.terms),
          '/privacy': (_) =>
              const LegalDocumentPage(type: LegalDocumentType.privacy),
        },
        home: PrivacyConsentPage(onAccept: () async {}),
      ),
    );
    await tester.pump();

    expect(find.text('隐私保护说明'), findsOneWidget);
    expect(find.text('同意并继续'), findsOneWidget);
    expect(find.text('暂不同意'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('landscape snake game renders its controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LandscapeTestPage()));

    expect(find.text('贪吃蛇'), findsOneWidget);
    expect(find.text('得分'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('report notification demo shows its entry state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ReportGenerationDemoPage()),
    );
    await tester.pump();

    expect(find.text('报告生成通知'), findsOneWidget);
    expect(find.text('报告完成后及时告诉你'), findsOneWidget);
    expect(find.text('开始模拟生成报告'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('agent demo clearly labels mock data and requires confirmation', (
    tester,
  ) async {
    await pumpAtSize(tester, const Size(390, 844), const AgentExperiencePage());

    expect(find.text('内部演示模式 · 未连接知乎、小红书或真实推送'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-message-input')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('agent-message-input')),
      '每天晚上八点推送人工智能专业内容',
    );
    await tester.tap(find.byKey(const ValueKey('agent-send-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('演示数据'), findsWidgets);
    expect(find.text('确认创建订阅'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('确认创建订阅'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认创建订阅'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('已确认'), findsOneWidget);
    expect(find.textContaining('内部演示订阅已创建'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('report result page renders the simulated report', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ReportResultPage(reportId: 'demo-123')),
    );

    expect(find.text('专业方向探索报告'), findsOneWidget);
    expect(find.text('探索型创造者'), findsOneWidget);
    expect(find.text('数字媒体艺术'), findsOneWidget);
  });

  testWidgets('generated report view renders real backend sections', (
    tester,
  ) async {
    await pumpAtSize(
      tester,
      const Size(390, 844),
      Scaffold(
        body: SingleChildScrollView(
          child: GeneratedReportView(
            reportId: 'report-real',
            report: const {
              'personalityAndCareerAnalysis': {
                'hollandType': {
                  'code': 'IA',
                  'title': '研究型探索者',
                  'reason': '喜欢理解复杂问题背后的规律。',
                },
                'careerTendencyAnalysis': {
                  'title': '职业倾向分析',
                  'body': '适合需要分析和持续学习的环境。',
                },
              },
              'majorRecommendations': {
                'title': '专业推荐',
                'majors': [
                  {'name': '数学与应用数学', 'personalizedReason': '与你的分析兴趣和抽象思维相匹配。'},
                ],
              },
              'comprehensiveAdvice': {
                'title': '发展建议',
                'developmentAdvice': '先体验核心课程，再验证长期投入意愿。',
              },
            },
          ),
        ),
      ),
    );

    expect(find.text('研究型探索者'), findsOneWidget);
    expect(find.text('数学与应用数学'), findsOneWidget);
    expect(find.text('发展建议'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Zhihu content test displays stage-recommended majors', (
    tester,
  ) async {
    await pumpAtSize(
      tester,
      const Size(390, 844),
      const ZhihuContentTestPage(
        recommendedMajors: ['人工智能', '计算机科学与技术', '人工智能'],
      ),
    );

    expect(
      find.byKey(const ValueKey('zhihu-recommended-majors')),
      findsOneWidget,
    );
    expect(find.text('人工智能'), findsOneWidget);
    expect(find.text('计算机科学与技术'), findsOneWidget);
    expect(find.text('补充兴趣标签（用逗号分隔）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('final assessment review restores the gold flip flow', (
    tester,
  ) async {
    await pumpAtSize(
      tester,
      const Size(390, 844),
      FinalAssessmentReviewPage(
        answers: const [],
        readyDelay: const Duration(seconds: 1),
        minimumFilteringDuration: Duration.zero,
        scoreLoader: () async => {
          'top15CandidatePool': [
            {'majorId': 'math', 'name': '数学与应用数学'},
            {'majorId': 'cs', 'name': '计算机科学与技术'},
            {'majorId': 'statistics', 'name': '统计学'},
          ],
        },
      ),
    );

    expect(find.byKey(const ValueKey('gold-flip-deck')), findsOneWidget);
    expect(find.text('全部测试已完成，即将开启专业匹配筛选'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('数学与应用数学'), findsOneWidget);
    expect(find.text('计算机科学与技术'), findsOneWidget);
    expect(find.text('生成报告'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('gold final review fits a compact phone', (tester) async {
    await pumpAtSize(
      tester,
      const Size(320, 568),
      FinalAssessmentReviewPage(
        answers: const [],
        readyDelay: const Duration(days: 1),
        scoreLoader: () async => const <String, dynamic>{},
      ),
    );

    expect(find.byKey(const ValueKey('gold-flip-deck')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('locked persona deck fits a compact phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              height: 331,
              child: LockedPersonaDeck(),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(LockedPersonaDeck), findsOneWidget);
  });

  testWidgets('message center exposes local and push notification tests', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MessageCenterPage()));
    await tester.pump();

    expect(find.text('消息通知'), findsOneWidget);
    expect(find.text('本地通知'), findsOneWidget);
    expect(find.text('模拟推送'), findsOneWidget);
    expect(find.text('真实推送通道：待后续接入个推与服务器'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('internal message detail renders persisted message fields', (
    tester,
  ) async {
    final message = AppMessage(
      id: 'message-1',
      source: 'push',
      title: '报告提醒',
      body: '你的报告已经生成。',
      createdAt: DateTime(2026, 7, 17, 10),
      isRead: false,
      route: '/messages',
    );
    await tester.pumpWidget(
      MaterialApp(home: MessageDetailPage(message: message)),
    );

    expect(find.text('消息详情'), findsOneWidget);
    expect(find.text('报告提醒'), findsOneWidget);
    expect(find.text('你的报告已经生成。'), findsOneWidget);
  });

  testWidgets('compact portrait report page has no layout overflow', (
    tester,
  ) async {
    await pumpAtSize(
      tester,
      const Size(320, 568),
      const ReportGenerationDemoPage(),
    );

    expect(find.text('报告完成后及时告诉你'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact landscape snake game keeps board and controls visible', (
    tester,
  ) async {
    await pumpAtSize(tester, const Size(568, 320), const LandscapeTestPage());

    expect(find.text('贪吃蛇'), findsOneWidget);
    expect(find.text('得分'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('wide screens constrain portrait content instead of stretching', (
    tester,
  ) async {
    await pumpAtSize(
      tester,
      const Size(900, 1200),
      const Scaffold(
        body: AppConstrainedContent(
          child: ColoredBox(key: ValueKey('content'), color: Colors.purple),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('content'))).width,
      AppLayout.phoneContentMaxWidth,
    );
    expect(tester.takeException(), isNull);
  });
}
