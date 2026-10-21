import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// BookingProvider + Idempotency-Key — mirror of the backend 0012 contract.
void main() {
  test('the provider forwards the idempotency key to the API', () async {
    final api = FakeBookingsApi(bookings: []);
    final provider = BookingProvider(bookingsApi: api);

    await provider.createBooking(
        poiId: 'p-1', adapterType: 'hotel', idempotencyKey: 'key-0001');

    expect(api.lastIdempotencyKey, 'key-0001');
    expect(api.idempotencyKeys, ['key-0001']);
  });

  test('same key + same request twice → one item, one reservation', () async {
    final api = FakeBookingsApi(bookings: []);
    final provider = BookingProvider(bookingsApi: api);

    final first = await provider.createBooking(
        poiId: 'p-1', adapterType: 'hotel', idempotencyKey: 'key-same');
    final second = await provider.createBooking(
        poiId: 'p-1', adapterType: 'hotel', idempotencyKey: 'key-same');

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(second!.id, first!.id, reason: 'the replay must return the origin');
    expect(provider.items, hasLength(1),
        reason: 'a replay must not duplicate the list item');
    expect(api.bookings, hasLength(1),
        reason: 'a replay must not create a second backend reservation');
  });

  test('same key with a different adapter → 409, items untouched', () async {
    final api = FakeBookingsApi(bookings: []);
    final provider = BookingProvider(bookingsApi: api);
    await provider.createBooking(
        poiId: 'p-1', adapterType: 'hotel', idempotencyKey: 'key-conflict');

    final failed = await provider.createBooking(
        poiId: 'p-1', adapterType: 'tour', idempotencyKey: 'key-conflict');

    expect(failed, isNull);
    expect(provider.actionStatusCode, 409);
    expect(provider.actionError, isNotNull);
    expect(provider.items, hasLength(1));
  });

  test('createError 422 → unavailable actionError, items untouched', () async {
    final api = FakeBookingsApi(bookings: [])
      ..createError = ApiException(
          422, '{"detail":"This place is information only and cannot be booked"}');
    final provider = BookingProvider(bookingsApi: api);

    final created = await provider.createBooking(
        poiId: 'p-1', adapterType: 'hotel', idempotencyKey: 'key-422');

    expect(created, isNull);
    expect(provider.actionError, BookingError.unavailable);
    expect(provider.actionStatusCode, 422);
    expect(provider.items, isEmpty);
  });

  test('api status codes map to BookingError codes', () async {
    final cases = <int?, BookingError>{
      409: BookingError.conflict,
      422: BookingError.unavailable,
      500: BookingError.generic,
      null: BookingError.network,
    };
    for (final entry in cases.entries) {
      final api = FakeBookingsApi(bookings: [])
        ..createError = ApiException(entry.key, '{"detail":"x"}');
      final provider = BookingProvider(bookingsApi: api);
      await provider.createBooking(
          poiId: 'p-1', adapterType: 'hotel', idempotencyKey: 'k');
      expect(provider.actionError, entry.value,
          reason: 'statusCode ${entry.key}');
    }
  });
}
