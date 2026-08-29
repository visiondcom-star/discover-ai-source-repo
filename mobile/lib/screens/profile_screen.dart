import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../providers/auth_provider.dart';

/// Profil tab — account summary and the explicit logout action.
///
/// Hosts the `logout_button` Key (previously on the POI list AppBar) so the
/// integration suite keeps exercising the real UI logout flow.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final scheme = Theme.of(context).colorScheme;

    final name = user?.fullName?.trim();
    final display =
        (name != null && name.isNotEmpty) ? name : (user?.email ?? 'Compte');
    final initial = display.isNotEmpty ? display[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: scheme.primary,
                child: Text(initial,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 28)),
              ),
              const SizedBox(height: 12),
              Text(display,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(user?.email ?? '',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.travel_explore, color: scheme.primary),
              title: const Text('Destination'),
              subtitle: const Text('Marché actif de l’app'),
              trailing: const Text(AppConfig.tenantSlug),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              enabled: false,
              leading:
                  Icon(Icons.tune, color: scheme.onSurfaceVariant),
              title: const Text('Préférences'),
              subtitle: const Text('À venir — prochain incrément'),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              key: const Key('logout_button'),
              leading: Icon(Icons.logout, color: scheme.error),
              iconColor: scheme.error,
              title: Text('Se déconnecter',
                  style: TextStyle(color: scheme.error)),
              onTap: () => context.read<AuthProvider>().logout(),
            ),
          ),
        ],
      ),
    );
  }
}
