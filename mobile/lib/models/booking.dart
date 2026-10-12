/// Mirrors the backend `BookingResponse` schema
/// (backend/app/schemas.py → Booking Schemas).
/// Keep fields in sync — no divergence between backend and mobile.
class Booking {
  Booking({
    required this.id,
    required this.tenantId,
    required this.userId,
    required this.poiId,
    required this.adapterType,
    this.externalId,
    required this.status,
    required this.consentGiven,
    this.price,
    required this.currency,
    this.bookingMode = 'request',
    this.respondBy,
    this.partnerNote,
    this.respondedAt,
    this.createdAt,
  });

  final String id;
  final String tenantId;
  final String userId;
  final String poiId;

  /// One of hotel | restaurant | tour | transport (validated backend-side).
  final String adapterType;

  /// Adapter reference generated only after explicit user consent
  /// (`EXT-…`); null while the booking is pending.
  final String? externalId;

  /// Backend state machine: pending → requested → confirmed | declined,
  /// then expired or cancelled (backend `booking.booking_status`). An
  /// unknown value must stay renderable (raw text), never crash the app.
  final String status;
  final bool consentGiven;

  /// Never populated by the current backend — rendered only when present.
  final double? price;

  /// Human-readable note from the partner (additive backend field
  /// `partner_note`); null when absent.
  final String? partnerNote;

  /// Instant at which the partner answered (additive backend field
  /// `responded_at`, ISO 8601); null while not answered.
  final DateTime? respondedAt;

  final String currency;

  /// Booking mode frozen at creation time from the POI — mirror of the
  /// backend `booking_mode` (defaults to 'request' for pre-0012 payloads).
  final String bookingMode;

  /// Answer SLA set by the backend for `manual_confirm` bookings only
  /// (ISO 8601, nullable) — mirror of the backend `respond_by`.
  final DateTime? respondBy;

  final DateTime? createdAt;

  /// State getters — single source of truth for the partner lifecycle.
  bool get isPending => status == 'pending';

  /// Consent granted, waiting for the partner's answer.
  bool get isAwaitingPartner => status == 'requested';

  bool get isConfirmed => status == 'confirmed';

  bool get isDeclined => status == 'declined';

  bool get isExpired => status == 'expired';

  bool get isCancelled => status == 'cancelled';

  bool get isTerminal => isConfirmed || isDeclined || isExpired || isCancelled;

  /// The traveller can still cancel (mirror of the backend).
  bool get canCancel => isPending || isAwaitingPartner;

  /// Consent only makes sense while the booking is still 'pending'.
  bool get canGiveConsent => isPending;

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String? ?? '',
        tenantId: json['tenant_id'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
        poiId: json['poi_id'] as String? ?? '',
        adapterType: json['adapter_type'] as String? ?? '',
        externalId: json['external_id'] as String?,
        status: json['status'] as String? ?? 'pending',
        consentGiven: json['consent_given'] as bool? ?? false,
        price: (json['price'] as num?)?.toDouble(),
        partnerNote: json['partner_note'] as String?,
        respondedAt: json['responded_at'] == null
            ? null
            : DateTime.tryParse(json['responded_at'] as String),
        currency: json['currency'] as String? ?? '',
        bookingMode: (json['booking_mode'] as String?) ?? 'request',
        respondBy: json['respond_by'] == null
            ? null
            : DateTime.tryParse(json['respond_by'] as String),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );
}
