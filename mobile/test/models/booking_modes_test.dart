import 'package:discover_ai/models/booking.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// Booking.bookingMode / Booking.respondBy — additive fields (0012).
void main() {
  test('fromJson fills booking_mode and respond_by', () {
    final booking = Booking.fromJson(sampleBookingJson(
      bookingMode: 'manual_confirm',
      respondBy: '2026-11-02T10:00:00Z',
    ));
    expect(booking.bookingMode, 'manual_confirm');
    expect(booking.respondBy, DateTime.parse('2026-11-02T10:00:00Z'));
  });

  test('fromJson defaults when the payload predates the 0012 fields', () {
    final json = sampleBookingJson()
      ..remove('booking_mode')
      ..remove('respond_by');
    final booking = Booking.fromJson(json);
    expect(booking.bookingMode, 'request');
    expect(booking.respondBy, isNull);
  });
}
