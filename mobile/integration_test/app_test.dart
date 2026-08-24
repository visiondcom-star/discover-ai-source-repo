/// Real end-to-end verification against the running dev backend.
///
/// Run with:
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/app_test.dart -d chrome \
///     --dart-define=API_BASE_URL=http://localhost:8000/api/v1 \
///     --dart-define=TENANT_SLUG=algeria
///
/// This exercises the REAL stack: real ApiService HTTP calls, real JWT,
/// real POI data — no fakes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/app.dart';
import 'package:discover_ai/models/poi.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/widgets/poi_card.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  const demoEmail = String.fromEnvironment(
    'E2E_EMAIL',
    defaultValue: 'demo@algeria.travel',
  );
  const demoPassword = String.fromEnvironment(
    'E2E_PASSWORD',
    defaultValue: 'demo1234',
  );

  Widget boot() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => POIProvider()),
          ChangeNotifierProvider(create: (_) => TripProvider()),
        ],
        child: const DiscoverAIApp(),
      );

  /// Polls until [finder] matches, pumping real frames meanwhile.
  /// pumpAndSettle would never settle while a progress indicator spins.
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var lastError = '';
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      try {
        if (finder.evaluate().isNotEmpty) return;
      } catch (e) {
        lastError = e.toString();
      }
    }
    fail('Timed out after $timeout waiting for $finder $lastError');
  }

  Future<void> typeCredentials(WidgetTester tester, String password) async {
    await tester.enterText(
        find.byKey(const Key('login_email')), demoEmail);
    await tester.enterText(
        find.byKey(const Key('login_password')), password);
    await tester.tap(find.text('Sign in'));
  }

  testWidgets('V1 — LoginScreen renders with email/password fields',
      (tester) async {
    await tester.pumpWidget(boot());
    await waitFor(tester, find.byKey(const Key('login_email')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('login_email')), findsOneWidget,
        reason: 'email field must be visible');
    expect(find.byKey(const Key('login_password')), findsOneWidget,
        reason: 'password field must be visible');
    expect(find.text('Sign in'), findsOneWidget,
        reason: 'submit button must be visible');

    debugPrint('V1_PASS: LoginScreen visible with Email + Password fields '
        'and Sign in button');
  });

  testWidgets('V4 — wrong password shows a visible on-screen error',
      (tester) async {
    await tester.pumpWidget(boot());
    await waitFor(tester, find.byKey(const Key('login_email')));

    await typeCredentials(tester, 'definitely-wrong-password');
    await waitFor(tester, find.text('Invalid email or password.'),
        timeout: const Duration(seconds: 20));

    debugPrint('V4_PASS: SnackBar "Invalid email or password." rendered '
        'on screen after failed login');
  });

  testWidgets('V2+V3 — real demo login lands on POI list with 8 POIs',
      (tester) async {
    await tester.pumpWidget(boot());
    await waitFor(tester, find.byKey(const Key('login_email')));

    await typeCredentials(tester, demoPassword);

    // Navigation happened once the login form is gone.
    await waitFor(
      tester,
      find.byKey(const Key('login_email')),
      timeout: const Duration(seconds: 20),
    );
    final loginGone = find
        .byKey(const Key('login_email'))
        .evaluate()
        .isEmpty;
    expect(loginGone, isTrue,
        reason: 'successful login must navigate away from LoginScreen');

    // At least one real POI card is painted...
    await waitFor(tester, find.byType(POICard),
        timeout: const Duration(seconds: 20));
    final visibleCards = find.byType(POICard).evaluate().length;

    // ...and the full dataset reached the provider (8 seeded POIs).
    final context = tester.element(find.byType(POICard).first);
    final pois = context.read<POIProvider>();
    final names = pois.items.map((p) => p.name).toList();

    debugPrint('V2_PASS: successful login navigated from LoginScreen '
        'to POIListScreen');
    debugPrint('V3_PASS: POI_COUNT_PROVIDER=${pois.items.length} '
        'POI_CARDS_VISIBLE=$visibleCards NAMES=$names');
    for (final POI p in pois.items) {
      debugPrint('  POI_ON_SCREEN: ${p.name} (${p.city}, ${p.category})');
    }

    expect(pois.items.length, 8,
        reason: 'backend seeds exactly 8 POIs for tenant algeria');
    expect(visibleCards, greaterThanOrEqualTo(1),
        reason: 'cards must actually be painted on screen');
    expect(find.text(names.first), findsWidgets,
        reason: 'first POI name must be present among rendered widgets');
  });

  testWidgets('V5 — trip form submit navigates to a real day-by-day timeline',
      (tester) async {
    await tester.pumpWidget(boot());
    await waitFor(tester, find.byKey(const Key('login_email')));

    await typeCredentials(tester, demoPassword);
    await waitFor(tester, find.byKey(const Key('plan_trip_fab')),
        timeout: const Duration(seconds: 20));

    // Open the generation form.
    await tester.tap(find.byKey(const Key('plan_trip_fab')));
    await waitFor(tester, find.byKey(const Key('generate_trip_button')));
    debugPrint('V5_FORM_PASS: TripFormScreen visible with interests, days '
        'slider and budget selector');

    // Pick two interests from the config-derived catalog.
    await tester.tap(find.byKey(const Key('interest_chip_history')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('interest_chip_culture')));
    await tester.pump();

    // Submit — the real POST /trips/generate runs against Docker dev.
    await tester.tap(find.byKey(const Key('generate_trip_button')));
    await waitFor(tester, find.byKey(const Key('day_header_1')),
        timeout: const Duration(seconds: 30));

    final timelineMounted =
        find.byKey(const Key('trip_timeline')).evaluate().isNotEmpty;
    expect(timelineMounted, isTrue,
        reason: 'timeline list must replace the form after generation');

    int countKeysStartingWith(String prefix) =>
        find
            .byWidgetPredicate((w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith(prefix))
            .evaluate()
            .length;

    final dayCards = countKeysStartingWith('day_card_');
    final poiRows = countKeysStartingWith('timeline_poi_');

    final context = tester.element(find.byKey(const Key('trip_timeline')));
    final trips = context.read<TripProvider>();
    final trip = trips.currentTrip!;

    debugPrint('V5_PASS: form submit navigated to TripTimelineScreen; '
        'TITLE="${trip.title}" DAYS=${trip.numDays} '
        'DAY_CARDS=$dayCards POI_ROWS=$poiRows');
    for (final entry in trip.itemsByDay.entries) {
      debugPrint('  DAY_${entry.key}: '
          '${entry.value.map((i) => i.poi?.name ?? i.poiId).join(" | ")}');
    }

    expect(dayCards, greaterThanOrEqualTo(1),
        reason: 'at least one day card must be rendered');
    expect(poiRows, greaterThanOrEqualTo(1),
        reason: 'at least one itinerary stop (POI row) must be rendered');
    expect(find.text(trip.title), findsWidgets,
        reason: 'trip title must be visible in the timeline');
  });
}