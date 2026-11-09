/// Secrets et réglages lus au build depuis `.env.json`
/// (`flutter run --dart-define-from-file=.env.json`, voir `tool/run.sh`).
class AppConfig {
  const AppConfig({
    this.smtpUser = const String.fromEnvironment('SMTP_USER'),
    this.smtpAppPassword = const String.fromEnvironment('SMTP_APP_PASSWORD'),
    this.geminiApiKey = const String.fromEnvironment('GEMINI_API_KEY'),
    this.geminiModel = const String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-3.5-flash'),
  });

  final String smtpUser;
  final String smtpAppPassword;
  final String geminiApiKey;
  final String geminiModel;

  bool get smtpConfigured => smtpUser.isNotEmpty && smtpAppPassword.isNotEmpty;
  bool get geminiConfigured => geminiApiKey.isNotEmpty;
}
