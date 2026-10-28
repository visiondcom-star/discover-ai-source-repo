import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/l10n/app_localizations_en.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/providers/chat_provider.dart';
import 'package:discover_ai/providers/locale_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/providers/promotion_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/screens/home_shell.dart';
import 'package:discover_ai/screens/login_screen.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:discover_ai/providers/tenant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fakes.dart';

/// LoginScreen — the auth entry point.
///
/// The screen owns the localization of auth failures: the provider is
/// locale-agnostic and exposes an [AuthError] code, and the screen maps it
/// to a user-facing string via AppLocalizations — the same pattern as the
/// partner screen (a1d26d9 / fa963ad).
void main() {
  /// Boots a LoginScreen with [locale] pinned and a fake that fails login
  /// with the given HTTP status.
  Future<void> pumpLogin(
    WidgetTester tester, {
    required Locale locale,
    int? failStatus,
  }) async {
    final auth = AuthProvider(
      api: _FailingAuthApi(status: failStatus),
      tokenStore: InMemoryTokenStore(),
    );
    await auth.initialized;
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Fills the form with a syntactically valid email + any password and taps
  /// submit. The token/password are irrelevant — the fake always rejects.
  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const Key('login_email')), 'demo@discoverai.dz');
    await tester.enterText(
        find.byKey(const Key('login_password')), 'wrong-password');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('401 → invalid-credentials error rendered in FR', (tester) async {
    await pumpLogin(tester, locale: const Locale('fr'), failStatus: 401);
    await submit(tester);

    expect(find.byKey(const Key('login_error')), findsOneWidget);
    expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
  });

  testWidgets('401 → invalid-credentials error rendered in EN', (tester) async {
    await pumpLogin(tester, locale: const Locale('en'), failStatus: 401);
    await submit(tester);

    expect(find.byKey(const Key('login_error')), findsOneWidget);
    expect(find.text('Invalid email or password.'), findsOneWidget);
  });

  testWidgets('transport failure (null status) → network error',
      (tester) async {
    await pumpLogin(tester, locale: const Locale('fr'), failStatus: null);
    await submit(tester);

    expect(find.text('Connexion impossible. Vérifiez votre réseau.'),
        findsOneWidget);
  });

  testWidgets('500 → generic error', (tester) async {
    await pumpLogin(tester, locale: const Locale('fr'), failStatus: 500);
    await submit(tester);

    expect(find.text('Une erreur est survenue. Réessayez.'), findsOneWidget);
  });

  test('the provider exposes the mapped AuthError code', () async {
    // Direct provider-level check of the enum contract — independent of the
    // screen. Mirrors the partner provider tests: the code is the interface,
    // the text is the screen's concern.
    final auth = AuthProvider(
      api: _FailingAuthApi(status: 401),
      tokenStore: InMemoryTokenStore(),
    );
    await auth.initialized;

    final ok = await auth.login('demo@discoverai.dz', 'wrong');

    expect(ok, isFalse);
    expect(auth.loginError, AuthError.invalidCredentials);
  });

  test('a successful login clears the error code', () async {
    final auth = AuthProvider(
      api: FakeAuthApi(),
      tokenStore: InMemoryTokenStore(),
    );
    await auth.initialized;

    final ok = await auth.login('demo@discoverai.dz', 'secret');

    expect(ok, isTrue);
    expect(auth.loginError, isNull);
  });

  testWidgets('email and password validators render EN messages',
      (tester) async {
    await pumpLogin(tester, locale: const Locale('en'), failStatus: 401);

    // Trigger field-level validation: empty / invalid fields.
    await tester.enterText(find.byKey(const Key('login_email')), '');
    await tester.enterText(find.byKey(const Key('login_password')), '');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    // Errors come from AppLocalizationsEn, not hardcoded strings.
    final en = AppLocalizationsEn();
    expect(find.text(en.loginEmailInvalid), findsOneWidget);
    expect(find.text(en.loginPasswordRequired), findsOneWidget);

    // Submit stays enabled: the validation happens on the fields, not the
    // button click.
    expect(find.byKey(const Key('login_submit')), findsOneWidget);
  });

  testWidgets('5 shell tab labels switch to EN after locale switch',
      (tester) async {
    final store = InMemoryLocaleStore();
    final first =
        LocaleProvider(localeStore: store, deviceLocaleCode: () => 'fr');
    await first.initialized;

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
          ChangeNotifierProvider<POIProvider>(
            create: (_) => POIProvider(poisApi: FakePoisApi()),
          ),
          ChangeNotifierProvider(create: (_) => TripProvider()),
          ChangeNotifierProvider(create: (_) => ChatProvider()),
          ChangeNotifierProvider<BookingProvider>(
            create: (_) =>
                BookingProvider(bookingsApi: FakeBookingsApi(bookings: [])),
          ),
          ChangeNotifierProvider<PromotionProvider>(
            create: (_) =>
                PromotionProvider(promotionsApi: FakePromotionsApi()),
          ),
          ChangeNotifierProvider<TenantProvider>(
            create: (_) => TenantProvider(tenantsApi: FakeTenantsApi()),
          ),
        ],
        child: const _Harness(child: HomeShell()),
      ),
    );
    await tester.pumpAndSettle();

    // All five tab labels are rendered in French at first.
    expect(
      find.descendant(
        of: find.byKey(const Key('tab_home')),
        matching: find.text('Accueil'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('tab_explore')),
        matching: find.text('Explorer'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('tab_bookings')),
        matching: find.text('Réservations'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('tab_assistant')),
        matching: find.text('Assistant'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('tab_profile')),
        matching: find.text('Profil'),
      ),
      findsOneWidget,
    );

    // Switch to the Profil tab so the language selector is visible.
    await tester.tap(find.byKey(const Key('tab_profile')));
    await tester.pumpAndSettle();

    // Tap EN — the whole shell rebuilds in English, including the tab labels.
    await tester.tap(find.byKey(const Key('language_en')));
    await tester.pumpAndSettle();

    expect(first.localeCode, 'en');
    expect(store.localeCode, 'en');
    expect(
      find.descendant(
          of: find.byKey(const Key('tab_home')), matching: find.text('Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byKey(const Key('tab_explore')),
          matching: find.text('Explore')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byKey(const Key('tab_bookings')),
          matching: find.text('Bookings')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byKey(const Key('tab_assistant')),
          matching: find.text('Assistant')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byKey(const Key('tab_profile')),
          matching: find.text('Profile')),
      findsOneWidget,
    );
  });
}

/// AuthApi whose `login` always fails with [status]. A null [status] simulates
/// a transport-level failure (ApiException with a null statusCode).
class _FailingAuthApi implements AuthApi {
  _FailingAuthApi({required this.status});
  final int? status;

  @override
  void setToken(String token) {}

  @override
  Future<Map<String, dynamic>> getMe() async => throw ApiException(401, '{}');

  @override
  Future<Map<String, dynamic>> login(String email, String password) async =>
      throw ApiException(status, '{"detail":"nope"}');

  @override
  Future<Map<String, dynamic>> register(String email, String password,
          {String? fullName}) async =>
      throw ApiException(status, '{"detail":"nope"}');

  @override
  Future<Map<String, dynamic>> updateMe({required String locale}) async =>
      throw ApiException(status, '{"detail":"nope"}');
}

/// Minimal MaterialApp wrapper used by the shell tab label tests.
/// Equivalent to `pumpLocalized` (commit 1) but without owning a fresh
/// LocaleProvider — the test owns its own so it can inspect state.
class _Harness extends StatelessWidget {
  const _Harness({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Watch LocaleProvider so MaterialApp.locale rebuilds on setLocale.
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
