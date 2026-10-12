import 'dart:convert';

import 'package:discover_ai/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// ApiService.createBooking — the real adapter's JSON body and its
/// Idempotency-Key header, intercepted at the transport layer with a
/// MockClient inside `http.runWithClient` (no network, no pubspec change:
/// MockClient ships with `package:http`).
void main() {
  /// Runs [body] with a recording client as the default top-level http
  /// client (no network) and returns the single captured request.
  Future<http.Request> capture(Future<void> Function() body) async {
    http.Request? captured;
    final handler = MockClient((req) async {
      captured = req;
      return http.Response(jsonEncode({'id': 'b-1', 'status': 'pending'}), 200);
    });
    await http.runWithClient(body, () => handler);
    return captured!;
  }

  test('body carries booking_data when details are provided', () async {
    final api = ApiService.withConfig(baseUrl: 'http://test.local');
    final req = await capture(
      () => api.createBooking(
        poiId: 'p-1',
        adapterType: 'hotel',
        bookingData: {'date': '2026-03-07', 'guests': 3, 'notes': 'Table'},
      ),
    );

    final sent = jsonDecode(req.body) as Map<String, dynamic>;
    expect(sent['booking_data'], {
      'date': '2026-03-07',
      'guests': 3,
      'notes': 'Table',
    });
  });

  test('body has an empty booking_data object when details are absent',
      () async {
    final api = ApiService.withConfig(baseUrl: 'http://test.local');
    final req = await capture(
        () => api.createBooking(poiId: 'p-1', adapterType: 'hotel'));

    final sent = jsonDecode(req.body) as Map<String, dynamic>;
    expect(sent['booking_data'], <String, dynamic>{},
        reason: 'historical body preserved byte for byte');
  });

  test('Idempotency-Key header is set when provided, absent otherwise',
      () async {
    final api = ApiService.withConfig(baseUrl: 'http://test.local');

    final withKey = await capture(
      () => api.createBooking(
        poiId: 'p-1',
        adapterType: 'hotel',
        idempotencyKey: 'key-1234',
      ),
    );
    expect(withKey.headers['Idempotency-Key'], 'key-1234');

    final without = await capture(
        () => api.createBooking(poiId: 'p-1', adapterType: 'hotel'));
    expect(without.headers.containsKey('Idempotency-Key'), isFalse);
  });
}
