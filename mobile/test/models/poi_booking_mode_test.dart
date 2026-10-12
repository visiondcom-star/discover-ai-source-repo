import 'package:discover_ai/models/poi.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// POI.bookingMode — mirror of the backend `booking_mode` (0012).
void main() {
  test('fromJson without booking_mode defaults to request and is bookable', () {
    final poi = POI.fromJson(Map<String, dynamic>.from(samplePoisJson[0]));
    expect(poi.bookingMode, 'request');
    expect(poi.isBookable, isTrue);
    expect(poi.isInfoOnly, isFalse);
  });

  test('info_only is visible but not bookable', () {
    final poi = POI.fromJson(
        {...samplePoisJson[0], 'booking_mode': 'info_only'});
    expect(poi.bookingMode, 'info_only');
    expect(poi.isInfoOnly, isTrue);
    expect(poi.isBookable, isFalse);
  });

  test('deposit and online_payment are not bookable', () {
    for (final mode in ['deposit', 'online_payment']) {
      final poi = POI.fromJson({...samplePoisJson[0], 'booking_mode': mode});
      expect(poi.isBookable, isFalse, reason: mode);
      expect(poi.isInfoOnly, isFalse, reason: mode);
    }
  });

  test('toJson keeps the mode through a fromJson round-trip', () {
    final poi =
        POI.fromJson({...samplePoisJson[0], 'booking_mode': 'pay_on_site'});
    expect(poi.toJson()['booking_mode'], 'pay_on_site');
    final round = POI.fromJson(poi.toJson());
    expect(round.bookingMode, 'pay_on_site');
  });
}
