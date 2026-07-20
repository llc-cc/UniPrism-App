part of 'main.dart';

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

  static bool get developerToolsEnabled =>
      !kReleaseMode && !isProduction && _developerToolsRequested;

  static bool get showDevelopmentSmsCode => developerToolsEnabled;

  static String displayOrPending(String value) =>
      value.trim().isEmpty ? '待主体确认' : value.trim();
}
