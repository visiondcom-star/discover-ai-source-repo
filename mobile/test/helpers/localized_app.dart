import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

/// Pumps [child] inside a `MaterialApp` wired for i18n: the generated
/// [AppLocalizations] delegates plus a [LocaleProvider] backed by an
/// in-memory store. Any screen reading `AppLocalizations.of(context)` — or a
/// `_LanguageTile` reading [LocaleProvider] — renders without throwing.
///
/// [locale] pins the rendered language (defaults to French, the tenant
/// default, so migrated FR assertions keep working); [localeProvider] lets a
/// test drive the persisted choice and observe runtime language switches.
Future<LocaleProvider> pumpLocalized(
  WidgetTester tester, {
  required Widget child,
  Locale locale = const Locale('fr'),
  LocaleProvider? localeProvider,
}) async {
  final provider = localeProvider ??
      LocaleProvider(
        localeStore: InMemoryLocaleStore(),
        deviceLocaleCode: () => locale.languageCode,
      );
  await tester.pumpWidget(
    ChangeNotifierProvider<LocaleProvider>.value(
      value: provider,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: child,
      ),
    ),
  );
  return provider;
}
