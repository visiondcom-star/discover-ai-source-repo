import 'package:discover_ai/models/booking_details.dart';
import 'package:flutter_test/flutter_test.dart';

/// BookingDetails — payload shape, validation and value equality. Pure Dart:
/// the injected clock makes "today is valid, yesterday is not" deterministic.
void main() {
  final today = DateTime(2026, 8, 24, 15, 30); // time must never matter.

  group('toBookingData', () {
    test('emits YYYY-MM-DD (zero-padded), integer guests and trimmed notes', () {
      final data = BookingDetails(
        date: DateTime(2026, 3, 7),
        guests: 3,
        notes: '  Table près de la fenêtre  ',
      ).toBookingData();

      expect(data['date'], '2026-03-07');
      expect(data['guests'], 3);
      expect(data['guests'], isA<int>());
      expect(data['notes'], 'Table près de la fenêtre');
    });

    test('omits the notes key when empty or only spaces', () {
      for (final note in <String?>[null, '', '   ', '\n\t ']) {
        final data =
            BookingDetails(date: today, guests: 2, notes: note).toBookingData();
        expect(data.containsKey('notes'), isFalse,
            reason: 'notes "$note" must not produce a notes key');
      }
    });
  });

  group('validate', () {
    test('accepts today and refuses a past date (clock injected)', () {
      expect(
        BookingDetails(date: today).validate(now: () => today),
        isEmpty,
        reason: 'today is a valid visit date',
      );
      expect(
        BookingDetails(date: DateTime(2026, 8, 23))
            .validate(now: () => today),
        [BookingDetailsError.pastDate],
      );
    });

    test('accepts guests 1 and 20, refuses 0 and 21', () {
      expect(
        BookingDetails(date: today, guests: 1).validate(now: () => today),
        isEmpty,
      );
      expect(
        BookingDetails(date: today, guests: 20).validate(now: () => today),
        isEmpty,
      );
      expect(
        BookingDetails(date: today, guests: 0).validate(now: () => today),
        [BookingDetailsError.guestsOutOfRange],
      );
      expect(
        BookingDetails(date: today, guests: 21).validate(now: () => today),
        [BookingDetailsError.guestsOutOfRange],
      );
    });

    test('accepts 500-char notes, refuses 501', () {
      expect(
        BookingDetails(date: today, notes: 'a' * 500)
            .validate(now: () => today),
        isEmpty,
      );
      expect(
        BookingDetails(date: today, notes: 'a' * 501)
            .validate(now: () => today),
        [BookingDetailsError.notesTooLong],
      );
    });
  });

  group('equality', () {
    test('is by value; differing details are not equal', () {
      final a = BookingDetails(date: DateTime(2026, 8, 24), guests: 2);
      final b = BookingDetails(date: DateTime(2026, 8, 24, 23, 59), guests: 2);
      expect(a, b, reason: 'same day, same guests — time of day ignored');
      expect(a.hashCode, b.hashCode);

      expect(a, isNot(BookingDetails(date: DateTime(2026, 8, 25), guests: 2)));
      expect(a, isNot(BookingDetails(date: DateTime(2026, 8, 24), guests: 3)));
      expect(
        BookingDetails(date: DateTime(2026, 8, 24), guests: 2, notes: 'x'),
        isNot(a),
      );
    });
  });
}
