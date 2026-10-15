import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/screens/login_screen.dart';
import 'package:discover_ai/services/api_service.dart';
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
}
