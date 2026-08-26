part of 'main.dart';

/// 解析开发者入口安全策略：production 永久拒绝，非 production 必须显式请求。
/// release 优化只影响编译方式，不应覆盖明确的本地或开发部署环境。
bool resolveDeveloperToolsEnabled({
  required bool isProduction,
  required bool requested,
}) => !isProduction && requested;

/// Compile-time application configuration.
///
/// Production builds always disable developer-only UI, even if a caller tries
/// to enable it with a dart-define. Non-production endpoints must be supplied
/// explicitly so test and production services cannot be mixed accidentally.
abstract final class AppConfig {
  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: kReleaseMode ? 'production' : 'development',
  );
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://uniprism.cn',
  );
  static const _developerToolsRequested = bool.fromEnvironment(
    'ENABLE_DEVELOPER_TOOLS',
    defaultValue: true,
  );
  static const agentEnabled = bool.fromEnvironment(
    'AGENT_ENABLED',
    defaultValue: false,
  );
  static const practiceAssessmentRemote = bool.fromEnvironment(
    'PRACTICE_ASSESSMENT_REMOTE',
    defaultValue: false,
  );
  static const spokenFormulaAsrMode = String.fromEnvironment(
    'SPOKEN_FORMULA_ASR_MODE',
    defaultValue: 'browser',
  );
  static const senseVoiceBaseUrl = String.fromEnvironment(
    'SENSEVOICE_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  static const _agentMockRequested = bool.fromEnvironment(
    'AGENT_MOCK_ENABLED',
    defaultValue: true,
  );
  static const contentSourceTestApiBaseUrl = String.fromEnvironment(
    'CONTENT_SOURCE_TEST_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
  static const passwordLoginEnabled = bool.fromEnvironment(
    'PASSWORD_LOGIN_ENABLED',
    defaultValue: false,
  );
  static const passwordLoginPath = String.fromEnvironment(
    'PASSWORD_LOGIN_PATH',
    defaultValue: '/api/app/auth/password/login',
  );
  static const wechatLoginEnabled = bool.fromEnvironment(
    'WECHAT_LOGIN_ENABLED',
    defaultValue: false,
  );
  static const privacyVersion = String.fromEnvironment(
    'PRIVACY_VERSION',
    defaultValue: '2026-07-20',
  );
  static const appVersion = String.fromEnvironment(
    'APP_VERSION_LABEL',
    defaultValue: '1.0.0',
  );
  static const companyName = String.fromEnvironment('COMPANY_NAME');
  static const appFilingNumber = String.fromEnvironment('APP_FILING_NUMBER');
  static const supportPhone = String.fromEnvironment('SUPPORT_PHONE');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');
  static const supportAddress = String.fromEnvironment('SUPPORT_ADDRESS');

  static bool get isProduction => environment == 'production';

  static bool get developerToolsEnabled => resolveDeveloperToolsEnabled(
    isProduction: isProduction,
    requested: _developerToolsRequested,
  );

  static bool get agentMockEnabled =>
      developerToolsEnabled && _agentMockRequested && !agentEnabled;

  static bool get agentFeatureVisible => agentEnabled || developerToolsEnabled;

  static bool get showDevelopmentSmsCode => developerToolsEnabled;

  static String displayOrPending(String value) =>
      value.trim().isEmpty ? '待主体确认' : value.trim();
}
