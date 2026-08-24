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

  /// Interest choices offered on the trip-generation form. Generic category
  /// labels by default; overridable per deployment without code change:
  /// --dart-define=TRIP_INTERESTS=culture,food,history
  static final List<String> tripInterestOptions =
      const String.fromEnvironment(
        'TRIP_INTERESTS',
        defaultValue: 'culture,food,history,nature,beaches,adventure,shopping,nightlife',
      )
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);

  /// Budget levels accepted by POST /trips/generate — mirrors the backend
  /// schema constraint `budget_level: ^(low|medium|high)$` (API contract,
  /// not market content).
  static const List<String> budgetLevels = ['low', 'medium', 'high'];

  /// Upper bound of the num-days selector — mirrors the backend schema
  /// constraint `num_days: ge=1, le=14`.
  static const int maxTripDays = 14;
}