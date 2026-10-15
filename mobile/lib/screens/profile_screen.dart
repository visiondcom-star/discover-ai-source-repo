import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/partner_bookings_provider.dart';
import 'admin_collection_screen.dart';
import 'admin_research_screen.dart';
import 'partner_bookings_screen.dart';

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
    final loc = AppLocalizations.of(context);

    final name = user?.fullName?.trim();
    final display = (name != null && name.isNotEmpty)
        ? name
        : (user?.email ?? loc.profileAccountFallback);
    final initial = display.isNotEmpty ? display[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(title: Text(loc.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: scheme.primary,
                child: Text(initial,
                    style: const TextStyle(color: Colors.white, fontSize: 28)),
              ),
              const SizedBox(height: 12),
              Text(display,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(user?.email ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.travel_explore, color: scheme.primary),
              title: Text(loc.profileDestination),
              subtitle: Text(loc.profileDestinationHint),
              trailing: Text(AppConfig.tenantSlug),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              enabled: false,
              leading: Icon(Icons.tune, color: scheme.onSurfaceVariant),
              title: Text(loc.profilePreferences),
              subtitle: Text(loc.profilePreferencesHint),
            ),
          ),
          const SizedBox(height: 12),
          const _LanguageTile(),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              key: const Key('admin_research_button'),
              leading: Icon(Icons.travel_explore, color: scheme.primary),
              title: Text(loc.profileAdminResearch),
              subtitle: Text(loc.profileAdminResearchHint),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminResearchScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              key: const Key('admin_collection_button'),
              leading:
                  Icon(Icons.cloud_download_outlined, color: scheme.primary),
              title: Text(loc.profileAdminCollection),
              subtitle: Text(loc.profileAdminCollectionHint),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminCollectionScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (user?.canUsePartnerSpace ?? false)
            Column(
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    key: const Key('partner_space_button'),
                    leading:
                        Icon(Icons.storefront_outlined, color: scheme.primary),
                    title: Text(loc.profilePartnerSpace),
                    subtitle: Text(loc.profilePartnerSpaceHint),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        // Provider created inside the route builder: a
                        // partner's queue must not survive a logout — the next
                        // user gets a fresh one.
                        builder: (_) => ChangeNotifierProvider(
                          create: (_) => PartnerBookingsProvider(),
                          child: const PartnerBookingsScreen(),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              key: const Key('logout_button'),
              leading: Icon(Icons.logout, color: scheme.error),
              iconColor: scheme.error,
              title: Text(loc.profileLogout,
                  style: TextStyle(color: scheme.error)),
              onTap: () => context.read<AuthProvider>().logout(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Language selector (FR/EN). Reads [LocaleProvider], writes the persisted
/// choice on tap — the whole app rebuilds in the new language via
/// `MaterialApp.locale`.
class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = context.watch<LocaleProvider>();
    final loc = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.translate, color: scheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.languageTitle),
                  Text(
                    loc.languageHint,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            SegmentedButton<String>(
              key: const Key('language_selector'),
              segments: [
                ButtonSegment(
                  value: 'fr',
                  label: Text(
                    loc.languageFrench,
                    key: const Key('language_fr'),
                  ),
                ),
                ButtonSegment(
                  value: 'en',
                  label: Text(
                    loc.languageEnglish,
                    key: const Key('language_en'),
                  ),
                ),
              ],
              selected: {locale.localeCode},
              onSelectionChanged: (codes) =>
                  context.read<LocaleProvider>().setLocale(codes.first),
            ),
          ],
        ),
      ),
    );
  }
}
