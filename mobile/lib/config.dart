/// Compile-time application configuration.
///
/// Everything market/deployment specific lives here and is injected at
/// build/run time via --dart-define. No tenant slug is ever hardcoded in
/// business code.
class AppConfig {
  const AppConfig._();

  /// API base URL. Examples:
  ///   iOS simulator:    --dart-define=API_BASE_URL=http://localhost:8000/api/v1
  ///   Android emulator: --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  /// Tenant slug sent as X-Tenant-Slug on every request.
  static const String tenantSlug = String.fromEnvironment(
    'TENANT_SLUG',
    defaultValue: 'algeria',
  );

  /// Demo account prefill, mirroring the backend seed convention in
  /// backend/app/initial_data.py: demo@{TENANT_SLUG}.travel.
  /// Overridable at build time: --dart-define=DEMO_EMAIL=you@example.com
  static const String demoEmail = String.fromEnvironment(
    'DEMO_EMAIL',
    defaultValue: 'demo@$tenantSlug.travel',
  );
}