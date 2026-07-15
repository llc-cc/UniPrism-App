import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'assessment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.instance.restore();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  runApp(const UniPrismApp());
}

class UniPrismApp extends StatelessWidget {
  const UniPrismApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '万有棱镜',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B23FF)),
        fontFamily: 'PingFang SC',
        scaffoldBackgroundColor: Colors.white,
      ),
      routes: {
        // Temporarily bypass the cold-start welcome screen and open the main
        // experience immediately.
        '/': (_) => const HomePage(),
        '/intro/interest': (_) => const ModuleIntroPage(config: IntroConfig.interest),
        '/intro/major': (_) => const ModuleIntroPage(config: IntroConfig.major),
        '/basic-profile': (_) => const BasicProfilePage(),
        '/login': (_) => const LoginPage(),
        '/assessment': (_) => const AssessmentPage(),
        '/home': (_) => const HomePage(),
      },
    );
  }
}

class AppAssets {
  static const launchHero = 'assets/auth/launch-entry-hero.png';
  static const welcomeCampusBackground =
      'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/welcome-campus-bg.png';
}

class ApiRequestException implements Exception {
  const ApiRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  static final instance = AuthService._();
  static const _baseUrl = 'https://uniprism.cn';
  static const _tokenKey = 'uniprism.token';
  static const _userKey = 'uniprism.user';
  static const _anonymousIdKey = 'uniprism.anonymousId';
  static const _anonymousCookieKey = 'uniprism.anonymousCookie';
  static const _exploreSessionIdKey = 'uniprism.exploreSessionId';
  static const _storageChannel = MethodChannel('uniprism/auth_storage');
  static final _httpClient = HttpClient();

  String? _token;
  Map<String, dynamic>? _user;
  String? _anonymousId;
  String? _anonymousCookie;
  String? _exploreSessionId;

  bool get isLoggedIn => (_token ?? '').isNotEmpty;
  String? get token => _token;
  String? get exploreSessionId => _exploreSessionId;
  String get displayName {
    final user = _user;
    if (user == null) return '';
    return '${user['name'] ?? user['wechatNickname'] ?? user['phone'] ?? ''}'.trim();
  }

  Future<void> restore() async {
    final stored = await _readStorage();
    _token = stored[_tokenKey]?.toString();
    _anonymousId = stored[_anonymousIdKey]?.toString();
    _anonymousCookie = stored[_anonymousCookieKey]?.toString();
    _exploreSessionId = stored[_exploreSessionIdKey]?.toString();
    final userJson = stored[_userKey]?.toString();
    if (userJson == null || userJson.isEmpty) return;
    try {
      final decoded = jsonDecode(userJson);
      if (decoded is Map<String, dynamic>) _user = decoded;
    } catch (_) {
      await _writeStorage({_userKey: null});
    }
  }

  Future<void> sendSmsCode(String phone) async {
    await _request('POST', '/api/miniapp/auth/sms/send', body: {'phone': phone});
  }

  Future<String?> sendSmsCodeWithDevCode(String phone) async {
    final data = await _request('POST', '/api/miniapp/auth/sms/send', body: {'phone': phone});
    return data['devCode']?.toString();
  }

  Future<void> loginWithPhone(String phone, String code) async {
    final data = await _request(
      'POST',
      '/api/miniapp/auth/sms/login',
      body: {'phone': phone, 'code': code},
    );
    final token = data['token']?.toString();
    final user = _map(data['user']);
    if (token == null || token.isEmpty || user == null) {
      throw const ApiRequestException('登录响应不完整，请稍后重试');
    }
    _token = token;
    _user = user;
    await _writeStorage({_tokenKey: token, _userKey: jsonEncode(user)});
    await ensureExploreSession(forceNew: true);
  }

  Future<String> ensureExploreSession({bool forceNew = false}) async {
    final existing = _exploreSessionId;
    if (!forceNew && existing != null && existing.isNotEmpty) return existing;

    final session = await _request(
      'POST',
      isLoggedIn ? '/api/miniapp/explore/session' : '/api/explore/session',
      body: {
        if ((_anonymousId ?? '').isNotEmpty) 'anonymousId': _anonymousId,
      },
    );
    final sessionId = session['sessionId']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      throw const ApiRequestException('无法创建探索会话，请重试');
    }
    _exploreSessionId = sessionId;
    await _writeStorage({_exploreSessionIdKey: sessionId});

    final returnedAnonymousId = session['anonymousId']?.toString();
    if (returnedAnonymousId != null && returnedAnonymousId.isNotEmpty) {
      _anonymousId = returnedAnonymousId;
      await _writeStorage({_anonymousIdKey: returnedAnonymousId});
    }
    return sessionId;
  }

  /// Starts a fresh assessment session. A new anonymous identity is used as
  /// well, preventing the API from resolving the previous guest session by
  /// cookie or anonymous-id and restoring its old answers.
  Future<void> restartExploreAssessment() async {
    _exploreSessionId = null;
    _anonymousId = 'anon-${DateTime.now().microsecondsSinceEpoch}';
    _anonymousCookie = null;
    await _writeStorage({
      _exploreSessionIdKey: null,
      _anonymousIdKey: _anonymousId,
      _anonymousCookieKey: null,
    });
    await ensureExploreSession(forceNew: true);
  }

  Future<void> submitBasicProfile({
    required String name,
    required String gender,
    required String status,
    required String referralSource,
    required String inviteCode,
  }) async {
    final sessionId = await ensureExploreSession();

    final clarity = status == 'status-checking' || status == 'status-late' ? 'clarity-area' : 'clarity-none';
    final displayFields = {
      'name': name,
      'gender': gender == 'gender-male' ? '男' : '女',
      'status': _statusLabel(status),
      'clarity': clarity == 'clarity-area' ? '只有大概领域' : '完全没有',
      'referralSource': _referralSourceLabel(referralSource),
    };
    final fields = {
      'name': name,
      'gender': gender,
      'status': status,
      'clarity': clarity,
      'referralSource': referralSource,
    };
    final summary = [
      '称呼：$name',
      '性别：${displayFields['gender']}',
      '当前状态：${displayFields['status']}',
      '来源：${displayFields['referralSource']}',
      if (inviteCode.isNotEmpty) '邀请码：$inviteCode',
    ].join('；');
    await _request(
      'POST',
      '/api/miniapp/explore/basic-profile',
      body: {
        'sessionId': sessionId,
        'fields': fields,
        'displayFields': displayFields,
        'summary': summary,
        if (inviteCode.isNotEmpty) 'inviteCode': inviteCode,
      },
    );
  }

  Future<List<HomeMajorCard>> loadHomePopularMajors({List<Map<String, dynamic>>? answers}) async {
    var sessionId = await ensureExploreSession();
    final currentAnswers = answers ?? await loadAssessmentAnswers();
    Map<String, dynamic> data;
    try {
      data = await _request(
        'POST',
        '/api/miniapp/explore/home-popular-majors',
        body: {'sessionId': sessionId, 'answers': currentAnswers},
      );
    } on ApiRequestException catch (error) {
      if (!_shouldRefreshSession(error)) rethrow;
      sessionId = await ensureExploreSession(forceNew: true);
      data = await _request(
        'POST',
        '/api/miniapp/explore/home-popular-majors',
        body: {'sessionId': sessionId, 'answers': currentAnswers},
      );
    }
    final rawCards = data['cards'];
    if (rawCards is! List) return HomeMajorCard.lockedCards;
    final cards = rawCards
        .whereType<Map>()
        .map((value) => HomeMajorCard.fromJson(_map(value) ?? <String, dynamic>{}))
        .toList();
    return cards.isEmpty ? HomeMajorCard.lockedCards : cards;
  }

  Future<List<Map<String, dynamic>>> loadAssessmentAnswers() async {
    final sessionId = _exploreSessionId;
    if (sessionId == null || sessionId.isEmpty) return <Map<String, dynamic>>[];
    Map<String, dynamic> data;
    try {
      data = await _request('GET', '/api/explore/discover/answers?sessionId=$sessionId');
    } on ApiRequestException catch (error) {
      if (!_shouldRefreshSession(error)) rethrow;
      await ensureExploreSession(forceNew: true);
      return <Map<String, dynamic>>[];
    }
    final rawAnswers = data['answers'];
    if (rawAnswers is! List) return <Map<String, dynamic>>[];
    return rawAnswers
        .whereType<Map>()
        .map((value) => _map(value) ?? <String, dynamic>{})
        .where((value) => value['questionId'] != null && value['value'] != null)
        .toList();
  }

  Future<void> saveAssessmentAnswers(List<Map<String, dynamic>> answers) async {
    if (answers.isEmpty) return;
    var sessionId = await ensureExploreSession();
    try {
      await _request(
        'POST',
        '/api/explore/discover/answers',
        body: {'sessionId': sessionId, 'answers': answers},
      );
    } on ApiRequestException catch (error) {
      if (!_shouldRefreshSession(error)) rethrow;
      sessionId = await ensureExploreSession(forceNew: true);
      await _request(
        'POST',
        '/api/explore/discover/answers',
        body: {'sessionId': sessionId, 'answers': answers},
      );
    }
  }

  /// Mirrors the mini-program's v0.2 stage-preview request.  The response
  /// provides the actual majors displayed by the stage elimination review.
  Future<Map<String, dynamic>> loadAssessmentStagePreview({
    required String stageId,
    required List<Map<String, dynamic>> answers,
  }) async {
    var sessionId = await ensureExploreSession();
    final answerMap = <String, dynamic>{
      for (final answer in answers)
        if (answer['questionId'] != null)
          '${answer['questionId']}': _map(answer['value']) ?? <String, dynamic>{},
    };
    Future<Map<String, dynamic>> requestPreview() => _request(
          'POST',
          '/api/interest-v020/stage-preview',
          body: {
            'sessionId': sessionId,
            'stageId': stageId,
            'answers': answerMap,
          },
        );
    try {
      return await requestPreview();
    } on ApiRequestException catch (error) {
      if (!_shouldRefreshSession(error)) rethrow;
      sessionId = await ensureExploreSession(forceNew: true);
      return requestPreview();
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final isMiniAppPath = path.startsWith('/api/miniapp/');
      final request = await _httpClient.openUrl(method, Uri.parse('$_baseUrl$path'));
      request.headers.set(HttpHeaders.contentTypeHeader, ContentType.json.mimeType);
      request.headers.set('Origin', _baseUrl);
      if (isMiniAppPath) request.headers.set('x-miniapp-client', 'uniprism-weapp');
      if ((_token ?? '').isNotEmpty) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      if (isMiniAppPath && (_anonymousId ?? '').isNotEmpty) {
        request.headers.set('x-anonymous-id', _anonymousId!);
      }
      if (!isMiniAppPath && (_anonymousCookie ?? '').isNotEmpty) {
        final separator = _anonymousCookie!.indexOf('=');
        if (separator > 0) {
          request.cookies.add(Cookie(
            _anonymousCookie!.substring(0, separator),
            _anonymousCookie!.substring(separator + 1),
          ));
        }
      }
      if (body != null) request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(const Duration(seconds: 15));
      for (final cookie in response.cookies) {
        if (cookie.name == 'uniprism_anonymous') {
          await _storeAnonymousCookie('${cookie.name}=${cookie.value}');
        }
      }
      final responseText = await utf8.decodeStream(response);
      dynamic decoded;
      try {
        decoded = responseText.isEmpty ? <String, dynamic>{} : jsonDecode(responseText);
      } catch (_) {
        throw const ApiRequestException('服务器返回了无法识别的数据');
      }
      final envelope = _map(decoded) ?? <String, dynamic>{};
      final data = _map(envelope['data']) ?? envelope;
      if (response.statusCode < 200 || response.statusCode >= 300 || envelope['ok'] == false) {
        throw ApiRequestException(_errorMessage(envelope));
      }
      return data;
    } on TimeoutException {
      throw const ApiRequestException('网络连接超时，请检查网络后重试');
    } on ApiRequestException {
      rethrow;
    } catch (_) {
      throw const ApiRequestException('网络连接失败，请稍后重试');
    }
  }

  static Map<String, dynamic>? _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    return null;
  }

  static Future<Map<String, dynamic>> _readStorage() async {
    try {
      return (await _storageChannel.invokeMapMethod<String, dynamic>('read')) ?? <String, dynamic>{};
    } on MissingPluginException {
      return <String, dynamic>{};
    }
  }

  static Future<void> _writeStorage(Map<String, String?> values) async {
    try {
      await _storageChannel.invokeMethod<void>('write', values);
    } on MissingPluginException {
      // Storage is optional on platforms that have not registered the native channel.
    }
  }

  Future<void> _storeAnonymousCookie(String? setCookie) async {
    if (setCookie == null || setCookie.isEmpty) return;
    final cookie = setCookie.split(';').first.trim();
    if (!cookie.startsWith('uniprism_anonymous=')) return;
    _anonymousCookie = cookie;
    await _writeStorage({_anonymousCookieKey: cookie});
  }

  static String _errorMessage(Map<String, dynamic> response) {
    return '${response['message'] ?? response['error'] ?? response['msg'] ?? '请求失败，请稍后重试'}';
  }

  static bool _shouldRefreshSession(ApiRequestException error) {
    final message = error.message.toLowerCase();
    return message.contains('unauthorized') || message.contains('探索会话') || message.contains('session');
  }

  static String _statusLabel(String value) {
    const labels = {
      'status-early': '还在广泛了解',
      'status-late': '需要尽快缩小范围',
      'status-checking': '有方向，想验证适配度',
      'status-lost': '比较迷茫，需要系统帮我筛选方向',
    };
    return labels[value] ?? '';
  }

  static String _referralSourceLabel(String value) {
    const labels = {
      'referral-xiaohongshu-official': '小红书官方号',
      'referral-introduction': '朋友圈、朋友、老师等介绍',
      'referral-social-nonofficial': '社交媒体如微信公众号、小红书（非官方）',
      'referral-other': '其他地方',
    };
    return labels[value] ?? '';
  }
}

class LaunchPage extends StatelessWidget {
  const LaunchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final horizontal = math.max(24.0, size.width * 0.064);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 28),
          child: Column(
            children: [
              SizedBox(height: _clamp(size.height * 0.12, 76, 122)),
              const Text(
                '在选择专业前，提前了解\n学什么、做什么、你想要什么',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 17,
                  height: 1.65,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: _clamp(size.height * 0.075, 48, 72)),
              SizedBox(
                width: math.min(size.width - 32, 342),
                height: 192,
                child: Image.asset(
                  AppAssets.launchHero,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                '在一万种可能中，看清独属于你的道路！',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF222222),
                  fontSize: 13,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 220,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PrimaryButton(
                      label: '开始体验',
                      onPressed: () => Navigator.of(context).pushNamed('/intro/interest'),
                    ),
                    const SizedBox(height: 16),
                    OutlineActionButton(
                      label: '登录',
                      onPressed: () => Navigator.of(context).pushNamed('/login'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ModuleIntroPage extends StatefulWidget {
  const ModuleIntroPage({super.key, required this.config});

  final IntroConfig config;

  @override
  State<ModuleIntroPage> createState() => _ModuleIntroPageState();
}

class _ModuleIntroPageState extends State<ModuleIntroPage> {
  late final PageController _pageController;
  Timer? _autoPlayTimer;
  int _activeIndex = 0;

  List<IntroSlide> get _visibleSlides => widget.config.slides.take(_activeIndex + 1).toList();

  bool get _isReady => _activeIndex >= widget.config.slides.length - 1;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _isReady) {
        _autoPlayTimer?.cancel();
        return;
      }
      _goToSlide(_activeIndex + 1);
    });
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _goToSlide(int index) {
    if (index < 0 || index >= widget.config.slides.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _activeIndex = index);
    if (_isReady) _autoPlayTimer?.cancel();
  }

  void _handlePrimaryAction() {
    if (!_isReady) {
      _goToSlide(_activeIndex + 1);
      return;
    }

    final nextRoute = widget.config.type == IntroType.interest ? '/intro/major' : '/basic-profile';
    Navigator.of(context).pushReplacementNamed(nextRoute);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final theme = widget.config.theme;
    final carouselWidth = math.min(size.width * 0.69, 270.0);

    return Scaffold(
      body: Stack(
        children: [
          IntroBackdrop(theme: theme),
          SafeArea(
            child: Column(
              children: [
                _IntroHeader(
                  title: widget.config.navTitle,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                SizedBox(height: _clamp(size.height * 0.036, 22, 34)),
                IntroCarousel(
                  controller: _pageController,
                  slides: widget.config.slides,
                  activeIndex: _activeIndex,
                  theme: theme,
                  width: carouselWidth,
                  onChanged: _onPageChanged,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.config.sectionTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.accent,
                    fontSize: 19,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: math.max(46, size.width * 0.13)),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: TimelineList(
                        slides: _visibleSlides,
                        activeIndex: _activeIndex,
                        theme: theme,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(86, 12, 86, 32 + MediaQuery.paddingOf(context).bottom),
                  child: PrimaryButton(
                    label: _isReady ? widget.config.primaryLabel : '下一步',
                    onPressed: _handlePrimaryAction,
                    backgroundColor: _isReady ? theme.activeButton : theme.mutedButton,
                    shadowColor: _isReady ? theme.activeShadow : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroHeader extends StatelessWidget {
  const _IntroHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 24, 0),
      child: SizedBox(
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                color: const Color(0xFF222222),
                iconSize: 21,
                tooltip: '返回',
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF222222),
                fontSize: 18,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IntroCarousel extends StatelessWidget {
  const IntroCarousel({
    super.key,
    required this.controller,
    required this.slides,
    required this.activeIndex,
    required this.theme,
    required this.width,
    required this.onChanged,
  });

  final PageController controller;
  final List<IntroSlide> slides;
  final int activeIndex;
  final IntroTheme theme;
  final double width;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 1.53,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -10,
              top: -7,
              right: 8,
              bottom: 8,
              child: _CarouselStackCard(
                imageUrl: slides[(activeIndex + 2) % slides.length].imageUrl,
                angle: -0.09,
                theme: theme,
              ),
            ),
            Positioned(
              left: 8,
              top: 3,
              right: -9,
              bottom: -3,
              child: _CarouselStackCard(
                imageUrl: slides[(activeIndex + 1) % slides.length].imageUrl,
                angle: 0.055,
                theme: theme,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.white, width: 5),
                  boxShadow: [BoxShadow(color: theme.accent.withOpacity(0.12), blurRadius: 18, offset: const Offset(0, 8))],
                ),
                child: ClipRect(
                  child: PageView.builder(
                    controller: controller,
                    itemCount: slides.length,
                    onPageChanged: onChanged,
                    itemBuilder: (context, index) => _RemoteSlideImage(slide: slides[index], theme: theme),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarouselStackCard extends StatelessWidget {
  const _CarouselStackCard({
    required this.imageUrl,
    required this.angle,
    required this.theme,
  });

  final String imageUrl;
  final double angle;
  final IntroTheme theme;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.white, width: 5),
          boxShadow: [BoxShadow(color: theme.accent.withOpacity(0.1), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _RemoteSlideImage extends StatelessWidget {
  const _RemoteSlideImage({required this.slide, required this.theme});

  final IntroSlide slide;
  final IntroTheme theme;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      slide.imageUrl,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return ColoredBox(
          color: theme.timelineSoft,
          child: Center(child: CircularProgressIndicator(color: theme.accent, strokeWidth: 2)),
        );
      },
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: theme.timelineSoft,
        child: Icon(Icons.image_not_supported_outlined, color: theme.accent, size: 30),
      ),
    );
  }
}

class TimelineList extends StatelessWidget {
  const TimelineList({
    super.key,
    required this.slides,
    required this.activeIndex,
    required this.theme,
  });

  final List<IntroSlide> slides;
  final int activeIndex;
  final IntroTheme theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      child: Stack(
        children: [
          if (slides.isNotEmpty)
            Positioned(
              left: 3,
              top: 12,
              bottom: 10,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: theme.timelineSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < slides.length; index++)
                TimelineItem(
                  key: ValueKey(slides[index].imageUrl),
                  text: slides[index].text,
                  isActive: index == activeIndex,
                  theme: theme,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class TimelineItem extends StatelessWidget {
  const TimelineItem({super.key, required this.text, required this.isActive, required this.theme});

  final String text;
  final bool isActive;
  final IntroTheme theme;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 8), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: isActive ? 8 : 7,
              height: isActive ? 8 : 7,
              margin: const EdgeInsets.only(top: 7),
              decoration: BoxDecoration(
                color: isActive ? theme.accent : theme.timelineSoft,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: TextStyle(
                  color: const Color(0xFF333333),
                  fontSize: 13,
                  height: 1.55,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
                child: Text(text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IntroBackdrop extends StatelessWidget {
  const IntroBackdrop({super.key, required this.theme});

  final IntroTheme theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              AppAssets.welcomeCampusBackground,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) => const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [theme.overlayColor.withOpacity(0.38), theme.overlayColor.withOpacity(0)],
                  stops: const [0.03, 0.64],
                ),
              ),
            ),
          ),
          const SizedBox.expand(),
        ],
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor = const Color(0xFF6B23FF),
    this.shadowColor = const Color(0xFF3D0AA8),
  });

  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color shadowColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: shadowColor, borderRadius: BorderRadius.circular(11)),
      child: Padding(
        padding: EdgeInsets.only(bottom: shadowColor == Colors.transparent ? 0 : 4),
        child: SizedBox(
          height: 50,
          width: double.infinity,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              elevation: 0,
              backgroundColor: backgroundColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class OutlineActionButton extends StatelessWidget {
  const OutlineActionButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF6B23FF),
          side: const BorderSide(color: Color(0xFFD8D8D8), width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        child: Text(label),
      ),
    );
  }
}

enum _LoginView { landing, phone }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  _LoginView _view = _LoginView.landing;
  Timer? _cooldownTimer;
  int _cooldown = 0;
  bool _agreedToTerms = false;
  bool _sendingCode = false;
  bool _loggingIn = false;
  String _error = '';
  String _devCodeHint = '';

  String get _phone => _phoneController.text.trim();
  String get _code => _codeController.text.trim();
  bool get _isValidPhone => RegExp(r'^1[3-9]\d{9}$').hasMatch(_phone);
  bool get _isValidCode => RegExp(r'^\d{6}$').hasMatch(_code);

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_refresh);
    _codeController.addListener(_refresh);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneController
      ..removeListener(_refresh)
      ..dispose();
    _codeController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  bool _ensureAgreement() {
    if (_agreedToTerms) return true;
    setState(() => _error = '请先阅读并同意用户服务条款和隐私政策');
    return false;
  }

  void _openPhoneLogin() {
    if (!_ensureAgreement()) return;
    setState(() {
      _view = _LoginView.phone;
      _error = '';
    });
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _cooldown = 0);
      } else if (mounted) {
        setState(() => _cooldown -= 1);
      }
    });
  }

  Future<void> _sendCode() async {
    if (!_ensureAgreement()) return;
    if (!_isValidPhone) {
      setState(() => _error = '请输入有效的中国大陆手机号');
      return;
    }
    if (_sendingCode || _cooldown > 0) return;
    setState(() {
      _sendingCode = true;
      _error = '';
      _devCodeHint = '';
    });
    try {
      final devCode = await AuthService.instance.sendSmsCodeWithDevCode(_phone);
      if (!mounted) return;
      if (devCode != null && devCode.isNotEmpty) {
        _codeController.text = devCode;
        setState(() => _devCodeHint = '开发验证码：$devCode');
      }
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('验证码已发送')));
    } on ApiRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _login() async {
    if (!_ensureAgreement()) return;
    if (!_isValidPhone) {
      setState(() => _error = '请输入有效的中国大陆手机号');
      return;
    }
    if (!_isValidCode) {
      setState(() => _error = '请输入 6 位验证码');
      return;
    }
    setState(() {
      _loggingIn = true;
      _error = '';
    });
    try {
      await AuthService.instance.loginWithPhone(_phone, _code);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } on ApiRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const IntroBackdrop(theme: IntroTheme.interest),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
              child: _view == _LoginView.landing ? _buildLanding() : _buildPhoneLogin(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanding() {
    return Column(
      children: [
        const Spacer(flex: 3),
        const Icon(Icons.change_history_rounded, size: 64, color: Color(0xFF6B23FF)),
        const SizedBox(height: 18),
        const Text('万有棱镜', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF262626))),
        const SizedBox(height: 10),
        const Text('告别专业迷茫，从容规划未来', style: TextStyle(fontSize: 15, color: Color(0xFF666666))),
        const Spacer(flex: 4),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _openPhoneLogin,
            icon: const Icon(Icons.phone_iphone_rounded, size: 20),
            label: const Text('手机号登录'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6B23FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _buildAgreement(),
      ],
    );
  }

  Widget _buildPhoneLogin() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () => setState(() {
              _view = _LoginView.landing;
              _error = '';
            }),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            tooltip: '返回',
          ),
        ),
        const SizedBox(height: 42),
        const Text('手机号登录', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Text('验证码登录，首次使用将自动创建账号', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Color(0xFF666666))),
        const SizedBox(height: 42),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          decoration: _loginInputDecoration('请输入手机号'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: _loginInputDecoration('6 位验证码').copyWith(
            suffixIcon: TextButton(
              onPressed: _sendingCode || _cooldown > 0 || !_isValidPhone ? null : _sendCode,
              child: Text(_cooldown > 0 ? '${_cooldown}s' : (_sendingCode ? '发送中' : '获取验证码')),
            ),
          ),
        ),
        if (_devCodeHint.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_devCodeHint, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFF6B23FF))),
        ],
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(_error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFFC62828))),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _loggingIn || !_isValidPhone || !_isValidCode ? null : _login,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6B23FF),
              disabledBackgroundColor: const Color(0xFFD7C9FF),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            child: Text(_loggingIn ? '登录中...' : '登录'),
          ),
        ),
        const Spacer(),
        _buildAgreement(),
      ],
    );
  }

  InputDecoration _loginInputDecoration(String hintText) {
    return InputDecoration(
      counterText: '',
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF9761FF), width: 1.5),
      ),
    );
  }

  Widget _buildAgreement() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _agreedToTerms,
            onChanged: (value) => setState(() {
              _agreedToTerms = value ?? false;
              if (_agreedToTerms) _error = '';
            }),
            activeColor: const Color(0xFF6B23FF),
          ),
        ),
        const SizedBox(width: 4),
        const Expanded(
          child: Text(
            '我已阅读并同意《用户服务条款》和《隐私政策》',
            style: TextStyle(color: Color(0xFF777777), fontSize: 12, height: 1.5),
          ),
        ),
      ],
    );
  }
}

class BasicProfilePage extends StatefulWidget {
  const BasicProfilePage({super.key});

  @override
  State<BasicProfilePage> createState() => _BasicProfilePageState();
}

class _BasicProfilePageState extends State<BasicProfilePage> {
  final _nameController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  int _stepIndex = 0;
  String _gender = '';
  String _status = '';
  String _referralSource = '';
  bool _submitting = false;

  bool get _canContinue {
    switch (_stepIndex) {
      case 0:
        return _nameController.text.trim().isNotEmpty && _gender.isNotEmpty;
      case 1:
        return _status.isNotEmpty;
      case 2:
        return _referralSource.isNotEmpty;
      default:
        return true;
    }
  }

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_refresh);
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_refresh)
      ..dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _chooseGender(String value) => setState(() => _gender = value);

  void _chooseStatus(String value) => setState(() => _status = value);

  void _chooseReferralSource(String value) => setState(() => _referralSource = value);

  Future<void> _continue() async {
    if (!_canContinue || _submitting) return;
    if (_stepIndex < 3) {
      setState(() => _stepIndex += 1);
      return;
    }
    setState(() => _submitting = true);
    try {
      await AuthService.instance.submitBasicProfile(
        name: _nameController.text.trim(),
        gender: _gender,
        status: _status,
        referralSource: _referralSource,
        inviteCode: _inviteCodeController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } on ApiRequestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final buttonColor = _canContinue && !_submitting ? const Color(0xFF6B23FF) : const Color(0xFFD7C9FF);

    return Scaffold(
      body: Stack(
        children: [
          const IntroBackdrop(theme: IntroTheme.interest),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  SizedBox(height: _clamp(size.height * 0.095, 62, 92)),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Column(
                      key: ValueKey(_stepIndex),
                      children: [
                        Text(
                          _profileStepTitle(_stepIndex),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF333333),
                            fontSize: 18,
                            height: 1.55,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_profileStepSubtitle(_stepIndex) case final subtitle?) ...[
                          const SizedBox(height: 15),
                          Text(
                            subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF333333),
                              fontSize: 17,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: _clamp(size.height * 0.048, 28, 44)),
                  Expanded(
                    child: SingleChildScrollView(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _buildStepFields(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(54, 16, 54, 32 + MediaQuery.paddingOf(context).bottom),
                    child: ProfilePrimaryButton(
                      label: _submitting ? '保存中...' : (_stepIndex == 3 ? '进入主页' : '下一步'),
                      isEnabled: _canContinue && !_submitting,
                      backgroundColor: buttonColor,
                      onPressed: _continue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepFields() {
    switch (_stepIndex) {
      case 0:
        return Column(
          key: const ValueKey('identity'),
          children: [
            const ProfileFieldLabel('你的昵称'),
            const SizedBox(height: 12),
            ProfileTextField(controller: _nameController, hintText: '请输入姓名或者昵称'),
            const SizedBox(height: 26),
            const ProfileFieldLabel('阁下的性别是？'),
            const SizedBox(height: 12),
            ProfileChoiceButton(
              label: '男',
              selected: _gender == 'gender-male',
              onPressed: () => _chooseGender('gender-male'),
            ),
            const SizedBox(height: 12),
            ProfileChoiceButton(
              label: '女',
              selected: _gender == 'gender-female',
              onPressed: () => _chooseGender('gender-female'),
            ),
          ],
        );
      case 1:
        return ProfileChoiceList(
          key: const ValueKey('status'),
          selectedValue: _status,
          onSelected: _chooseStatus,
          options: const [
            ('status-early', '还在广泛了解'),
            ('status-late', '需要尽快缩小范围'),
            ('status-checking', '有方向，想验证适配度'),
            ('status-lost', '比较迷茫，需要系统帮我筛选方向'),
          ],
        );
      case 2:
        return ProfileChoiceList(
          key: const ValueKey('source'),
          selectedValue: _referralSource,
          onSelected: _chooseReferralSource,
          options: const [
            ('referral-xiaohongshu-official', '小红书官方号'),
            ('referral-introduction', '朋友圈、朋友、老师等介绍'),
            ('referral-social-nonofficial', '社交媒体如微信公众号、小红书（非官方）'),
            ('referral-other', '其他地方'),
          ],
        );
      default:
        return Column(
          key: const ValueKey('invite'),
          children: [
            ProfileTextField(controller: _inviteCodeController, hintText: '请输入您的邀请码'),
          ],
        );
    }
  }
}

String _profileStepTitle(int index) => index == 3 ? '（可选）您是否有对应的邀请码' : '初次见面，我们该怎么称呼你？';

String? _profileStepSubtitle(int index) {
  switch (index) {
    case 1:
      return '你现在更接近那种状态？';
    case 2:
      return '你是从哪里了解到我们的？';
    case 3:
      return '如有，请填写';
    default:
      return null;
  }
}

class ProfileFieldLabel extends StatelessWidget {
  const ProfileFieldLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xFF333333), fontSize: 17, height: 1.35, fontWeight: FontWeight.w500),
    );
  }
}

class ProfileTextField extends StatelessWidget {
  const ProfileTextField({super.key, required this.controller, required this.hintText});

  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: 40,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xFF18181B), fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        counterText: '',
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF9761FF), width: 1.5),
        ),
      ),
    );
  }
}

class ProfileChoiceList extends StatelessWidget {
  const ProfileChoiceList({super.key, required this.options, required this.selectedValue, required this.onSelected});

  final List<(String, String)> options;
  final String selectedValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final option in options) ...[
          ProfileChoiceButton(
            label: option.$2,
            selected: selectedValue == option.$1,
            onPressed: () => onSelected(option.$1),
          ),
          if (option != options.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class ProfileChoiceButton extends StatelessWidget {
  const ProfileChoiceButton({super.key, required this.label, required this.selected, required this.onPressed});

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF333333),
          backgroundColor: selected ? const Color(0xFFF0E8FF) : Colors.white,
          side: BorderSide(color: selected ? const Color(0xFF9761FF) : Colors.transparent, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

class ProfilePrimaryButton extends StatelessWidget {
  const ProfilePrimaryButton({
    super.key,
    required this.label,
    required this.isEnabled,
    required this.backgroundColor,
    required this.onPressed,
  });

  final String label;
  final bool isEnabled;
  final Color backgroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: isEnabled ? onPressed : null,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: backgroundColor,
          disabledBackgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}

class HomeMajorCard {
  const HomeMajorCard({
    required this.rank,
    required this.locked,
    required this.starCount,
    this.majorId,
    this.name,
    this.iconPath,
  });

  final int rank;
  final bool locked;
  final int starCount;
  final String? majorId;
  final String? name;
  final String? iconPath;

  factory HomeMajorCard.fromJson(Map<String, dynamic> json) {
    final rank = int.tryParse('${json['rank'] ?? ''}') ?? 1;
    // Match the mini-program normalizer: an explicit `locked: false` from
    // the stage recommendation API is authoritative even when a card does
    // not carry a detail-page majorId yet.
    final locked = json['locked'] is bool ? json['locked'] as bool : json['majorId'] == null;
    return HomeMajorCard(
      rank: rank,
      locked: locked,
      starCount: int.tryParse('${json['starCount'] ?? ''}') ?? math.max(1, 6 - rank),
      majorId: json['majorId']?.toString(),
      name: json['name']?.toString(),
      iconPath: json['iconPath']?.toString(),
    );
  }

  static List<HomeMajorCard> get lockedCards => List<HomeMajorCard>.generate(
        5,
        (index) => HomeMajorCard(rank: index + 1, locked: true, starCount: 5 - index),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<HomeMajorCard> _majorCards = HomeMajorCard.lockedCards;
  bool _loading = false;
  bool _showPersona = false;
  int _completedStageCount = 0;
  bool _hasStarted = false;
  bool _restarting = false;

  static const _heroBackground =
      'https://assets.uniprism.cn/images/explore/discover/figma/home-prism-v1/hero-bg-999-1.png';
  static const _heroVisual =
      'https://assets.uniprism.cn/images/explore/discover/figma/home-prism-v1/hero-stage-05-icons.png';

  @override
  void initState() {
    super.initState();
    _loadMajorCards();
  }

  Future<void> _loadMajorCards() async {
    setState(() => _loading = true);
    try {
      // Keep the same exploration session between stages so the server can
      // generate recommendations from every answer collected so far.
      await AuthService.instance.ensureExploreSession();
      final answers = await AuthService.instance.loadAssessmentAnswers();
      final answerMap = <String, Map<String, dynamic>>{};
      for (final answer in answers) {
        final questionId = answer['questionId']?.toString();
        final value = answer['value'];
        if (questionId != null && value is Map) answerMap[questionId] = Map<String, dynamic>.from(value);
      }
      final completedStages = AssessmentBank.stages.where((stage) {
        final questions = AssessmentBank.questionsFor(stage.id);
        return questions.every((question) => _isAssessmentAnswerComplete(question, answerMap[question.id]));
      }).length;
      final cards = await AuthService.instance.loadHomePopularMajors(answers: answers);
      if (mounted) setState(() {
        _majorCards = cards;
        _completedStageCount = completedStages;
        _hasStarted = answers.isNotEmpty;
      });
    } catch (_) {
      // The locked state is a complete and intentional first-visit state.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('该功能将在后续页面接入。')),
    );
  }

  void _openMajor(HomeMajorCard card) {
    if (card.locked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('完成对应阶段测评后即可解锁。')),
      );
      return;
    }
    _showComingSoon();
  }

  Future<void> _restartAssessment() async {
    if (_restarting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认重来'),
        content: const Text('确定要重新开始测评吗？当前阶段的答题进度将从头计算。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('重来')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _restarting = true);
    try {
      await AuthService.instance.restartExploreAssessment();
      if (!mounted) return;
      setState(() {
        _majorCards = HomeMajorCard.lockedCards;
        _completedStageCount = 0;
        _hasStarted = false;
      });
      await _loadMajorCards();
    } on ApiRequestException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        centerTitle: true,
        title: const Text('兴趣探索', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _loadMajorCards,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(15, 18, 15, 28),
          children: [
            _HomeHero(
              completedStages: _completedStageCount,
              hasStarted: _hasStarted,
              restarting: _restarting,
              onRestart: _restartAssessment,
              onStart: () async {
                try {
                  await AuthService.instance.ensureExploreSession();
                  if (!mounted) return;
                  await Navigator.of(context).pushNamed('/assessment');
                  _loadMajorCards();
                } on ApiRequestException catch (error) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('启动测评失败，请稍后重试')),
                  );
                }
              },
            ),
            const SizedBox(height: 20),
            _HomeTabs(
              showPersona: _showPersona,
              onChanged: (showPersona) => setState(() => _showPersona = showPersona),
            ),
            const SizedBox(height: 18),
            if (_loading) const LinearProgressIndicator(minHeight: 2, color: Colors.black),
            if (_loading) const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _showPersona
                  ? const _PersonaPreview(key: ValueKey('persona'))
                  : _PopularMajorList(
                      key: const ValueKey('majors'),
                      cards: _majorCards,
                      onTap: _openMajor,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.onStart,
    required this.onRestart,
    required this.completedStages,
    required this.hasStarted,
    required this.restarting,
  });

  final Future<void> Function() onStart;
  final Future<void> Function() onRestart;
  final int completedStages;
  final bool hasStarted;
  final bool restarting;

  static const _stageCopy = <String, _HomeHeroCopy>{
    'interest': _HomeHeroCopy(
      title: '兴趣探索测评',
      subtitle: '从学科、活动和兴趣中找到专业方向线索',
      stageText: '探索开始',
    ),
    'personality': _HomeHeroCopy(
      title: '性格测评',
      subtitle: '判断更自然的协作、计划、原则和表达方式',
      stageText: '性格测评进行中',
    ),
    'thinking_ability': _HomeHeroCopy(
      title: '思维方式 & 能力',
      subtitle: '把表达、公式、抽象、实验和现场耐受转成学习任务匹配',
      stageText: '思维能力进行中',
    ),
    'values': _HomeHeroCopy(
      title: '偏好 & 价值观',
      subtitle: '识别自主、稳定、回报和意义边界的长期偏好',
      stageText: '价值偏好进行中',
    ),
    'future_requirements': _HomeHeroCopy(
      title: '对未来的要求',
      subtitle: '从时间、空间、收入机会和反馈形式反推现实适配',
      stageText: '未来要求进行中',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final stageIndex = completedStages < 0
        ? 0
        : (completedStages > AssessmentBank.stages.length ? AssessmentBank.stages.length : completedStages);
    final isComplete = stageIndex == AssessmentBank.stages.length;
    final activeStage = isComplete ? AssessmentBank.stages.last : AssessmentBank.stages[stageIndex];
    final copy = _stageCopy[activeStage.id] ?? _stageCopy['interest']!;
    final imageBlur = (7.0 - stageIndex * 1.4).clamp(0.0, 7.0).toDouble();
    final imageOpacity = (0.48 + stageIndex * 0.104).clamp(0.0, 1.0).toDouble();
    final title = isComplete ? '测评完成' : copy.title;
    final subtitle = isComplete ? '你的专业方向已生成' : hasStarted ? copy.subtitle : '找到真正适合你的专业方向';
    final buttonLabel = isComplete ? '查看结果' : hasStarted ? '继续' : '开始探索';
    final stageLabel = isComplete
        ? '阶段五：结果揭晓'
        : !hasStarted
            ? '阶段一：探索未开始'
            : '阶段 ${stageIndex + 1}：${copy.stageText}';
    return SizedBox(
      height: 195,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(_HomePageState._heroBackground, fit: BoxFit.cover),
            Positioned(
              right: -8,
              top: 18,
              width: 155,
              height: 145,
              child: Opacity(
                opacity: imageOpacity,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: imageBlur, sigmaY: imageBlur),
                  child: Image.network(
                    _HomePageState._heroVisual,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 22, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: 150,
                    child: Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.35, color: Color(0x99000000)),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 37,
                        child: FilledButton(
                          onPressed: () => unawaited(onStart()),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            backgroundColor: Colors.black,
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          child: Text(buttonLabel),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 37,
                        child: OutlinedButton(
                          onPressed: restarting ? null : () => unawaited(onRestart()),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 13),
                            foregroundColor: Colors.black,
                            side: const BorderSide(color: Colors.black, width: 1),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          child: Text(restarting ? '重置中' : '重来'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Text(stageLabel, style: const TextStyle(fontSize: 12, color: Color(0xFF222222))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeroCopy {
  const _HomeHeroCopy({
    required this.title,
    required this.subtitle,
    required this.stageText,
  });

  final String title;
  final String subtitle;
  final String stageText;
}

class _HomeTabs extends StatelessWidget {
  const _HomeTabs({required this.showPersona, required this.onChanged});

  final bool showPersona;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HomeTab(label: '热门专业推荐', active: !showPersona, onPressed: () => onChanged(false)),
        const SizedBox(width: 8),
        _HomeTab(label: '我的人格画像', active: showPersona, onPressed: () => onChanged(true)),
      ],
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.label, required this.active, required this.onPressed});

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          side: BorderSide(color: active ? Colors.black : const Color(0xFF111111)),
          foregroundColor: active ? Colors.white : Colors.black,
          backgroundColor: active ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500),
        ),
        child: Text(label),
      ),
    );
  }
}

class _PopularMajorList extends StatelessWidget {
  const _PopularMajorList({super.key, required this.cards, required this.onTap});

  final List<HomeMajorCard> cards;
  final ValueChanged<HomeMajorCard> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final card in cards) ...[
          _PopularMajorCard(card: card, onTap: () => onTap(card)),
          if (card != cards.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _PopularMajorCard extends StatelessWidget {
  const _PopularMajorCard({required this.card, required this.onTap});

  final HomeMajorCard card;
  final VoidCallback onTap;

  String? get _imageUrl {
    final path = card.iconPath;
    if (path == null || path.isEmpty) return null;
    return path.startsWith('http') ? path : 'https://assets.uniprism.cn$path';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2.5,
      shadowColor: Colors.black.withOpacity(0.16),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 123,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    colors: card.locked
                        ? const [Color(0xFFF0F0F0), Color(0xFFF7F7F7)]
                        : const [Color(0xFF2AA5AB), Color(0xFF8DE5BF)],
                  ),
                ),
                child: card.locked
                    ? const Center(child: _LockBadge())
                    : _UnlockedMajorVisual(name: card.name ?? '', imageUrl: _imageUrl),
              ),
              const SizedBox(height: 10),
              // The stars describe this major, so keep them next to its
              // title rather than anchoring them to the far side of the card.
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    card.locked ? '待解锁TOP${card.rank}' : '${card.name ?? '专业'} TOP${card.rank}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF333333)),
                  ),
                  Text(
                    List<String>.filled(
                      card.starCount < 1 ? 1 : (card.starCount > 5 ? 5 : card.starCount),
                      '★',
                    ).join(),
                    style: const TextStyle(color: Color(0xFFFFA000), fontSize: 17, height: 1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockBadge extends StatelessWidget {
  const _LockBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: const BoxDecoration(color: Color(0xFFF0F0F0), shape: BoxShape.circle),
      child: const Icon(Icons.lock, color: Colors.black, size: 25),
    );
  }
}

class _UnlockedMajorVisual extends StatelessWidget {
  const _UnlockedMajorVisual({required this.name, required this.imageUrl});

  final String name;
  final String? imageUrl;

  static const _overlayUrl =
      'https://assets.uniprism.cn/images/explore/discover/figma/home-interest-20260624/popular-overlay-current.png';

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: 0.42,
          child: Image.network(
            _overlayUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.expand(),
          ),
        ),
        Center(
          child: Container(
            width: 86,
            height: 79,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: const Color(0xFF105652).withOpacity(0.14), blurRadius: 10, offset: const Offset(0, 5))],
            ),
            child: imageUrl == null
                ? _fallback()
                : Image.network(
                    imageUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _fallback(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _fallback() => Center(
        child: Text(
          name.isEmpty ? '专业' : name.substring(0, 1),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF6B23FF)),
        ),
      );
}

class _PersonaPreview extends StatelessWidget {
  const _PersonaPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SizedBox(
              width: 250,
              height: 320,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.rotate(angle: 0.14, child: const _PersonaCard(offset: true)),
                  const _PersonaCard(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text('完成所有测试即可解锁', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('待解锁……', style: TextStyle(fontSize: 14, color: Color(0xFF888888))),
        ],
      ),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({this.offset = false});

  final bool offset;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(offset ? 22 : 0, offset ? 7 : 0),
      child: Container(
        width: 210,
        height: 284,
        decoration: BoxDecoration(
          color: const Color(0xFF03111B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFB98521), width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.17), blurRadius: 12, offset: const Offset(0, 8))],
        ),
        child: offset
            ? const SizedBox.shrink()
            : Column(
                children: [
                  const SizedBox(height: 14),
                  const Text('万有棱镜', style: TextStyle(color: Color(0xFFBA8A28), fontSize: 10, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(color: Color(0xFFD9EFD8), shape: BoxShape.circle),
                    child: const Icon(Icons.person, color: Color(0xFF03111B), size: 53),
                  ),
                  const Spacer(),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.6)),
        ),
      ),
    );
  }
}

enum IntroType { interest, major }

class IntroSlide {
  const IntroSlide({required this.imageUrl, required this.text});

  final String imageUrl;
  final String text;
}

class IntroConfig {
  const IntroConfig({
    required this.type,
    required this.navTitle,
    required this.sectionTitle,
    required this.primaryLabel,
    required this.theme,
    required this.slides,
  });

  final IntroType type;
  final String navTitle;
  final String sectionTitle;
  final String primaryLabel;
  final IntroTheme theme;
  final List<IntroSlide> slides;

  static const interest = IntroConfig(
    type: IntroType.interest,
    navTitle: '兴趣探索',
    sectionTitle: '兴趣探索',
    primaryLabel: '开始兴趣探索',
    theme: IntroTheme.interest,
    slides: [
      IntroSlide(
        imageUrl: 'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/interest-stage-01.png',
        text: '从你的兴趣线索与思考方式出发，开启专业方向的初步探索',
      ),
      IntroSlide(
        imageUrl: 'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260705-pure/exact/interest-stage-02.png',
        text: '我们从你的兴趣爱好入手，一步步发掘你的天赋与热爱',
      ),
      IntroSlide(
        imageUrl: 'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260705-pure/exact/interest-stage-03.png',
        text: '在这个过程中，你会看到更清晰的自我不断浮现',
      ),
      IntroSlide(
        imageUrl: 'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/interest-stage-04b.png',
        text: '除了你的能力，我们也考虑你的需求和偏好；为你精准匹配',
      ),
      IntroSlide(
        imageUrl: 'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260705-pure/exact/interest-stage-05.png',
        text: '最终系统会为你提供推荐专业 Top 5，以及一份详细的人格报告',
      ),
    ],
  );

  static const major = IntroConfig(
    type: IntroType.major,
    navTitle: '专业体验',
    sectionTitle: '专业体验',
    primaryLabel: '下一步',
    theme: IntroTheme.major,
    slides: [
      IntroSlide(
        imageUrl: 'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/pro-stage-extra.png',
        text: '走近不同专业的学习场景，感受它们是否与你的期待相契合',
      ),
      IntroSlide(
        imageUrl: 'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/pro-stage-02.png',
        text: '先看看这个专业都学什么，能做什么；是不是你喜欢的类型',
      ),
      IntroSlide(
        imageUrl: 'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/pro-stage-03.png',
        text: '通过实际的课程介绍，看看这些内容你是否适应',
      ),
      IntroSlide(
        imageUrl: 'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/pro-stage-04b.png',
        text: '同一个专业，不同的发展道路；哪一条是你的 Top 1？',
      ),
      IntroSlide(
        imageUrl: 'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/pro-stage-05.png',
        text: '最后，代入这个专业最真实的工作场景；提前看到若干年后的自己',
      ),
    ],
  );
}

class IntroTheme {
  const IntroTheme({
    required this.accent,
    required this.overlayColor,
    required this.timelineSoft,
    required this.mutedButton,
    required this.activeButton,
    required this.activeShadow,
  });

  final Color accent;
  final Color overlayColor;
  final Color timelineSoft;
  final Color mutedButton;
  final Color activeButton;
  final Color activeShadow;

  static const interest = IntroTheme(
    accent: Color(0xFF7A2BFF),
    overlayColor: Color(0xFF9762FF),
    timelineSoft: Color(0xFFC9AEFF),
    mutedButton: Color(0xFFC9B3F7),
    activeButton: Color(0xFF6B23FF),
    activeShadow: Color(0xFF3D0AA8),
  );

  static const major = IntroTheme(
    accent: Color(0xFF2B8CFF),
    overlayColor: Color(0xFF319AFF),
    timelineSoft: Color(0xFF9CCCFF),
    mutedButton: Color(0xFFB8D9FF),
    activeButton: Color(0xFF2B8CFF),
    activeShadow: Color(0xFF1670D8),
  );
}

double _clamp(num value, num min, num max) => value.clamp(min, max).toDouble();
