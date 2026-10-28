import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'main.dart';
import 'providers/auth_provider.dart';

/// Scopes user-specific providers (Trip, Chat, Booking, Notifications, Admin)
/// above the Navigator and recreates them when the authenticated user changes.
class UserScope extends StatelessWidget {
  const UserScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider?>();
    final userId = (auth != null && auth.isAuthenticated && auth.user != null)
        ? auth.user!.id
        : null;

    return MultiProvider(
      key: ValueKey<String?>(userId),
      providers: userScopedProviders(),
      child: child,
    );
  }
}
