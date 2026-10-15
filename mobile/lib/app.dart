import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'models/tenant.dart';
import 'providers/auth_provider.dart';
import 'providers/locale_provider.dart';
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
      // i18n FR/EN (chantier i18n). Delegates + locales are additive — screens
      // that have already migrated (Profil, partner space, login, etc.) read
      // AppLocalizations.of(context), so existing widget tests must wire the
      // delegates. The locale follows the user's persisted choice
      // (LocaleProvider, first), then the tenant's defaultLanguage as a
      // hint while nothing is stored, then the system locale. Unsupported
      // languages never render: the lookup always lands on fr or en.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: _localeForTenant(tenant, context.watch<LocaleProvider?>()),
      home: const AuthGate(),
    );
  }

  /// Locale resolution.
  ///
  /// Order, first hit wins:
  /// 1. The user's persisted choice in [LocaleProvider]. Once the secure
  ///    store read completes (isLoading flips to false), this is the
  ///    authoritative source — it survives restarts and explicit switches.
  /// 2. The tenant's [Tenant.defaultLanguage]. This is only consulted
  ///    during the brief window where LocaleProvider is still loading the
  ///    persisted choice (isLoading == true), so the first frame after
  ///    cold start already renders in the right brand language. After the
  ///    load completes, step 1 takes over — the tenant never silently
  ///    flips the user's explicit choice on a tenant switch.
  /// 3. null — defer to the system locale. Also covers "language we do not
  ///    ship" (e.g. `ar`), so the app never renders an unsupported locale.
  Locale? _localeForTenant(Tenant? tenant, LocaleProvider? localeProvider) {
    final code = localeProvider == null || localeProvider.isLoading
        ? tenant?.defaultLanguage
        : localeProvider.localeCode;
    if (code == null || code.isEmpty) return null;
    final normalized = code.toLowerCase();
    final isSupported = AppLocalizations.supportedLocales
        .any((l) => l.languageCode == normalized);
    return isSupported ? Locale(normalized) : null;
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
