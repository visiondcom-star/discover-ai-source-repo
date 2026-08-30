/// Integration test that verifies the login flow with demo credentials.
///
/// Run with:
///   flutter test integration_test/login_flow_test.dart \
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
import 'package:discover_ai/widgets/poi_card.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Match the AppConfig defaults — no need for extra dart-defines.
  const demoEmail = AppConfig.demoEmail; // demo@algeria.travel
  const demoPassword = 'demo1234';

  Widget boot() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
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
      );

  /// Pumps until [finder] is found or [timeout] elapses.
  /// Unlike the original waitFor in app_test.dart, this returns when the
  /// widget is NO LONGER present (i.e., we want to wait for something to
  /// DISAPPEAR) when [waitForAbsence] is true.
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
      if (waitForAbsence) {
        if (!isPresent) return; // widget is gone → done
      } else {
        if (isPresent) return; // widget is found → done
      }
    }
    fail('Timed out after $timeout. '
        'Widget ${waitForAbsence ? "gone?" : "present?"}: '
        '${finder.evaluate().isNotEmpty}');
  }

  testWidgets(
      'V2 — Login with demo credentials lands on the main shell (Explorer)',
      (tester) async {
    // --- Fresh auth state -------------------------------------------------
    // A previous run (or a manual session) may have left a valid JWT in the
    // iOS Keychain. The AuthGate would then restore the session and NEVER
    // show the LoginScreen (that is exactly what happened on the first run:
    // /auth/me → 200, straight to POIListScreen, test timed out waiting for
    // the login field). Clear the stored token so POST /auth/login is really
    // exercised.
    final auth = AuthProvider();
    await auth.initialized;
    if (auth.isAuthenticated) {
      debugPrint(
          '=== PREP: stored session found → logout() to force LoginScreen ===');
      await auth.logout();
    }

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => POIProvider()),
        ChangeNotifierProvider(create: (_) => TripProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => BookingProvider()),
        ChangeNotifierProvider(create: (_) => PromotionProvider()),
      ],
      child: const DiscoverAIApp(),
    ));

    // Fresh state → LoginScreen must be visible.
    await waitForWidget(tester, find.byKey(const Key('login_email')));

    debugPrint('=== STEP 1: LoginScreen visible ===');
    expect(find.byKey(const Key('login_email')), findsOneWidget);
    expect(find.byKey(const Key('login_password')), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    debugPrint('email field: $demoEmail');
    debugPrint('password field: $demoPassword');

    // Enter credentials and tap Sign in.
    await tester.enterText(
        find.byKey(const Key('login_email')), demoEmail);
    await tester.enterText(
        find.byKey(const Key('login_password')), demoPassword);
    await tester.tap(find.text('Sign in'));
    debugPrint('=== STEP 2: Tapped "Sign in" ===');

    // Wait for the login form to disappear (navigation to POI list).
    await waitForWidget(
      tester,
      find.byKey(const Key('login_email')),
      timeout: const Duration(seconds: 30),
      waitForAbsence: true,
    );

    debugPrint('=== STEP 3: LoginScreen gone — HomeShell mounted (Accueil) ===');

    // The shell boots on the Accueil tab; the POI list lives on Explorer.
    await waitForWidget(tester, find.byKey(const Key('tab_explore')));
    await tester.tap(find.byKey(const Key('tab_explore')));

    // Wait for POI cards to appear (API call for POIs completes).
    await waitForWidget(tester, find.byType(POICard),
        timeout: const Duration(seconds: 30));
    final visibleCards = find.byType(POICard).evaluate().length;

    // Read POI count from the provider.
    final context = tester.element(find.byType(POICard).first);
    final pois = context.read<POIProvider>();
    final names = pois.items.map((p) => p.name).toList();

    debugPrint('=== STEP 4: POI list loaded ===');
    debugPrint('V2_PASS: successful login navigated from LoginScreen '
        'to the main shell (Explorer tab shows the POI list)');
    debugPrint('V3_PASS: POI_COUNT_PROVIDER=${pois.items.length} '
        'POI_CARDS_VISIBLE=$visibleCards NAMES=$names');
    for (final poi in pois.items) {
      debugPrint('  POI_ON_SCREEN: ${poi.name} (${poi.city}, ${poi.category})');
    }

    expect(pois.items.length, greaterThan(0),
        reason: 'at least one POI should be loaded');
    expect(visibleCards, greaterThanOrEqualTo(1),
        reason: 'at least one POI card must be painted');

    // V6 — tapping a POI card opens the place detail screen (P3) and coming
    // back restores the Explorer list.
    debugPrint('=== STEP 5: Tap first POI card → detail screen ===');
    await tester.tap(find.byType(POICard).first);
    await waitForWidget(tester, find.byKey(const Key('poi_detail_screen')),
        timeout: const Duration(seconds: 15));

    final firstPoi = pois.items.first;
    expect(find.text(firstPoi.name), findsWidgets,
        reason: 'detail screen must show the tapped POI name');
    expect(find.byKey(const Key('poi_detail_plan_button')), findsOneWidget,
        reason: 'detail CTA (Plan a visit) must be visible');
    debugPrint('V6_PASS: POI detail screen rendered for "${firstPoi.name}"');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await waitForWidget(tester, find.byType(POICard),
        timeout: const Duration(seconds: 15));
    debugPrint('=== STEP 6: Back on Explorer list ===');
  });
}