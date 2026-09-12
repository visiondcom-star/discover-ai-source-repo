/// Mirrors the backend `TenantCategoryResponse` schema (backend/app/schemas.py).
///
/// Implements the 3-level taxonomy:
/// - Level 1: [parentFamily] (macro-family e.g. culture, history, nature, desert)
/// - Level 2: [slug] & [label] (local specificity generated/adapted by AI)
class TenantCategory {
  const TenantCategory({
    required this.id,
    required this.tenantId,
    required this.slug,
    required this.label,
    this.parentFamily,
    this.iconSuggestion,
    this.description,
    this.displayOrder = 0,
    this.aiGenerated = true,
  });

  final String id;
  final String tenantId;
  final String slug;
  final String label;
  final String? parentFamily;
  final String? iconSuggestion;
  final String? description;
  final int displayOrder;
  final bool aiGenerated;

  factory TenantCategory.fromJson(Map<String, dynamic> json) => TenantCategory(
        id: json['id'] as String? ?? '',
        tenantId: json['tenant_id'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        label: json['label'] as String? ?? '',
        parentFamily: json['parent_family'] as String?,
        iconSuggestion: json['icon_suggestion'] as String?,
        description: json['description'] as String?,
        displayOrder: json['display_order'] as int? ?? 0,
        aiGenerated: json['ai_generated'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'slug': slug,
        'label': label,
        if (parentFamily != null) 'parent_family': parentFamily,
        if (iconSuggestion != null) 'icon_suggestion': iconSuggestion,
        if (description != null) 'description': description,
        'display_order': displayOrder,
        'ai_generated': aiGenerated,
      };
}
