import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

class DiscoverAIApp extends StatelessWidget {
  const DiscoverAIApp({super.key});

  // Base theme seed now lives in AppTheme/AppColors (theme/app_theme.dart),
  // sourced from the official design-system blueprint. Per-tenant theming
  // returns with the tenant increment — configuration-driven, never
  // hardcoded per market.

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Discover AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
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