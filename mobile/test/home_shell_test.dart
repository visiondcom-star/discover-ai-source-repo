import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/providers/chat_provider.dart';
import 'package:discover_ai/providers/locale_provider.dart';
import 'package:discover_ai/providers/notifications_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/providers/promotion_provider.dart';
import 'package:discover_ai/providers/tenant_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/screens/home_screen.dart';
import 'package:discover_ai/screens/home_shell.dart';
import 'package:discover_ai/services/locale_store.dart';

import 'helpers/fakes.dart';

class _DelayedLocaleStore implements LocaleStore {
  _DelayedLocaleStore(this.completer);
  final Completer<String?> completer;

  @override
  Future<void> deleteLocaleCode() async {}

  @override
  Future<String?> readLocaleCode() => completer.future;

  @override
  Future<void> writeLocaleCode(String code) async {}
}

/// HomeShell tab navigation — all five tabs stay alive across switches
/// (IndexedStack) and expose the stable `tab_*` Keys used by the
/// integration suite for navigation.
void main() {
  Widget boot({
    Locale locale = const Locale('fr'),
    AuthProvider? authProvider,
    LocaleProvider? localeProvider,
  }) =>
      MultiProvider(
        providers: [
          if (authProvider != null)
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider)
          else
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => AuthProvider(
                api: FakeAuthApi(),
                tokenStore: InMemoryTokenStore(),
              ),
            ),
          ChangeNotifierProvider<POIProvider>(
            create: (_) => POIProvider(poisApi: FakePoisApi()),
          ),
          ChangeNotifierProvider(create: (_) => TripProvider()),
          ChangeNotifierProvider(create: (_) => ChatProvider()),
          // IndexedStack mounts every tab eagerly → Réservations needs a
          // BookingProvider; the empty fake keeps boot deterministic
          // (bookings_empty) without any fake booking content.
          ChangeNotifierProvider<BookingProvider>(
            create: (_) =>
                BookingProvider(bookingsApi: FakeBookingsApi(bookings: [])),
          ),
          // Accueil's promo banner — empty fake so these navigation tests
          // stay unaffected by banner content (covered separately in
          // home_screen tests).
          ChangeNotifierProvider<PromotionProvider>(
            create: (_) =>
                PromotionProvider(promotionsApi: FakePromotionsApi()),
          ),
          ChangeNotifierProvider<TenantProvider>(
            create: (_) => TenantProvider(tenantsApi: FakeTenantsApi()),
          ),
          // Profil hosts the language selector; IndexedStack mounts every tab,
          // so LocaleProvider must be present or the selector throws.
          if (localeProvider != null)
            ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider)
          else
            ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider(localeStore: InMemoryLocaleStore()),
            ),
          ChangeNotifierProvider<NotificationsProvider>(
            create: (_) => NotificationsProvider(
              api: FakeNotificationsApi(unreadCount: 0),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: const HomeShell(),
        ),
      );

  testWidgets('shell boots on Accueil with the greeting placeholder',
      (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tab_home')), findsOneWidget);
    expect(find.byKey(const Key('home_greeting')), findsOneWidget);
    // No login in this test → user is null → neutral fallback, never a
    // hardcoded market name.
    expect(find.text('Bonjour, voyageur 👋'), findsOneWidget);
  });

  testWidgets('every tab is reachable and keeps its content mounted',
      (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    // Explorer — FakePoisApi serves the two fixture POIs.
    await tester.tap(find.byKey(const Key('tab_explore')));
    await tester.pumpAndSettle();
    expect(find.text('Casbah of Algiers'), findsOneWidget);

    // Réservations — empty fake bookings → explicit empty state.
    await tester.tap(find.byKey(const Key('tab_bookings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookings_empty')), findsOneWidget);

    // Assistant — chat input ready with the empty state.
    await tester.tap(find.byKey(const Key('tab_assistant')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat_input')), findsOneWidget);
    expect(find.byKey(const Key('chat_empty')), findsOneWidget);

    // Profil — héberge les entrées admin et la déconnexion. La carte
    // « Collecte de documents » a allongé la liste : `logout_button` passe
    // sous la ligne de flottaison du viewport de test (ListView construit
    // paresseusement), d'où le scroll avant l'assertion.
    await tester.tap(find.byKey(const Key('tab_profile')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('admin_collection_button')), 200);
    expect(find.byKey(const Key('admin_collection_button')), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const Key('logout_button')), 200);
    expect(find.byKey(const Key('logout_button')), findsOneWidget);

    // Back to Accueil — state preserved (IndexedStack).
    await tester.tap(find.byKey(const Key('tab_home')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home_greeting')), findsOneWidget);
  });

  testWidgets('travel-type card opens the wizard with the interest preselected',
      (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    // Home grid → wizard, interest chip already selected.
    await tester.tap(find.byKey(const Key('home_type_history')));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<FilterChip>(
              find.byKey(const Key('interest_chip_history')),
            )
            .selected,
        isTrue,
        reason: 'grid shortcut must preselect the interest');

    // Untouched catalog entries stay unselected.
    expect(
        tester
            .widget<FilterChip>(
              find.byKey(const Key('interest_chip_culture')),
            )
            .selected,
        isFalse);
  });

  testWidgets('Accueil renders its FR strings after the i18n migration',
      (tester) async {
    // The boot() harness defaults to locale 'fr' — this covers every
    // migrated Accueil label in its reference language. The ListView only
    // builds visible items, so the lower cards need a scroll first.
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    expect(find.text('Bonjour, voyageur 👋'), findsOneWidget);
    expect(find.text('Que souhaitez-vous découvrir aujourd’hui ?'),
        findsOneWidget);
    expect(find.text('Type de voyage'), findsOneWidget);
    expect(find.text('Culture & Médinas'), findsOneWidget);
    // The ListView only builds visible items: drag the Accueil tab's own
    // Scrollable up until the lower card is constructed, then assert.
    // The ListTile key propagates to its internal nodes, so match .first.
    Future<void> revealLowerCards() async {
      final scrollable = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scrollable),
      );
      for (var i = 0; i < 10; i++) {
        await tester.drag(scrollable.first, const Offset(0, -300));
        await tester.pumpAndSettle();
        if (find.text('Planifier un voyage').evaluate().isNotEmpty) {
          break;
        }
      }
    }

    await revealLowerCards();
    expect(
      find.descendant(
        of: find.byKey(const Key('home_plan_trip_button')).first,
        matching: find.text('Planifier un voyage'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home_explore_button')).first,
        matching: find.text('Explorer les lieux'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Accueil renders its EN strings after the i18n migration',
      (tester) async {
    await tester.pumpWidget(boot(locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Hello, traveller 👋'), findsOneWidget);
    expect(find.text('What would you like to discover today?'), findsOneWidget);
    expect(find.text('Travel type'), findsOneWidget);
    expect(find.text('Culture & medinas'), findsOneWidget);
    Future<void> revealLowerCardsEn() async {
      final scrollable = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scrollable),
      );
      for (var i = 0; i < 10; i++) {
        await tester.drag(scrollable.first, const Offset(0, -300));
        await tester.pumpAndSettle();
        if (find.text('Plan a trip').evaluate().isNotEmpty) {
          break;
        }
      }
    }

    await revealLowerCardsEn();
    expect(
      find.descendant(
        of: find.byKey(const Key('home_plan_trip_button')).first,
        matching: find.text('Plan a trip'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home_explore_button')).first,
        matching: find.text('Explore places'),
      ),
      findsOneWidget,
    );
  });

  group('HomeShell locale sync', () {
    testWidgets(
        'HomeShell synchronise la langue une fois quand user.locale diffère',
        (tester) async {
      final fakeApi = FakeAuthApi(userLocale: 'fr');
      final authProvider =
          AuthProvider(api: fakeApi, tokenStore: InMemoryTokenStore());
      await authProvider.initialized;
      await authProvider.login('demo@discoverai.dz', 'secret');

      final store = InMemoryLocaleStore()..localeCode = 'en';
      final localeProvider = LocaleProvider(localeStore: store);
      await localeProvider.initialized;

      await tester.pumpWidget(boot(
        authProvider: authProvider,
        localeProvider: localeProvider,
      ));
      await tester.pumpAndSettle();

      expect(fakeApi.updateMeCalls, 1);
      expect(fakeApi.lastUpdatedLocale, 'en');
      expect(authProvider.user?.locale, 'en');
    });

    testWidgets(
        'ne synchronise pas tant que LocaleProvider charge, puis une fois après',
        (tester) async {
      final fakeApi = FakeAuthApi(userLocale: 'fr');
      final authProvider =
          AuthProvider(api: fakeApi, tokenStore: InMemoryTokenStore());
      await authProvider.initialized;
      await authProvider.login('demo@discoverai.dz', 'secret');

      final completer = Completer<String?>();
      final delayedStore = _DelayedLocaleStore(completer);
      final localeProvider = LocaleProvider(localeStore: delayedStore);
      expect(localeProvider.isLoading, isTrue);

      await tester.pumpWidget(boot(
        authProvider: authProvider,
        localeProvider: localeProvider,
      ));
      await tester.pump();
      expect(localeProvider.isLoading, isTrue);
      expect(fakeApi.updateMeCalls, 0);

      completer.complete('en');
      await tester.pumpAndSettle();

      expect(localeProvider.isLoading, isFalse);
      expect(fakeApi.updateMeCalls, 1);
      expect(fakeApi.lastUpdatedLocale, 'en');
      expect(authProvider.user?.locale, 'en');
    });

    testWidgets('ne synchronise pas quand user.locale est déjà égale',
        (tester) async {
      final fakeApi = FakeAuthApi(userLocale: 'fr');
      final authProvider =
          AuthProvider(api: fakeApi, tokenStore: InMemoryTokenStore());
      await authProvider.initialized;
      await authProvider.login('demo@discoverai.dz', 'secret');

      final store = InMemoryLocaleStore()..localeCode = 'fr';
      final localeProvider = LocaleProvider(localeStore: store);
      await localeProvider.initialized;

      await tester.pumpWidget(boot(
        authProvider: authProvider,
        localeProvider: localeProvider,
      ));
      await tester.pumpAndSettle();

      expect(fakeApi.updateMeCalls, 0);
    });
  });
}
