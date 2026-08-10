class User {
  final String id;
  final String email;
  final String? fullName;
  final bool isAdmin;

  User({
    required this.id,
    required this.email,
    this.fullName,
    this.isAdmin = false,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] ?? '',
    email: json['email'] ?? '',
    fullName: json['full_name'],
    isAdmin: json['is_admin'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
    'is_admin': isAdmin,
  };
}
