/// Integration test that verifies session persistence across an app
/// relaunch (cold restart), without ever calling logout().
///
/// A real `flutter test integration_test/...` run is a single Dart process
/// from start to finish, so we can't kill the actual OS process mid-test.
/// Instead we prove the same thing that matters: a *brand-new*
/// `AuthProvider` instance — as created fresh on every real app launch —
/// restores the session directly from secure storage (`_restoreSession()`),
/// without ever calling `login()` again, and lands straight on HomeShell
/// instead of LoginScreen.
///
/// Run with:
///   flutter test integration_test/kill_relaunch_persistence_test.dart \
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
import 'package:discover_ai/providers/tenant_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/screens/login_screen.dart';
import 'package:discover_ai/services/secure_storage_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const demoEmail = AppConfig.demoEmail; // demo@algeria.travel
  const demoPassword = 'demo1234';

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

  /// Mounts a fresh DiscoverAIApp bound to [auth] — same provider wiring
  /// used across the other integration tests (every tab's provider needed
  /// because IndexedStack mounts them eagerly).
  Widget bootWith(AuthProvider auth) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => POIProvider()),
          ChangeNotifierProvider(create: (_) => TripProvider()),
          ChangeNotifierProvider(create: (_) => ChatProvider()),
          ChangeNotifierProvider(create: (_) => BookingProvider()),
          ChangeNotifierProvider(create: (_) => PromotionProvider()),
          ChangeNotifierProvider(create: (_) => TenantProvider()),
        ],
        child: const DiscoverAIApp(),
      );

  testWidgets(
      'V5 — session survives a simulated relaunch (fresh AuthProvider '
      'restores from secure storage, no re-login)', (tester) async {
    final store = SecureStorageService();

    // --- PHASE 1: "first launch" — guarantee a logged-in session ----------
    final authBeforeRelaunch = AuthProvider();
    await authBeforeRelaunch.initialized;
    if (!authBeforeRelaunch.isAuthenticated) {
      debugPrint('=== PREP: no session → login($demoEmail) ===');
      final ok = await authBeforeRelaunch.login(demoEmail, demoPassword);
      expect(ok, isTrue, reason: 'demo login must succeed');
    } else {
      debugPrint('=== PREP: session already present (previous test run) ===');
    }

    await tester.pumpWidget(bootWith(authBeforeRelaunch));
    await waitForWidget(tester, find.byKey(const Key('tab_profile')));
    debugPrint('=== STEP 1: first "launch" — HomeShell visible, logged in ===');

    final tokenBeforeRelaunch = await store.readToken();
    expect(tokenBeforeRelaunch, isNotNull,
        reason: 'JWT must be in the Keychain before the simulated relaunch');

    // --- PHASE 2: "kill" — tear down the widget tree and every in-memory
    // provider. Nothing survives this except what's actually on disk
    // (secure storage) — the real thing a process kill would leave behind.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    debugPrint('=== STEP 2: simulated kill — widget tree and old '
        'AuthProvider instance torn down ===');

    // --- PHASE 3: "relaunch" — brand-new AuthProvider, exactly like a
    // real cold start. This is the actual assertion: restoration must come
    // from secure storage alone, no login() call anywhere in this phase.
    final authAfterRelaunch = AuthProvider();
    await authAfterRelaunch.initialized;
    debugPrint('=== STEP 3: fresh AuthProvider created — '
        'isAuthenticated=${authAfterRelaunch.isAuthenticated} '
        '(before any pumpWidget) ===');

    expect(authAfterRelaunch.isAuthenticated, isTrue,
        reason:
            '_restoreSession() must restore from secure storage on its own, '
            'without a fresh login() call');
    expect(authAfterRelaunch.token, tokenBeforeRelaunch,
        reason: 'the restored token must be the same one persisted before '
            'the simulated relaunch — not a newly issued one');

    await tester.pumpWidget(bootWith(authAfterRelaunch));

    // AuthGate must go straight to HomeShell — LoginScreen must never
    // flash, even briefly, once restoration has completed.
    await waitForWidget(tester, find.byKey(const Key('tab_profile')));
    expect(find.byType(LoginScreen), findsNothing);
    debugPrint('=== STEP 4: "relaunch" landed straight on HomeShell — '
        'no re-login required ===');

    final tokenAfterRelaunch = await store.readToken();
    expect(tokenAfterRelaunch, tokenBeforeRelaunch,
        reason: 'secure storage itself must be untouched by the relaunch');

    debugPrint('V5_PASS: fresh AuthProvider + fresh widget tree restored '
        'the session from secure storage alone, matching token, '
        'landed on HomeShell without hitting LoginScreen');
  });
}
