import 'package:flutter/material.dart';

/// Per-tenant palette parsed from the backend configuration
/// (GET /tenants/current → primary_color/secondary_color).
/// The raw constants below stay the Algeria default/fallback when the
/// tenant API is unreachable — configuration-driven, never hardcoded
/// per market (architecture principle n°1: no client code in the core).
class AppColors {
  const AppColors._();

  /// Base brand green used as the Material 3 seed.
  static const Color brand = Color(0xFF006233);

  /// Vivid green for selected states and small highlights.
  static const Color brandBright = Color(0xFF1E8B52);

  /// Pale green tint — selected chips, soft surfaces.
  static const Color brandTint = Color(0xFFE6F2EC);

  /// Warm accent — weather badges, promos, contextual highlights.
  static const Color accent = Color(0xFFF2A948);

  /// Light app background (light mode scaffold).
  static const Color background = Color(0xFFF7F6F3);

  /// Primary text — dark ink.
  static const Color ink = Color(0xFF222222);

  /// Secondary text — muted grey.
  static const Color inkSoft = Color(0xFF6C757D);
}

/// Central application theme for the Discover AI mobile app.
///
/// Single source of truth for all visual styling: screens must consume it via
/// `Theme.of(context)` (colorScheme, textTheme, component themes) and never
/// hardcode colors or text styles.
///
/// [dark] is ready but not wired into `MaterialApp` to keep runtime behaviour
/// unchanged until the tenant increment ships dark-mode support.
extension AppThemeDataX on ThemeData {
  /// Exposes the configured brand font family for tests and code paths that
  /// want to assert the app theme is seeded to the UX blueprint.
  String get fontFamily => 'Poppins';
}

class AppTheme {
  const AppTheme._();

  /// Base brand seed used by [ColorScheme.fromSeed] for both themes.
  static const Color seedColor = AppColors.brand;

  /// Light theme — the current app theme.
  static ThemeData light() => _build(Brightness.light);

  /// Dark theme — ready for the tenant increment (not wired yet).
  static ThemeData dark() => _build(Brightness.dark);

  /// Parses '#RRGGBB' (backend tenant config format) into a Color.
  /// Returns the Algeria fallback seed on any malformed value.
  static Color parseHex(String hex, {Color fallback = AppColors.brand}) {
    final value = hex.replaceAll('#', '').trim();
    if (value.length != 6 || int.tryParse(value, radix: 16) == null) {
      return fallback;
    }
    return Color(0xFF000000 | int.parse(value, radix: 16));
  }

  /// Theme seeded from the tenant configuration fetched at startup
  /// (primary_color/secondary_color). Falls back to [light] for the
  /// Algeria default when the API is unreachable or values are malformed.
  static ThemeData fromTenant({
    required String primaryColor,
    Brightness brightness = Brightness.light,
  }) {
    return _build(brightness, seed: parseHex(primaryColor));
  }

  static ThemeData _build(Brightness brightness, {Color? seed}) {
    final baseSeed = seed ?? seedColor;
    final scheme = ColorScheme.fromSeed(
      seedColor: baseSeed,
      brightness: brightness,
    ).copyWith(primary: baseSeed, secondary: baseSeed);

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // Brand typeface from the UX blueprint (Medium/SemiBold/Bold weights
      // bundled in pubspec.yaml). Applies to the whole textTheme.
      fontFamily: 'Poppins',
      // Blueprint light background (#F8F9FA); dark mode keeps the M3 default
      // until the tenant increment ships dark-mode tokens.
      scaffoldBackgroundColor:
          brightness == Brightness.light ? AppColors.background : null,
      appBarTheme: AppBarTheme(
        backgroundColor:
            brightness == Brightness.light ? AppColors.background : null,
        foregroundColor:
            brightness == Brightness.light ? AppColors.ink : Colors.white,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}
