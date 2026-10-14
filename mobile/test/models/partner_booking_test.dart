import 'package:discover_ai/models/partner_booking.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// PartnerBooking reuses Booking.fromJson for every shared field and layers on
/// poi_name / traveller_name / details. Tolerant: a missing field never
/// crashes — it falls back to a safe default.
void main() {
  test('fromPartnerJson reads the full payload', () {
    final booking = PartnerBooking.fromPartnerJson(samplePartnerBookingJson());
    expect(booking.id, 'b-1');
    expect(booking.status, 'requested');
    expect(booking.bookingMode, 'manual_confirm');
    expect(booking.isAwaitingPartner, isTrue);
    expect(booking.poiName, 'Hôtel El Djazaïr');
    expect(booking.travellerName, 'Amine');
    expect(booking.details['date'], '2026-09-15');
    expect(booking.details['guests'], 2);
    expect(booking.details['notes'], 'Chambre calme si possible.');
  });

  test('traveller_name null is preserved (never an email fallback)', () {
    final booking =
        PartnerBooking.fromPartnerJson(samplePartnerBookingJson(travellerName: null));
    expect(booking.travellerName, isNull);
  });

  test('empty details yields empty map and null detail labels', () {
    final booking =
        PartnerBooking.fromPartnerJson(samplePartnerBookingJson(details: {}));
    expect(booking.details, isEmpty);
    expect(booking.dateLabel, isNull);
    expect(booking.guestsLabel, isNull);
    expect(booking.notes, isNull);
  });

  test('missing partner-only fields fall back to defaults, no crash', () {
    // A pre-partner payload: only the base booking fields.
    final json = sampleBookingJson(status: 'requested');
    final booking = PartnerBooking.fromPartnerJson(json);
    expect(booking.poiName, '');
    expect(booking.travellerName, isNull);
    expect(booking.details, isEmpty);
    expect(booking.id, 'b-1');
  });

  test('details of an unexpected type degrade to an empty map', () {
    final json = samplePartnerBookingJson()..['details'] = 'not-a-map';
    final booking = PartnerBooking.fromPartnerJson(json);
    expect(booking.details, isEmpty);
  });

  test('date/guests/notes read the details keys, blank notes → null', () {
    final booking = PartnerBooking.fromPartnerJson(samplePartnerBookingJson(
      details: <String, dynamic>{'date': '2026-09-15', 'guests': 3, 'notes': '   '},
    ));
    expect(booking.dateLabel, '2026-09-15');
    expect(booking.guestsLabel, '3');
    expect(booking.notes, isNull);
  });

  test('guests accepts a numeric string, missing date tolerated', () {
    final booking = PartnerBooking.fromPartnerJson(samplePartnerBookingJson(
      details: <String, dynamic>{'guests': '4'},
    ));
    expect(booking.dateLabel, isNull);
    expect(booking.guestsLabel, '4');
  });

  test('respond_by deadline helpers: overdue, soon, far', () {
    final now = DateTime(2026, 9, 10, 12);
    final overdue = PartnerBooking.fromPartnerJson(
        samplePartnerBookingJson(respondBy: '2026-09-09T10:00:00Z'));
    final soon = PartnerBooking.fromPartnerJson(
        samplePartnerBookingJson(respondBy: '2026-09-10T20:00:00Z'));
    final far = PartnerBooking.fromPartnerJson(
        samplePartnerBookingJson(respondBy: '2026-09-20T10:00:00Z'));
    final none = PartnerBooking.fromPartnerJson(
        samplePartnerBookingJson(respondBy: null));

    expect(overdue.isOverdue(now), isTrue);
    expect(soon.isOverdue(now), isFalse);
    expect(soon.isDueSoon(now), isTrue);
    expect(far.isDueSoon(now), isFalse);
    expect(none.isDueSoon(now), isFalse);
    expect(none.isOverdue(now), isFalse);
  });
}
