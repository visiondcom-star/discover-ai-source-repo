/// Mirrors the backend `UserResponse` schema (backend/app/schemas.py).
/// Keep fields in sync — no divergence between backend and mobile.
class User {
  User({
    required this.id,
    required this.email,
    this.fullName,
    this.locale,
    this.isActive = true,
    this.isAdmin = false,
    this.isPartner = false,
    this.preferences = const {},
    this.createdAt,
  });

  final String id;
  final String email;
  final String? fullName;
  final String? locale;
  final bool isActive;
  final bool isAdmin;

  /// Partner role: the user manages at least one POI of the tenant (backend
  /// `UserResponse.is_partner`, served only on `GET /auth/me`). Not an ORM
  /// attribute — it is derived from `poi_managers`, so a plain traveller keeps
  /// it false.
  final bool isPartner;

  final Map<String, dynamic> preferences;
  final DateTime? createdAt;

  /// Who may open the partner space. A partner obviously may; an admin may too
  /// (the backend grants the same access as a safety net, `_require_partner`).
  bool get canUsePartnerSpace => isPartner || isAdmin;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        fullName: json['full_name'] as String?,
        locale: json['locale'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        isAdmin: json['is_admin'] as bool? ?? false,
        isPartner: json['is_partner'] as bool? ?? false,
        preferences:
            Map<String, dynamic>.from(json['preferences'] as Map? ?? {}),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'locale': locale,
        'is_active': isActive,
        'is_admin': isAdmin,
        'is_partner': isPartner,
        'preferences': preferences,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}
