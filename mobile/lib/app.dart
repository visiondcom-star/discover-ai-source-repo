import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/tenant_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

class DiscoverAIApp extends StatelessWidget {
  const DiscoverAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Consumer isolates MaterialApp rebuild to ONLY when tenant changes.
    // AuthGate is passed as stable 'child' — it does NOT rebuild on tenant changes.
    return Consumer<TenantProvider>(
      builder: (context, tenantProvider, child) {
        final tenant = tenantProvider.tenant;
        final primaryColor = _parseColor(tenant?.primaryColor);

        return MaterialApp(
          title: tenant?.name ?? 'Discover AI',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
            useMaterial3: true,
            appBarTheme: AppBarTheme(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            cardTheme: CardThemeData(
              elevation: 2,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          ),
          home: child,
        );
      },
      child: const AuthGate(), // Stable: never rebuilds when tenant changes
    );
  }

  /// Safe color parser — never crashes on bad hex strings.
  static Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF006233);
    try {
      final sanitized = hex.trim().replaceFirst('#', '0xFF');
      return Color(int.parse(sanitized));
    } catch (_) {
      return const Color(0xFF006233);
    }
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return auth.isAuthenticated ? const HomeScreen() : const LoginScreen();
  }
}
