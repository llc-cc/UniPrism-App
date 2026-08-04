import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reactive_mind_map/reactive_mind_map.dart';

part 'app_config.dart';
part 'agent_experience.dart';
part 'assessment.dart';
part 'compliance.dart';
part 'content_ingestion_preview.dart';
part 'content_source_test.dart';
part 'github_content_source_test.dart';
part 'knowledge_forest.dart';
part 'knowledge_models.dart';
part 'knowledge_service.dart';
part 'unified_content_answer_test.dart';
part 'login.dart';
part 'notification_center.dart';
part 'professional_experience.dart';
part 'report_backend.dart';
part 'report_notification.dart';
part 'responsive_layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
  await ReportNotificationService.instance.initialize();
  await AuthService.instance.restore();
  await ComplianceService.instance.restore();
  await AppMessageCenter.instance.restore();
  // 恢复上次退出 App 时尚未完成的后台采集任务。
  await ContentAcquisitionMonitor.instance.initialize();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  runApp(const UniPrismApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ReportNotificationService.instance.handlePendingLaunch();
  });
}

class UniPrismApp extends StatelessWidget {
  const UniPrismApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
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
        '/': (_) => const ComplianceGate(),
        '/intro/interest': (_) =>
            const ModuleIntroPage(config: IntroConfig.interest),
        '/intro/major': (_) => const ModuleIntroPage(config: IntroConfig.major),
        '/basic-profile': (_) => const BasicProfilePage(),
        '/login': (_) => const AppLoginPage(),
        '/assessment': (_) => const AssessmentPage(),
        '/agent': (_) => const AgentExperiencePage(),
        '/agent-subscriptions': (_) => const AgentSubscriptionsPage(),
        '/reports': (_) => const ReportCenterPage(),
        '/home': (_) => const ComplianceGate(),
        '/messages': (_) => const ComplianceGate(initialIndex: 2),
        '/terms': (_) => const LegalDocumentPage(type: LegalDocumentType.terms),
        '/privacy': (_) =>
            const LegalDocumentPage(type: LegalDocumentType.privacy),
        '/help-feedback': (_) => const HelpAndFeedbackPage(),
        '/about': (_) => const AboutAndFilingPage(),
        '/account-security': (_) => const AccountSecurityPage(),
        if (AppConfig.developerToolsEnabled) ...{
          '/content-source-test': (_) => const ZhihuContentTestPage(),
          '/github-content-source-test': (_) => const GitHubContentTestPage(),
          '/content-ingestion-preview': (_) =>
              const ContentIngestionPreviewPage(),
          '/unified-content-answer-test': (_) =>
              const UnifiedContentAnswerTestPage(),
          '/landscape-test': (_) => const LandscapeTestPage(),
          '/report-notification-demo': (_) => const ReportGenerationDemoPage(),
        },
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
  const ApiRequestException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  static final instance = AuthService._();
  static String get _baseUrl => AppConfig.apiBaseUrl;
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
  Future<String>? _exploreSessionRequest;

  bool get isLoggedIn => (_token ?? '').isNotEmpty;
  String? get token => _token;
  String? get exploreSessionId => _exploreSessionId;
  String get agentChatStorageScope {
    final userId = _user?['id']?.toString().trim() ?? '';
    if (isLoggedIn && userId.isNotEmpty) return 'user:$userId';

    final anonymousId = (_anonymousId ?? '').trim();
    if (anonymousId.isNotEmpty) return 'guest:$anonymousId';

    final sessionId = (_exploreSessionId ?? '').trim();
    if (sessionId.isNotEmpty) return 'guest-session:$sessionId';

    return 'guest-device';
  }

  String get displayName {
    final user = _user;
    if (user == null) return '';
    return '${user['name'] ?? user['wechatNickname'] ?? user['phone'] ?? ''}'
        .trim();
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
    await _request(
      'POST',
      '/api/miniapp/auth/sms/send',
      body: {'phone': phone},
    );
  }

  Future<String?> sendSmsCodeWithDevCode(String phone) async {
    final data = await _request(
      'POST',
      '/api/miniapp/auth/sms/send',
      body: {'phone': phone},
    );
    return data['devCode']?.toString();
  }

  Future<void> loginWithPhone(String phone, String code) async {
    final data = await _request(
      'POST',
      '/api/miniapp/auth/sms/login',
      body: {'phone': phone, 'code': code},
    );
    await _completeLogin(data);
  }

  Future<void> loginWithPassword(String account, String password) async {
    if (!AppConfig.passwordLoginEnabled) {
      throw const ApiRequestException('账号密码登录尚未接入服务端');
    }
    final data = await _request(
      'POST',
      AppConfig.passwordLoginPath,
      body: {'account': account, 'password': password},
    );
    await _completeLogin(data);
  }

  /// Refreshes the locally restored user with the existing backend endpoint.
  /// Only an explicit 401 clears local auth; temporary network failures keep
  /// the cached session so offline startup does not log the user out.
  Future<bool> validateCurrentSession() async {
    if (!isLoggedIn) return false;
    try {
      final data = await _request('GET', '/api/miniapp/auth/me');
      final user = _map(data['user']);
      if (user == null) {
        throw const ApiRequestException('用户资料响应不完整，请稍后重试');
      }
      _user = user;
      await _writeStorage({_userKey: jsonEncode(user)});
      return true;
    } on ApiRequestException catch (error) {
      if (error.statusCode == HttpStatus.unauthorized) {
        await logout();
        return false;
      }
      rethrow;
    }
  }

  Future<void> _completeLogin(Map<String, dynamic> data) async {
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

  Future<void> logout() async {
    final pendingSessionRequest = _exploreSessionRequest;
    if (pendingSessionRequest != null) {
      try {
        await pendingSessionRequest;
      } catch (_) {
        // Logout must still complete if a background session request failed.
      }
    }
    _token = null;
    _user = null;
    _anonymousId = null;
    _anonymousCookie = null;
    _exploreSessionId = null;
    _exploreSessionRequest = null;
    await _writeStorage({
      _tokenKey: null,
      _userKey: null,
      _anonymousIdKey: null,
      _anonymousCookieKey: null,
      _exploreSessionIdKey: null,
    });
  }

  Future<String> ensureExploreSession({bool forceNew = false}) async {
    final existing = _exploreSessionId;
    if (!forceNew && existing != null && existing.isNotEmpty) return existing;

    final pending = _exploreSessionRequest;
    if (pending != null) return pending;

    final request = _createExploreSession();
    _exploreSessionRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_exploreSessionRequest, request)) {
        _exploreSessionRequest = null;
      }
    }
  }

  Future<String> _createExploreSession() async {
    final session = await _request(
      'POST',
      // Assessment routes are shared with the web client. The production
      // deployment still authenticates these routes with the signed anonymous
      // cookie, even when a mini-app bearer token is present. Keep assessment
      // sessions anonymous here, then bind them to the user only when a full
      // report is requested.
      '/api/explore/session',
      body: {if ((_anonymousId ?? '').isNotEmpty) 'anonymousId': _anonymousId},
    );
    final sessionId = session['sessionId']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      throw const ApiRequestException('无法创建探索会话，请重试');
    }
    final returnedAnonymousId = session['anonymousId']?.toString();
    if (returnedAnonymousId != null && returnedAnonymousId.isNotEmpty) {
      _anonymousId = returnedAnonymousId;
    }
    _exploreSessionId = sessionId;
    await _writeStorage({
      _exploreSessionIdKey: sessionId,
      if (returnedAnonymousId != null && returnedAnonymousId.isNotEmpty)
        _anonymousIdKey: returnedAnonymousId,
    });
    return sessionId;
  }

  Future<String> bindExploreSessionToCurrentUser() async {
    if (!isLoggedIn) {
      throw const ApiRequestException(
        '请先登录后再生成完整报告',
        statusCode: HttpStatus.unauthorized,
      );
    }
    final currentSessionId = await ensureExploreSession();
    final session = await _request(
      'POST',
      '/api/miniapp/explore/session',
      body: {if ((_anonymousId ?? '').isNotEmpty) 'anonymousId': _anonymousId},
    );
    final sessionId = session['sessionId']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      throw const ApiRequestException('无法绑定探索会话，请重试');
    }
    if (sessionId != currentSessionId) {
      _exploreSessionId = sessionId;
      await _writeStorage({_exploreSessionIdKey: sessionId});
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

    final clarity = status == 'status-checking' || status == 'status-late'
        ? 'clarity-area'
        : 'clarity-none';
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

  Future<List<HomeMajorCard>> loadHomePopularMajors({
    List<Map<String, dynamic>>? answers,
  }) async {
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
        .map(
          (value) => HomeMajorCard.fromJson(_map(value) ?? <String, dynamic>{}),
        )
        .toList();
    return cards.isEmpty ? HomeMajorCard.lockedCards : cards;
  }

  Future<List<Map<String, dynamic>>> loadAssessmentAnswers() async {
    final sessionId = _exploreSessionId;
    if (sessionId == null || sessionId.isEmpty) return <Map<String, dynamic>>[];
    Map<String, dynamic> data;
    try {
      data = await _request(
        'GET',
        '/api/explore/discover/answers?sessionId=$sessionId',
      );
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
          '${answer['questionId']}':
              _map(answer['value']) ?? <String, dynamic>{},
    };
    Future<Map<String, dynamic>> requestPreview() => _request(
      'POST',
      '/api/interest-v020/stage-preview',
      body: {'sessionId': sessionId, 'stageId': stageId, 'answers': answerMap},
    );
    try {
      return await requestPreview();
    } on ApiRequestException catch (error) {
      if (!_shouldRefreshSession(error)) rethrow;
      sessionId = await ensureExploreSession(forceNew: true);
      return requestPreview();
    }
  }

  /// Persists the final five-stage score and marks the exploration session as
  /// completed. This is the same v0.2 endpoint used by the web and mini app.
  Future<Map<String, dynamic>> completeAssessment(
    List<Map<String, dynamic>> answers,
  ) async {
    var sessionId = await ensureExploreSession();
    final answerMap = <String, dynamic>{};
    for (final answer in answers) {
      final questionId = answer['questionId']?.toString();
      final value = _map(answer['value']);
      if (questionId == null || questionId.isEmpty || value == null) continue;
      answerMap[questionId] = _normalizeAssessmentValue(value);
    }
    Future<Map<String, dynamic>> requestScore() => _request(
      'POST',
      '/api/interest-v020/score',
      body: {'sessionId': sessionId, 'answers': answerMap},
      timeout: const Duration(seconds: 60),
    );
    try {
      return await requestScore();
    } on ApiRequestException catch (error) {
      if (!_shouldRefreshSession(error)) rethrow;
      sessionId = await ensureExploreSession(forceNew: true);
      return requestScore();
    }
  }

  Future<PersonaCardSnapshot> loadPersonaCard() async {
    var sessionId = await ensureExploreSession();
    Future<Map<String, dynamic>> requestPersonaCard() => _request(
      'GET',
      '/api/interest-v020/persona-card?sessionId=${Uri.encodeQueryComponent(sessionId)}',
    );
    Map<String, dynamic> data;
    try {
      data = await requestPersonaCard();
    } on ApiRequestException catch (error) {
      if (!_shouldRefreshSession(error)) rethrow;
      sessionId = await ensureExploreSession(forceNew: true);
      data = await requestPersonaCard();
    }
    return PersonaCardSnapshot.fromJson(data);
  }

  String resolveAssetUrl(String? path) {
    final value = path?.trim() ?? '';
    if (value.isEmpty) return '';
    final uri = Uri.tryParse(value);
    if (uri?.hasScheme == true) return value;
    return '$_baseUrl${value.startsWith('/') ? value : '/$value'}';
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final isMiniAppPath = path.startsWith('/api/miniapp/');
      final request = await _httpClient.openUrl(
        method,
        Uri.parse('$_baseUrl$path'),
      );
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        ContentType.json.mimeType,
      );
      request.headers.set('Origin', _baseUrl);
      // The existing v0.2 web routes deliberately accept the mini-app JWT and
      // anonymous identity when this compatibility header is present. Keep it
      // on every request until feature/app-support exposes APP-specific routes.
      request.headers.set('x-miniapp-client', 'uniprism-weapp');
      if ((_token ?? '').isNotEmpty)
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      if ((_anonymousId ?? '').isNotEmpty) {
        request.headers.set('x-anonymous-id', _anonymousId!);
      }
      if (!isMiniAppPath && (_anonymousCookie ?? '').isNotEmpty) {
        final separator = _anonymousCookie!.indexOf('=');
        if (separator > 0) {
          request.cookies.add(
            Cookie(
              _anonymousCookie!.substring(0, separator),
              _anonymousCookie!.substring(separator + 1),
            ),
          );
        }
      }
      if (body != null) request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(timeout);
      for (final cookie in response.cookies) {
        if (cookie.name == 'uniprism_anonymous') {
          await _storeAnonymousCookie('${cookie.name}=${cookie.value}');
        }
      }
      final responseText = await utf8.decodeStream(response);
      dynamic decoded;
      try {
        decoded = responseText.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(responseText);
      } catch (_) {
        throw const ApiRequestException('服务器返回了无法识别的数据');
      }
      final envelope = _map(decoded) ?? <String, dynamic>{};
      final data = _map(envelope['data']) ?? envelope;
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          envelope['ok'] == false) {
        final error = _map(envelope['error']);
        throw ApiRequestException(
          _errorMessage(envelope),
          code: error?['code']?.toString(),
          statusCode: response.statusCode,
        );
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
      return (await _storageChannel.invokeMapMethod<String, dynamic>('read')) ??
          <String, dynamic>{};
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
    final rawError = response['error'];
    final error = _map(rawError);
    return '${error?['message'] ?? response['message'] ?? (rawError is String ? rawError : null) ?? response['msg'] ?? '请求失败，请稍后重试'}';
  }

  static Map<String, dynamic> _normalizeAssessmentValue(
    Map<String, dynamic> value,
  ) {
    final kind = value['questionKind']?.toString();
    return {
      'questionKind': kind == 'scaleGrid' || kind == 'scale'
          ? 'scale-grid'
          : kind,
      if (value['answerMode'] != null) 'answerMode': value['answerMode'],
      if (value['selectedOptionId'] != null)
        'selectedOptionId': value['selectedOptionId'],
      if (value['rankedOptionIds'] is List)
        'rankedOptionIds': value['rankedOptionIds'],
      if (value['ratings'] is Map) 'ratings': value['ratings'],
      if (value['text'] is String) 'text': value['text'],
    };
  }

  static bool _shouldRefreshSession(ApiRequestException error) {
    if (error.statusCode == HttpStatus.unauthorized) return true;
    final message = error.message.toLowerCase();
    return message.contains('unauthorized') ||
        message.contains('探索会话') ||
        message.contains('会话') ||
        message.contains('session');
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
    final availableWidth = math.min(size.width, AppLayout.phoneContentMaxWidth);
    final horizontal = math.max(20.0, availableWidth * 0.064);

    return Scaffold(
      body: SafeArea(
        child: AppConstrainedContent(
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
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/intro/interest'),
                      ),
                      const SizedBox(height: 16),
                      OutlineActionButton(
                        label: '登录',
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/login'),
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

  List<IntroSlide> get _visibleSlides =>
      widget.config.slides.take(_activeIndex + 1).toList();

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

    final nextRoute = widget.config.type == IntroType.interest
        ? '/intro/major'
        : '/basic-profile';
    Navigator.of(context).pushReplacementNamed(nextRoute);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final theme = widget.config.theme;
    final availableWidth = math.min(size.width, AppLayout.phoneContentMaxWidth);
    final carouselWidth = math.min(
      availableWidth * (AppLayout.isCompactWidth(context) ? 0.66 : 0.69),
      270.0,
    );
    final buttonInset = math.max(24.0, (availableWidth - 220) / 2);

    return Scaffold(
      body: Stack(
        children: [
          IntroBackdrop(theme: theme),
          SafeArea(
            child: AppConstrainedContent(
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
                      padding: EdgeInsets.symmetric(
                        horizontal: math.max(28, availableWidth * 0.12),
                      ),
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
                    padding: EdgeInsets.fromLTRB(
                      buttonInset,
                      12,
                      buttonInset,
                      32 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: PrimaryButton(
                      label: _isReady ? widget.config.primaryLabel : '下一步',
                      onPressed: _handlePrimaryAction,
                      backgroundColor: _isReady
                          ? theme.activeButton
                          : theme.mutedButton,
                      shadowColor: _isReady
                          ? theme.activeShadow
                          : Colors.transparent,
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
                  boxShadow: [
                    BoxShadow(
                      color: theme.accent.withOpacity(0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRect(
                  child: PageView.builder(
                    controller: controller,
                    itemCount: slides.length,
                    onPageChanged: onChanged,
                    itemBuilder: (context, index) =>
                        _RemoteSlideImage(slide: slides[index], theme: theme),
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
          boxShadow: [
            BoxShadow(
              color: theme.accent.withOpacity(0.1),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
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
          child: Center(
            child: CircularProgressIndicator(
              color: theme.accent,
              strokeWidth: 2,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: theme.timelineSoft,
        child: Icon(
          Icons.image_not_supported_outlined,
          color: theme.accent,
          size: 30,
        ),
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
  const TimelineItem({
    super.key,
    required this.text,
    required this.isActive,
    required this.theme,
  });

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
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 8),
          child: child,
        ),
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
      decoration: BoxDecoration(color: Colors.white),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              AppAssets.welcomeCampusBackground,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    theme.overlayColor.withOpacity(0.38),
                    theme.overlayColor.withOpacity(0),
                  ],
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
      decoration: BoxDecoration(
        color: shadowColor,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: shadowColor == Colors.transparent ? 0 : 4,
        ),
        child: SizedBox(
          height: 50,
          width: double.infinity,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              elevation: 0,
              backgroundColor: backgroundColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class OutlineActionButton extends StatelessWidget {
  const OutlineActionButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
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
      final devCode = AppConfig.showDevelopmentSmsCode
          ? await AuthService.instance.sendSmsCodeWithDevCode(_phone)
          : await (() async {
              await AuthService.instance.sendSmsCode(_phone);
              return null;
            })();
      if (!mounted) return;
      if (devCode != null && devCode.isNotEmpty) {
        _codeController.text = devCode;
        setState(() => _devCodeHint = '开发验证码：$devCode');
      }
      _startCooldown();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('验证码已发送')));
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
            child: AppConstrainedContent(
              maxWidth: AppLayout.dialogContentMaxWidth,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppLayout.pagePadding(context),
                  8,
                  AppLayout.pagePadding(context),
                  28,
                ),
                child: _view == _LoginView.landing
                    ? _buildLanding()
                    : _buildPhoneLogin(),
              ),
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
        const Icon(
          Icons.change_history_rounded,
          size: 64,
          color: Color(0xFF6B23FF),
        ),
        const SizedBox(height: 18),
        const Text(
          '万有棱镜',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF262626),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '告别专业迷茫，从容规划未来',
          style: TextStyle(fontSize: 15, color: Color(0xFF666666)),
        ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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
        const Text(
          '手机号登录',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const Text(
          '验证码登录，首次使用将自动创建账号',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
        ),
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
              onPressed: _sendingCode || _cooldown > 0 || !_isValidPhone
                  ? null
                  : _sendCode,
              child: Text(
                _cooldown > 0
                    ? '${_cooldown}s'
                    : (_sendingCode ? '发送中' : '获取验证码'),
              ),
            ),
          ),
        ),
        if (_devCodeHint.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _devCodeHint,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B23FF)),
          ),
        ],
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            _error,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFFC62828)),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: _loggingIn || !_isValidPhone || !_isValidCode
                ? null
                : _login,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6B23FF),
              disabledBackgroundColor: const Color(0xFFD7C9FF),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
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
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '我已阅读并同意',
                style: TextStyle(color: Color(0xFF777777), fontSize: 12),
              ),
              _agreementLink('《用户服务条款》', '/terms'),
              const Text(
                '和',
                style: TextStyle(color: Color(0xFF777777), fontSize: 12),
              ),
              _agreementLink('《隐私政策》', '/privacy'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _agreementLink(String label, String route) => InkWell(
    onTap: () => Navigator.of(context).pushNamed(route),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF6B23FF),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
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

  void _chooseReferralSource(String value) =>
      setState(() => _referralSource = value);

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final buttonColor = _canContinue && !_submitting
        ? const Color(0xFF6B23FF)
        : const Color(0xFFD7C9FF);

    return Scaffold(
      body: Stack(
        children: [
          const IntroBackdrop(theme: IntroTheme.interest),
          SafeArea(
            child: AppConstrainedContent(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppLayout.pagePadding(context),
                ),
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
                          if (_profileStepSubtitle(_stepIndex)
                              case final subtitle?) ...[
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
                      padding: EdgeInsets.fromLTRB(
                        AppLayout.isCompactWidth(context) ? 12 : 36,
                        16,
                        AppLayout.isCompactWidth(context) ? 12 : 36,
                        32 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: ProfilePrimaryButton(
                        label: _submitting
                            ? '保存中...'
                            : (_stepIndex == 3 ? '进入主页' : '下一步'),
                        isEnabled: _canContinue && !_submitting,
                        backgroundColor: buttonColor,
                        onPressed: _continue,
                      ),
                    ),
                  ],
                ),
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
            ProfileTextField(
              controller: _nameController,
              hintText: '请输入姓名或者昵称',
            ),
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
            ProfileTextField(
              controller: _inviteCodeController,
              hintText: '请输入您的邀请码',
            ),
          ],
        );
    }
  }
}

String _profileStepTitle(int index) =>
    index == 3 ? '（可选）您是否有对应的邀请码' : '初次见面，我们该怎么称呼你？';

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
      style: const TextStyle(
        color: Color(0xFF333333),
        fontSize: 17,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class ProfileTextField extends StatelessWidget {
  const ProfileTextField({
    super.key,
    required this.controller,
    required this.hintText,
  });

  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: 40,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF18181B),
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF9761FF), width: 1.5),
        ),
      ),
    );
  }
}

class ProfileChoiceList extends StatelessWidget {
  const ProfileChoiceList({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

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
  const ProfileChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

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
          side: BorderSide(
            color: selected ? const Color(0xFF9761FF) : Colors.transparent,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
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
    final locked = json['locked'] is bool
        ? json['locked'] as bool
        : json['majorId'] == null;
    return HomeMajorCard(
      rank: rank,
      locked: locked,
      starCount:
          int.tryParse('${json['starCount'] ?? ''}') ?? math.max(1, 6 - rank),
      majorId: json['majorId']?.toString(),
      name: json['name']?.toString(),
      iconPath: json['iconPath']?.toString(),
    );
  }

  static List<HomeMajorCard> get lockedCards => List<HomeMajorCard>.generate(
    5,
    (index) =>
        HomeMajorCard(rank: index + 1, locked: true, starCount: 5 - index),
  );
}

class PersonaCardSnapshot {
  const PersonaCardSnapshot({
    required this.state,
    this.codeTag,
    this.title,
    this.cardImagePath,
    this.avatarImagePath,
    this.summary,
    this.reportId,
  });

  factory PersonaCardSnapshot.fromJson(Map<String, dynamic> json) =>
      PersonaCardSnapshot(
        state: json['state']?.toString() ?? 'locked',
        codeTag: json['codeTag']?.toString(),
        title: json['title']?.toString(),
        cardImagePath: json['cardImagePath']?.toString(),
        avatarImagePath: json['avatarImagePath']?.toString(),
        summary: json['summary']?.toString(),
        reportId: json['reportId']?.toString(),
      );

  static const locked = PersonaCardSnapshot(state: 'locked');

  final String state;
  final String? codeTag;
  final String? title;
  final String? cardImagePath;
  final String? avatarImagePath;
  final String? summary;
  final String? reportId;

  bool get isUnlocked => state == 'ready' || state == 'completed';
  bool get hasCompletedReport =>
      state == 'completed' && (reportId?.isNotEmpty ?? false);
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 3);
  }

  @override
  void didUpdateWidget(MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _selectedIndex = widget.initialIndex.clamp(0, 3);
    }
  }

  void _selectTab(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex != 0) _selectTab(0);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            HomePage(onOpenMessages: () => _selectTab(2)),
            const ProfessionalExperiencePage(),
            const MessageCenterPage(),
            _ProfileTab(onOpenMessages: () => _selectTab(2)),
          ],
        ),
        bottomNavigationBar: AppBottomNavigationBar(
          selectedIndex: _selectedIndex,
          onSelected: _selectTab,
        ),
      ),
    );
  }
}

class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = [
    _BottomNavigationItem(
      label: '兴趣探索',
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore_rounded,
    ),
    _BottomNavigationItem(
      label: '专业体验',
      icon: Icons.school_outlined,
      selectedIcon: Icons.school_rounded,
    ),
    _BottomNavigationItem(
      label: '消息',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
    ),
    _BottomNavigationItem(
      label: '我的',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompactWidth(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFECEAF0), width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(top: compact ? 5 : 7, bottom: 3),
        child: SizedBox(
          height: compact ? 51 : 55,
          child: AnimatedBuilder(
            animation: AppMessageCenter.instance,
            builder: (context, _) => Row(
              children: List.generate(_items.length, (index) {
                final item = _items[index];
                return Expanded(
                  child: _BottomNavigationButton(
                    key: ValueKey('main-tab-$index'),
                    item: item,
                    selected: selectedIndex == index,
                    unreadCount: index == 2
                        ? AppMessageCenter.instance.unreadCount
                        : 0,
                    compact: compact,
                    onTap: () => onSelected(index),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavigationItem {
  const _BottomNavigationItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _BottomNavigationButton extends StatelessWidget {
  const _BottomNavigationButton({
    super.key,
    required this.item,
    required this.selected,
    required this.unreadCount,
    required this.compact,
    required this.onTap,
  });

  final _BottomNavigationItem item;
  final bool selected;
  final int unreadCount;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF6B23FF);
    const inactiveColor = Color(0xFF8A8790);
    final color = selected ? activeColor : inactiveColor;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      selected ? item.selectedIcon : item.icon,
                      key: ValueKey(selected),
                      size: compact ? 22 : 24,
                      color: color,
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: -10,
                      top: -7,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF426F),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: compact ? 2 : 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: compact ? 10 : 11,
                    height: 1,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({required this.onOpenMessages});

  final VoidCallback onOpenMessages;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  bool _validatingSession = false;

  @override
  void initState() {
    super.initState();
    if (AuthService.instance.isLoggedIn) {
      _validatingSession = true;
      unawaited(_validateSession());
    }
  }

  Future<void> _validateSession() async {
    try {
      await AuthService.instance.validateCurrentSession();
    } on ApiRequestException {
      // Keep the locally restored session during temporary network failures.
    } finally {
      if (mounted) setState(() => _validatingSession = false);
    }
  }

  Future<void> _openLogin() async {
    await openAppLogin(context);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final name = auth.displayName;
    final horizontalPadding = AppLayout.pagePadding(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6FA),
      appBar: AppBar(
        title: const Text('我的'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF7F6FA),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppConstrainedContent(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            12,
            horizontalPadding,
            28,
          ),
          children: [
            if (_validatingSession) ...[
              const LinearProgressIndicator(
                minHeight: 2,
                color: Color(0xFF6B23FF),
              ),
              const SizedBox(height: 10),
            ],
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEDE4FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF6B23FF),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? '登录万有棱镜' : name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          auth.isLoggedIn ? '继续探索你的专业方向' : '登录后同步测评进度与报告',
                          style: const TextStyle(
                            color: Color(0xFF8A8790),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!auth.isLoggedIn)
                    FilledButton(
                      onPressed: _openLogin,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6B23FF),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('登录'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ProfileMenuCard(
              children: [
                _ProfileMenuItem(
                  icon: Icons.notifications_none_rounded,
                  label: '消息通知',
                  onTap: widget.onOpenMessages,
                ),
                _ProfileMenuItem(
                  icon: Icons.auto_awesome_outlined,
                  label: '我的测评报告',
                  onTap: () => Navigator.of(context).pushNamed('/reports'),
                ),
                _ProfileMenuItem(
                  icon: Icons.description_outlined,
                  label: '用户服务条款',
                  onTap: () => Navigator.of(context).pushNamed('/terms'),
                ),
                _ProfileMenuItem(
                  icon: Icons.privacy_tip_outlined,
                  label: '隐私政策',
                  onTap: () => Navigator.of(context).pushNamed('/privacy'),
                ),
                _ProfileMenuItem(
                  icon: Icons.security_rounded,
                  label: '账号与安全',
                  onTap: () =>
                      Navigator.of(context).pushNamed('/account-security'),
                ),
                _ProfileMenuItem(
                  icon: Icons.support_agent_rounded,
                  label: '帮助与反馈',
                  onTap: () =>
                      Navigator.of(context).pushNamed('/help-feedback'),
                ),
                _ProfileMenuItem(
                  icon: Icons.info_outline_rounded,
                  label: '关于万有棱镜',
                  onTap: () => Navigator.of(context).pushNamed('/about'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuCard extends StatelessWidget {
  const _ProfileMenuCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1)
            const Divider(height: 1, indent: 54, color: Color(0xFFF0EEF3)),
        ],
      ],
    ),
  );
}

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: Icon(icon, color: const Color(0xFF6B23FF)),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFB2AEB8)),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onOpenMessages});

  final VoidCallback? onOpenMessages;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<HomeMajorCard> _majorCards = HomeMajorCard.lockedCards;
  PersonaCardSnapshot _personaCard = PersonaCardSnapshot.locked;
  List<String> _agentInterestTags = const [];
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

  void _openZhihuContentTest() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ZhihuContentTestPage(
          recommendedMajors: _currentRecommendedMajorNames,
        ),
      ),
    );
  }

  List<String> get _currentRecommendedMajorNames => _majorCards
      .where((card) => !card.locked)
      .map((card) => card.name?.trim() ?? '')
      .where((name) => name.isNotEmpty)
      .toSet()
      .take(5)
      .toList(growable: false);

  List<String> _buildAgentInterestTags(
    Map<String, Map<String, dynamic>> answers,
    PersonaCardSnapshot persona,
  ) {
    final tags = <String>[];
    final personaTitle = persona.title?.trim() ?? '';
    final personaCode = persona.codeTag?.trim() ?? '';
    if (personaTitle.isNotEmpty) tags.add(personaTitle);
    if (personaCode.isNotEmpty) tags.add(personaCode);

    for (final question in AssessmentBank.questionsFor('interest')) {
      final value = answers[question.id];
      if (value == null) continue;
      final optionIds = <String>[
        if ('${value['selectedOptionId'] ?? ''}'.isNotEmpty)
          '${value['selectedOptionId']}',
        if (value['rankedOptionIds'] is List)
          ...(value['rankedOptionIds'] as List).map((item) => '$item'),
      ];
      for (final optionId in optionIds) {
        for (final option in question.options) {
          if (option.id == optionId) {
            tags.add(option.label);
            break;
          }
        }
      }
      final customText = '${value['text'] ?? ''}'.trim();
      if (customText.isNotEmpty) tags.add(customText);
    }

    return tags
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((item) => item.length <= 40 ? item : item.substring(0, 40))
        .toSet()
        .take(10)
        .toList(growable: false);
  }

  void _openGitHubContentTest() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GitHubContentTestPage(
          recommendedMajors: _currentRecommendedMajorNames,
        ),
      ),
    );
  }

  /// 打开 Agent，并传入只用于回答个性化的用户画像。
  void _openAgent() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AgentExperiencePage(
          recommendedMajors: _currentRecommendedMajorNames,
          interests: _agentInterestTags,
        ),
      ),
    );
  }

  /// 入库预览仅在开发工具开启时可进入。
  void _openContentIngestionPreview() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ContentIngestionPreviewPage()),
    );
  }

  void _openUnifiedContentAnswerTest() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UnifiedContentAnswerTestPage(
          recommendedMajors: _currentRecommendedMajorNames,
          interests: _agentInterestTags,
        ),
      ),
    );
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
        if (questionId != null && value is Map) {
          answerMap[questionId] = Map<String, dynamic>.from(value);
        }
      }
      final completedStages = AssessmentBank.stages.where((stage) {
        final questions = AssessmentBank.questionsFor(stage.id);
        return questions.every(
          (question) =>
              _isAssessmentAnswerComplete(question, answerMap[question.id]),
        );
      }).length;
      final cards = await AuthService.instance.loadHomePopularMajors(
        answers: answers,
      );
      var personaCard = PersonaCardSnapshot.locked;
      try {
        personaCard = await AuthService.instance.loadPersonaCard();
      } on ApiRequestException {
        // Major recommendations remain usable if persona-card loading fails.
      }
      if (mounted) {
        setState(() {
          _majorCards = cards;
          _personaCard = personaCard;
          _agentInterestTags = _buildAgentInterestTags(answerMap, personaCard);
          _completedStageCount = completedStages;
          _hasStarted = answers.isNotEmpty;
        });
      }
    } catch (_) {
      // The locked state is a complete and intentional first-visit state.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restartAssessment() async {
    if (_restarting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认重来'),
        content: const Text('确定要重新开始测评吗？当前阶段的答题进度将从头计算。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重来'),
          ),
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
        _personaCard = PersonaCardSnapshot.locked;
        _agentInterestTags = const [];
        _completedStageCount = 0;
        _hasStarted = false;
      });
      await _loadMajorCards();
    } on ApiRequestException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = AppLayout.pagePadding(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        centerTitle: true,
        title: const Text(
          '兴趣探索',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          _MessageCenterButton(onPressed: widget.onOpenMessages),
          const SizedBox(width: 6),
        ],
      ),
      body: AppConstrainedContent(
        maxWidth: AppLayout.homeContentMaxWidth,
        child: RefreshIndicator(
          onRefresh: _loadMajorCards,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              18,
              horizontalPadding,
              28,
            ),
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
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.message)));
                  } catch (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('启动测评失败，请稍后重试')),
                    );
                  }
                },
              ),
              if (AppConfig.agentFeatureVisible) ...[
                const SizedBox(height: 16),
                _AgentHomeEntry(onTap: _openAgent),
              ],
              if (AppConfig.developerToolsEnabled) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openContentIngestionPreview,
                    icon: const Icon(Icons.storage_rounded),
                    label: const Text('真实内容入库预览'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: const Color(0xFF1C6B52),
                      side: const BorderSide(color: Color(0xFF7BBFA9)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openZhihuContentTest,
                    icon: const Icon(Icons.travel_explore_rounded),
                    label: const Text('推荐专业 × 知乎真实性测试'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: const Color(0xFF5420BF),
                      side: const BorderSide(color: Color(0xFFB99AFF)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openGitHubContentTest,
                    icon: const Icon(Icons.code_rounded),
                    label: const Text('推荐专业 × GitHub真实性测试'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: const Color(0xFF24292F),
                      side: const BorderSide(color: Color(0xFF8C959F)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openUnifiedContentAnswerTest,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('推荐专业 × Agent统一回答测试'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: const Color(0xFF6A52A3),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamed('/report-notification-demo'),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('报告生成通知测试'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: const Color(0xFF5420BF),
                      side: const BorderSide(color: Color(0xFFB99AFF)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/landscape-test'),
                    icon: const Icon(Icons.sports_esports_rounded),
                    label: const Text('横屏贪吃蛇'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: const Color(0xFF5420BF),
                      side: const BorderSide(color: Color(0xFFB99AFF)),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _HomeTabs(
                showPersona: _showPersona,
                onChanged: (showPersona) =>
                    setState(() => _showPersona = showPersona),
              ),
              const SizedBox(height: 18),
              if (_loading)
                const LinearProgressIndicator(
                  minHeight: 2,
                  color: Colors.black,
                ),
              if (_loading) const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _showPersona
                    ? _PersonaPreview(
                        key: const ValueKey('persona'),
                        snapshot: _personaCard,
                        onOpenReport: () =>
                            Navigator.of(context).pushNamed('/reports'),
                      )
                    : _PopularMajorList(
                        key: const ValueKey('majors'),
                        cards: _majorCards,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A route-scoped landscape mini game. Leaving it returns the app to its
/// portrait-only home experience.
class LandscapeTestPage extends StatefulWidget {
  const LandscapeTestPage({super.key});

  @override
  State<LandscapeTestPage> createState() => _LandscapeTestPageState();
}

class _LandscapeTestPageState extends State<LandscapeTestPage> {
  static const _columns = 28;
  static const _rows = 16;
  static const _tickDuration = Duration(milliseconds: 145);

  final math.Random _random = math.Random();
  final List<math.Point<int>> _snake = [];
  Timer? _timer;
  late math.Point<int> _food;
  _SnakeDirection _direction = _SnakeDirection.right;
  _SnakeDirection _pendingDirection = _SnakeDirection.right;
  int _score = 0;
  int _bestScore = 0;
  bool _paused = false;
  bool _gameOver = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _resetGame();
    _timer = Timer.periodic(_tickDuration, (_) => _moveSnake());
  }

  @override
  void dispose() {
    _timer?.cancel();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _resetGame() {
    _snake
      ..clear()
      ..addAll(const [
        math.Point<int>(8, 8),
        math.Point<int>(7, 8),
        math.Point<int>(6, 8),
        math.Point<int>(5, 8),
      ]);
    _direction = _SnakeDirection.right;
    _pendingDirection = _SnakeDirection.right;
    _score = 0;
    _paused = false;
    _gameOver = false;
    _placeFood();
  }

  void _restartGame() => setState(_resetGame);

  void _placeFood() {
    do {
      _food = math.Point<int>(
        _random.nextInt(_columns),
        _random.nextInt(_rows),
      );
    } while (_snake.contains(_food));
  }

  void _moveSnake() {
    if (!mounted || _paused || _gameOver) return;
    _direction = _pendingDirection;
    final head = _snake.first;
    final delta = switch (_direction) {
      _SnakeDirection.up => const math.Point<int>(0, -1),
      _SnakeDirection.down => const math.Point<int>(0, 1),
      _SnakeDirection.left => const math.Point<int>(-1, 0),
      _SnakeDirection.right => const math.Point<int>(1, 0),
    };
    final next = math.Point<int>(head.x + delta.x, head.y + delta.y);
    final hitWall =
        next.x < 0 || next.x >= _columns || next.y < 0 || next.y >= _rows;
    final willEat = next == _food;
    final bodyToCheck = willEat ? _snake : _snake.take(_snake.length - 1);
    if (hitWall || bodyToCheck.contains(next)) {
      setState(() {
        _gameOver = true;
        _bestScore = math.max(_bestScore, _score);
      });
      return;
    }

    setState(() {
      _snake.insert(0, next);
      if (willEat) {
        _score += 10;
        _bestScore = math.max(_bestScore, _score);
        _placeFood();
      } else {
        _snake.removeLast();
      }
    });
  }

  void _changeDirection(_SnakeDirection next) {
    if (_gameOver) return;
    final opposite = switch (_direction) {
      _SnakeDirection.up => _SnakeDirection.down,
      _SnakeDirection.down => _SnakeDirection.up,
      _SnakeDirection.left => _SnakeDirection.right,
      _SnakeDirection.right => _SnakeDirection.left,
    };
    if (next != opposite) _pendingDirection = next;
  }

  void _handleSwipe(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    if (velocity.distance < 120) return;
    if (velocity.dx.abs() > velocity.dy.abs()) {
      _changeDirection(
        velocity.dx > 0 ? _SnakeDirection.right : _SnakeDirection.left,
      );
    } else {
      _changeDirection(
        velocity.dy > 0 ? _SnakeDirection.down : _SnakeDirection.up,
      );
    }
  }

  Future<void> _leaveGame() async {
    _timer?.cancel();
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1C),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactHeight = constraints.maxHeight < 360;
            final edge = compactHeight ? 6.0 : 12.0;
            final controlWidth = (constraints.maxWidth * 0.27)
                .clamp(168.0, 210.0)
                .toDouble();
            final showHint = constraints.maxWidth >= 700;
            return AppConstrainedContent(
              maxWidth: 1200,
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.all(edge),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          SizedBox(
                            height: compactHeight ? 34 : 40,
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: '返回主页',
                                  onPressed: _leaveGame,
                                  color: Colors.white,
                                  icon: const Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    size: 19,
                                  ),
                                ),
                                const Text(
                                  '贪吃蛇',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                if (showHint)
                                  const Text(
                                    '滑动游戏区域或使用方向键',
                                    style: TextStyle(
                                      color: Color(0xFFAAA5C1),
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: compactHeight ? 4 : 8),
                          Expanded(
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: _columns / _rows,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanEnd: _handleSwipe,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        CustomPaint(
                                          painter: _SnakeBoardPainter(
                                            snake: List.unmodifiable(_snake),
                                            food: _food,
                                            columns: _columns,
                                            rows: _rows,
                                          ),
                                        ),
                                        if (_paused || _gameOver)
                                          ColoredBox(
                                            color: Colors.black.withOpacity(
                                              0.52,
                                            ),
                                            child: Center(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _gameOver ? '游戏结束' : '已暂停',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 26,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  if (_gameOver) ...[
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      '本局得分 $_score',
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFFD8D3E8,
                                                        ),
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: compactHeight ? 8 : 14),
                    SizedBox(
                      width: controlWidth,
                      child: _SnakeControlPanel(
                        score: _score,
                        bestScore: _bestScore,
                        paused: _paused,
                        gameOver: _gameOver,
                        compact: compactHeight,
                        onDirection: _changeDirection,
                        onPause: () => setState(() => _paused = !_paused),
                        onRestart: _restartGame,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _SnakeDirection { up, down, left, right }

class _SnakeControlPanel extends StatelessWidget {
  const _SnakeControlPanel({
    required this.score,
    required this.bestScore,
    required this.paused,
    required this.gameOver,
    required this.compact,
    required this.onDirection,
    required this.onPause,
    required this.onRestart,
  });

  final int score;
  final int bestScore;
  final bool paused;
  final bool gameOver;
  final bool compact;
  final ValueChanged<_SnakeDirection> onDirection;
  final VoidCallback onPause;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(compact ? 9 : 14),
    decoration: BoxDecoration(
      color: const Color(0xFF18172D),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF302D4C)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SnakeScore(label: '得分', value: score),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SnakeScore(label: '最高', value: bestScore),
            ),
          ],
        ),
        if (!compact) const Spacer(),
        _SnakeDirectionButton(
          icon: Icons.keyboard_arrow_up_rounded,
          onPressed: () => onDirection(_SnakeDirection.up),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SnakeDirectionButton(
              icon: Icons.keyboard_arrow_left_rounded,
              onPressed: () => onDirection(_SnakeDirection.left),
            ),
            const SizedBox(width: 46),
            _SnakeDirectionButton(
              icon: Icons.keyboard_arrow_right_rounded,
              onPressed: () => onDirection(_SnakeDirection.right),
            ),
          ],
        ),
        _SnakeDirectionButton(
          icon: Icons.keyboard_arrow_down_rounded,
          onPressed: () => onDirection(_SnakeDirection.down),
        ),
        if (!compact) const Spacer(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: gameOver ? null : onPause,
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 18,
                ),
                label: AppButtonLabel(paused ? '继续' : '暂停'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF716A98)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: onRestart,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6B23FF),
                ),
                child: AppButtonLabel(gameOver ? '再来' : '重开'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SnakeScore extends StatelessWidget {
  const _SnakeScore({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFF24213E),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFFAAA5C1), fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _SnakeDirectionButton extends StatelessWidget {
  const _SnakeDirectionButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 46,
    height: 42,
    child: IconButton.filled(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF302B53),
        foregroundColor: Colors.white,
        highlightColor: const Color(0xFF7A46FF),
      ),
      icon: Icon(icon, size: 27),
    ),
  );
}

class _SnakeBoardPainter extends CustomPainter {
  const _SnakeBoardPainter({
    required this.snake,
    required this.food,
    required this.columns,
    required this.rows,
  });

  final List<math.Point<int>> snake;
  final math.Point<int> food;
  final int columns;
  final int rows;

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / columns;
    final cellHeight = size.height / rows;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF121126),
    );

    final gridPaint = Paint()
      ..color = const Color(0xFF25223D)
      ..strokeWidth = 0.7;
    for (var column = 1; column < columns; column++) {
      final x = column * cellWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var row = 1; row < rows; row++) {
      final y = row * cellHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final foodCenter = Offset(
      (food.x + 0.5) * cellWidth,
      (food.y + 0.5) * cellHeight,
    );
    canvas.drawCircle(
      foodCenter,
      math.min(cellWidth, cellHeight) * 0.31,
      Paint()..color = const Color(0xFFFF5D8F),
    );
    canvas.drawCircle(
      foodCenter,
      math.min(cellWidth, cellHeight) * 0.43,
      Paint()..color = const Color(0x33FF5D8F),
    );

    for (var index = snake.length - 1; index >= 0; index--) {
      final segment = snake[index];
      final inset = index == 0 ? 1.4 : 2.0;
      final rect = Rect.fromLTWH(
        segment.x * cellWidth + inset,
        segment.y * cellHeight + inset,
        cellWidth - inset * 2,
        cellHeight - inset * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(math.min(cellWidth, cellHeight) * 0.28),
        ),
        Paint()
          ..color = index == 0
              ? const Color(0xFFB486FF)
              : Color.lerp(
                  const Color(0xFF7047E8),
                  const Color(0xFF48C9B0),
                  index / math.max(1, snake.length - 1),
                )!,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnakeBoardPainter oldDelegate) =>
      oldDelegate.snake != snake || oldDelegate.food != food;
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
        : (completedStages > AssessmentBank.stages.length
              ? AssessmentBank.stages.length
              : completedStages);
    final isComplete = stageIndex == AssessmentBank.stages.length;
    final activeStage = isComplete
        ? AssessmentBank.stages.last
        : AssessmentBank.stages[stageIndex];
    final copy = _stageCopy[activeStage.id] ?? _stageCopy['interest']!;
    final imageBlur = (7.0 - stageIndex * 1.4).clamp(0.0, 7.0).toDouble();
    final imageOpacity = (0.48 + stageIndex * 0.104).clamp(0.0, 1.0).toDouble();
    final title = isComplete ? '测评完成' : copy.title;
    final subtitle = isComplete
        ? '你的专业方向已生成'
        : hasStarted
        ? copy.subtitle
        : '找到真正适合你的专业方向';
    final buttonLabel = isComplete
        ? '查看结果'
        : hasStarted
        ? '继续'
        : '开始探索';
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
                  imageFilter: ImageFilter.blur(
                    sigmaX: imageBlur,
                    sigmaY: imageBlur,
                  ),
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
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: 150,
                    child: Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0x99000000),
                      ),
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
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(buttonLabel),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 37,
                        child: OutlinedButton(
                          onPressed: restarting
                              ? null
                              : () => unawaited(onRestart()),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 13),
                            foregroundColor: Colors.black,
                            side: const BorderSide(
                              color: Colors.black,
                              width: 1,
                            ),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(restarting ? '重置中' : '重来'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Text(
                    stageLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF222222),
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
        _HomeTab(
          label: '热门专业推荐',
          active: !showPersona,
          onPressed: () => onChanged(false),
        ),
        const SizedBox(width: 8),
        _HomeTab(
          label: '我的人格画像',
          active: showPersona,
          onPressed: () => onChanged(true),
        ),
      ],
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.label,
    required this.active,
    required this.onPressed,
  });

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
          side: BorderSide(
            color: active ? Colors.black : const Color(0xFF111111),
          ),
          foregroundColor: active ? Colors.white : Colors.black,
          backgroundColor: active ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _PopularMajorList extends StatelessWidget {
  const _PopularMajorList({super.key, required this.cards});

  final List<HomeMajorCard> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final card in cards) ...[
          PopularMajorCard(card: card),
          if (card != cards.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class PopularMajorCard extends StatelessWidget {
  const PopularMajorCard({super.key, required this.card});

  final HomeMajorCard card;

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
                  : _UnlockedMajorVisual(
                      name: card.name ?? '',
                      imageUrl: _imageUrl,
                    ),
            ),
            const SizedBox(height: 10),
            // The stars describe this major, so keep them next to its
            // title rather than anchoring them to the far side of the card.
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  card.locked
                      ? '待解锁TOP${card.rank}'
                      : '${card.name ?? '专业'} TOP${card.rank}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF333333),
                  ),
                ),
                Text(
                  List<String>.filled(
                    card.starCount < 1
                        ? 1
                        : (card.starCount > 5 ? 5 : card.starCount),
                    '★',
                  ).join(),
                  style: const TextStyle(
                    color: Color(0xFFFFA000),
                    fontSize: 17,
                    height: 1,
                  ),
                ),
              ],
            ),
          ],
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
      decoration: const BoxDecoration(
        color: Color(0xFFF0F0F0),
        shape: BoxShape.circle,
      ),
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
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF105652).withOpacity(0.14),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
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
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: Color(0xFF6B23FF),
      ),
    ),
  );
}

class _PersonaPreview extends StatelessWidget {
  const _PersonaPreview({
    super.key,
    required this.snapshot,
    required this.onOpenReport,
  });

  final PersonaCardSnapshot snapshot;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final cardImageUrl = AuthService.instance.resolveAssetUrl(
      snapshot.cardImagePath,
    );
    final unlocked = snapshot.isUnlocked;
    final lockedDeckWidth = math.min(
      MediaQuery.sizeOf(context).width - 54,
      320.0,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: unlocked && cardImageUrl.isNotEmpty
                ? SizedBox(
                    width: 250,
                    height: 320,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        cardImageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _fallbackCards(),
                      ),
                    ),
                  )
                : SizedBox(
                    width: lockedDeckWidth,
                    height: lockedDeckWidth * 1.18,
                    child: _fallbackCards(),
                  ),
          ),
          const SizedBox(height: 22),
          Text(
            unlocked ? (snapshot.title ?? '你的探索者画像') : '完成所有测试即可解锁',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            unlocked
                ? (snapshot.summary?.trim().isNotEmpty == true
                      ? snapshot.summary!
                      : '测评画像已生成，完整报告生成后可查看更详细的分析。')
                : '待解锁……',
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF888888),
            ),
          ),
          if (unlocked && (snapshot.codeTag?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 12),
            Chip(
              label: Text(snapshot.codeTag!),
              backgroundColor: const Color(0xFFEDE4FF),
              side: BorderSide.none,
              labelStyle: const TextStyle(
                color: Color(0xFF5A20C8),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (unlocked) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenReport,
                icon: const Icon(Icons.description_outlined),
                label: Text(snapshot.hasCompletedReport ? '查看完整报告' : '生成完整报告'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: const Color(0xFF6B23FF),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fallbackCards() => const LockedPersonaDeck();
}

class LockedPersonaDeck extends StatelessWidget {
  const LockedPersonaDeck({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final cardWidth = width * 0.7;
      final cardHeight = cardWidth * (317 / 238);
      final frontLeft = width * 0.075;
      final top = width * 0.025;
      final backWidth = cardWidth * 0.88;
      final backHeight = cardHeight * 0.88;

      return CustomPaint(
        painter: const _LockedPersonaDeckBackgroundPainter(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: frontLeft,
              top: top + cardHeight + width * 0.012,
              width: cardWidth,
              height: cardHeight * 0.24,
              child: _LockedPersonaReflection(cardHeight: cardHeight),
            ),
            Positioned(
              left: frontLeft + cardWidth * 0.36,
              top: top + cardHeight * 0.09,
              width: backWidth,
              height: backHeight,
              child: Transform.rotate(
                angle: 0.11,
                alignment: Alignment.topCenter,
                child: const _LockedPersonaCard(rear: true),
              ),
            ),
            Positioned(
              left: frontLeft,
              top: top,
              width: cardWidth,
              height: cardHeight,
              child: const _LockedPersonaCard(),
            ),
          ],
        ),
      );
    },
  );
}

class _LockedPersonaReflection extends StatelessWidget {
  const _LockedPersonaReflection({required this.cardHeight});

  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x70000000), Color(0x22000000), Color(0x00000000)],
        stops: [0, 0.48, 1],
      ).createShader(bounds),
      child: Opacity(
        opacity: 0.34,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: cardHeight,
            maxHeight: cardHeight,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(1, -1, 1),
              child: SizedBox(
                height: cardHeight,
                child: const CustomPaint(
                  painter: _LockedPersonaCardPainter(rear: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LockedPersonaCard extends StatelessWidget {
  const _LockedPersonaCard({this.rear = false});

  final bool rear;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: rear ? 0.12 : 0.2),
            blurRadius: rear ? 12 : 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: CustomPaint(painter: _LockedPersonaCardPainter(rear: rear)),
    );
  }
}

class _LockedPersonaDeckBackgroundPainter extends CustomPainter {
  const _LockedPersonaDeckBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..color = const Color(0xFFE9E9E9);
    final spacing = size.width * 0.025;
    final radius = math.max(0.7, size.width * 0.0032);
    for (var row = 0; row < 11; row++) {
      for (var column = 0; column < 9; column++) {
        final fade = 1 - (column / 12);
        dotPaint.color = const Color(0xFFE2E2E2).withValues(alpha: 0.64 * fade);
        canvas.drawCircle(
          Offset(
            size.width * 0.74 + column * spacing,
            size.height * 0.19 + row * spacing,
          ),
          radius,
          dotPaint,
        );
      }
    }
    for (var row = 0; row < 6; row++) {
      for (var column = 0; column < 8; column++) {
        dotPaint.color = const Color(0xFFE5E5E5).withValues(alpha: 0.42);
        canvas.drawCircle(
          Offset(
            -size.width * 0.02 + column * spacing,
            size.height * 0.76 + row * spacing,
          ),
          radius,
          dotPaint,
        );
      }
    }

    final shadowRect = Rect.fromCenter(
      center: Offset(size.width * 0.48, size.height * 0.91),
      width: size.width * 0.7,
      height: size.height * 0.085,
    );
    canvas.drawOval(
      shadowRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x3B55606A), Color(0x0055606A)],
        ).createShader(shadowRect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LockedPersonaCardPainter extends CustomPainter {
  const _LockedPersonaCardPainter({required this.rear});

  final bool rear;

  static const _surface = Color(0xFF020D16);
  static const _gold = Color(0xFFC0823C);
  static const _brightGold = Color(0xFFD79A44);
  static const _teal = Color(0xFF0F7C7E);
  static const _avatar = Color(0xFFDDEFD7);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width * 0.055;
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRRect(outer, Paint()..color = _surface);
    canvas.drawRRect(
      outer.deflate(size.width * 0.009),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.009
        ..color = const Color(0xFF06131C),
    );
    canvas.drawRRect(
      outer.deflate(size.width * 0.022),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.0048
        ..color = _gold,
    );
    canvas.drawRRect(
      outer.deflate(size.width * 0.038),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.004
        ..color = _teal,
    );

    final surface = Rect.fromLTWH(
      size.width * 0.084,
      size.height * 0.085,
      size.width * 0.832,
      size.height * 0.83,
    );
    canvas.drawRect(surface, Paint()..color = _surface);
    canvas.drawRect(
      surface.deflate(size.width * 0.022),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.004
        ..color = _teal.withValues(alpha: 0.84),
    );
    _drawSurfaceDetails(canvas, surface, size.width);
    _drawBrand(canvas, size);
    _drawAvatar(canvas, surface);
    if (!rear) _drawStars(canvas, surface, size.width);
  }

  void _drawSurfaceDetails(Canvas canvas, Rect rect, double width) {
    final line = Paint()
      ..color = _gold
      ..strokeWidth = math.max(1, width * 0.004)
      ..style = PaintingStyle.stroke;
    final short = width * 0.105;
    final inset = width * 0.01;
    for (final corner in <Offset>[
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      final right = corner.dx > rect.center.dx;
      final bottom = corner.dy > rect.center.dy;
      final start = Offset(
        corner.dx + (right ? -inset : inset),
        corner.dy + (bottom ? -inset : inset),
      );
      canvas.drawLine(
        start,
        Offset(start.dx + (right ? -short : short), start.dy),
        line,
      );
      canvas.drawLine(
        start,
        Offset(start.dx, start.dy + (bottom ? -short : short)),
        line,
      );
    }

    final segmentY = rect.top;
    canvas.drawLine(
      Offset(rect.left, segmentY),
      Offset(rect.left + rect.width * 0.21, segmentY),
      line,
    );
    canvas.drawLine(
      Offset(rect.left + rect.width * 0.23, segmentY),
      Offset(rect.left + rect.width * 0.41, segmentY),
      Paint()
        ..color = _teal
        ..strokeWidth = line.strokeWidth,
    );
    canvas.drawLine(
      Offset(rect.right - rect.width * 0.21, segmentY),
      Offset(rect.right, segmentY),
      line,
    );
  }

  void _drawBrand(Canvas canvas, Size size) {
    final width = size.width * 0.49;
    final height = math.max(size.height * 0.088, 22.0);
    final left = (size.width - width) / 2;
    final path = Path()
      ..moveTo(left + width * 0.12, 0)
      ..lineTo(left + width * 0.88, 0)
      ..lineTo(left + width, height / 2)
      ..lineTo(left + width * 0.88, height)
      ..lineTo(left + width * 0.12, height)
      ..lineTo(left, height / 2)
      ..close();
    canvas.drawPath(path, Paint()..color = _surface);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, size.width * 0.004)
        ..color = _gold,
    );

    final markCenter = Offset(left + width * 0.27, height * 0.51);
    canvas.save();
    canvas.translate(markCenter.dx, markCenter.dy);
    canvas.rotate(math.pi / 4);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width * 0.046,
        height: size.width * 0.046,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, size.width * 0.005)
        ..color = _brightGold,
    );
    canvas.restore();

    final painter = TextPainter(
      text: TextSpan(
        text: '万有棱镜',
        style: TextStyle(
          color: _brightGold,
          fontSize: size.width * 0.052,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(
      canvas,
      Offset(left + width * 0.38, (height - painter.height) / 2),
    );
  }

  void _drawAvatar(Canvas canvas, Rect surface) {
    final radius = surface.width * 0.218;
    final center = Offset(
      surface.center.dx,
      surface.top + surface.height * 0.53,
    );
    final avatarPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(avatarPath, Paint()..color = _avatar);
    canvas.save();
    canvas.clipPath(avatarPath);
    canvas.drawCircle(
      Offset(center.dx, center.dy - radius * 0.27),
      radius * 0.235,
      Paint()..color = _surface,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * 0.82),
        width: radius * 1.64,
        height: radius * 1.45,
      ),
      Paint()..color = _surface,
    );
    canvas.restore();
  }

  void _drawStars(Canvas canvas, Rect surface, double width) {
    final paint = Paint()..color = _gold.withValues(alpha: 0.28);
    const points = <Offset>[
      Offset(0.08, 0.24),
      Offset(0.84, 0.19),
      Offset(0.73, 0.74),
      Offset(0.18, 0.82),
      Offset(0.9, 0.56),
      Offset(0.31, 0.13),
    ];
    for (final point in points) {
      canvas.drawCircle(
        Offset(
          surface.left + surface.width * point.dx,
          surface.top + surface.height * point.dy,
        ),
        math.max(0.6, width * 0.003),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LockedPersonaCardPainter oldDelegate) =>
      oldDelegate.rear != rear;
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1.6),
          ),
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
        imageUrl:
            'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/interest-stage-01.png',
        text: '从你的兴趣线索与思考方式出发，开启专业方向的初步探索',
      ),
      IntroSlide(
        imageUrl:
            'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260705-pure/exact/interest-stage-02.png',
        text: '我们从你的兴趣爱好入手，一步步发掘你的天赋与热爱',
      ),
      IntroSlide(
        imageUrl:
            'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260705-pure/exact/interest-stage-03.png',
        text: '在这个过程中，你会看到更清晰的自我不断浮现',
      ),
      IntroSlide(
        imageUrl:
            'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/interest-stage-04b.png',
        text: '除了你的能力，我们也考虑你的需求和偏好；为你精准匹配',
      ),
      IntroSlide(
        imageUrl:
            'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260705-pure/exact/interest-stage-05.png',
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
        imageUrl:
            'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/pro-stage-extra.png',
        text: '走近不同专业的学习场景，感受它们是否与你的期待相契合',
      ),
      IntroSlide(
        imageUrl:
            'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/pro-stage-02.png',
        text: '先看看这个专业都学什么，能做什么；是不是你喜欢的类型',
      ),
      IntroSlide(
        imageUrl:
            'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/pro-stage-03.png',
        text: '通过实际的课程介绍，看看这些内容你是否适应',
      ),
      IntroSlide(
        imageUrl:
            'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/pro-stage-04b.png',
        text: '同一个专业，不同的发展道路；哪一条是你的 Top 1？',
      ),
      IntroSlide(
        imageUrl:
            'https://assets.uniprism.cn/images/explore/discover/figma/welcome-20260701/exact/pro-stage-05.png',
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
