import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:discover_ai/theme/app_theme.dart';

/// Tenant theming contract: the seed comes from the backend tenant config
/// (GET /tenants/current), malformed/unreachable values fall back to the
/// Algeria default instead of crashing.
void main() {
  group('AppTheme.parseHex', () {
    test('parses a valid #RRGGBB value', () {
      expect(AppTheme.parseHex('#1E90FF'), const Color(0xFF1E90FF));
      expect(AppTheme.parseHex('006233'), const Color(0xFF006233));
    });

    test('falls back to the Algeria seed on malformed values', () {
      expect(AppTheme.parseHex(''), AppColors.brand);
      expect(AppTheme.parseHex('#12345'), AppColors.brand);
      expect(AppTheme.parseHex('#ZZZZZZ'), AppColors.brand);
      expect(
        AppTheme.parseHex('#ZZZZZZ', fallback: const Color(0xFFABCDEF)),
        const Color(0xFFABCDEF),
      );
    });
  });

  group('AppTheme.fromTenant', () {
    test('seeds the color scheme from the tenant primary color', () {
      final theme = AppTheme.fromTenant(primaryColor: '#1E90FF');
      expect(theme.colorScheme.primary, const Color(0xFF1E90FF));
      expect(theme.useMaterial3, isTrue);
    });

    test('keeps the M3 font family', () {
      expect(AppTheme.fromTenant(primaryColor: '#1E90FF').fontFamily, 'Poppins');
    });
  });

  group('AppTheme.light (fallback)', () {
    test('still seeds from the Algeria default #006233', () {
      expect(AppTheme.light().colorScheme.primary, AppColors.brand);
    });
  });
}
