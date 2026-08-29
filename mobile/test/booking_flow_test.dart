import 'package:discover_ai/models/poi.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/screens/bookings_screen.dart';
import 'package:discover_ai/screens/poi_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fakes.dart';

POI _poi(Map<String, dynamic> json) => POI.fromJson(json);

void main() {
  Future<POIProvider> loadedPois() async {
    final provider = POIProvider(poisApi: FakePoisApi());
    await provider.loadPOIs();
    return provider;
  }

  Future<void> pumpBookings(
    WidgetTester tester, {
    required BookingProvider bookingProvider,
    required POIProvider poiProvider,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BookingProvider>.value(value: bookingProvider),
          ChangeNotifierProvider<POIProvider>.value(value: poiProvider),
        ],
        child: const MaterialApp(home: BookingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'renders the pending booking with consent and cancel actions and the '
      'resolved POI name', (tester) async {
    await pumpBookings(
      tester,
      bookingProvider: BookingProvider(bookingsApi: FakeBookingsApi()),
      poiProvider: await loadedPois(),
    );
    expect(find.byKey(const Key('booking_card_b-1')), findsOneWidget);
    expect(find.byKey(const Key('booking_status_b-1')), findsOneWidget);
    expect(find.text('Casbah of Algiers'), findsOneWidget);
    expect(find.byKey(const Key('booking_consent_b-1')), findsOneWidget);
    expect(find.byKey(const Key('booking_cancel_b-1')), findsOneWidget);
    expect(find.byKey(const Key('booking_ref_b-1')), findsNothing,
        reason: 'no external reference before consent');
  });

  testWidgets('refusing consent cancels the booking', (tester) async {
    final api = FakeBookingsApi();
    final provider = BookingProvider(bookingsApi: api);
    await pumpBookings(tester,
        bookingProvider: provider, poiProvider: await loadedPois());

    await tester.tap(find.byKey(const Key('booking_consent_b-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking_consent_dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('booking_consent_refuse')));
    await tester.pumpAndSettle();
    expect(api.lastConsentValue, false);
    expect(provider.items.single.status, 'cancelled');
    expect(find.byKey(const Key('booking_consent_b-1')), findsNothing,
        reason: 'a cancelled booking has no consent action left');
  });

  testWidgets('confirming consent confirms with an EXT reference',
      (tester) async {
    final api = FakeBookingsApi();
    final provider = BookingProvider(bookingsApi: api);
    await pumpBookings(tester,
        bookingProvider: provider, poiProvider: await loadedPois());

    await tester.tap(find.byKey(const Key('booking_consent_b-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking_consent_confirm')));
    await tester.pumpAndSettle();

    expect(api.lastConsentValue, true);
    expect(provider.items.single.status, 'confirmed');
    expect(find.byKey(const Key('booking_ref_b-1')), findsOneWidget);
  });

  testWidgets('shows the empty state when no booking exists', (tester) async {
    await pumpBookings(
      tester,
      bookingProvider:
          BookingProvider(bookingsApi: FakeBookingsApi(bookings: [])),
      poiProvider: await loadedPois(),
    );
    expect(find.byKey(const Key('bookings_empty')), findsOneWidget);
  });

  testWidgets('the POI detail book button walks the full consent flow',
      (tester) async {
    final api = FakeBookingsApi(bookings: []);
    final provider = BookingProvider(bookingsApi: api);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BookingProvider>.value(value: provider),
          ChangeNotifierProvider<POIProvider>.value(value: await loadedPois()),
        ],
        child: MaterialApp(
            home: PoiDetailScreen(poi: _poi(samplePoisJson[0]))),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
        find.byKey(const Key('poi_detail_book_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('poi_detail_book_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking_sheet')), findsOneWidget);
    expect(find.byKey(const Key('booking_adapter_hotel')), findsOneWidget);
    expect(find.byKey(const Key('booking_adapter_tour')), findsOneWidget,
        reason: 'the sheet lists every adapter the backend advertises');

    await tester.tap(find.byKey(const Key('booking_adapter_hotel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking_create_button')));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.lastCreatedPoiId, 'p-1');
    expect(api.lastCreatedAdapter, 'hotel');
    expect(find.byKey(const Key('booking_consent_dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('booking_consent_confirm')));
    await tester.pumpAndSettle();
    expect(provider.items.single.status, 'confirmed');
    expect(provider.items.single.externalId, 'EXT-b-1');
  });
}