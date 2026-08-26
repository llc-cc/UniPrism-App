import 'package:flutter/material.dart';

import 'high_school_math_catalog.dart';

const _green = Color(0xFF24C48C);
const _lockedLine = Color(0xFFD3D8D6);
const _ink = Color(0xFF111827);
const _muted = Color(0xFF667085);
const _line = Color(0xFFDCE4ED);
const _canvas = Color(0xFFF7F9FB);

/// 高中数学知识图谱实验页，用于验证模块、主题与知识点的三级浏览交互。
final class HighSchoolMathKnowledgeMapPage extends StatefulWidget {
  const HighSchoolMathKnowledgeMapPage({super.key});

  @override
  State<HighSchoolMathKnowledgeMapPage> createState() =>
      _HighSchoolMathKnowledgeMapPageState();
}

final class _HighSchoolMathKnowledgeMapPageState
    extends State<HighSchoolMathKnowledgeMapPage> {
  MathKnowledgeModule _module = HighSchoolMathCatalog.modules.first;
  MathKnowledgeTheme? _theme;
  MathKnowledgePoint? _point;
  bool _showPointDetail = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 820;
            final content = compact
                ? _CompactLayout(
                    module: _module,
                    theme: _theme,
                    point: _point,
                    onModuleTap: _selectModule,
                    onThemeTap: _selectTheme,
                    onBack: _backToThemes,
                    onPointTap: _selectPoint,
                  )
                : _DesktopLayout(
                    module: _module,
                    theme: _theme,
                    point: _point,
                    showPointDetail: _showPointDetail,
                    onModuleTap: _selectModule,
                    onThemeTap: _selectTheme,
                    onBack: _backToThemes,
                    onPointTap: _selectPoint,
                  );
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1600),
                child: content,
              ),
            );
          },
        ),
      ),
    );
  }

  void _selectModule(MathKnowledgeModule module) {
    setState(() {
      _module = module;
      _theme = null;
      _point = null;
      _showPointDetail = false;
    });
  }

  void _selectTheme(MathKnowledgeTheme theme) {
    if (theme.points.isEmpty) return;
    setState(() {
      _theme = theme;
      // 进入第三级时默认聚焦首个知识点，对齐设计稿“进入即有详情”的路径体验。
      _point = theme.points.firstOrNull;
      _showPointDetail = false;
    });
  }

  void _backToThemes() {
    setState(() {
      _theme = null;
      _point = null;
      _showPointDetail = false;
    });
  }

  void _selectPoint(MathKnowledgePoint point) {
    setState(() {
      _point = point;
      _showPointDetail = true;
    });
  }
}

final class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.module,
    required this.theme,
    required this.point,
    required this.showPointDetail,
    required this.onModuleTap,
    required this.onThemeTap,
    required this.onBack,
    required this.onPointTap,
  });

  final MathKnowledgeModule module;
  final MathKnowledgeTheme? theme;
  final MathKnowledgePoint? point;
  final bool showPointDetail;
  final ValueChanged<MathKnowledgeModule> onModuleTap;
  final ValueChanged<MathKnowledgeTheme> onThemeTap;
  final VoidCallback onBack;
  final ValueChanged<MathKnowledgePoint> onPointTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 21, 40, 48),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sidebarWidth = (constraints.maxWidth * .275)
              .clamp(260.0, 374.0)
              .toDouble();
          final mainGap = (constraints.maxWidth * .0287)
              .clamp(16.0, 39.0)
              .toDouble();
          final detailWidth = (constraints.maxWidth * .275)
              .clamp(300.0, 374.0)
              .toDouble();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 45, child: _DesktopTopBar()),
              const SizedBox(height: 6),
              SizedBox(
                height: 45,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: sidebarWidth,
                      child: const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '高中数学知识点总览',
                          key: ValueKey('knowledge-map-desktop-title'),
                          style: TextStyle(
                            color: _ink,
                            fontSize: 24,
                            height: 44 / 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: mainGap),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _DesktopToolbar(
                              module: module,
                              theme: theme,
                              selectedPoint: point,
                              onBack: onBack,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Padding(
                            padding: EdgeInsets.only(top: 4, bottom: 2),
                            child: _FullscreenButton(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: sidebarWidth,
                      child: _ModuleList(selected: module, onTap: onModuleTap),
                    ),
                    SizedBox(width: mainGap),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _DesktopMapCanvas(
                              module: module,
                              theme: theme,
                              selectedPoint: point,
                              focusSelectedPoint: showPointDetail,
                              onThemeTap: onThemeTap,
                              onPointTap: onPointTap,
                            ),
                          ),
                          if (theme != null &&
                              point != null &&
                              showPointDetail) ...[
                            const SizedBox(width: 14),
                            SizedBox(
                              width: detailWidth,
                              child: _KnowledgeDetailPanel(point: point!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

final class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: 45,
          child: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 15),
            color: const Color(0xFF98A2B3),
            tooltip: '返回',
            padding: EdgeInsets.zero,
          ),
        ),
        const Spacer(),
        Container(
          key: const ValueKey('knowledge-map-search-box'),
          width: 200,
          height: 45,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(43),
          ),
          child: const Row(
            children: [
              Icon(Icons.search_rounded, color: Color(0xFF98A2B3), size: 16),
              SizedBox(width: 8),
              Text(
                '搜索知识点...',
                style: TextStyle(color: Color(0xFF999999), fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const CircleAvatar(
          radius: 22.5,
          backgroundColor: Color(0xFF151515),
          child: Icon(Icons.person_rounded, color: Colors.white, size: 20),
        ),
      ],
    );
  }
}

final class _FullscreenButton extends StatelessWidget {
  const _FullscreenButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('knowledge-map-fullscreen-button'),
      width: 39,
      height: 39,
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FA),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.center_focus_strong, size: 24),
    );
  }
}

final class _DesktopToolbar extends StatelessWidget {
  const _DesktopToolbar({
    required this.module,
    required this.theme,
    required this.selectedPoint,
    required this.onBack,
  });

  final MathKnowledgeModule module;
  final MathKnowledgeTheme? theme;
  final MathKnowledgePoint? selectedPoint;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('knowledge-map-toolbar'),
      children: [
        if (theme == null)
          _LevelButton(
            buttonKey: const ValueKey('knowledge-level-overview'),
            label: '分支总览',
          )
        else
          _LevelButton(
            buttonKey: const ValueKey('knowledge-level-back'),
            label: '返回上一级',
            onPressed: onBack,
          ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            theme == null
                ? '${_moduleNumber(module.id)}. ${module.title}'
                : '${_moduleNumber(module.id)}. ${module.title} / ${_themeNumber(theme!.id)} ${theme!.title} / ${selectedPoint?.id ?? ''} ${selectedPoint?.title ?? ''}',
            key: theme == null
                ? null
                : const ValueKey('knowledge-breadcrumb-theme'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _muted,
              fontSize: 14,
              height: 21.314 / 14,
            ),
          ),
        ),
      ],
    );
  }
}

final class _LevelButton extends StatelessWidget {
  const _LevelButton({required this.label, this.buttonKey, this.onPressed});

  final String label;
  final Key? buttonKey;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _LevelButtonPainter(),
      child: FilledButton(
        key: buttonKey,
        onPressed: onPressed ?? () {},
        style: FilledButton.styleFrom(
          fixedSize: const Size(129, 42),
          minimumSize: const Size(129, 42),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, height: 21.314 / 16),
        ),
      ),
    );
  }
}

final class _LevelButtonPainter extends CustomPainter {
  const _LevelButtonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(bounds, const Radius.circular(6));
    canvas.drawRRect(shape, Paint()..color = const Color(0xFF1FA877));

    canvas.save();
    canvas.clipRRect(shape);
    final bandPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x4DE7FAF4), Color(0x00FFFFFF)],
      ).createShader(bounds);
    final wideBand = Path()
      ..moveTo(size.width - 25, 0)
      ..lineTo(size.width - 2, 0)
      ..lineTo(size.width - 29, size.height)
      ..lineTo(size.width - 52, size.height)
      ..close();
    final narrowBand = Path()
      ..moveTo(size.width - 3, 0)
      ..lineTo(size.width + 8, 0)
      ..lineTo(size.width - 19, size.height)
      ..lineTo(size.width - 30, size.height)
      ..close();
    canvas
      ..drawPath(wideBand, bandPaint)
      ..drawPath(narrowBand, bandPaint)
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _LevelButtonPainter oldDelegate) => false;
}

final class _DesktopMapCanvas extends StatefulWidget {
  const _DesktopMapCanvas({
    required this.module,
    required this.theme,
    required this.selectedPoint,
    required this.focusSelectedPoint,
    required this.onThemeTap,
    required this.onPointTap,
  });

  final MathKnowledgeModule module;
  final MathKnowledgeTheme? theme;
  final MathKnowledgePoint? selectedPoint;
  final bool focusSelectedPoint;
  final ValueChanged<MathKnowledgeTheme> onThemeTap;
  final ValueChanged<MathKnowledgePoint> onPointTap;

  @override
  State<_DesktopMapCanvas> createState() => _DesktopMapCanvasState();
}

final class _DesktopMapCanvasState extends State<_DesktopMapCanvas> {
  static const double _scenePadding = 300;
  final TransformationController _transformationController =
      TransformationController();
  double _scale = 1;
  Size _viewportSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(-_scenePadding, -_scenePadding, 0, 1);
    _transformationController.addListener(_handleTransformationChanged);
  }

  @override
  void didUpdateWidget(covariant _DesktopMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module.id != widget.module.id ||
        oldWidget.theme?.id != widget.theme?.id ||
        oldWidget.focusSelectedPoint != widget.focusSelectedPoint ||
        (widget.focusSelectedPoint &&
            oldWidget.selectedPoint?.id != widget.selectedPoint?.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitCanvas());
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_handleTransformationChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _handleTransformationChanged() {
    final nextScale = _transformationController.value.getMaxScaleOnAxis();
    if ((nextScale - _scale).abs() < .005 || !mounted) return;
    setState(() => _scale = nextScale);
  }

  void _zoomBy(double delta) {
    final targetScale = (_scale + delta).clamp(.5, 2.5).toDouble();
    if ((targetScale - _scale).abs() < .005) return;

    final viewportCenter = _viewportSize.center(Offset.zero);
    final sceneCenter = _transformationController.toScene(viewportCenter);
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(viewportCenter.dx, viewportCenter.dy, 0, 1)
      ..scaleByDouble(targetScale, targetScale, targetScale, 1)
      ..translateByDouble(-sceneCenter.dx, -sceneCenter.dy, 0, 1);
  }

  void _fitCanvas() {
    if (!mounted) return;
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(-_scenePadding, -_scenePadding, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: const ValueKey('knowledge-map-canvas'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewportSize = constraints.biggest;
          final sceneSize = Size(
            constraints.maxWidth + _scenePadding * 2,
            constraints.maxHeight + _scenePadding * 2,
          );
          return Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  key: const ValueKey('knowledge-map-interactive-viewer'),
                  transformationController: _transformationController,
                  minScale: .5,
                  maxScale: 2.5,
                  panEnabled: true,
                  scaleEnabled: true,
                  trackpadScrollCausesScale: true,
                  boundaryMargin: const EdgeInsets.all(600),
                  constrained: false,
                  child: SizedBox(
                    width: sceneSize.width,
                    height: sceneSize.height,
                    child: _MapContent(
                      module: widget.module,
                      theme: widget.theme,
                      selectedPoint: widget.selectedPoint,
                      focusSelectedPoint: widget.focusSelectedPoint,
                      compact: false,
                      onThemeTap: widget.onThemeTap,
                      onPointTap: widget.onPointTap,
                      canvasSize: sceneSize,
                      viewportSize: constraints.biggest,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: _MapCanvasControls(
                  scale: _scale,
                  onZoomOut: () => _zoomBy(-.25),
                  onZoomIn: () => _zoomBy(.25),
                  onFit: _fitCanvas,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

final class _MapCanvasControls extends StatelessWidget {
  const _MapCanvasControls({
    required this.scale,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
  });

  final double scale;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: const Color(0x26000000),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE4E7EC)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('knowledge-map-zoom-out'),
              onPressed: onZoomOut,
              tooltip: '缩小',
              constraints: const BoxConstraints.tightFor(width: 38, height: 38),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.remove_rounded, size: 18),
            ),
            SizedBox(
              width: 50,
              child: Text(
                '${(scale * 100).round()}%',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('knowledge-map-zoom-in'),
              onPressed: onZoomIn,
              tooltip: '放大',
              constraints: const BoxConstraints.tightFor(width: 38, height: 38),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.add_rounded, size: 18),
            ),
            Container(width: 1, height: 20, color: const Color(0xFFE4E7EC)),
            IconButton(
              key: const ValueKey('knowledge-map-fit'),
              onPressed: onFit,
              tooltip: '适应画布',
              constraints: const BoxConstraints.tightFor(width: 40, height: 38),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.fit_screen_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.module,
    required this.theme,
    required this.point,
    required this.onModuleTap,
    required this.onThemeTap,
    required this.onBack,
    required this.onPointTap,
  });

  final MathKnowledgeModule module;
  final MathKnowledgeTheme? theme;
  final MathKnowledgePoint? point;
  final ValueChanged<MathKnowledgeModule> onModuleTap;
  final ValueChanged<MathKnowledgeTheme> onThemeTap;
  final VoidCallback onBack;
  final ValueChanged<MathKnowledgePoint> onPointTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('knowledge-map-compact'),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      children: [
        const _PageHeader(compact: true),
        const SizedBox(height: 14),
        _CompactModuleStrip(selected: module, onTap: onModuleTap),
        const SizedBox(height: 14),
        _MapPanel(
          module: module,
          theme: theme,
          selectedPoint: point,
          compact: true,
          onBack: onBack,
          onThemeTap: onThemeTap,
          onPointTap: onPointTap,
        ),
        if (theme != null && point != null) ...[
          const SizedBox(height: 14),
          _KnowledgeDetailPanel(point: point!, compact: true),
        ],
      ],
    );
  }
}

final class _PageHeader extends StatelessWidget {
  const _PageHeader({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (Navigator.of(context).canPop())
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回',
              ),
            Expanded(
              child: Text(
                '高中数学知识点总览',
                style: TextStyle(
                  color: _ink,
                  fontSize: compact ? 23 : 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (!compact)
              Container(
                width: 220,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2F6),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: Color(0xFF98A2B3),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '搜索知识点…',
                      style: TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

final class _ModuleList extends StatelessWidget {
  const _ModuleList({required this.selected, required this.onTap});

  final MathKnowledgeModule selected;
  final ValueChanged<MathKnowledgeModule> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('knowledge-map-module-pane'),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(11.5, 6, 11.5, 6),
        itemCount: HighSchoolMathCatalog.modules.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 8, thickness: 1, color: Color(0xFFF0F1F2)),
        itemBuilder: (context, index) {
          final module = HighSchoolMathCatalog.modules[index];
          return _ModuleCard(
            module: module,
            index: index,
            selected: module.id == selected.id,
            onTap: () => onTap(module),
          );
        },
      ),
    );
  }
}

final class _CompactModuleStrip extends StatelessWidget {
  const _CompactModuleStrip({required this.selected, required this.onTap});

  final MathKnowledgeModule selected;
  final ValueChanged<MathKnowledgeModule> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: HighSchoolMathCatalog.modules.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final module = HighSchoolMathCatalog.modules[index];
          return SizedBox(
            width: 245,
            child: _ModuleCard(
              module: module,
              index: index,
              selected: module.id == selected.id,
              onTap: () => onTap(module),
              compact: true,
            ),
          );
        },
      ),
    );
  }
}

final class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.module,
    required this.index,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final MathKnowledgeModule module;
  final int index;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('knowledge-module-card-${module.id}'),
      height: compact ? 84 : 75,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey('knowledge-module-${module.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? _green : Colors.transparent,
                width: selected ? 2.5 : 1,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _ModuleProgressIcon(selected: selected),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ${module.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0D0D0D),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: '进度：已完成'),
                            TextSpan(
                              text: '${module.pointCount}',
                              style: const TextStyle(
                                color: Color(0xFF0D0D0D),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(text: '个知识点，总共'),
                            TextSpan(
                              text: '${module.branchCount}',
                              style: const TextStyle(
                                color: Color(0xFF0D0D0D),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(text: '分支。'),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF5D5D5D),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _ModuleProgressIcon extends StatelessWidget {
  const _ModuleProgressIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: CustomPaint(
        painter: _ProgressRingPainter(selected: selected),
        child: Center(
          child: selected
              ? const Text(
                  '10%',
                  style: TextStyle(
                    color: Color(0xFF16B67F),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : const Icon(
                  Icons.menu_book_rounded,
                  size: 17,
                  color: Color(0xFFE0E3E6),
                ),
        ),
      ),
    );
  }
}

final class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({required this.selected});

  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 4;
    final track = Paint()
      ..color = const Color(0xFFE7E8EA)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, track);
    if (!selected) return;
    final progress = Paint()
      ..color = const Color(0xFF20AC7A)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.57,
      .72 * 3.14,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      selected != oldDelegate.selected;
}

final class _MapPanel extends StatelessWidget {
  const _MapPanel({
    required this.module,
    required this.theme,
    required this.selectedPoint,
    required this.compact,
    required this.onBack,
    required this.onThemeTap,
    required this.onPointTap,
  });

  final MathKnowledgeModule module;
  final MathKnowledgeTheme? theme;
  final MathKnowledgePoint? selectedPoint;
  final bool compact;
  final VoidCallback onBack;
  final ValueChanged<MathKnowledgeTheme> onThemeTap;
  final ValueChanged<MathKnowledgePoint> onPointTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: compact ? const BoxConstraints(minHeight: 520) : null,
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 28,
              20,
              compact ? 16 : 28,
              16,
            ),
            child: Row(
              key: const ValueKey('knowledge-map-toolbar'),
              children: [
                if (theme == null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _green,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.layers_outlined,
                          color: Colors.white,
                          size: 17,
                        ),
                        SizedBox(width: 7),
                        Text(
                          '分支总览',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  FilledButton.icon(
                    key: const ValueKey('knowledge-level-back'),
                    onPressed: onBack,
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    icon: const Icon(Icons.keyboard_return_rounded, size: 16),
                    label: const Text('返回上一级'),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    theme == null
                        ? module.title
                        : '${module.title} / ${theme!.title}${selectedPoint == null ? '' : ' / ${selectedPoint!.title}'}',
                    key: theme == null
                        ? null
                        : const ValueKey('knowledge-breadcrumb-theme'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEF1F5)),
          if (compact)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _MapContent(
                module: module,
                theme: theme,
                selectedPoint: selectedPoint,
                compact: true,
                onThemeTap: onThemeTap,
                onPointTap: onPointTap,
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(30),
                child: _MapContent(
                  module: module,
                  theme: theme,
                  selectedPoint: selectedPoint,
                  compact: false,
                  onThemeTap: onThemeTap,
                  onPointTap: onPointTap,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final class _MapContent extends StatelessWidget {
  const _MapContent({
    required this.module,
    required this.theme,
    required this.selectedPoint,
    required this.compact,
    required this.onThemeTap,
    required this.onPointTap,
    this.focusSelectedPoint = false,
    this.canvasSize,
    this.viewportSize,
  });

  final MathKnowledgeModule module;
  final MathKnowledgeTheme? theme;
  final MathKnowledgePoint? selectedPoint;
  final bool compact;
  final ValueChanged<MathKnowledgeTheme> onThemeTap;
  final ValueChanged<MathKnowledgePoint> onPointTap;
  final bool focusSelectedPoint;
  final Size? canvasSize;
  final Size? viewportSize;

  @override
  Widget build(BuildContext context) {
    if (!module.hasExplorationData) {
      return SizedBox(
        height: compact ? 340 : 520,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.account_tree_outlined,
                color: Color(0xFF98A2B3),
                size: 42,
              ),
              const SizedBox(height: 14),
              Text(
                module.title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '该模块的三级内容将在后续批次接入',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final root = _RootNode(
      title: theme?.title ?? module.title,
      subtitle: theme == null
          ? '共 ${module.pointCount} 个知识点，${module.branchCount} 个分支'
          : '${theme!.pointCount} 个知识点',
    );
    if (theme == null) {
      final branches = Column(
        children: [
          for (final item in module.themes) ...[
            _ThemeNode(theme: item, onTap: () => onThemeTap(item)),
            const SizedBox(height: 14),
          ],
        ],
      );
      if (compact) {
        return Column(children: [root, const SizedBox(height: 18), branches]);
      }
      return _DesktopBranchOverview(
        root: root,
        themes: module.themes,
        onThemeTap: onThemeTap,
        canvasSize: canvasSize,
      );
    }

    if (theme!.points.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: compact ? Alignment.centerLeft : Alignment.center,
            child: SizedBox(
              width: compact ? double.infinity : 330,
              child: root,
            ),
          ),
          const SizedBox(height: 28),
          const _PendingThirdLevel(),
        ],
      );
    }

    if (compact) {
      return _PointPath(
        points: theme!.points,
        selectedPoint: selectedPoint,
        compact: true,
        onPointTap: onPointTap,
      );
    }

    return _DesktopPointOverview(
      root: root,
      points: theme!.points,
      selectedPoint: selectedPoint,
      focusSelectedPoint: focusSelectedPoint,
      onPointTap: onPointTap,
      canvasSize: canvasSize,
      viewportSize: viewportSize,
    );
  }
}

final class _RootNode extends StatelessWidget {
  const _RootNode({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dense =
            !constraints.maxHeight.isFinite || constraints.maxHeight <= 90;
        final height = dense
            ? 84.0
            : constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 131.0;
        return SizedBox(
          key: const ValueKey('knowledge-root-node'),
          height: height,
          child: CustomPaint(
            painter: const _KnowledgeNodeFramePainter(unlocked: true),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: dense ? 18 : 30,
                vertical: dense ? 12 : 20,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: dense ? 14 : 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: dense ? 7 : 16),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: dense ? 11 : 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _PointPath extends StatelessWidget {
  const _PointPath({
    required this.points,
    required this.selectedPoint,
    required this.compact,
    required this.onPointTap,
  });

  final List<MathKnowledgePoint> points;
  final MathKnowledgePoint? selectedPoint;
  final bool compact;
  final ValueChanged<MathKnowledgePoint> onPointTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < points.length; index++) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact) Container(width: 12, height: 2, color: _green),
              _PointNode(
                point: points[index],
                selected: points[index].id == selectedPoint?.id,
                compact: compact,
                onTap: () => onPointTap(points[index]),
              ),
            ],
          ),
          if (index != points.length - 1) SizedBox(height: compact ? 12 : 30),
        ],
      ],
    );
  }
}

final class _DesktopBranchOverview extends StatelessWidget {
  const _DesktopBranchOverview({
    required this.root,
    required this.themes,
    required this.onThemeTap,
    required this.canvasSize,
  });

  static const double _rootWidth = 258;
  static const double _branchWidth = 258;
  static const double _nodeHeight = 73;
  static const double _horizontalGap = 96;
  static const double _verticalGap = 32;

  final Widget root;
  final List<MathKnowledgeTheme> themes;
  final ValueChanged<MathKnowledgeTheme> onThemeTap;
  final Size? canvasSize;

  @override
  Widget build(BuildContext context) {
    final height =
        themes.length * _nodeHeight +
        (themes.length - 1).clamp(0, themes.length) * _verticalGap;
    const width = _rootWidth + _horizontalGap + _branchWidth;
    final rootRect = Rect.fromLTWH(
      0,
      (height - _nodeHeight) / 2,
      _rootWidth,
      _nodeHeight,
    );
    final branchRects = <Rect>[
      for (var index = 0; index < themes.length; index++)
        Rect.fromLTWH(
          _rootWidth + _horizontalGap,
          index * (_nodeHeight + _verticalGap),
          _branchWidth,
          _nodeHeight,
        ),
    ];

    final layoutSize = canvasSize ?? Size(width, height);
    final origin = Offset(
      (layoutSize.width - width) / 2,
      (layoutSize.height - height) / 2,
    );
    final shiftedRootRect = rootRect.shift(origin);
    final shiftedBranchRects = branchRects
        .map((rect) => rect.shift(origin))
        .toList();
    return SizedBox(
      width: layoutSize.width,
      height: layoutSize.height,
      child: Transform.scale(
        scale: 1.15,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                key: const ValueKey('knowledge-connector-layer'),
                painter: _BranchConnectorPainter(
                  rootRect: shiftedRootRect,
                  branchRects: shiftedBranchRects,
                  color: themes.every((theme) => theme.points.isEmpty)
                      ? _lockedLine
                      : _green,
                ),
              ),
            ),
            Positioned(
              left: shiftedRootRect.left,
              top: shiftedRootRect.top,
              width: _rootWidth,
              height: _nodeHeight,
              child: root,
            ),
            for (var index = 0; index < themes.length; index++)
              Positioned(
                left: shiftedBranchRects[index].left,
                top: shiftedBranchRects[index].top,
                width: _branchWidth,
                height: _nodeHeight,
                child: _ThemeNode(
                  theme: themes[index],
                  onTap: () => onThemeTap(themes[index]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _DesktopPointOverview extends StatelessWidget {
  const _DesktopPointOverview({
    required this.root,
    required this.points,
    required this.selectedPoint,
    required this.focusSelectedPoint,
    required this.onPointTap,
    required this.canvasSize,
    required this.viewportSize,
  });

  static const double _rootWidth = 258;
  static const double _branchWidth = 258;
  static const double _nodeHeight = 73;
  static const double _horizontalGap = 96;
  static const double _verticalGap = 24;
  static const double _focusedWidth = 456;
  static const double _focusedHeight = 131;
  static const double _siblingWidth = 301;
  static const double _siblingHeight = 86;
  static const double _focusedVerticalGap = 32;

  final Widget root;
  final List<MathKnowledgePoint> points;
  final MathKnowledgePoint? selectedPoint;
  final bool focusSelectedPoint;
  final ValueChanged<MathKnowledgePoint> onPointTap;
  final Size? canvasSize;
  final Size? viewportSize;

  @override
  Widget build(BuildContext context) {
    if (focusSelectedPoint && selectedPoint != null) {
      return _buildFocusedOverview();
    }

    final height =
        points.length * _nodeHeight +
        (points.length - 1).clamp(0, points.length) * _verticalGap;
    const width = _rootWidth + _horizontalGap + _branchWidth;
    final rootRect = Rect.fromLTWH(
      0,
      (height - _nodeHeight) / 2,
      _rootWidth,
      _nodeHeight,
    );
    final branchRects = <Rect>[
      for (var index = 0; index < points.length; index++)
        Rect.fromLTWH(
          _rootWidth + _horizontalGap,
          index * (_nodeHeight + _verticalGap),
          _branchWidth,
          _nodeHeight,
        ),
    ];

    final layoutSize = canvasSize ?? Size(width, height);
    final origin = Offset(
      (layoutSize.width - width) / 2,
      (layoutSize.height - height) / 2,
    );
    final shiftedRootRect = rootRect.shift(origin);
    final shiftedBranchRects = branchRects
        .map((rect) => rect.shift(origin))
        .toList();
    return SizedBox(
      width: layoutSize.width,
      height: layoutSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              key: const ValueKey('knowledge-third-level-connector-layer'),
              painter: _BranchConnectorPainter(
                rootRect: shiftedRootRect,
                branchRects: shiftedBranchRects,
                color: _green,
              ),
            ),
          ),
          Positioned(
            left: shiftedRootRect.left,
            top: shiftedRootRect.top,
            width: _rootWidth,
            height: _nodeHeight,
            child: root,
          ),
          for (var index = 0; index < points.length; index++)
            Positioned(
              left: shiftedBranchRects[index].left,
              top: shiftedBranchRects[index].top,
              width: _branchWidth,
              height: _nodeHeight,
              child: _KnowledgePointBranchNode(
                point: points[index],
                selected: points[index].id == selectedPoint?.id,
                onTap: () => onPointTap(points[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFocusedOverview() {
    final layoutSize = canvasSize ?? const Size(760, 560);
    final visibleSize = viewportSize ?? layoutSize;
    final maxNodeWidth = visibleSize.width > 260
        ? visibleSize.width - 40
        : 220.0;
    final focusedWidth = _focusedWidth.clamp(220.0, maxNodeWidth).toDouble();
    final focusedHeight = _focusedHeight * focusedWidth / _focusedWidth;
    final siblingWidth = _siblingWidth.clamp(200.0, maxNodeWidth).toDouble();
    final siblingHeight = _siblingHeight * siblingWidth / _siblingWidth;
    final viewportTop = (layoutSize.height - visibleSize.height) / 2;
    final desiredTop = visibleSize.height * .34 - focusedHeight / 2;
    final maxTop = visibleSize.height - focusedHeight - 24;
    final focusedTop = viewportTop + desiredTop.clamp(24.0, maxTop).toDouble();
    final focusedLeft = (layoutSize.width - focusedWidth) / 2;
    final siblings = points
        .where((point) => point.id != selectedPoint!.id)
        .toList(growable: false);
    final siblingLeft = focusedLeft;
    final firstSiblingTop = focusedTop + focusedHeight + _focusedVerticalGap;

    return SizedBox(
      width: layoutSize.width,
      height: layoutSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: focusedLeft,
            top: focusedTop,
            width: focusedWidth,
            height: focusedHeight,
            child: _KnowledgePointBranchNode(
              point: selectedPoint!,
              selected: true,
              emphasized: true,
              onTap: () => onPointTap(selectedPoint!),
            ),
          ),
          for (var index = 0; index < siblings.length; index++)
            Positioned(
              left: siblingLeft,
              top:
                  firstSiblingTop +
                  index * (siblingHeight + _focusedVerticalGap),
              width: siblingWidth,
              height: siblingHeight,
              child: _KnowledgePointBranchNode(
                point: siblings[index],
                selected: false,
                muted: true,
                onTap: () => onPointTap(siblings[index]),
              ),
            ),
        ],
      ),
    );
  }
}

final class _BranchConnectorPainter extends CustomPainter {
  const _BranchConnectorPainter({
    required this.rootRect,
    required this.branchRects,
    required this.color,
  });

  final Rect rootRect;
  final List<Rect> branchRects;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (branchRects.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rootAnchor = rootRect.centerRight;
    final branchAnchors = branchRects.map((rect) => rect.centerLeft).toList();
    final averageBranchX =
        branchAnchors.fold<double>(0, (sum, point) => sum + point.dx) /
        branchAnchors.length;
    final trunkX = (rootAnchor.dx + averageBranchX) / 2;
    final firstCenterY = branchAnchors
        .map((point) => point.dy)
        .reduce((a, b) => a < b ? a : b);
    final lastCenterY = branchAnchors
        .map((point) => point.dy)
        .reduce((a, b) => a > b ? a : b);

    canvas.drawLine(rootAnchor, Offset(trunkX, rootAnchor.dy), paint);
    const bendRadius = 12.0;
    if (branchAnchors.length == 1) {
      canvas.drawLine(
        Offset(trunkX, branchAnchors.first.dy),
        branchAnchors.first,
        paint,
      );
      return;
    }
    final trunk = Path()
      ..moveTo(trunkX, firstCenterY + bendRadius)
      ..lineTo(trunkX, lastCenterY - bendRadius);
    canvas.drawPath(trunk, paint);
    final topBranch = Path()
      ..moveTo(trunkX, firstCenterY + bendRadius)
      ..quadraticBezierTo(
        trunkX,
        firstCenterY,
        trunkX + bendRadius,
        firstCenterY,
      )
      ..lineTo(
        branchAnchors.firstWhere((point) => point.dy == firstCenterY).dx,
        firstCenterY,
      );
    final bottomBranch = Path()
      ..moveTo(trunkX, lastCenterY - bendRadius)
      ..quadraticBezierTo(trunkX, lastCenterY, trunkX + bendRadius, lastCenterY)
      ..lineTo(
        branchAnchors.firstWhere((point) => point.dy == lastCenterY).dx,
        lastCenterY,
      );
    canvas.drawPath(topBranch, paint);
    canvas.drawPath(bottomBranch, paint);
    for (final anchor in branchAnchors) {
      if (anchor.dy == firstCenterY || anchor.dy == lastCenterY) continue;
      canvas.drawLine(Offset(trunkX, anchor.dy), anchor, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BranchConnectorPainter oldDelegate) {
    if (color != oldDelegate.color ||
        rootRect != oldDelegate.rootRect ||
        branchRects.length != oldDelegate.branchRects.length) {
      return true;
    }
    for (var index = 0; index < branchRects.length; index++) {
      if (branchRects[index] != oldDelegate.branchRects[index]) return true;
    }
    return false;
  }
}

final class _PendingThirdLevel extends StatelessWidget {
  const _PendingThirdLevel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: const Column(
        children: [
          Icon(Icons.route_outlined, color: Color(0xFF98A2B3), size: 34),
          SizedBox(height: 12),
          Text(
            '该主题的三级知识点将在后续批次接入',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

final class _KnowledgeNodeFramePainter extends CustomPainter {
  const _KnowledgeNodeFramePainter({required this.unlocked});

  final bool unlocked;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const radius = Radius.circular(16);
    final fill = Paint()..color = unlocked ? _green : const Color(0xFFE5E5E5);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), fill);

    if (unlocked) {
      final outerStroke = Paint()
        ..color = _green
        ..strokeWidth = size.height > 100 ? 6 : 3
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(3), radius),
        outerStroke,
      );
    }

    final inset = size.height > 100 ? 12.0 : 7.0;
    final innerStroke = Paint()
      ..color = unlocked
          ? Colors.white.withValues(alpha: .85)
          : const Color(0xFFCCCCCC)
      ..strokeWidth = size.height > 100 ? 4 : 2
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(inset), const Radius.circular(12)),
      innerStroke,
    );
  }

  @override
  bool shouldRepaint(covariant _KnowledgeNodeFramePainter oldDelegate) =>
      unlocked != oldDelegate.unlocked;
}

final class _ThemeNode extends StatelessWidget {
  const _ThemeNode({required this.theme, required this.onTap});
  final MathKnowledgeTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unlocked = theme.points.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final dense =
            !constraints.maxHeight.isFinite || constraints.maxHeight <= 90;
        final height = dense
            ? 84.0
            : constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 131.0;
        return SizedBox(
          key: ValueKey(
            'knowledge-theme-${theme.id}-${unlocked ? 'unlocked' : 'locked'}',
          ),
          height: height,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(dense ? 12 : 24),
            child: InkWell(
              key: ValueKey('knowledge-theme-${theme.id}'),
              onTap: unlocked ? onTap : null,
              borderRadius: BorderRadius.circular(dense ? 12 : 24),
              child: CustomPaint(
                key: ValueKey('knowledge-node-frame-clean-${theme.id}'),
                painter: _KnowledgeNodeFramePainter(unlocked: unlocked),
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        dense ? 17 : 20,
                        dense ? 8 : 14,
                        dense ? 8 : 14,
                        dense ? 8 : 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            key: ValueKey('knowledge-theme-icon-${theme.id}'),
                            width: dense ? 48 : 52,
                            height: dense ? 48 : 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: unlocked
                                  ? const Color(0xFF1FA877)
                                  : const Color(0xFFE5E5E5),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: unlocked
                                    ? Colors.white
                                    : const Color(0xFFCCCCCC),
                                width: dense ? 2.5 : 3,
                              ),
                            ),
                            child: Icon(
                              unlocked
                                  ? Icons.menu_book_rounded
                                  : Icons.lock_rounded,
                              color: unlocked
                                  ? Colors.white
                                  : const Color(0xFF9B9F9D),
                              size: dense ? 21 : 23,
                            ),
                          ),
                          SizedBox(width: dense ? 9 : 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _themeNumber(theme.id),
                                      style: TextStyle(
                                        color: unlocked
                                            ? Colors.white
                                            : const Color(0xFF999999),
                                        fontSize: dense ? 12 : 15,
                                      ),
                                    ),
                                    SizedBox(width: dense ? 4 : 6),
                                    Expanded(
                                      child: Text(
                                        theme.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: unlocked
                                              ? Colors.white
                                              : const Color(0xFF999999),
                                          fontSize: dense ? 12 : 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: dense ? 5 : 6),
                                _KnowledgeBadgeStrip(
                                  count: theme.pointCount.clamp(1, 4),
                                  unlocked: unlocked,
                                  large: !dense,
                                  keyPrefix:
                                      'knowledge-theme-badge-${theme.id}',
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: unlocked
                                ? Colors.white
                                : const Color(0xFF999999),
                            size: dense ? 29 : 28,
                          ),
                        ],
                      ),
                    ),
                    if (unlocked)
                      Positioned(
                        right: dense ? 15 : 20,
                        top: dense ? 11 : 12,
                        child: Container(
                          key: ValueKey('knowledge-theme-status-${theme.id}'),
                          width: dense ? 15 : 18,
                          height: dense ? 15 : 18,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1FA877),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: dense ? 11 : 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _KnowledgeBadgeStrip extends StatelessWidget {
  const _KnowledgeBadgeStrip({
    required this.count,
    required this.unlocked,
    this.large = false,
    this.keyPrefix,
  });

  final int count;
  final bool unlocked;
  final bool large;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: large ? 174 : null,
      height: large ? 30 : 27,
      padding: EdgeInsets.symmetric(horizontal: large ? 6 : 5),
      decoration: BoxDecoration(
        color: unlocked ? const Color(0xFF1FA877) : const Color(0xFF999999),
        borderRadius: BorderRadius.circular(large ? 8 : 5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < count; index++) ...[
            Container(
              key: keyPrefix == null ? null : ValueKey('$keyPrefix-$index'),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: large ? 2 : 1.4),
              ),
              child: Icon(
                unlocked ? Icons.science_outlined : Icons.lock_outline_rounded,
                color: Colors.white,
                size: large ? 12 : 11,
              ),
            ),
            if (index != count - 1) SizedBox(width: large ? 6 : 4),
          ],
        ],
      ),
    );
  }
}

final class _KnowledgePointBranchNode extends StatelessWidget {
  const _KnowledgePointBranchNode({
    required this.point,
    required this.selected,
    required this.onTap,
    this.emphasized = false,
    this.muted = false,
  });

  final MathKnowledgePoint point;
  final bool selected;
  final VoidCallback onTap;
  final bool emphasized;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final large = emphasized || constraints.maxHeight >= 110;
        final radius = large ? 16.0 : 12.0;
        return AnimatedOpacity(
          key: ValueKey('knowledge-point-opacity-${point.id}'),
          duration: const Duration(milliseconds: 180),
          opacity: muted ? .2 : 1,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(radius),
            child: InkWell(
              key: ValueKey('knowledge-point-${point.id}'),
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: CustomPaint(
                painter: const _KnowledgeNodeFramePainter(unlocked: true),
                child: Stack(
                  children: [
                    Padding(
                      padding: large
                          ? const EdgeInsets.fromLTRB(22, 12, 20, 12)
                          : const EdgeInsets.fromLTRB(17, 8, 13, 8),
                      child: Row(
                        children: [
                          Container(
                            width: large ? 76 : 48,
                            height: large ? 76 : 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1FA877),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: large ? 3 : 2.5,
                              ),
                            ),
                            child: Icon(
                              Icons.menu_book_rounded,
                              color: Colors.white,
                              size: large ? 31 : 21,
                            ),
                          ),
                          SizedBox(width: large ? 14 : 9),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      point.id,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: large ? 18 : 12,
                                      ),
                                    ),
                                    SizedBox(width: large ? 7 : 4),
                                    Expanded(
                                      child: Text(
                                        point.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: large ? 20 : 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: large ? 9 : 5),
                                _KnowledgeBadgeStrip(
                                  count: 4,
                                  unlocked: true,
                                  large: large,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            key: ValueKey(
                              'knowledge-point-chevron-${point.id}',
                            ),
                            Icons.chevron_right_rounded,
                            color: Colors.white,
                            size: large ? 37 : 25,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: large ? 25 : 17,
                      top: large ? 16 : 11,
                      child: Container(
                        key: ValueKey('knowledge-point-status-${point.id}'),
                        width: large ? 23 : 15,
                        height: large ? 23 : 15,
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF0C8F65)
                              : const Color(0xFF1FA877),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: large ? 15 : 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _PointNode extends StatelessWidget {
  const _PointNode({
    required this.point,
    required this.selected,
    required this.compact,
    required this.onTap,
  });
  final MathKnowledgePoint point;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = compact ? MediaQuery.sizeOf(context).width - 64 : 301.0;
    return SizedBox(
      width: width,
      height: compact ? 80 : 86,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: selected ? 1 : .48,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: ValueKey('knowledge-point-${point.id}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        colors: [Color(0xFF29C98F), Color(0xFF0DBB84)],
                      )
                    : const LinearGradient(
                        colors: [Color(0xFFE8FAF3), Color(0xFFD8F6EA)],
                      ),
                border: Border.all(color: _green, width: 2),
                borderRadius: BorderRadius.circular(12),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x240DBB84),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF1FA877) : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? Colors.white
                            : const Color(0xFF9DDFC7),
                        width: 2.5,
                      ),
                    ),
                    child: Icon(
                      selected
                          ? Icons.menu_book_rounded
                          : Icons.lock_outline_rounded,
                      color: selected ? Colors.white : const Color(0xFF72CDAE),
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              point.id,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF41B68E),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                point.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF41B68E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        _KnowledgeBadgeStrip(count: 4, unlocked: selected),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: selected ? Colors.white : const Color(0xFF72CDAE),
                    size: 23,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _KnowledgeDetailPanel extends StatelessWidget {
  const _KnowledgeDetailPanel({required this.point, this.compact = false});

  final MathKnowledgePoint point;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('knowledge-map-detail-pane'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '知识点',
            style: TextStyle(
              color: Color(0xFF0D0D0D),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 15),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'A. 对${point.title}的判断，'),
                const TextSpan(
                  text: '它是什么？',
                  style: TextStyle(color: Color(0xFF3B82F6)),
                ),
              ],
            ),
            style: const TextStyle(
              color: Color(0xFF0D0D0D),
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 15),
          Container(
            height: 39,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '这是需要理解或记忆点的具体知识点',
              style: TextStyle(color: Color(0xFF0D0D0D), fontSize: 14),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 20),
          const Text(
            '关键内容',
            style: TextStyle(
              color: Color(0xFF0D0D0D),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 15),
          const Row(
            children: [
              SizedBox(
                width: 3,
                height: 15,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF0D0D0D),
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text(
                '考试提示',
                style: TextStyle(
                  color: Color(0xFF0D0D0D),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(9, 12, 9, 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${point.summary}（选择题）',
                  style: const TextStyle(
                    color: Color(0xFF0D0D0D),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const _DetailBullet(text: '理解核心概念和定义条件'),
                const _DetailBullet(text: '掌握典型表示方法与基本性质'),
                const _DetailBullet(text: '判断题目条件是否完整成立'),
              ],
            ),
          ),
          if (compact) const SizedBox(height: 20) else const Spacer(),
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已选择「${point.title}」，学习流程将在下一阶段接入。')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: const Text('去学习'),
          ),
        ],
      ),
    );
  }
}

final class _DetailBullet extends StatelessWidget {
  const _DetailBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: SizedBox(
              width: 4,
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(color: _ink, shape: BoxShape.circle),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

int _moduleNumber(String moduleId) =>
    moduleId.toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0) + 1;

String _themeNumber(String themeId) {
  final module = _moduleNumber(themeId.substring(0, 1));
  return '$module.${themeId.substring(1)}';
}

BoxDecoration _panelDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: _line),
  boxShadow: const [
    BoxShadow(color: Color(0x080F172A), blurRadius: 24, offset: Offset(0, 10)),
  ],
);
