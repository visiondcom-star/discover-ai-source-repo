import 'package:flutter/material.dart';

import '../models/promotion.dart';

/// Full-bleed image banner with a dark scrim and title/subtitle overlay,
/// matching the "L'Algérie vous attend" pattern from the UX blueprint.
/// Purely presentational — the caller decides what CTA tap does, if
/// anything (a promotion with link_type "none" has no CTA at all).
class PromoBanner extends StatelessWidget {
  const PromoBanner({super.key, required this.promotion, this.onTap});

  final Promotion promotion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ClipRRect(
      key: Key('promo_banner_${promotion.id}'),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 160,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                promotion.imageUrl,
                fit: BoxFit.cover,
                // A promo image failing to load must never break the
                // screen — fall back to a plain brand-colored surface so
                // the title/subtitle overlay still reads fine.
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  );
                },
              ),
              // Scrim: gradient rather than a flat overlay so the top of
              // the image stays visible while the text at the bottom
              // stays legible regardless of the photo's own contrast.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                    stops: [0.4, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      promotion.title,
                      key: Key('promo_banner_title_${promotion.id}'),
                      style: text.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (promotion.subtitle != null &&
                        promotion.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        promotion.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ),
              if (promotion.ctaLabel != null &&
                  promotion.ctaLabel!.isNotEmpty)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      promotion.ctaLabel!,
                      style: text.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
