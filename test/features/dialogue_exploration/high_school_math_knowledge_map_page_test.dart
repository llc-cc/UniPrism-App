import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniprism_app/main.dart' as app;

void main() {
  testWidgets('知识图谱从模块下钻到主题和知识点并可返回', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 1000));

    expect(find.text('高中数学知识点总览'), findsOneWidget);
    expect(find.text('共 8 个知识点，2 个分支'), findsWidgets);
    expect(find.text('集合与常用逻辑用语'), findsOneWidget);
    expect(find.text('等式与不等式'), findsOneWidget);
    expect(find.text('分支总览'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('knowledge-theme-A1')));
    await tester.pumpAndSettle();

    expect(find.text('分支总览'), findsNothing);
    expect(find.text('集合的概念与表示'), findsOneWidget);
    expect(find.text('集合的基本运算'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('knowledge-breadcrumb-theme')),
      findsOneWidget,
    );
    final back = find.byKey(const ValueKey('knowledge-level-back'));
    expect(tester.widget(back), isA<FilledButton>());
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('knowledge-map-toolbar')),
        matching: back,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('knowledge-third-level-connector-layer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('knowledge-map-detail-pane')),
      findsNothing,
    );
    expect(find.text('去学习'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('knowledge-point-A1.3')));
    await tester.pumpAndSettle();
    expect(find.text('知识点'), findsOneWidget);
    expect(find.text('关键内容'), findsOneWidget);
    expect(find.text('考试提示'), findsOneWidget);
    expect(find.text('集合的基本运算'), findsWidgets);
    expect(find.textContaining('交集、并集和补集'), findsOneWidget);

    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('knowledge-theme-A2')), findsOneWidget);
    expect(find.text('分支总览'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('knowledge-map-detail-pane')),
      findsNothing,
    );
  });

  testWidgets('函数模块展示本地图谱中的三个主题和十七个知识点统计', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 1000));

    await tester.tap(find.byKey(const ValueKey('knowledge-module-B')));
    await tester.pumpAndSettle();

    expect(find.text('共 17 个知识点，3 个分支'), findsWidgets);
    expect(find.text('函数的概念与基本性质'), findsOneWidget);
    expect(find.text('幂函数、指数函数与对数函数'), findsOneWidget);
    expect(find.text('函数的图象与应用'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('knowledge-theme-B3')));
    await tester.pumpAndSettle();
    expect(find.text('函数的图象与图象变换'), findsOneWidget);
    expect(find.text('函数模型及其应用'), findsOneWidget);
  });

  testWidgets('其余数学模块均展示本地图谱中的二级分支', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 1000));

    const expectedThemes = <String, List<String>>{
      'C': ['导数的概念与运算', '导数的综合应用'],
      'D': ['三角函数的概念与公式', '解三角形'],
      'E': ['平面向量的概念与线性运算', '复数'],
      'F': ['等差数列与等比数列', '数列的综合与创新'],
      'G': ['空间几何体', '空间向量与立体几何'],
      'H': ['直线与圆', '直线与圆锥曲线的位置关系'],
      'I': ['计数原理', '统计'],
    };

    for (final entry in expectedThemes.entries) {
      final module = find.byKey(ValueKey('knowledge-module-${entry.key}'));
      await tester.ensureVisible(module);
      await tester.tap(module);
      await tester.pumpAndSettle();

      expect(find.text(entry.value.first), findsOneWidget);
      expect(find.text(entry.value.last), findsOneWidget);
      expect(find.text('该模块的三级内容将在后续批次接入'), findsNothing);
    }

    expect(
      find.byKey(const ValueKey('knowledge-theme-I1-locked')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('knowledge-theme-I1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('knowledge-level-back')), findsNothing);
    expect(find.text('分支总览'), findsOneWidget);
  });

  testWidgets('窄屏使用紧凑布局且不发生溢出', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(390, 844));

    expect(find.byKey(const ValueKey('knowledge-map-compact')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('knowledge-theme-A2')));
    await tester.pumpAndSettle();
    expect(find.text('基本不等式'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('knowledge-map-detail-pane')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面分支总览按 Figma 尺寸展示节点和连接线', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 1000));

    await tester.tap(find.byKey(const ValueKey('knowledge-module-C')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('knowledge-connector-layer')),
      findsOneWidget,
    );
    final rootRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-root-node')),
    );
    final branchRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-theme-C1')),
    );
    expect(rootRect.width, closeTo(296.7, 1));
    expect(rootRect.height, closeTo(83.95, 1));
    expect(branchRect.width, closeTo(296.7, 1));
    expect(branchRect.height, closeTo(83.95, 1));
    expect(branchRect.left, greaterThan(rootRect.right));
    expect(
      find.byKey(const ValueKey('knowledge-node-frame-clean-C1')),
      findsOneWidget,
    );
    final iconRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-theme-icon-C1')),
    );
    final badgeRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-theme-badge-C1-0')),
    );
    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-map-canvas')),
    );
    expect(iconRect.width, closeTo(55.2, 1));
    expect(iconRect.height, closeTo(55.2, 1));
    expect(iconRect.left - branchRect.left, closeTo(19.55, 1));
    expect(badgeRect.width, closeTo(25.3, 1));
    expect(badgeRect.height, closeTo(25.3, 1));
    expect(branchRect.right, lessThanOrEqualTo(canvasRect.right));
  });

  testWidgets('二级分支节点勾选离开内层装饰线', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 810));

    final nodeRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-theme-A1')),
    );
    final status = find.byKey(const ValueKey('knowledge-theme-status-A1'));
    expect(status, findsOneWidget);
    final statusRect = tester.getRect(status);

    expect(statusRect.size, const Size.square(17.25));
    expect(statusRect.top - nodeRect.top, closeTo(12.65, 1));
    expect(nodeRect.right - statusRect.right, closeTo(17.25, 1));
  });

  testWidgets('二级分支节点箭头放大并与勾选垂直对齐', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 810));

    final node = find.byKey(const ValueKey('knowledge-theme-A1'));
    final chevron = find.descendant(
      of: node,
      matching: find.byIcon(Icons.chevron_right_rounded),
    );
    final status = find.byKey(const ValueKey('knowledge-theme-status-A1'));

    expect(chevron, findsOneWidget);
    final nodeRect = tester.getRect(node);
    final chevronRect = tester.getRect(chevron);
    final statusRect = tester.getRect(status);
    expect(chevronRect.width, closeTo(33.35, 0.2));
    expect(chevronRect.height, closeTo(33.35, 0.2));
    expect(nodeRect.right - chevronRect.right, closeTo(9.2, 1));
    expect(nodeRect.right - statusRect.right, closeTo(17.25, 1));
    expect(chevronRect.center.dx, closeTo(statusRect.center.dx, 1));
  });

  testWidgets('分支总览按钮使用 Figma 主绿色和浅色斜带', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 810));

    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-level-overview')),
    );
    final baseColor = await _sampleRenderedPixel(
      tester,
      Offset(buttonRect.left + 10, buttonRect.center.dy),
    );
    final bandColor = await _sampleRenderedPixel(
      tester,
      Offset(buttonRect.left + 104, buttonRect.top + 21),
    );

    expect(baseColor, const Color(0xFF1FA877));
    expect(
      bandColor.computeLuminance(),
      greaterThan(baseColor.computeLuminance()),
    );
  });

  testWidgets('二级分支节点白色内描边在缩放后保持清晰厚度', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 810));

    final nodeRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-theme-A1')),
    );
    final upperEdge = await _sampleRenderedPixel(
      tester,
      Offset(nodeRect.center.dx, nodeRect.top + 7),
    );
    final lowerEdge = await _sampleRenderedPixel(
      tester,
      Offset(nodeRect.center.dx, nodeRect.top + 9),
    );

    expect(upperEdge.computeLuminance(), greaterThan(0.7));
    expect(lowerEdge.computeLuminance(), greaterThan(0.48));
  });

  testWidgets('locked branch node uses the Figma neutral-gray palette', (
    tester,
  ) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 1000));

    await tester.tap(find.byKey(const ValueKey('knowledge-module-C')));
    await tester.pumpAndSettle();

    final nodeRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-theme-C1')),
    );
    final iconRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-theme-icon-C1')),
    );
    final nodeFill = await _sampleRenderedPixel(
      tester,
      Offset(nodeRect.right - 45, nodeRect.bottom - 15),
    );
    final iconFill = await _sampleRenderedPixel(
      tester,
      Offset(iconRect.left + 10, iconRect.center.dy),
    );
    final innerStroke = await _sampleRenderedPixel(
      tester,
      Offset(nodeRect.center.dx, nodeRect.top + 8),
    );

    expect(nodeFill, const Color(0xFFE5E5E5));
    expect(iconFill, const Color(0xFFE5E5E5));
    expect(innerStroke, const Color(0xFFCCCCCC));
  });

  testWidgets('locked branch node renders only the inner contour', (
    tester,
  ) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 1000));

    await tester.tap(find.byKey(const ValueKey('knowledge-module-C')));
    await tester.pumpAndSettle();

    final nodeRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-theme-C1')),
    );
    final outerBand = await _sampleRenderedPixel(
      tester,
      Offset(nodeRect.center.dx, nodeRect.top + 4),
    );
    final innerContour = await _sampleRenderedPixel(
      tester,
      Offset(nodeRect.center.dx, nodeRect.top + 8),
    );

    expect(outerBand, const Color(0xFFE5E5E5));
    expect(innerContour, const Color(0xFFCCCCCC));
  });

  testWidgets('锁定分支节点使用灰色连接线', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 1000));

    await tester.tap(find.byKey(const ValueKey('knowledge-module-C')));
    await tester.pumpAndSettle();

    final connector = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('knowledge-connector-layer')),
    );
    expect(
      (Canvas canvas) => connector.painter!.paint(canvas, const Size(700, 400)),
      paints..line(color: const Color(0xFFD3D8D6), strokeWidth: 4),
    );
  });

  testWidgets('桌面目录和三级详情按 Figma 基准尺寸布局', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 810));

    final selectedModuleRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-module-card-A')),
    );
    final secondModuleRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-module-card-B')),
    );
    final modulePaneRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-map-module-pane')),
    );
    expect(modulePaneRect.width, closeTo(374, 1));
    expect(selectedModuleRect.width, closeTo(349, 1));
    expect(selectedModuleRect.height, closeTo(75, 1));
    expect(secondModuleRect.top - selectedModuleRect.bottom, closeTo(8, 1));
    expect(
      find.byKey(const ValueKey('knowledge-theme-A1-unlocked')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('knowledge-theme-A1')));
    await tester.pumpAndSettle();

    final point = find.byKey(const ValueKey('knowledge-point-A1.1'));
    final pointRect = tester.getRect(point);
    expect(pointRect.width, closeTo(258, 1));
    expect(pointRect.height, closeTo(73, 1));
    expect(find.byKey(const ValueKey('knowledge-root-node')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('knowledge-third-level-connector-layer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('knowledge-map-detail-pane')),
      findsNothing,
    );

    await tester.tap(point);
    await tester.pumpAndSettle();

    final focusedPointRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-point-A1.1')),
    );
    final siblingPointRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-point-A1.2')),
    );
    expect(focusedPointRect.width, closeTo(456, 1));
    expect(focusedPointRect.height, closeTo(131, 1));
    expect(siblingPointRect.width, closeTo(301, 1));
    expect(siblingPointRect.height, closeTo(86, 1));
    expect(siblingPointRect.left, closeTo(focusedPointRect.left, 1));
    expect(siblingPointRect.top - focusedPointRect.bottom, closeTo(32, 1));
    final selectedCheckRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('knowledge-point-A1.1')),
        matching: find.byIcon(Icons.check_rounded),
      ),
    );
    expect(selectedCheckRect.top - focusedPointRect.top, closeTo(16, 1));
    expect(find.byKey(const ValueKey('knowledge-root-node')), findsNothing);
    expect(
      find.byKey(const ValueKey('knowledge-third-level-connector-layer')),
      findsNothing,
    );

    final detailRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-map-detail-pane')),
    );
    expect(detailRect.width, closeTo(374, 1));

    final siblingOpacity = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('knowledge-point-opacity-A1.2')),
    );
    expect(siblingOpacity.opacity, closeTo(.2, .01));

    await tester.tap(find.byKey(const ValueKey('knowledge-point-A1.2')));
    await tester.pumpAndSettle();
    final nextFocusedRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-point-A1.2')),
    );
    final previousFocusedRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-point-A1.1')),
    );
    expect(nextFocusedRect.width, closeTo(456, 1));
    expect(nextFocusedRect.height, closeTo(131, 1));
    expect(previousFocusedRect.width, closeTo(301, 1));
    expect(previousFocusedRect.height, closeTo(86, 1));
  });

  testWidgets(
    'third-level overview node keeps the icon clear of the inner frame',
    (tester) async {
      await _pumpKnowledgeMap(tester, const Size(1440, 810));

      await tester.tap(find.byKey(const ValueKey('knowledge-theme-A1')));
      await tester.pumpAndSettle();

      final point = find.byKey(const ValueKey('knowledge-point-A1.1'));
      final pointRect = tester.getRect(point);
      final bookIconRect = tester.getRect(
        find.descendant(
          of: point,
          matching: find.byIcon(Icons.menu_book_rounded),
        ),
      );
      final iconCircleLeft = bookIconRect.center.dx - 24;

      expect(iconCircleLeft - pointRect.left, closeTo(17, 1));
    },
  );

  testWidgets(
    'third-level focused node keeps the icon clear of the inner frame',
    (tester) async {
      await _pumpKnowledgeMap(tester, const Size(1440, 810));

      await tester.tap(find.byKey(const ValueKey('knowledge-theme-A1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('knowledge-point-A1.1')));
      await tester.pumpAndSettle();

      final point = find.byKey(const ValueKey('knowledge-point-A1.1'));
      final pointRect = tester.getRect(point);
      final bookIconRect = tester.getRect(
        find.descendant(
          of: point,
          matching: find.byIcon(Icons.menu_book_rounded),
        ),
      );
      final iconCircleLeft = bookIconRect.center.dx - 38;

      expect(iconCircleLeft - pointRect.left, closeTo(22, 1));
    },
  );

  testWidgets('三级聚焦节点右侧状态区按 Figma 间距展示', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 810));

    await tester.tap(find.byKey(const ValueKey('knowledge-theme-A1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('knowledge-point-A1.1')));
    await tester.pumpAndSettle();

    final selectedRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-point-A1.1')),
    );
    final selectedChevron = find.byKey(
      const ValueKey('knowledge-point-chevron-A1.1'),
    );
    final selectedStatus = find.byKey(
      const ValueKey('knowledge-point-status-A1.1'),
    );
    expect(selectedChevron, findsOneWidget);
    expect(selectedStatus, findsOneWidget);
    final selectedChevronRect = tester.getRect(selectedChevron);
    final selectedStatusRect = tester.getRect(selectedStatus);
    expect(selectedChevronRect.size, const Size.square(37));
    expect(selectedRect.right - selectedChevronRect.right, closeTo(20, 1));
    expect(selectedStatusRect.size, const Size.square(23));
    expect(selectedRect.right - selectedStatusRect.right, closeTo(25, 1));
    expect(selectedStatusRect.top - selectedRect.top, closeTo(16, 1));

    final siblingRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-point-A1.2')),
    );
    final siblingChevron = find.byKey(
      const ValueKey('knowledge-point-chevron-A1.2'),
    );
    final siblingStatus = find.byKey(
      const ValueKey('knowledge-point-status-A1.2'),
    );
    expect(siblingChevron, findsOneWidget);
    expect(siblingStatus, findsOneWidget);
    final siblingChevronRect = tester.getRect(siblingChevron);
    final siblingStatusRect = tester.getRect(siblingStatus);
    expect(siblingChevronRect.size, const Size.square(25));
    expect(siblingRect.right - siblingChevronRect.right, closeTo(13, 1));
    expect(siblingStatusRect.size, const Size.square(15));
    expect(siblingRect.right - siblingStatusRect.right, closeTo(17, 1));
    expect(siblingStatusRect.top - siblingRect.top, closeTo(11, 1));
  });

  testWidgets('桌面端按 Figma 顶部基线并在首屏完整展示第六个目录项', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 720));

    final firstModuleRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-module-card-A')),
    );
    final sixthModuleRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-module-card-F')),
    );
    final levelButtonRect = tester.getRect(find.text('分支总览'));

    expect(firstModuleRect.top, closeTo(142, 1));
    expect(sixthModuleRect.bottom, lessThanOrEqualTo(632));
    expect(levelButtonRect.height, closeTo(21.314, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面目录保留字号并收紧图标与两行文字间距', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 720));

    final card = find.byKey(const ValueKey('knowledge-module-card-A'));
    final progressIcon = find
        .descendant(of: card, matching: find.byType(CustomPaint))
        .first;
    final title = find.descendant(of: card, matching: find.text('1. 预备知识与不等式'));
    final description = find.descendant(
      of: card,
      matching: find.textContaining('进度：已完成8个知识点'),
    );
    final titleWidget = tester.widget<Text>(title);

    expect(titleWidget.style?.fontSize, 14);
    expect(
      tester.getRect(title).left - tester.getRect(progressIcon).right,
      lessThanOrEqualTo(8),
    );
    expect(
      tester.getRect(description).top - tester.getRect(title).bottom,
      lessThanOrEqualTo(6),
    );
  });

  testWidgets('桌面右上角头像与全屏按钮纵向排列在搜索框右侧', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 720));

    final searchRect = tester.getRect(find.textContaining('搜索知识点'));
    final avatarRect = tester.getRect(find.byType(CircleAvatar));
    final fullScreenRect = tester.getRect(
      find.byIcon(Icons.center_focus_strong),
    );

    expect(avatarRect.left, greaterThan(searchRect.right));
    expect(fullScreenRect.top, greaterThan(avatarRect.bottom));
    expect(fullScreenRect.center.dx, closeTo(avatarRect.center.dx, 3));
  });

  testWidgets('三级详情面板与左侧目录上下对齐且不遮挡全屏按钮', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 810));

    await tester.tap(find.byKey(const ValueKey('knowledge-theme-A1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('knowledge-point-A1.1')));
    await tester.pumpAndSettle();

    final fullScreenRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-map-fullscreen-button')),
    );
    final detailRect = tester.getRect(
      find.byKey(const ValueKey('knowledge-map-detail-pane')),
    );
    final modulePane = find.byKey(const ValueKey('knowledge-map-module-pane'));
    expect(modulePane, findsOneWidget);
    final modulePaneRect = tester.getRect(modulePane);

    expect(modulePaneRect.top, closeTo(detailRect.top, 1));
    expect(modulePaneRect.bottom, closeTo(detailRect.bottom, 1));
    expect(detailRect.top - fullScreenRect.bottom, inInclusiveRange(18, 22));
  });

  testWidgets('桌面搜索框与等级切换区按确认规格展示', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 720));

    final search = find.byKey(const ValueKey('knowledge-map-search-box'));
    final searchWidget = tester.widget<Container>(search);
    final searchDecoration = searchWidget.decoration! as BoxDecoration;
    expect(tester.getSize(search), const Size(200, 45));
    expect(
      searchWidget.padding,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
    expect(searchDecoration.color, const Color(0xFFF7F8FA));
    expect(searchDecoration.borderRadius, BorderRadius.circular(43));
    expect(
      tester
          .widget<Text>(
            find.descendant(of: search, matching: find.byType(Text)),
          )
          .style
          ?.fontSize,
      14,
    );

    expect(tester.getSize(find.byType(CircleAvatar)), const Size.square(45));
    expect(
      tester.getSize(
        find.byKey(const ValueKey('knowledge-map-fullscreen-button')),
      ),
      const Size.square(39),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.center_focus_strong)).size,
      24,
    );

    final button = find.byKey(const ValueKey('knowledge-level-overview'));
    final buttonWidget = tester.widget<FilledButton>(button);
    final buttonShape =
        buttonWidget.style!.shape!.resolve({})! as RoundedRectangleBorder;
    expect(tester.getSize(button), const Size(129, 42));
    expect(buttonShape.borderRadius, BorderRadius.circular(6));
    expect(
      tester
          .widget<Text>(
            find.descendant(of: button, matching: find.text('分支总览')),
          )
          .style
          ?.fontSize,
      16,
    );

    final toolbar = find.byKey(const ValueKey('knowledge-map-toolbar'));
    final breadcrumb = find.descendant(
      of: toolbar,
      matching: find.textContaining('预备知识与不等式'),
    );
    expect(tester.widget<Text>(breadcrumb).style?.fontSize, 14);
    expect(
      tester.getRect(breadcrumb).left - tester.getRect(button).right,
      closeTo(14, 1),
    );

    final title = find.byKey(const ValueKey('knowledge-map-desktop-title'));
    expect(tester.widget<Text>(title).style?.fontSize, 24);
    expect(tester.getRect(title).top, closeTo(tester.getRect(button).top, 1));
  });

  testWidgets('桌面侧栏随窗口宽度收缩并保持文字字号', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1000, 720));

    final card = find.byKey(const ValueKey('knowledge-module-card-A'));
    final cardRect = tester.getRect(card);
    final title = tester.widget<Text>(
      find.descendant(of: card, matching: find.text('1. 预备知识与不等式')),
    );

    expect(cardRect.width, closeTo(235, 1));
    expect(title.style?.fontSize, 14);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面图谱画布支持平移缩放控制并在切换模块时复位', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 720));

    final viewerFinder = find.byKey(
      const ValueKey('knowledge-map-interactive-viewer'),
    );
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    final controller = viewer.transformationController!;

    expect(viewer.minScale, .5);
    expect(viewer.maxScale, 2.5);
    expect(viewer.panEnabled, isTrue);
    expect(viewer.scaleEnabled, isTrue);
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('knowledge-map-zoom-in')));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1.25, .01));
    expect(find.text('125%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('knowledge-map-fit')));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, .01));
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('knowledge-map-zoom-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('knowledge-module-B')));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, .01));
  });
  testWidgets('桌面节点保持固定而空白画布可整体拖动', (tester) async {
    await _pumpKnowledgeMap(tester, const Size(1440, 720));

    final node = find.byKey(const ValueKey('knowledge-theme-A1'));
    final root = find.byKey(const ValueKey('knowledge-root-node'));
    final relationshipBefore =
        tester.getRect(node).topLeft - tester.getRect(root).topLeft;
    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('knowledge-map-interactive-viewer')),
    );
    final transformBefore = viewer.transformationController!.value.clone();
    final canvas = tester.getRect(
      find.byKey(const ValueKey('knowledge-map-canvas')),
    );

    await tester.dragFrom(
      Offset(canvas.left + 30, canvas.bottom - 30),
      const Offset(70, -40),
    );
    await tester.pumpAndSettle();

    final relationshipAfter =
        tester.getRect(node).topLeft - tester.getRect(root).topLeft;
    expect(relationshipAfter.dx, closeTo(relationshipBefore.dx, .01));
    expect(relationshipAfter.dy, closeTo(relationshipBefore.dy, .01));
    expect(viewer.transformationController!.value, isNot(transformBefore));
    expect(
      find.byKey(const ValueKey('knowledge-draggable-root')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('knowledge-map-reset-layout')),
      findsNothing,
    );
  });
}

Future<void> _pumpKnowledgeMap(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const app.UniPrismApp());
  final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
  final routeBuilder = materialApp.routes!['/knowledge-map-lab'];
  expect(routeBuilder, isNotNull);

  final context = tester.element(find.byType(MaterialApp));
  await tester.pumpWidget(MaterialApp(home: routeBuilder!(context)));
  await tester.pumpAndSettle();
}

Future<Color> _sampleRenderedPixel(
  WidgetTester tester,
  Offset logicalPosition,
) async {
  return (await tester.runAsync(() async {
    final renderView = tester.binding.renderViews.single;
    final layer = renderView.debugLayer! as OffsetLayer;
    final image = await layer.toImage(renderView.paintBounds);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final x = logicalPosition.dx.round();
    final y = logicalPosition.dy.round();
    final offset = (y * image.width + x) * 4;
    final data = bytes!.buffer.asUint8List();
    return Color.fromARGB(
      data[offset + 3],
      data[offset],
      data[offset + 1],
      data[offset + 2],
    );
  }))!;
}
