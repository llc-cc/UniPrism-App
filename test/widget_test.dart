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
