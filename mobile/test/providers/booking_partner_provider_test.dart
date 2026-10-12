import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// Provider contract for the partner lifecycle (§4 of the
/// requested/declined/expired patch): the server response is used as-is and
/// the cancellation errors get their own copy.
void main() {
  test('giveConsent on a manual_confirm booking stays requested', () async {
    final api = FakeBookingsApi(bookings: [
      sampleBookingJson(bookingMode: 'manual_confirm'),
    ]);
    final provider = BookingProvider(bookingsApi: api);
    await provider.loadBookings();

    final updated =
        await provider.giveConsent(provider.items.single, consent: true);

    expect(updated, isNotNull);
    expect(updated!.status, 'requested');
    expect(provider.items.single.status, 'requested',
        reason: 'the provider must never force confirmed');
  });

  test('cancelErrorMessage maps 409 to the dedicated cancellation copy', () {
    expect(
      cancelErrorMessage(
          ApiException(409, '{"detail":"Booking cannot be cancelled"}')),
      'Cette réservation ne peut plus être annulée.',
    );
    expect(cancelErrorMessage(ApiException(500, '{}')),
        contains('Réessayez'));
    expect(cancelErrorMessage(ApiException(null, '{}')),
        contains('Réessayez'));
  });

  test('bookingErrorMessage keeps its creation cases untouched', () {
    expect(bookingErrorMessage(ApiException(409, '{}')),
        contains('informations différentes'));
    expect(bookingErrorMessage(ApiException(422, '{}')),
        contains('pas disponible'));
    expect(bookingErrorMessage(ApiException(500, '{}')),
        contains('Réessayez dans un instant'));
    expect(bookingErrorMessage(ApiException(null, '{}')),
        contains('Réessayez dans un instant'));
  });
}
