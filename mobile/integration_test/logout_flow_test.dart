/// Integration test that verifies the explicit UI logout flow.
///
/// Unlike the logout() call used as *state preparation* in
/// login_flow_test.dart, this test exercises the actual UI button
/// (`logout_button`, hosted by the Profil tab of the HomeShell) and verifies:
///   1. the app returns to the LoginScreen,
///   2. the AuthProvider state is cleared,
///   3. the JWT is really gone from the secure storage (iOS Keychain).
///
/// Run with:
///   flutter test integration_test/logout_flow_test.dart \
///     -d "iPhone 15 Pro Max" \
///     --dart-define=API_BASE_URL=http://localhost:8000/api/v1 \
///     --dart-define=TENANT_SLUG=algeria
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/app.dart';
import 'package:discover_ai/config.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/providers/chat_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/providers/promotion_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/screens/login_screen.dart';
import 'package:discover_ai/screens/poi_list_screen.dart';
import 'package:discover_ai/services/secure_storage_service.dart';
import 'package:discover_ai/widgets/poi_card.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Match the AppConfig defaults — no need for extra dart-defines.
  const demoEmail = AppConfig.demoEmail; // demo@algeria.travel
  const demoPassword = 'demo1234';

  /// Pumps until [finder] is found or [timeout] elapses.
  Future<void> waitForWidget(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
    bool waitForAbsence = false,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 500));
      final isPresent = finder.evaluate().isNotEmpty;
      if (waitForAbsence ? !isPresent : isPresent) return;
    }
    fail('Timed out after $timeout. '
        'Widget ${waitForAbsence ? "gone?" : "present?"}: '
        '${finder.evaluate().isNotEmpty}');
  }

  testWidgets(
      'V4 — Logout button returns to LoginScreen and clears secure storage',
      (tester) async {
    final store = SecureStorageService();

    // --- PREP: guarantee a logged-in state --------------------------------
    // Reuse the same AuthProvider instance the app will watch, so assertions
    // on `auth.isAuthenticated` always mirror what the AuthGate renders.
    final auth = AuthProvider();
    await auth.initialized;
    if (auth.isAuthenticated) {
      debugPrint('=== PREP: session already restored (cold-restart '
          'persistence proof) → going straight to logout test ===');
    } else {
      debugPrint('=== PREP: no session → login($demoEmail) via provider ===');
      final ok = await auth.login(demoEmail, demoPassword);
      expect(ok, isTrue, reason: 'demo login must succeed');
    }

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => POIProvider()),
        ChangeNotifierProvider(create: (_) => TripProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        // IndexedStack mounts every tab eagerly → Réservations needs a
        // BookingProvider (real Booking-Agent API).
        ChangeNotifierProvider(create: (_) => BookingProvider()),
        // Same requirement for Accueil's promo banner.
        ChangeNotifierProvider(create: (_) => PromotionProvider()),
      ],
      child: const DiscoverAIApp(),
    ));

    // Authenticated → HomeShell (boots on Accueil). Logout lives on Profil.
    await waitForWidget(tester, find.byKey(const Key('tab_profile')));
    debugPrint('=== STEP 1: HomeShell visible — opening the Profil tab ===');
    await tester.tap(find.byKey(const Key('tab_profile')));
    await waitForWidget(tester, find.byKey(const Key('logout_button')));
    expect(find.byKey(const Key('logout_button')), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    // Sanity: the token is really persisted before we log out.
    final tokenBefore = await store.readToken();
    debugPrint('=== STEP 2: token in secure storage before logout: '
        '${tokenBefore == null ? "NULL" : "PRESENT (${tokenBefore.length} chars)"} ===');
    expect(tokenBefore, isNotNull,
        reason: 'JWT must be in the Keychain while authenticated');
    expect(auth.isAuthenticated, isTrue);

    // --- THE ACTUAL UI LOGOUT ---------------------------------------------
    await tester.tap(find.byKey(const Key('logout_button')));
    debugPrint('=== STEP 3: tapped logout_button ===');

    // AuthGate must switch back to the LoginScreen.
    await waitForWidget(tester, find.byKey(const Key('login_email')));
    debugPrint('=== STEP 4: LoginScreen is back ===');
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(POIListScreen), findsNothing);
    expect(find.byType(POICard), findsNothing);

    // Provider state cleared…
    expect(auth.isAuthenticated, isFalse, reason: 'auth state must be cleared');
    expect(auth.token, isNull);
    expect(auth.user, isNull);

    // …and the JWT really deleted from the iOS Keychain (not just in memory).
    final tokenAfter = await store.readToken();
    debugPrint('=== STEP 5: token in secure storage after logout: '
        '${tokenAfter == null ? "NULL ✅" : "STILL PRESENT ❌"} ===');
    expect(tokenAfter, isNull,
        reason: 'deleteToken() must have removed the JWT from secure storage');

    debugPrint('V4_PASS: logout button → LoginScreen, provider state and '
        'Keychain token both cleared');
  });
}
