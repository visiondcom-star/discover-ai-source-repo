import 'booking.dart';

/// Partner-facing view of a booking awaiting a decision
/// (`GET /partner/bookings`, `POST /partner/bookings/{id}/respond`).
///
/// Extends [Booking] and reuses `Booking.fromJson` verbatim for every shared
/// field — nothing is duplicated or re-parsed here. On top of the base booking
/// it carries the three fields the partner needs to decide:
///
/// * [poiName] — the place's name (the traveller-side booking only carries a
///   `poi_id`);
/// * [travellerName] — the requester's display name, `null` when the backend
///   could not resolve it. It is **never** an email or any contact detail;
/// * [details] — the whitelisted request payload (`date`, `guests`, `notes`, …)
///   served only to partner/admin calls.
///
/// Tolerant by design: any field the backend omits falls back to a safe
/// default, so a partially-populated payload never crashes the screen.
class PartnerBooking extends Booking {
  PartnerBooking({
    required super.id,
    required super.tenantId,
    required super.userId,
    required super.poiId,
    required super.adapterType,
    required super.status,
    required super.consentGiven,
    required super.createdAt,
    super.externalId,
    super.price,
    required super.currency,
    super.bookingMode = 'request',
    super.respondBy,
    super.partnerNote,
    super.respondedAt,
    required this.poiName,
    this.travellerName,
    Map<String, dynamic>? details,
  }) : details = details ?? const <String, dynamic>{};

  /// Name of the managed place. Always a non-null string: the backend never
  /// sends `null` here (it maps a missing POI to `""`).
  final String poiName;

  /// Requester's display name, or `null` when unknown. Never an email.
  final String? travellerName;

  /// Whitelisted request details (`date`, `guests`, `notes`, …). Values are
  /// not typed by the backend, so read them through [dateLabel], [guestsLabel]
  /// and [notes] rather than indexing the map directly.
  final Map<String, dynamic> details;

  /// Builds a [PartnerBooking] from a `PartnerBookingResponse` payload.
  ///
  /// Delegates every shared field to [Booking.fromJson] so the base contract
  /// stays the single source of truth, then layers on the partner-only fields.
  static PartnerBooking fromPartnerJson(Map<String, dynamic> json) {
    final base = Booking.fromJson(json);
    return PartnerBooking(
      id: base.id,
      tenantId: base.tenantId,
      userId: base.userId,
      poiId: base.poiId,
      adapterType: base.adapterType,
      status: base.status,
      consentGiven: base.consentGiven,
      createdAt: base.createdAt,
      externalId: base.externalId,
      price: base.price,
      currency: base.currency,
      bookingMode: base.bookingMode,
      respondBy: base.respondBy,
      partnerNote: base.partnerNote,
      respondedAt: base.respondedAt,
      poiName: _readString(json['poi_name']) ?? '',
      travellerName: _readString(json['traveller_name']),
      details: _readMap(json['details']),
    );
  }

  /// Visit date as a display string, or `null` when `details` has no usable
  /// `date`. Accepts a string (`YYYY-MM-DD`) or a scalar, so a differently
  /// typed payload degrades to "not shown" instead of throwing.
  String? get dateLabel => _readString(details['date']);

  /// Number of people as a display string, or `null` when absent. Handles int,
  /// double and string forms.
  String? get guestsLabel => _readNumberString(details['guests']);

  /// Free-text note (`notes`) from the traveller, or `null` when absent/empty.
  String? get notes {
    final value = _readString(details['notes']);
    return (value == null || value.trim().isEmpty) ? null : value;
  }

  /// True when the response deadline is within the next 24 hours (the card
  /// highlights these). A missing [respondBy] is never "soon".
  bool isDueSoon(DateTime now) {
    final deadline = respondBy;
    if (deadline == null) return false;
    final remaining = deadline.difference(now);
    return !remaining.isNegative && remaining <= const Duration(hours: 24);
  }

  /// True when the response deadline has already passed.
  bool isOverdue(DateTime now) => respondBy != null && respondBy!.isBefore(now);

  /// Backward-compatible alias of [isOverdue].
  bool isPastDeadline(DateTime now) => isOverdue(now);

  /// Reads a value as a trimmed, non-empty string, or `null`.
  static String? _readString(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  /// Reads a numeric value (int, double or numeric string) as a plain string,
  /// or `null` when it is missing or not numeric.
  static String? _readNumberString(Object? value) {
    if (value is int) return value.toString();
    if (value is double) {
      final rounded = value.round();
      return value == rounded ? rounded.toString() : value.toString();
    }
    return _readString(value);
  }

  /// Reads `details` as a string-keyed map, defaulting to empty when the
  /// backend sent something unexpected.
  static Map<String, dynamic> _readMap(Object? value) {
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return const <String, dynamic>{};
  }
}
