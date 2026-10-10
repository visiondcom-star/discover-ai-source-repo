/// Mirrors the backend `POIResponse` schema (backend/app/schemas.py).
/// Keep fields in sync — no divergence between backend and mobile.
class POI {
  POI({
    required this.id,
    required this.slug,
    required this.tenantId,
    required this.name,
    this.description,
    required this.city,
    List<String>? categories,
    String? category,
    this.experiences = const [],
    this.durationMinutes = 60,
    this.priceRange = 'free',
    this.latitude,
    this.longitude,
    this.address,
    this.images = const [],
    this.tags = const [],
    this.accessibility = const [],
    this.openingHours = const {},
    this.isVerified = false,
    this.isActive = true,
    this.averageRating,
    this.reviewCount = 0,
    this.bookingMode = 'request',
    this.createdAt,
    this.updatedAt,
  }) : categories = categories ?? (category != null ? [category] : const []);

  final String id;
  final String slug;
  final String tenantId;
  final String name;
  final String? description;
  final String city;
  final List<String> categories;
  final List<String> experiences;

  /// First category convenience getter for legacy usages.
  String get category => categories.isNotEmpty ? categories.first : '';
  final int durationMinutes;
  final String priceRange;
  final double? latitude;
  final double? longitude;
  final String? address;
  final List<String> images;
  final List<String> tags;
  final List<String> accessibility;
  final Map<String, dynamic> openingHours;
  final bool isVerified;
  final bool isActive;

  /// Rating aggregate maintained by the backend review flow.
  final double? averageRating;
  final int reviewCount;

  /// How (and whether) this place can be booked — mirror of the backend
  /// `booking_mode` (schemas.py: info_only | request | manual_confirm |
  /// pay_on_site | deposit | online_payment). Defaults to 'request' so a
  /// backend (or fixture) that predates the field keeps behaving as before.
  final String bookingMode;

  /// Modes this app knows how to book with — mobile mirror of the backend's
  /// BOOKING_MODES_SUPPORTED. 'deposit'/'online_payment' need a payment
  /// module and stay unsupported until then.
  static const Set<String> bookableModes = {
    'request',
    'manual_confirm',
    'pay_on_site',
  };

  /// True when a booking can be created from this POI's detail screen.
  bool get isBookable => bookableModes.contains(bookingMode);

  /// Information-only places: the Book CTA is replaced by a plain notice.
  bool get isInfoOnly => bookingMode == 'info_only';

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory POI.fromJson(Map<String, dynamic> json) => POI(
        id: json['id'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        tenantId: json['tenant_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        city: json['city'] as String? ?? '',
        categories: json['categories'] != null
            ? List<String>.from(json['categories'] as List)
            : (json['category'] != null
                ? [json['category'] as String]
                : const []),
        experiences: List<String>.from(json['experiences'] as List? ?? []),
        durationMinutes: json['duration_minutes'] as int? ?? 60,
        priceRange: json['price_range'] as String? ?? 'free',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        address: json['address'] as String?,
        images: List<String>.from(json['images'] as List? ?? []),
        tags: List<String>.from(json['tags'] as List? ?? []),
        accessibility: List<String>.from(json['accessibility'] as List? ?? []),
        openingHours:
            Map<String, dynamic>.from(json['opening_hours'] as Map? ?? {}),
        isVerified: json['is_verified'] as bool? ?? false,
        isActive: json['is_active'] as bool? ?? true,
        averageRating: (json['average_rating'] as num?)?.toDouble(),
        reviewCount: json['review_count'] as int? ?? 0,
        bookingMode: (json['booking_mode'] as String?) ?? 'request',
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
        updatedAt: json['updated_at'] == null
            ? null
            : DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'tenant_id': tenantId,
        'name': name,
        'description': description,
        'city': city,
        'categories': categories,
        'experiences': experiences,
        'duration_minutes': durationMinutes,
        'price_range': priceRange,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'images': images,
        'tags': tags,
        'accessibility': accessibility,
        'opening_hours': openingHours,
        'is_verified': isVerified,
        'is_active': isActive,
        'average_rating': averageRating,
        'review_count': reviewCount,
        'booking_mode': bookingMode,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };
}
