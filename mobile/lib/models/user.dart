/// Mirrors the backend `UserResponse` schema (backend/app/schemas.py).
/// Keep fields in sync — no divergence between backend and mobile.
class User {
  User({
    required this.id,
    required this.email,
    this.fullName,
    this.isActive = true,
    this.isAdmin = false,
    this.preferences = const {},
    this.createdAt,
  });

  final String id;
  final String email;
  final String? fullName;
  final bool isActive;
  final bool isAdmin;
  final Map<String, dynamic> preferences;
  final DateTime? createdAt;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        fullName: json['full_name'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        isAdmin: json['is_admin'] as bool? ?? false,
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
        'is_active': isActive,
        'is_admin': isAdmin,
        'preferences': preferences,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}
