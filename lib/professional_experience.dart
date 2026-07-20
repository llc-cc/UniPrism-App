part of 'main.dart';

class MathMajorIntroData {
  const MathMajorIntroData({
    required this.title,
    required this.stageLabel,
    required this.subtitle,
    required this.video,
    required this.sections,
  });

  factory MathMajorIntroData.fromJson(Map<String, dynamic> json) {
    return MathMajorIntroData(
      title: json['title']?.toString() ?? '数学专业介绍',
      stageLabel: json['stageLabel']?.toString() ?? 'Part 1 · 专业画像',
      subtitle: json['subtitle']?.toString() ?? '',
      video: _mathMap(json['video']),
      sections: _mathList(
        json['sections'],
      ).map(MathMajorIntroSection.fromJson).toList(),
    );
  }

  final String title;
  final String stageLabel;
  final String subtitle;
  final Map<String, dynamic> video;
  final List<MathMajorIntroSection> sections;
}

class MathMajorIntroSection {
  const MathMajorIntroSection({
    this.title,
    required this.paragraphs,
    this.figure,
  });

  factory MathMajorIntroSection.fromJson(Map<String, dynamic> json) =>
      MathMajorIntroSection(
        title: json['title']?.toString(),
        paragraphs: (json['paragraphs'] as List? ?? const [])
            .map((value) => value.toString())
            .toList(),
        figure: json['figure'] is Map ? _mathMap(json['figure']) : null,
      );

  final String? title;
  final List<String> paragraphs;
  final Map<String, dynamic>? figure;
}

class MathCoursePageData {
  const MathCoursePageData({
    required this.id,
    required this.stageIndex,
    required this.stageTitle,
    required this.kind,
    required this.title,
    required this.navTitle,
    this.subtitle,
    this.summary,
    this.videoSrc,
    this.webPageId,
    this.courseId,
  });

  factory MathCoursePageData.fromJson(Map<String, dynamic> json) =>
      MathCoursePageData(
        id: json['id']?.toString() ?? '',
        stageIndex: json['stageIndex'] is num
            ? (json['stageIndex'] as num).toInt()
            : 0,
        stageTitle: json['stageTitle']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'overview',
        title: json['title']?.toString() ?? '',
        navTitle: json['navTitle']?.toString() ?? '',
        subtitle: json['subtitle']?.toString(),
        summary: json['summary']?.toString(),
        videoSrc: json['videoSrc']?.toString(),
        webPageId: json['webPageId']?.toString(),
        courseId: json['courseId']?.toString(),
      );

  final String id;
  final int stageIndex;
  final String stageTitle;
  final String kind;
  final String title;
  final String navTitle;
  final String? subtitle;
  final String? summary;
  final String? videoSrc;
  final String? webPageId;
  final String? courseId;

  bool get hasNativeContent =>
      kind == 'web-experience' && (webPageId?.isNotEmpty ?? false);
}

class MathProfessionalPageData {
  const MathProfessionalPageData({
    required this.pageId,
    required this.title,
    required this.subtitle,
    required this.sections,
  });

  factory MathProfessionalPageData.fromJson(Map<String, dynamic> json) =>
      MathProfessionalPageData(
        pageId: json['pageId']?.toString() ?? '',
        title: json['title']?.toString() ?? '课程体验',
        subtitle: json['subtitle']?.toString() ?? '',
        sections: _mathList(json['sections']),
      );

  final String pageId;
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> sections;
}

extension AuthServiceMathApi on AuthService {
  Future<MathMajorIntroData> loadMathMajorIntro() async {
    final data = await _request('GET', '/api/miniapp/explore/math/major-intro');
    return MathMajorIntroData.fromJson(data);
  }

  Future<List<MathCoursePageData>> loadMathCoursePages() async {
    final data = await _request(
      'GET',
      '/api/miniapp/explore/math/course-intro-pages',
    );
    return _mathList(data['pages']).map(MathCoursePageData.fromJson).toList();
  }

  Future<MathProfessionalPageData> loadMathProfessionalPage(
    String pageId,
  ) async {
    final data = await _request(
      'GET',
      '/api/miniapp/explore/math/professional-page?pageId=${Uri.encodeQueryComponent(pageId)}',
    );
    if (data['pageId']?.toString() != pageId || data['sections'] is! List) {
      throw const ApiRequestException('专业体验详情接口暂未返回页面内容，请稍后重试');
    }
    return MathProfessionalPageData.fromJson(data);
  }
}

class ProfessionalExperiencePage extends StatefulWidget {
  const ProfessionalExperiencePage({super.key});

  @override
  State<ProfessionalExperiencePage> createState() =>
      _ProfessionalExperiencePageState();
}

class _ProfessionalExperiencePageState
    extends State<ProfessionalExperiencePage> {
  MathMajorIntroData? _intro;
  List<MathCoursePageData> _pages = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<dynamic>([
        AuthService.instance.loadMathMajorIntro(),
        AuthService.instance.loadMathCoursePages(),
      ]);
      if (!mounted) return;
      setState(() {
        _intro = values[0] as MathMajorIntroData;
        _pages = values[1] as List<MathCoursePageData>;
      });
    } on ApiRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCourse(MathCoursePageData page) {
    if (page.kind == 'major-intro') {
      final intro = _intro;
      if (intro != null) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MathMajorIntroPage(data: intro),
          ),
        );
      }
      return;
    }
    if (page.hasNativeContent) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MathProfessionalContentPage(pageId: page.webPageId!),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MathCourseInfoPage(page: page)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = AppLayout.pagePadding(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FB),
      appBar: AppBar(
        title: const Text('专业体验'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF8F7FB),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppConstrainedContent(
        maxWidth: AppLayout.homeContentMaxWidth,
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading && _intro == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 28),
                  children: [
                    if (_error != null && _intro == null)
                      _MathErrorCard(message: _error!, onRetry: _load)
                    else ...[
                      if (_intro != null)
                        _MathIntroHero(
                          data: _intro!,
                          onOpen: () => _openCourse(_majorIntroPage),
                        ),
                      const SizedBox(height: 22),
                      for (final stage in _stageIndexes) ...[
                        _MathStageHeader(
                          title: _pages
                              .firstWhere((page) => page.stageIndex == stage)
                              .stageTitle,
                          subtitle: stage == 0
                              ? '先认识专业，再决定是否继续深入。'
                              : '进入数学分析与线性代数的真实学习样本。',
                        ),
                        const SizedBox(height: 10),
                        for (final page in _pages.where(
                          (item) =>
                              item.stageIndex == stage &&
                              item.id != 'major-intro-text',
                        )) ...[
                          _MathCourseTile(
                            page: page,
                            onTap: () => _openCourse(page),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  List<int> get _stageIndexes {
    final values = _pages.map((page) => page.stageIndex).toSet().toList()
      ..sort();
    return values;
  }

  MathCoursePageData get _majorIntroPage => _pages.firstWhere(
    (page) => page.kind == 'major-intro',
    orElse: () => const MathCoursePageData(
      id: 'major-intro-text',
      stageIndex: 0,
      stageTitle: 'Part 1：数学专业介绍',
      kind: 'major-intro',
      title: '数学专业介绍',
      navTitle: '介绍',
    ),
  );
}

class _MathIntroHero extends StatelessWidget {
  const _MathIntroHero({required this.data, required this.onOpen});

  final MathMajorIntroData data;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final poster = AuthService.instance.resolveAssetUrl(
      data.video['poster']?.toString(),
    );
    return Material(
      color: const Color(0xFF171126),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (poster.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  poster,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const _MathImageFallback(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.stageLabel,
                    style: const TextStyle(
                      color: Color(0xFFC9ABFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    data.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    data.subtitle,
                    style: const TextStyle(
                      color: Color(0xFFD8D1E2),
                      height: 1.55,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Text(
                        '查看完整介绍',
                        style: TextStyle(
                          color: Color(0xFFC9ABFF),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: Color(0xFFC9ABFF),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MathStageHeader extends StatelessWidget {
  const _MathStageHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(
          color: Color(0xFF78717E),
          fontSize: 13,
          height: 1.5,
        ),
      ),
    ],
  );
}

class _MathCourseTile extends StatelessWidget {
  const _MathCourseTile({required this.page, required this.onTap});

  final MathCoursePageData page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (page.kind) {
      'longform-video' => Icons.play_circle_outline_rounded,
      'web-experience' => Icons.touch_app_outlined,
      'course-challenge' => Icons.task_alt_rounded,
      _ => Icons.menu_book_outlined,
    };
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE4FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF6B23FF)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      page.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((page.summary ?? page.subtitle ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        page.summary ?? page.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF77717D),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFAAA4AF)),
            ],
          ),
        ),
      ),
    );
  }
}

class MathMajorIntroPage extends StatelessWidget {
  const MathMajorIntroPage({super.key, required this.data});

  final MathMajorIntroData data;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F7FB),
    appBar: AppBar(
      title: Text(data.title),
      backgroundColor: const Color(0xFFF8F7FB),
      surfaceTintColor: Colors.transparent,
    ),
    body: AppConstrainedContent(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppLayout.pagePadding(context),
          12,
          AppLayout.pagePadding(context),
          30,
        ),
        children: [
          Text(
            data.stageLabel,
            style: const TextStyle(
              color: Color(0xFF6B23FF),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.subtitle,
            style: const TextStyle(
              fontSize: 15,
              height: 1.65,
              color: Color(0xFF5E5864),
            ),
          ),
          const SizedBox(height: 18),
          _MathVideoResourceCard(video: data.video),
          const SizedBox(height: 18),
          for (var index = 0; index < data.sections.length; index++) ...[
            _MathIntroSectionCard(section: data.sections[index]),
            if (index != data.sections.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    ),
  );
}

class MathProfessionalContentPage extends StatefulWidget {
  const MathProfessionalContentPage({super.key, required this.pageId});

  final String pageId;

  @override
  State<MathProfessionalContentPage> createState() =>
      _MathProfessionalContentPageState();
}

class _MathProfessionalContentPageState
    extends State<MathProfessionalContentPage> {
  MathProfessionalPageData? _page;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await AuthService.instance.loadMathProfessionalPage(
        widget.pageId,
      );
      if (mounted) setState(() => _page = page);
    } on ApiRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FB),
      appBar: AppBar(
        title: Text(page?.title ?? '课程体验'),
        backgroundColor: const Color(0xFFF8F7FB),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppConstrainedContent(
        child: page == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: _MathErrorCard(message: _error!, onRetry: _load),
                      ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  AppLayout.pagePadding(context),
                  12,
                  AppLayout.pagePadding(context),
                  30,
                ),
                children: [
                  if (page.subtitle.isNotEmpty)
                    Text(
                      page.subtitle,
                      style: const TextStyle(
                        color: Color(0xFF6B23FF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 14),
                  for (
                    var index = 0;
                    index < page.sections.length;
                    index++
                  ) ...[
                    _MathProfessionalSection(section: page.sections[index]),
                    if (index != page.sections.length - 1)
                      const SizedBox(height: 14),
                  ],
                ],
              ),
      ),
    );
  }
}

class MathCourseInfoPage extends StatelessWidget {
  const MathCourseInfoPage({super.key, required this.page});

  final MathCoursePageData page;

  @override
  Widget build(BuildContext context) {
    final isVideo = page.kind == 'longform-video';
    final unavailable = page.kind == 'course-challenge';
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FB),
      appBar: AppBar(
        title: Text(page.title),
        backgroundColor: const Color(0xFFF8F7FB),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppConstrainedContent(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppLayout.pagePadding(context),
            18,
            AppLayout.pagePadding(context),
            30,
          ),
          children: [
            if (isVideo)
              _MathVideoResourceCard(
                video: {'title': page.title, 'src': page.videoSrc},
              )
            else
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Icon(
                      unavailable
                          ? Icons.construction_rounded
                          : Icons.menu_book_outlined,
                      size: 46,
                      color: const Color(0xFF6B23FF),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      page.summary ??
                          (unavailable
                              ? '这部分需要继续适配 APP 原生习题交互。'
                              : '该页面目前由后端提供目录信息。'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        height: 1.65,
                        color: Color(0xFF625A6C),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MathIntroSectionCard extends StatelessWidget {
  const _MathIntroSectionCard({required this.section});

  final MathMajorIntroSection section;

  @override
  Widget build(BuildContext context) {
    final figure = section.figure;
    final imageUrl = AuthService.instance.resolveAssetUrl(
      figure?['src']?.toString(),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title?.isNotEmpty == true) ...[
            Text(
              section.title!,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
          ],
          for (var index = 0; index < section.paragraphs.length; index++) ...[
            Text(
              section.paragraphs[index],
              style: const TextStyle(
                fontSize: 14,
                height: 1.75,
                color: Color(0xFF5E5864),
              ),
            ),
            if (index != section.paragraphs.length - 1)
              const SizedBox(height: 10),
          ],
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _MathImageFallback(),
              ),
            ),
            if (figure?['title']?.toString().isNotEmpty == true) ...[
              const SizedBox(height: 7),
              Text(
                '${figure!['title']}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF847D89)),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _MathProfessionalSection extends StatelessWidget {
  const _MathProfessionalSection({required this.section});

  final Map<String, dynamic> section;

  @override
  Widget build(BuildContext context) {
    final type = section['type']?.toString();
    if (type == 'prose') {
      final paragraphs = (section['paragraphs'] as List? ?? const [])
          .map((item) => item.toString())
          .toList();
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < paragraphs.length; index++) ...[
              Text(
                paragraphs[index],
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.75,
                  color: Color(0xFF524C58),
                ),
              ),
              if (index != paragraphs.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      );
    }
    if (type == 'figure' || type == 'character-interaction') {
      final path = type == 'figure'
          ? section['src']
          : section['characterImage'];
      final url = AuthService.instance.resolveAssetUrl(path?.toString());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: url.isEmpty
                ? const _MathImageFallback()
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _MathImageFallback(),
                  ),
          ),
          if (type == 'character-interaction') ...[
            const SizedBox(height: 10),
            _MathInteractionCard(
              interaction: section['interaction']?.toString() ?? '',
            ),
          ],
        ],
      );
    }
    if (type == 'formula') {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF171126),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section['title']?.toString() ?? '公式',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (section['description'] != null) ...[
              const SizedBox(height: 8),
              Text(
                '${section['description']}',
                style: const TextStyle(color: Color(0xFFD8D1E2), height: 1.55),
              ),
            ],
            if (section['math'] != null) ...[
              const SizedBox(height: 15),
              SelectableText(
                '${section['math']}',
                style: const TextStyle(
                  color: Color(0xFFC9ABFF),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    }
    if (type == 'interaction') {
      return _MathInteractionCard(
        interaction: section['interaction']?.toString() ?? '',
      );
    }
    return const SizedBox.shrink();
  }
}

class _MathInteractionCard extends StatelessWidget {
  const _MathInteractionCard({required this.interaction});

  final String interaction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E8),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFF0D69A)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.touch_app_outlined, color: Color(0xFF8A5A00)),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '本节文字、插图和公式已接入；互动操作需要下一阶段继续做 APP 原生适配。',
                style: TextStyle(
                  color: Color(0xFF725221),
                  height: 1.5,
                  fontSize: 13,
                ),
              ),
              if (interaction.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  '交互标识：$interaction',
                  style: const TextStyle(
                    color: Color(0xFF9A7A43),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _MathVideoResourceCard extends StatelessWidget {
  const _MathVideoResourceCard({required this.video});

  final Map<String, dynamic> video;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF171126),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.play_circle_outline_rounded,
          size: 54,
          color: Color(0xFFC9ABFF),
        ),
        const SizedBox(height: 10),
        Text(
          video['title']?.toString() ?? '课程视频',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          '后端视频资源已提供，APP 播放器组件待接入。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFD8D1E2), fontSize: 13),
        ),
      ],
    ),
  );
}

class _MathImageFallback extends StatelessWidget {
  const _MathImageFallback();

  @override
  Widget build(BuildContext context) => Container(
    height: 170,
    color: const Color(0xFFEDE4FF),
    alignment: Alignment.center,
    child: const Icon(
      Icons.functions_rounded,
      size: 52,
      color: Color(0xFF6B23FF),
    ),
  );
}

class _MathErrorCard extends StatelessWidget {
  const _MathErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        const Icon(Icons.cloud_off_rounded, size: 42, color: Color(0xFF6B23FF)),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.5),
        ),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
      ],
    ),
  );
}

Map<String, dynamic> _mathMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry('$key', item));
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _mathList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map(_mathMap).toList();
}
