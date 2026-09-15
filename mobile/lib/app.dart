import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/tenant_provider.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

class DiscoverAIApp extends StatelessWidget {
  const DiscoverAIApp({super.key});

  // Base theme seed now lives in AppTheme/AppColors (theme/app_theme.dart),
  // sourced from the design-system blueprint. The seed is configuration-
  // driven: it comes from the tenant config (GET /tenants/current) fetched
  // at startup, falling back to the Algeria default while loading or when
  // the API is unreachable.

  @override
  Widget build(BuildContext context) {
    // Nullable watch: absent TenantProvider (unit tests, etc.) → default
    // theme, never a crash. Unlike the previous listen:false lookup, this
    // also rebuilds when the tenant config lands, so the theme switches
    // from the default seed to the tenant brand without an app restart.
    final tenant = context.watch<TenantProvider?>()?.tenant;
    return MaterialApp(
      title: 'Discover AI',
      debugShowCheckedModeBanner: false,
      theme: tenant == null
          ? AppTheme.light()
          : AppTheme.fromTenant(primaryColor: tenant.primaryColor),
      home: const AuthGate(),
    );
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
    return auth.isAuthenticated ? const HomeShell() : const LoginScreen();
  }
}
