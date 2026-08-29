import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/models/poi.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/screens/poi_detail_screen.dart';
import 'package:discover_ai/screens/trip_form_screen.dart';

import 'helpers/fakes.dart';

/// PoiDetailScreen — sections render only when the backend provides them,
/// and the CTA opens the real trip wizard.
void main() {
  POI poi({
    String? description,
    List<String> tags = const [],
    List<String> accessibility = const [],
    Map<String, dynamic> openingHours = const {},
    String? address,
    double? rating,
    bool verified = false,
  }) =>
      POI(
        id: 'poi-1',
        slug: 'poi-1',
        tenantId: 't1',
        name: 'Casbah of Algiers',
        description: description,
        city: 'Algiers',
        category: 'historical',
        durationMinutes: 90,
        priceRange: 'free',
        address: address,
        tags: tags,
        accessibility: accessibility,
        openingHours: openingHours,
        isVerified: verified,
        averageRating: rating,
        reviewCount: rating == null ? 0 : 12,
      );

  Widget wrap(POI poi) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider(
              api: FakeAuthApi(),
              tokenStore: InMemoryTokenStore(),
            ),
          ),
          ChangeNotifierProvider<TripProvider>(create: (_) => TripProvider()),
        ],
        child: MaterialApp(home: PoiDetailScreen(poi: poi)),
      );

  testWidgets('renders every section the backend provides', (tester) async {
    await tester.pumpWidget(wrap(poi(
      description: 'A UNESCO-listed medina overlooking the bay.',
      tags: const ['unesco', 'medina'],
      accessibility: const ['wheelchair ramp'],
      openingHours: const {'Mon-Sun': '09:00-17:00'},
      address: 'Rue Djamaa el Djedid',
      rating: 4.5,
      verified: true,
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_screen')), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_name')), findsOneWidget);
    expect(find.text('Casbah of Algiers'), findsWidgets);
    expect(find.byKey(const Key('poi_detail_rating')), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('(12 reviews)'), findsOneWidget);
    expect(find.text('90 min'), findsOneWidget);
    expect(find.text('free'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_description')), findsOneWidget);
    expect(find.text('unesco'), findsOneWidget);
    expect(find.text('wheelchair ramp'), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_hours')), findsOneWidget);
    expect(find.text('09:00-17:00'), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_plan_button')), findsOneWidget);
  });

  testWidgets('omits sections the backend does not provide', (tester) async {
    await tester.pumpWidget(wrap(poi()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_screen')), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_name')), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_rating')), findsNothing);
    expect(find.byKey(const Key('poi_detail_description')), findsNothing);
    expect(find.byKey(const Key('poi_detail_images')), findsNothing);
    expect(find.byKey(const Key('poi_detail_tags')), findsNothing);
    expect(find.byKey(const Key('poi_detail_accessibility')), findsNothing);
    expect(find.byKey(const Key('poi_detail_hours')), findsNothing);
    expect(find.byKey(const Key('poi_detail_plan_button')), findsOneWidget);
  });

  testWidgets('Plan a visit opens the trip wizard', (tester) async {
    await tester.pumpWidget(wrap(poi()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('poi_detail_plan_button')));
    await tester.pumpAndSettle();

    expect(find.byType(TripFormScreen), findsOneWidget);
  });
}