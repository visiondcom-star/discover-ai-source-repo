import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/l10n/app_localizations_en.dart';
import 'package:discover_ai/l10n/app_localizations_fr.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/screens/bookings_screen.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
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
    Locale locale = const Locale('fr'),
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BookingProvider>.value(value: bookingProvider),
          ChangeNotifierProvider<POIProvider>.value(value: poiProvider),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: const BookingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'manual_confirm creation + consent ⇒ awaiting the partner, snackbar, '
      'no reference', (tester) async {
    final provider = BookingProvider(
        bookingsApi: FakeBookingsApi(bookings: [
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
    // The deadline line goes through bookingAwaitingPartnerBy and the
    // locale-aware formatDate ⇒ « 2 nov. 2026 » in FR (not 2/11/2026).
    // The expected wording is built from the same sources as the UI: the
    // locale-aware date format and the FR localization.
    final date = DateFormat.yMMMd('fr').format(DateTime(2026, 11, 2));
    expect(find.text(AppLocalizationsFr().bookingAwaitingPartnerBy(date)),
        findsOneWidget);
    expect(find.byKey(const Key('booking_awaiting_b-1')), findsOneWidget);
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

    expect(
        find.text(AppLocalizationsFr().bookingStatusConfirmed), findsOneWidget);
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
    final provider = BookingProvider(
        bookingsApi: FakeBookingsApi(bookings: [
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

  testWidgets(
      'cancelling from declined ⇒ structured 409 code, status unchanged',
      (tester) async {
    final provider = BookingProvider(
        bookingsApi: FakeBookingsApi(bookings: [
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

    expect(provider.cancelError, BookingCancelError.notCancellable,
        reason: '409 ⇒ the booking left the cancellable window');
    expect(provider.actionError, isNull,
        reason: 'a refused cancellation never uses the create/consent code');
    expect(provider.items.single.status, 'declined');
  });

  testWidgets('an unknown status still renders its raw text, no exception',
      (tester) async {
    final provider = BookingProvider(
        bookingsApi: FakeBookingsApi(bookings: [
      sampleBookingJson(status: 'archived'),
    ]));
    await pumpBookings(tester,
        bookingProvider: provider, poiProvider: await loadedPois());

    expect(find.byKey(const Key('booking_card_b-1')), findsOneWidget);
    expect(find.text('archived'), findsOneWidget);
    expect(find.byKey(const Key('booking_consent_b-1')), findsNothing);
    expect(find.byKey(const Key('booking_cancel_b-1')), findsNothing);
  });

  /// Cancels a pending booking whose cancellation fails with [error] and
  /// asserts the failure is surfaced as a snackbar carrying [expectedMessage]
  /// — the wording comes from the localization, never from a literal.
  Future<void> expectCancelFailureSnackbar(
    WidgetTester tester, {
    required ApiException error,
    required String expectedMessage,
    required Locale locale,
  }) async {
    final api = FakeBookingsApi(bookings: [sampleBookingJson()])
      ..cancelError = error;
    final provider = BookingProvider(bookingsApi: api);
    await pumpBookings(tester,
        bookingProvider: provider,
        poiProvider: await loadedPois(),
        locale: locale);

    await tester.tap(find.byKey(const Key('booking_cancel_b-1')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('booking_cancel_error_snackbar')), findsOneWidget,
        reason: 'a failed cancellation must be reported to the traveller');
    expect(find.text(expectedMessage), findsOneWidget);
    // The booking is untouched: a refusal never changes its status.
    expect(provider.items.single.status, 'pending');
  }

  testWidgets('cancel 409 ⇒ snackbar « not cancellable » in FR',
      (tester) async {
    await expectCancelFailureSnackbar(
      tester,
      error: ApiException(409, '{"detail":"Booking cannot be cancelled"}'),
      expectedMessage: AppLocalizationsFr().bookingCancelErrorNotCancellable,
      locale: const Locale('fr'),
    );
    expect(find.text(AppLocalizationsFr().bookingCancelErrorNotCancellable),
        findsOneWidget);
  });

  testWidgets('cancel 500 ⇒ snackbar « generic failure » in FR',
      (tester) async {
    await expectCancelFailureSnackbar(
      tester,
      error: ApiException(500, '{"detail":"Server error"}'),
      expectedMessage: AppLocalizationsFr().bookingCancelErrorGeneric,
      locale: const Locale('fr'),
    );
  });

  testWidgets(
      'cancel network failure ⇒ snackbar « check your connection » in FR',
      (tester) async {
    await expectCancelFailureSnackbar(
      tester,
      error: ApiException(null, '{"detail":"Network error"}'),
      expectedMessage: AppLocalizationsFr().bookingCancelErrorNetwork,
      locale: const Locale('fr'),
    );
  });

  testWidgets('cancel 409 ⇒ snackbar « not cancellable » in EN',
      (tester) async {
    await expectCancelFailureSnackbar(
      tester,
      error: ApiException(409, '{"detail":"Booking cannot be cancelled"}'),
      expectedMessage: AppLocalizationsEn().bookingCancelErrorNotCancellable,
      locale: const Locale('en'),
    );
  });

  testWidgets('cancel 500 ⇒ snackbar « generic failure » in EN',
      (tester) async {
    await expectCancelFailureSnackbar(
      tester,
      error: ApiException(500, '{"detail":"Server error"}'),
      expectedMessage: AppLocalizationsEn().bookingCancelErrorGeneric,
      locale: const Locale('en'),
    );
  });

  testWidgets(
      'cancel network failure ⇒ snackbar « check your connection » in EN',
      (tester) async {
    await expectCancelFailureSnackbar(
      tester,
      error: ApiException(null, '{"detail":"Network error"}'),
      expectedMessage: AppLocalizationsEn().bookingCancelErrorNetwork,
      locale: const Locale('en'),
    );
  });
}
