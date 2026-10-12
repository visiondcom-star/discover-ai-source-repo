import 'package:discover_ai/models/booking_details.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// BookingProvider + booking_data: the idempotency key is bound to the
/// request *content*, so a network retry replays while any changed field
/// (here: the guest count) starts a fresh logical attempt.
void main() {
  final details = BookingDetails(date: DateTime(2026, 8, 24), guests: 2);

  test('same content, two attempts (retry) → same key', () async {
    final api = FakeBookingsApi(bookings: [])
      ..createError = ApiException(500, '{"detail":"backend unavailable"}');
    final provider = BookingProvider(bookingsApi: api);

    // First attempt fails (transport/5xx) — the key must be kept for the
    // retry, exactly like a flaky connection.
    await provider.createBooking(
        poiId: 'p-1', adapterType: 'hotel', details: details);
    api.createError = null;
    await provider.createBooking(
        poiId: 'p-1', adapterType: 'hotel', details: details);

    expect(api.idempotencyKeys, hasLength(2));
    expect(api.idempotencyKeys[0], isNotNull);
    expect(api.idempotencyKeys[1], api.idempotencyKeys[0],
        reason: 'unchanged content must reuse the key on retry');
  });

  test('guests changed between two attempts → different key', () async {
    final api = FakeBookingsApi(bookings: [])
      ..createError = ApiException(500, '{"detail":"backend unavailable"}');
    final provider = BookingProvider(bookingsApi: api);

    await provider.createBooking(
        poiId: 'p-1', adapterType: 'hotel', details: details);
    api.createError = null;
    await provider.createBooking(
      poiId: 'p-1',
      adapterType: 'hotel',
      details: BookingDetails(date: details.date, guests: details.guests + 1),
    );

    expect(api.idempotencyKeys, hasLength(2));
    expect(api.idempotencyKeys[1], isNot(api.idempotencyKeys[0]),
        reason: 'a different body would be a 409 on the same key');
  });

  test('details become booking_data on the wire', () async {
    final api = FakeBookingsApi(bookings: []);
    final provider = BookingProvider(bookingsApi: api);

    await provider.createBooking(
      poiId: 'p-1',
      adapterType: 'hotel',
      details: BookingDetails(
          date: DateTime(2026, 3, 7), guests: 4, notes: 'Anniversaire'),
    );

    expect(api.lastBookingData, {
      'date': '2026-03-07',
      'guests': 4,
      'notes': 'Anniversaire',
    });
  });

  test('no details → no booking_data sent (historical body preserved)',
      () async {
    final api = FakeBookingsApi(bookings: []);
    final provider = BookingProvider(bookingsApi: api);

    await provider.createBooking(poiId: 'p-1', adapterType: 'hotel');

    expect(api.lastBookingData, isNull);
  });
}
