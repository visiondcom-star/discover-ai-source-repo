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

  /// Backend state machine: pending → confirmed | cancelled.
  final String status;
  final bool consentGiven;

  /// Never populated by the current backend — rendered only when present.
  final double? price;
  final String currency;
  final DateTime? createdAt;

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
        currency: json['currency'] as String? ?? '',
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );
}