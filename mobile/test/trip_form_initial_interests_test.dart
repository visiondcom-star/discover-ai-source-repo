// test/trip_form_initial_interests_test.dart
//
// Régression : les intérêts pré-sélectionnés étaient validés contre
// `AppConfig.tripInterestOptions` alors que les chips affichés viennent du
// catalogue dynamique du tenant.

import 'package:discover_ai/config.dart';
import 'package:discover_ai/providers/tenant_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/screens/trip_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fakes.dart';

/// Slug absent de `AppConfig.tripInterestOptions` : il n'existe que parce que
/// l'admin l'a publié après le build de l'app.
const dynamicOnlySlug = 'oasis_tam';

/// Monte le formulaire avec un TenantProvider dont le catalogue dynamique ne
/// contient que [dynamicOnlySlug] — un slug que la liste compile-time ignore.
Future<void> _pumpWithDynamicCatalog(
  WidgetTester tester, {
  required TripProvider trips,
  required Set<String> initialInterests,
}) async {
  final tenants =
      TenantProvider(tenantsApi: FakeTenantsApi(categorySlugs: [dynamicOnlySlug]));
  // Le catalogue arrive comme en production : après le premier build.
  await tenants.loadCategories();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TenantProvider>.value(value: tenants),
        ChangeNotifierProvider<TripProvider>.value(value: trips),
      ],
      child: MaterialApp(
        home: TripFormScreen(initialInterests: initialInterests),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'pre-sélectionne un slug présent seulement dans le catalogue dynamique',
      (tester) async {
    // Garde-fou du scénario : si le slug entrait dans la liste compile-time,
    // le test passerait même avec l'ancien code.
    expect(AppConfig.tripInterestOptions.contains(dynamicOnlySlug), isFalse);

    final trips = TripProvider(tripsApi: FakeTripsApi());
    await _pumpWithDynamicCatalog(
      tester,
      trips: trips,
      initialInterests: {dynamicOnlySlug},
    );

    final chip = find.byKey(const Key('interest_chip_$dynamicOnlySlug'));
    expect(chip, findsOneWidget, reason: 'la puce est bien affichée');

    expect(tester.widget<FilterChip>(chip).selected, isTrue,
        reason: 'le slug du catalogue dynamique doit être pré-sélectionné');
  });

  testWidgets("la sélection initiale est réellement envoyée à l'API",
      (tester) async {
    final api = FakeTripsApi();
    final trips = TripProvider(tripsApi: api);
    await _pumpWithDynamicCatalog(
      tester,
      trips: trips,
      initialInterests: {dynamicOnlySlug},
    );

    await tester.tap(find.byKey(const Key('generate_trip_button')));
    await tester.pumpAndSettle();

    expect(api.lastGeneratePayload, isNotNull);
    expect(api.lastGeneratePayload!['interests'], [dynamicOnlySlug],
        reason: 'le slug doit atteindre generate(), pas être perdu');
  });

  testWidgets('ignore un slug absent du catalogue affiché', (tester) async {
    final api = FakeTripsApi();
    final trips = TripProvider(tripsApi: api);
    await _pumpWithDynamicCatalog(
      tester,
      trips: trips,
      initialInterests: {'slug_qui_nexiste_pas'},
    );

    // Rien de sélectionné → la validation doit se déclencher.
    await tester.tap(find.byKey(const Key('generate_trip_button')));
    await tester.pump();

    expect(api.generateCalls, 0);
    expect(find.byKey(const Key('trip_form_validation')), findsOneWidget);
  });

  testWidgets('retombe sur le catalogue compile-time quand le tenant n\'en a pas',
      (tester) async {
    final api = FakeTripsApi();
    final trips = TripProvider(tripsApi: api);
    final tenants = TenantProvider(tenantsApi: FakeTenantsApi(fail: true));
    await tenants.loadCategories(); // reste vide

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TenantProvider>.value(value: tenants),
          ChangeNotifierProvider<TripProvider>.value(value: trips),
        ],
        child: const MaterialApp(home: TripFormScreen()),
      ),
    );
    await tester.pump();

    // Le repli compile-time reste affiché...
    expect(find.byKey(const Key('interest_chip_culture')), findsOneWidget);
    // ...et le formulaire reste valide (aucune sélection → blocage attendu).
    await tester.tap(find.byKey(const Key('generate_trip_button')));
    await tester.pump();
    expect(find.byKey(const Key('trip_form_validation')), findsOneWidget);
  });
}