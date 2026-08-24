import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/screens/poi_map_screen.dart';

import 'helpers/fakes.dart';

/// Fixture: three POIs, two geolocated, one without coordinates — the map
/// must render exactly one marker per geolocated POI and skip the rest.
final List<Map<String, dynamic>> mapPoisJson = [
  {
    'id': 'p-1',
    'slug': 'casbah-of-algiers',
    'tenant_id': 't-1',
    'name': 'Casbah of Algiers',
    'city': 'Algiers',
    'category': 'historical',
    'latitude': 36.7836,
    'longitude': 3.06,
  },
  {
    'id': 'p-2',
    'slug': 'constantine-bridges',
    'tenant_id': 't-1',
    'name': 'Ponts de Constantine',
    'city': 'Constantine',
    'category': 'culture',
    'latitude': 36.365,
    'longitude': 6.6147,
  },
  {
    'id': 'p-3',
    'slug': 'no-coordinates',
    'tenant_id': 't-1',
    'name': 'Place without coordinates',
    'city': 'Nowhere',
    'category': 'culture',
  },
];

Widget _wrap(POIProvider pois) {
  return ChangeNotifierProvider<POIProvider>.value(
    value: pois,
    child: const MaterialApp(home: PoiMapScreen()),
  );
}

POIProvider _providerWith(List<Map<String, dynamic>> items) {
  final pois = POIProvider(poisApi: FakePoisApi(itemsJson: items));
  // loadPOIs is synchronous-enough for the fake; flush its microtasks.
  pois.loadPOIs();
  return pois;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders exactly one marker per geolocated POI',
      (tester) async {
    await tester.pumpWidget(_wrap(_providerWith(mapPoisJson)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('poi_marker_p-1')), findsOneWidget,
        reason: 'geolocated POI 1 must produce a marker');
    expect(find.byKey(const Key('poi_marker_p-2')), findsOneWidget,
        reason: 'geolocated POI 2 must produce a marker');
    expect(find.byKey(const Key('poi_marker_p-3')), findsNothing,
        reason: 'a POI without latitude/longitude must not produce a marker');
    expect(find.byKey(const Key('map_empty')), findsNothing);
  });

  testWidgets('tapping a marker opens the bottom sheet with name and city',
      (tester) async {
    await tester.pumpWidget(_wrap(_providerWith(mapPoisJson)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('poi_marker_p-1')));
    // Fixed-duration pumps: the sheet animation completes without relying
    // on pumpAndSettle, which tile loading could keep from settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('poi_sheet_p-1')), findsOneWidget);
    expect(find.text('Casbah of Algiers'), findsOneWidget);
    expect(find.text('Algiers'), findsOneWidget);
  });

  testWidgets('shows the explicit empty state without geolocated POIs',
      (tester) async {
    await tester.pumpWidget(_wrap(_providerWith([mapPoisJson.last])));
    await tester.pump();

    expect(find.byKey(const Key('map_empty')), findsOneWidget);
    expect(find.byType(PoiMapScreen), findsOneWidget);
  });
}
