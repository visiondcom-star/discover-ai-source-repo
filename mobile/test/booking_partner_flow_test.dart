import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/screens/bookings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fakes.dart';

/// Widget flow for the partner lifecycle (§6 of the requested/declined/
/// expired patch): manual_confirm consent, partner answers, expiry,
/// cancellation windows and unknown statuses.
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
      'manual_confirm creation + consent ⇒ awaiting the partner, snackbar, '
      'no reference', (tester) async {
    final provider = BookingProvider(bookingsApi: FakeBookingsApi(bookings: [
      sampleBookingJson(
          bookingMode: 'manual_confirm', respondBy: '2026-11-02T10:00:00Z'),
    ]));
    await pumpBookings(tester,
        bookingProvider: provider, poiProvider: await loadedPois());

    await tester.tap(find.byKey(const Key('booking_consent_b-1')));
    await tester.pumpAndSettle();
    expect(
        find.text('Votre demande sera transmise au prestataire, qui doit la '
            'confirmer.'),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('booking_consent_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('En attente du prestataire'), findsOneWidget);
    expect(find.text('Le prestataire doit confirmer avant le 2/11/2026'),
        findsOneWidget);
    expect(find.byKey(const Key('booking_ref_b-1')), findsNothing,
        reason: 'no EXT reference before the partner answers');
    expect(find.byKey(const Key('booking_consent_b-1')), findsNothing);
    expect(find.byKey(const Key('booking_cancel_b-1')), findsOneWidget);
    expect(find.byKey(const Key('booking_requested_snackbar')), findsOneWidget);
  });

  testWidgets('request-mode creation + consent ⇒ confirmed with EXT reference',
      (tester) async {
    final provider = BookingProvider(bookingsApi: FakeBookingsApi());
    await pumpBookings(tester,
        bookingProvider: provider, poiProvider: await loadedPois());

    await tester.tap(find.byKey(const Key('booking_consent_b-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking_consent_confirm')));
    await tester.pumpAndSettle();

    expect(provider.items.single.status, 'confirmed');
    expect(find.byKey(const Key('booking_ref_b-1')), findsOneWidget);
    expect(find.byKey(const Key('booking_requested_snackbar')), findsNothing,
        reason: 'non-manual_confirm consent stays a direct confirmation');
  });

  testWidgets(
      'partnerDecline + refresh ⇒ refusal label, partner note, no actions',
      (tester) async {
    final api = FakeBookingsApi(bookings: [
      sampleBookingJson(
          bookingMode: 'manual_confirm',
          status: 'requested',
          consentGiven: true),
    ]);
    final provider = BookingProvider(bookingsApi: api);
    await pumpBookings(tester,
        bookingProvider: provider, poiProvider: await loadedPois());

    api.partnerDecline('b-1', note: 'Complet ce jour-là');
    await provider.loadBookings();
    await tester.pumpAndSettle();

    expect(find.text('Refusée par le prestataire'), findsOneWidget);
    expect(find.text('Message du prestataire : Complet ce jour-là'),
        findsOneWidget);
    expect(find.byKey(const Key('booking_partner_note_b-1')), findsOneWidget);
    expect(find.byKey(const Key('booking_cancel_b-1')), findsNothing);
    expect(find.byKey(const Key('booking_consent_b-1')), findsNothing);
  });

  testWidgets('partnerConfirm + refresh ⇒ confirmed with EXT reference',
      (tester) async {
    final api = FakeBookingsApi(bookings: [
      sampleBookingJson(
          bookingMode: 'manual_confirm',
          status: 'requested',
          consentGiven: true),
    ]);
    final provider = BookingProvider(bookingsApi: api);
    await pumpBookings(tester,
        bookingProvider: provider, poiProvider: await loadedPois());

    api.partnerConfirm('b-1');
    await provider.loadBookings();
    await tester.pumpAndSettle();

    expect(find.text('confirmed'), findsOneWidget);
    expect(find.byKey(const Key('booking_ref_b-1')), findsOneWidget);
    expect(find.byKey(const Key('booking_cancel_b-1')), findsNothing);
  });

  testWidgets('expire + refresh ⇒ expired label and hint, no actions',
      (tester) async {
    final api = FakeBookingsApi(bookings: [
      sampleBookingJson(
          bookingMode: 'manual_confirm',
          status: 'requested',
          consentGiven: true),
    ]);
    final provider = BookingProvider(bookingsApi: api);
    await pumpBookings(tester,
        bookingProvider: provider, poiProvider: await loadedPois());

    api.expire('b-1');
    await provider.loadBookings();
    await tester.pumpAndSettle();

    expect(find.text('Demande expirée'), findsOneWidget);
    expect(find.byKey(const Key('booking_expired_hint_b-1')), findsOneWidget);
    expect(find.byKey(const Key('booking_cancel_b-1')), findsNothing);
    expect(find.byKey(const Key('booking_consent_b-1')), findsNothing);
  });

  testWidgets('cancelling a requested booking ⇒ cancelled, no buttons left',
      (tester) async {
    final provider = BookingProvider(bookingsApi: FakeBookingsApi(bookings: [
      sampleBookingJson(bookingMode: 'manual_confirm'),
    ]));
    await pumpBookings(tester,
        bookingProvider: provider, poiProvider: await loadedPois());

    await tester.tap(find.byKey(const Key('booking_consent_b-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking_consent_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking_cancel_b-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('booking_cancel_b-1')));
    await tester.pumpAndSettle();

    expect(provider.items.single.status, 'cancelled');
    expect(find.byKey(const Key('booking_cancel_b-1')), findsNothing);
    expect(find.byKey(const Key('booking_consent_b-1')), findsNothing);
  });

  testWidgets('cancelling from declined ⇒ readable 409, status unchanged',
      (tester) async {
    final provider = BookingProvider(bookingsApi: FakeBookingsApi(bookings: [
      sampleBookingJson(
          bookingMode: 'manual_confirm',
          status: 'declined',
          consentGiven: true,
          partnerNote: 'Complet ce jour-là'),
    ]));
    await pumpBookings(tester,
        bookingProvider: provider, poiProvider: await loadedPois());
    // No cancel button on the card (declined is not cancellable): the
    // backend refusal is exercised through the provider seam.
    await provider.cancelBooking(provider.items.single);
    await tester.pumpAndSettle();

    expect(provider.actionError,
        'Cette réservation ne peut plus être annulée.');
    expect(provider.items.single.status, 'declined');
  });

  testWidgets('an unknown status still renders its raw text, no exception',
      (tester) async {
    final provider = BookingProvider(bookingsApi: FakeBookingsApi(bookings: [
      sampleBookingJson(status: 'archived'),
    ]));
    await pumpBookings(tester,
        bookingProvider: provider, poiProvider: await loadedPois());

    expect(find.byKey(const Key('booking_card_b-1')), findsOneWidget);
    expect(find.text('archived'), findsOneWidget);
    expect(find.byKey(const Key('booking_consent_b-1')), findsNothing);
    expect(find.byKey(const Key('booking_cancel_b-1')), findsNothing);
  });
}

