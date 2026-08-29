import 'package:flutter/material.dart';

/// Brand palette — single source of truth for raw color constants.
///
/// Sourced from the "Discover AI" UX blueprint. Secondary values below are
/// estimated from the mockup — replace with the exact designer tokens when
/// they are handed over. Per-tenant overrides return with the tenant
/// increment — configuration-driven, never hardcoded per market
/// (architecture principle n°1: no client code in the core).
class AppColors {
  const AppColors._();

  /// Base brand green used as the Material 3 seed.
  static const Color brand = Color(0xFF006233);

  /// Vivid green for selected states and small highlights.
  static const Color brandBright = Color(0xFF00915A);

  /// Pale green tint — selected chips, soft surfaces.
  static const Color brandTint = Color(0xFFE6F2EC);

  /// Warm accent — weather badges, promos, contextual highlights.
  static const Color accent = Color(0xFFE8A33D);

  /// Light app background (light mode scaffold).
  static const Color background = Color(0xFFF8F9FA);

  /// Primary text — dark ink.
  static const Color ink = Color(0xFF1A1A2E);

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
class AppTheme {
  const AppTheme._();

  /// Base brand seed used by [ColorScheme.fromSeed] for both themes.
  static const Color seedColor = AppColors.brand;

  /// Light theme — the current app theme.
  static ThemeData light() => _build(Brightness.light);

  /// Dark theme — ready for the tenant increment (not wired yet).
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
      useMaterial3: true,
      // Brand typeface from the UX blueprint (Medium/SemiBold/Bold weights
      // bundled in pubspec.yaml). Applies to the whole textTheme.
      fontFamily: 'Poppins',
      // Blueprint light background (#F8F9FA); dark mode keeps the M3 default
      // until the tenant increment ships dark-mode tokens.
      scaffoldBackgroundColor: brightness == Brightness.light
          ? AppColors.background
          : null,
      appBarTheme: const AppBarTheme(
        backgroundColor: seedColor,
        foregroundColor: Colors.white,
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
