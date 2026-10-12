import 'package:discover_ai/models/booking.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// Booking partner lifecycle getters + additive partner fields (§2 of the
/// requested/declined/expired patch).
void main() {
  test('requested ⇒ awaiting partner, cancellable, no consent, not terminal',
      () {
    final b =
        Booking.fromJson(sampleBookingJson(status: 'requested', consentGiven: true));
    expect(b.isAwaitingPartner, isTrue);
    expect(b.canCancel, isTrue);
    expect(b.canGiveConsent, isFalse);
    expect(b.isTerminal, isFalse);
    expect(b.isPending, isFalse);
  });

  test('declined + partner_note ⇒ terminal, note read, not cancellable', () {
    final b = Booking.fromJson(sampleBookingJson(
        status: 'declined', partnerNote: 'Complet ce jour-là'));
    expect(b.isDeclined, isTrue);
    expect(b.isTerminal, isTrue);
    expect(b.canCancel, isFalse);
    expect(b.partnerNote, 'Complet ce jour-là');
  });

  test('expired ⇒ isExpired and terminal', () {
    final b = Booking.fromJson(sampleBookingJson(status: 'expired'));
    expect(b.isExpired, isTrue);
    expect(b.isTerminal, isTrue);
  });

  test("unknown status 'archived' ⇒ no getter true, no exception", () {
    final b = Booking.fromJson(sampleBookingJson(status: 'archived'));
    expect(b.isPending, isFalse);
    expect(b.isAwaitingPartner, isFalse);
    expect(b.isConfirmed, isFalse);
    expect(b.isDeclined, isFalse);
    expect(b.isExpired, isFalse);
    expect(b.isCancelled, isFalse);
    expect(b.isTerminal, isFalse);
    expect(b.canCancel, isFalse);
    expect(b.canGiveConsent, isFalse);
  });

  test('partner_note / responded_at absent ⇒ null', () {
    final b = Booking.fromJson(sampleBookingJson());
    expect(b.partnerNote, isNull);
    expect(b.respondedAt, isNull);
  });

  test('responded_at is parsed via tryParse, partner_note kept as-is', () {
    final b = Booking.fromJson(sampleBookingJson(
        respondedAt: '2026-08-29T12:00:00Z', partnerNote: 'ok'));
    expect(b.respondedAt, DateTime.parse('2026-08-29T12:00:00Z'));
    expect(b.partnerNote, 'ok');
  });
}
