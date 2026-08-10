class POI {
  final String id;
  final String slug;
  final String name;
  final String? description;
  final String city;
  final String category;
  final int durationMinutes;
  final String priceRange;
  final double? latitude;
  final double? longitude;
  final List<String> tags;
  final bool isVerified;

  POI({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    required this.city,
    required this.category,
    required this.durationMinutes,
    required this.priceRange,
    this.latitude,
    this.longitude,
    required this.tags,
    this.isVerified = false,
  });

  factory POI.fromJson(Map<String, dynamic> json) => POI(
    id: json['id'] ?? '',
    slug: json['slug'] ?? '',
    name: json['name'] ?? '',
    description: json['description'],
    city: json['city'] ?? '',
    category: json['category'] ?? 'culture',
    durationMinutes: json['duration_minutes'] ?? 60,
    priceRange: json['price_range'] ?? 'free',
    latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
    longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
    tags: List<String>.from(json['tags'] ?? []),
    isVerified: json['is_verified'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'slug': slug,
    'name': name,
    'description': description,
    'city': city,
    'category': category,
    'duration_minutes': durationMinutes,
    'price_range': priceRange,
    'latitude': latitude,
    'longitude': longitude,
    'tags': tags,
    'is_verified': isVerified,
  };
}
