/// Real-backend verification of the research -> categories validation loop.
///
/// Lives in `test_live/`, not `test/`, so the default `flutter test` run stays
/// hermetic (this needs a running backend). Run it explicitly:
///   flutter test test_live \
///     --dart-define=API_BASE_URL=http://127.0.0.1:8013/api/v1 \
///     --dart-define=TENANT_SLUG=e2e-demo
///
/// Drives the actual widgets (AdminResearchScreen + TripFormScreen) against a
/// live FastAPI + Postgres, so the publish/reject loop is exercised through the
/// real ApiService rather than a fake.
///
/// NOTE ON SCOPE: this is a widget test on the Dart VM, not an on-device
/// integration test. `flutter test integration_test` cannot run on this machine
/// — no iOS runtime installed, no macOS desktop project, and web does not
/// support integration tests. What it does prove is that the real widgets, the
/// real ApiService and the real backend agree end to end.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:discover_ai/providers/admin_categories_provider.dart';
import 'package:discover_ai/providers/research_provider.dart';
import 'package:discover_ai/providers/tenant_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/screens/admin_research_screen.dart';
import 'package:discover_ai/screens/trip_form_screen.dart';
import 'package:discover_ai/services/api_service.dart';

// The tile key uses `category.id` (a UUID from the server), not the slug.
// Fetched from the live admin queue so the test stays in sync with the API.
String publishedId = '';
String otherId = '';

/// Admin credentials of the e2e-demo tenant, created by the seeding script.
const adminEmail = 'admin@e2e-demo.travel';
const adminPassword = 'Passw0rd!23';

void main() {
  // `TestWidgetsFlutterBinding` installs an HttpOverrides mock that makes every
  // request return 400. This test deliberately talks to a real server, so the
  // override is removed for the duration of the suite.
  setUpAll(() => HttpOverrides.global = null);
  tearDownAll(() => HttpOverrides.global = null);

  /// Sleeps on the real clock, then rebuilds on the fake one.
  ///
  /// `testWidgets` runs the body in a fake-async zone where a real socket never
  /// completes. Any HTTP therefore has to be awaited inside
  /// [WidgetTester.runAsync], while the resulting widget update has to be pumped
  /// *outside* it. Pumping inside `runAsync` is a no-op for the tree.
  Future<void> settle(
    WidgetTester tester, {
    Duration delay = const Duration(milliseconds: 200),
  }) async {
    await tester.runAsync(() => Future<void>.delayed(delay));
    await tester.pump();
  }

  /// Repeats [settle] until [finder] appears.
  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await settle(tester);
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Timed out waiting for $finder');
  }

  testWidgets('publish then reject drives the traveller catalogue',
      (tester) async {
    // Real ApiService -> real HTTP -> real Postgres. No fakes anywhere.
    final api = ApiService();

    // The screen's ListView builds lazily and this tenant has 13 categories,
    // so the tiles of interest fall outside the default 800x600 test surface.
    // A tall surface makes them build, as they would on a real phone.
    await tester.binding.setSurfaceSize(const Size(1000, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Real login through the real endpoint: the PATCH is admin-only, so the
    // token is what proves the auth path too. runAsync because a real socket
    // never completes under the fake clock.
    final token = (await tester.runAsync(() => _loginForToken(api)))!;
    api.setToken(token);
    debugPrint('E2E: authenticated as $adminEmail');

    final tenants = TenantProvider(tenantsApi: api);
    final admin = AdminCategoriesProvider(api);
    final research = ResearchProvider(api);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TenantProvider>.value(value: tenants),
          ChangeNotifierProvider<AdminCategoriesProvider>.value(value: admin),
          // AdminResearchScreen also watches ResearchProvider for the IA job.
          ChangeNotifierProvider<ResearchProvider>.value(value: research),
        ],
        child: const MaterialApp(home: AdminResearchScreen()),
      ),
    );

    // The screen loads the queue from initState, but that callback fires in the
    // fake-async zone where a real socket cannot complete. So the same call the
    // screen makes is issued explicitly inside runAsync; the widget under test
    // is still the real one, reading the real provider.
    await tester.runAsync(() => admin.load());
    await tester.pumpAndSettle();

    // Resolve the ids the widget keys are built from.
    publishedId = admin.categories
        .firstWhere((c) => c.slug == 'oasis_tam')
        .id;
    otherId = admin.categories.firstWhere((c) => c.slug == 'ksar_ojda').id;
    debugPrint('E2E: queue holds ${admin.categories.length} categories; '
        'publishing id=$publishedId rejecting id=$otherId');

    await pumpUntilFound(tester, find.byKey(Key('publish_$publishedId')));
    debugPrint('E2E: admin queue rendered the proposed categories');

    // Sanity: before publishing, the traveller catalogue must NOT offer it.
    await tester.runAsync(() => tenants.loadCategories());
    expect(
      tenants.categories.map((c) => c.slug),
      isNot(contains('oasis_tam')),
      reason: 'a proposed category must not reach the trip form',
    );
    debugPrint('E2E: proposed correctly absent from traveller catalogue');

    // STEP 4 — publish through the real UI button. The tap handler awaits the PATCH
    // on the fake clock, which never fires; the settle loop below is what gives
    // the real request its event loop.
    await tester.tap(find.byKey(Key('publish_$publishedId')));
    await tester.pump();
    await pumpUntilFound(tester, find.byKey(Key('retire_$publishedId')));
    debugPrint('E2E: published via UI');

    // Reload the traveller catalogue exactly as the app's onChanged does, then
    // assert the trip form offers the newly published slug.
    await tester.runAsync(() => tenants.loadCategories());
    expect(tenants.categories.map((c) => c.slug),
        contains('oasis_tam'),
        reason: 'a published category must reach the traveller catalogue');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TenantProvider>.value(value: tenants),
          // TripFormScreen watches TripProvider for the submit action.
          ChangeNotifierProvider<TripProvider>(
            create: (_) => TripProvider(tripsApi: api),
          ),
        ],
        child: const MaterialApp(home: TripFormScreen()),
      ),
    );
    await pumpUntilFound(tester, find.byKey(const Key('interest_chip_oasis_tam')));
    debugPrint('E2E: published category now offered in the trip form');

    // STEP 5 — reject the other one; the trip form must stop offering it.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TenantProvider>.value(value: tenants),
          ChangeNotifierProvider<AdminCategoriesProvider>.value(value: admin),
          ChangeNotifierProvider<ResearchProvider>.value(value: research),
        ],
        child: const MaterialApp(home: AdminResearchScreen()),
      ),
    );
    // Re-mounting the screen creates a fresh state whose initState load again runs
    // in the fake-async zone, so the same explicit call is needed here. The tall
    // surface is re-asserted because pumpWidget rebuilt the view from scratch.
    await tester.binding.setSurfaceSize(const Size(1000, 3000));
    await tester.runAsync(() => admin.load());
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.byKey(Key('reject_$otherId')));

    await tester.tap(find.byKey(Key('reject_$otherId')));
    await pumpUntilFound(tester, find.text('Confirmer'));
    await tester.tap(find.text('Confirmer'));
    await tester.pump();
    await settle(tester, delay: const Duration(milliseconds: 500));
    await pumpUntilFound(tester, find.text('Rejetée'));
    debugPrint('E2E: rejected via UI + confirmation dialog');

    // Reload the traveller catalogue the way the app does.
    await tester.runAsync(() => tenants.loadCategories());
    expect(tenants.categories.map((c) => c.slug),
        isNot(contains('ksar_ojda')));
    debugPrint('E2E: rejected category absent from traveller catalogue');

    admin.dispose();
    tenants.dispose();
    research.dispose();
  });
}

/// Logs in against the live backend and returns the bearer token.
///
/// Uses [http] directly rather than AuthProvider so the test does not depend on
/// platform secure storage (unavailable on the Dart VM); the credentials and the
/// endpoint are the real ones the app uses.
Future<String> _loginForToken(ApiService api) async {
  final res = await http.post(
    Uri.parse('${api.baseUrl}/auth/login'),
    headers: {
      'Content-Type': 'application/json',
      'X-Tenant-Slug': api.tenantSlug,
    },
    body: jsonEncode({'email': adminEmail, 'password': adminPassword}),
  );
  expect(res.statusCode, 200,
      reason: 'admin login against the live backend: ${res.body}');
  return (jsonDecode(res.body) as Map)['access_token'] as String;
}