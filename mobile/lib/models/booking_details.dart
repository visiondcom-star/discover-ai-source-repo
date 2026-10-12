/// Booking details collected by the mobile booking sheet and sent to the
/// backend inside `booking_data` (POST /api/v1/bookings/).
///
/// The partner sees a whitelisted view of that object
/// (backend/app/schemas.py → `PartnerBookingResponse.details` accepts `date`,
/// `start_date`, `end_date`, `time`, `nights`, `guests`, `party_size`,
/// `adults`, `children`, `duration`, `notes`, `message`, `special_requests`).
/// This model only ever emits `date`, `guests` and `notes` — **no personal
/// data** (email, phone, identity document) is ever collected or written.
///
/// Immutable and Flutter-free on purpose: the same class is the single source
/// of truth for validation and for the JSON payload, so the sheet, the
/// provider and the tests share one contract.
class BookingDetails {
  const BookingDetails({
    required this.date,
    this.guests = kMinGuests,
    this.notes,
  });

  /// Local date of the visit — sent as `date` (`YYYY-MM-DD`).
  final DateTime date;

  /// Number of people, [kMinGuests]..[kMaxGuests] — sent as `guests`.
  final int guests;

  /// Free text sent as `notes`; omitted from the payload when empty.
  final String? notes;

  /// Accepted range for [guests]. The sheet's stepper and the validation
  /// below share these bounds — one place to change them.
  static const int kMinGuests = 1;
  static const int kMaxGuests = 20;

  /// Longest accepted [notes] (same 500-char ceiling as the backend's
  /// partner note).
  static const int kMaxNotesLength = 500;

  /// JSON object sent as the request's `booking_data`.
  ///
  /// `date` is zero-padded and carries neither time nor timezone, so the
  /// partner sees the very day the traveller picked. `notes` is trimmed and
  /// the key is omitted when nothing meaningful was typed.
  Map<String, dynamic> toBookingData() {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final trimmed = notes?.trim();
    return <String, dynamic>{
      'date': '${date.year}-$month-$day',
      'guests': guests,
      if (trimmed != null && trimmed.isNotEmpty) 'notes': trimmed,
    };
  }

  /// Typed validation errors, never display strings — the model stays free of
  /// any UI concern. An empty result means the details are ready to send.
  ///
  /// [now] is injectable so "today is valid, yesterday is not" is testable
  /// without touching the widget layer. Dates are compared as days, so the
  /// time of day never matters.
  List<BookingDetailsError> validate({DateTime Function()? now}) {
    final errors = <BookingDetailsError>[];
    final today = _dayOf((now ?? DateTime.now)());
    if (_dayOf(date).isBefore(today)) {
      errors.add(BookingDetailsError.pastDate);
    }
    if (guests < kMinGuests || guests > kMaxGuests) {
      errors.add(BookingDetailsError.guestsOutOfRange);
    }
    if ((notes?.length ?? 0) > kMaxNotesLength) {
      errors.add(BookingDetailsError.notesTooLong);
    }
    return errors;
  }

  /// Day granularity, so a date-only field compares by date only.
  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookingDetails &&
          _dayOf(date) == _dayOf(other.date) &&
          guests == other.guests &&
          notes == other.notes;

  @override
  int get hashCode => Object.hash(_dayOf(date), guests, notes);

  @override
  String toString() => 'BookingDetails(${toBookingData()})';
}

/// Machine-readable reasons a [BookingDetails] cannot be submitted yet. The
/// booking sheet maps them to French copy; the model never does.
enum BookingDetailsError {
  /// The chosen day is before today.
  pastDate,

  /// Outside the 1..20 people range.
  guestsOutOfRange,

  /// Longer than [BookingDetails.kMaxNotesLength].
  notesTooLong,
}
