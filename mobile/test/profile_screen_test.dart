import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/locale_provider.dart';
import 'package:discover_ai/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fakes.dart';

/// Profil tab — focused on the language selector wiring.
///
/// The selector lives inside ProfileScreen and reads/writes LocaleProvider.
/// The end-to-end contract is:
///   1. tapping `language_en` flips the rendered strings to English;
///   2. the choice is persisted in the underlying LocaleStore;
///   3. a fresh LocaleProvider over the same store restores 'en' on init.
///
/// We don't re-test the ProfileScreen rows or the partner button (covered
/// by partner_bookings_screen_test). The harness here uses an injected
/// AuthProvider with a known user, a real LocaleProvider, and an
/// InMemoryLocaleStore that outlives the widget tree.
void main() {
  testWidgets(
    'language_en: rendered strings switch to English, store persists "en", '
    'a fresh provider restores the choice',
    (tester) async {
      // Shared store — both providers read/write the same instance.
      final store = InMemoryLocaleStore();

      // First pump: AuthProvider already authenticated so the screen renders
      // past the loading splash. LocaleProvider defaults to fr (the device
      // fallback while nothing is persisted) until the user taps a segment.
      final first =
          LocaleProvider(localeStore: store, deviceLocaleCode: () => 'fr');
      await first.initialized;
      expect(first.localeCode, 'fr');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleProvider>.value(value: first),
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => AuthProvider(
                api: FakeAuthApi(),
                tokenStore: InMemoryTokenStore(),
              )..login('user@discoverai.dz', 'secret'),
            ),
          ],
          child: const _Harness(child: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Sanity: rendered in French at first.
      expect(find.text('Profil'), findsOneWidget);
      expect(find.text('Langue'), findsOneWidget);
      expect(find.text('Interface language'), findsNothing);

      // 1) Tap the EN segment — the SegmentedButton rebuilds the app in EN.
      await tester.tap(find.byKey(const Key('language_en')));
      await tester.pumpAndSettle();

      expect(first.localeCode, 'en', reason: 'in-memory provider switched');
      expect(store.localeCode, 'en', reason: 'setLocale persisted the choice');
      // Rendered title flipped to the EN translation.
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Langue'), findsNothing);
      expect(find.text('Profil'), findsNothing);

      // 2) A second pump on the same store (simulating an app restart): a
      //    fresh LocaleProvider reads 'en' from the store and exposes it
      //    once initialized resolves. The widget tree picks it up.
      final second =
          LocaleProvider(localeStore: store, deviceLocaleCode: () => 'fr');
      await second.initialized;
      expect(second.localeCode, 'en',
          reason: 'persisted choice restored across provider instances');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleProvider>.value(value: second),
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => AuthProvider(
                api: FakeAuthApi(),
                tokenStore: InMemoryTokenStore(),
              )..login('user@discoverai.dz', 'secret'),
            ),
          ],
          child: const _Harness(child: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Still EN — the persisted choice won over the device fallback.
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(second.localeCode, 'en');

      // The setLocale persisted string is the same one the fresh provider
      // restored from. End-to-end: tap → write → kill → restore.
      expect(store.localeCode, 'en');
    },
  );

  testWidgets(
    'language_fr after switching to en returns the UI to French',
    (tester) async {
      // Parity check: switching back to fr must also flip the strings.
      final store = InMemoryLocaleStore()..localeCode = 'en';
      final provider =
          LocaleProvider(localeStore: store, deviceLocaleCode: () => 'fr');
      await provider.initialized;
      expect(provider.localeCode, 'en');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleProvider>.value(value: provider),
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => AuthProvider(
                api: FakeAuthApi(),
                tokenStore: InMemoryTokenStore(),
              )..login('user@discoverai.dz', 'secret'),
            ),
          ],
          child: const _Harness(child: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Language'), findsOneWidget);

      await tester.tap(find.byKey(const Key('language_fr')));
      await tester.pumpAndSettle();

      expect(provider.localeCode, 'fr');
      expect(store.localeCode, 'fr');
      expect(find.text('Profil'), findsOneWidget);
      expect(find.text('Langue'), findsOneWidget);
      expect(find.text('Language'), findsNothing);
    },
  );

  testWidgets(
    'language switch in profile triggers AuthProvider.syncLocale',
    (tester) async {
      final store = InMemoryLocaleStore();
      final localeProvider =
          LocaleProvider(localeStore: store, deviceLocaleCode: () => 'fr');
      await localeProvider.initialized;

      final fakeApi = FakeAuthApi(userLocale: 'fr');
      final authProvider = AuthProvider(
        api: fakeApi,
        tokenStore: InMemoryTokenStore(),
      );
      await authProvider.initialized;
      await authProvider.login('user@discoverai.dz', 'secret');

      expect(fakeApi.updateMeCalls, 0);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: const _Harness(child: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('language_en')));
      await tester.pumpAndSettle();

      expect(fakeApi.updateMeCalls, 1);
      expect(fakeApi.lastUpdatedLocale, 'en');
    },
  );
}

/// Minimal MaterialApp wrapper used by the two tests above. Equivalent to
/// `pumpLocalized` (commit 1) but without owning a fresh LocaleProvider —
/// the tests own their own so they can inspect state and reuse the store.
class _Harness extends StatelessWidget {
  const _Harness({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Watch LocaleProvider so MaterialApp.locale rebuilds on setLocale —
    // same pattern as DiscoverAIApp in lib/app.dart.
    final localeProvider = context.watch<LocaleProvider>();
    final locale =
        localeProvider.isLoading ? null : Locale(localeProvider.localeCode);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: child,
    );
  }
}
