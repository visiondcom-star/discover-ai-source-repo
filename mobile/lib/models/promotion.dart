/// Mirrors the backend `PromotionResponse` schema (backend/app/schemas.py).
/// Keep fields in sync — no divergence between backend and mobile.
class Promotion {
  Promotion({
    required this.id,
    required this.tenantId,
    required this.title,
    this.subtitle,
    required this.imageUrl,
    this.ctaLabel,
    this.linkType,
    this.linkTarget,
    this.priority = 0,
    this.isActive = true,
  });

  final String id;
  final String tenantId;
  final String title;
  final String? subtitle;
  final String imageUrl;
  final String? ctaLabel;
  final String? linkType; // poi, trip, external, none
  final String? linkTarget;
  final int priority;
  final bool isActive;

  factory Promotion.fromJson(Map<String, dynamic> json) => Promotion(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String?,
        imageUrl: json['image_url'] as String,
        ctaLabel: json['cta_label'] as String?,
        linkType: json['link_type'] as String?,
        linkTarget: json['link_target'] as String?,
        priority: json['priority'] as int? ?? 0,
        isActive: json['is_active'] as bool? ?? true,
      );
}
