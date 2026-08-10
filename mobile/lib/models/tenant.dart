class Tenant {
  final String id;
  final String slug;
  final String name;
  final String defaultLanguage;
  final List<String> supportedLanguages;
  final String defaultCurrency;
  final String primaryColor;
  final String secondaryColor;

  Tenant({
    required this.id,
    required this.slug,
    required this.name,
    required this.defaultLanguage,
    required this.supportedLanguages,
    required this.defaultCurrency,
    required this.primaryColor,
    required this.secondaryColor,
  });

  factory Tenant.fromJson(Map<String, dynamic> json) => Tenant(
    id: json['id'] ?? '',
    slug: json['slug'] ?? '',
    name: json['name'] ?? '',
    defaultLanguage: json['default_language'] ?? 'fr',
    supportedLanguages: List<String>.from(json['supported_languages'] ?? []),
    defaultCurrency: json['default_currency'] ?? 'DZD',
    primaryColor: json['primary_color'] ?? '#006233',
    secondaryColor: json['secondary_color'] ?? '#FFFFFF',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'slug': slug,
    'name': name,
    'default_language': defaultLanguage,
    'supported_languages': supportedLanguages,
    'default_currency': defaultCurrency,
    'primary_color': primaryColor,
    'secondary_color': secondaryColor,
  };
}
