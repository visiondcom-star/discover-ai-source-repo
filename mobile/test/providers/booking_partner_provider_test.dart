import 'dart:io';

import 'package:discover_ai/models/booking.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

class _SocketThrowingBookingsApi extends FakeBookingsApi {
  @override
  Future<Map<String, dynamic>> createBooking({
    required String poiId,
    required String adapterType,
    Map<String, dynamic>? bookingData,
    String? idempotencyKey,
  }) async {
    throw const SocketException('no internet');
  }

  @override
  Future<List<Map<String, dynamic>>> listBookings() async {
    throw const SocketException('no internet');
  }
}

class _FormatThrowingBookingsApi extends FakeBookingsApi {
  @override
  Future<Map<String, dynamic>> createBooking({
    required String poiId,
    required String adapterType,
    Map<String, dynamic>? bookingData,
    String? idempotencyKey,
  }) async {
    throw const FormatException('bad json');
  }

  @override
  Future<List<Map<String, dynamic>>> listBookings() async {
    throw const FormatException('bad json');
  }
}

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

  test('cancel: 409 → notCancellable, 5xx → generic, null → network', () async {
    // 409 via a declined manual_confirm booking (backend contract)
    final api409 = FakeBookingsApi(bookings: [
      sampleBookingJson(bookingMode: 'manual_confirm'),
    ]);
    final p409 = BookingProvider(bookingsApi: api409);
    await p409.loadBookings();
    api409.partnerDecline(p409.items.single.id);
    await p409.cancelBooking(p409.items.single);
    expect(p409.cancelError, BookingCancelError.notCancellable);

    // 500 → generic via cancelError
    final api500 = FakeBookingsApi(bookings: [])
      ..cancelError = ApiException(500, '{}');
    final p500 = BookingProvider(bookingsApi: api500);
    await p500.cancelBooking(Booking.fromJson(sampleBookingJson()));
    expect(p500.cancelError, BookingCancelError.generic);

    // null status → network via cancelError
    final apiNet = FakeBookingsApi(bookings: [])
      ..cancelError = ApiException(null, '{}');
    final pNet = BookingProvider(bookingsApi: apiNet);
    await pNet.cancelBooking(Booking.fromJson(sampleBookingJson()));
    expect(pNet.cancelError, BookingCancelError.network);
  });

  test(
      'create: 409 → conflict, 422 → unavailable, 5xx → generic, null → network',
      () async {
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

  test('SocketException maps to network error', () async {
    final provider = BookingProvider(bookingsApi: _SocketThrowingBookingsApi());
    await provider.createBooking(
        poiId: 'p-1', adapterType: 'hotel', idempotencyKey: 'k');
    expect(provider.actionError, BookingError.network);
  });

  test('FormatException maps to generic error', () async {
    final provider = BookingProvider(bookingsApi: _FormatThrowingBookingsApi());
    await provider.createBooking(
        poiId: 'p-1', adapterType: 'hotel', idempotencyKey: 'k');
    expect(provider.actionError, BookingError.generic);
  });

  test('loadBookings with SocketException maps to BookingLoadError.network',
      () async {
    final provider = BookingProvider(bookingsApi: _SocketThrowingBookingsApi());
    await provider.loadBookings();
    expect(provider.loadError, BookingLoadError.network);
    expect(provider.items, isEmpty);
  });

  test('loadBookings with FormatException maps to BookingLoadError.generic',
      () async {
    final provider = BookingProvider(bookingsApi: _FormatThrowingBookingsApi());
    await provider.loadBookings();
    expect(provider.loadError, BookingLoadError.generic);
    expect(provider.items, isEmpty);
  });
}
