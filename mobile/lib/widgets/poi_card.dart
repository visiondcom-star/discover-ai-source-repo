import 'package:flutter/material.dart';

import '../models/poi.dart';

/// Reusable POI card — the mobile equivalent of the web `POICard.tsx`.
class POICard extends StatelessWidget {
  const POICard({super.key, required this.poi, this.onTap});

  final POI poi;
  final VoidCallback? onTap;

  static const Map<String, IconData> _categoryIcons = {
    'historical': Icons.castle_outlined,
    'nature': Icons.forest_outlined,
    'culture': Icons.museum_outlined,
    'adventure': Icons.hiking_outlined,
    'desert': Icons.wb_sunny_outlined,
    'food': Icons.restaurant_outlined,
    'beaches': Icons.beach_access_outlined,
    'monuments': Icons.explore_outlined,
    'crafts': Icons.shopping_bag_outlined,
    'thermal': Icons.hot_tub_outlined,
    'wellness': Icons.spa_outlined,
    'shopping': Icons.shopping_bag_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Icon(_categoryIcons[poi.category] ?? Icons.place),
        ),
        title: Text(
          poi.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${poi.city} • ${poi.durationMinutes} min'),
            if (poi.categories.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  for (final cat in poi.categories)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        cat,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                            ),
                      ),
                    ),
                ],
              ),
            ],
            if (poi.experiences.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  for (final exp in poi.experiences.take(2))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '✨ ${exp.replaceAll('_', ' ')}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (poi.averageRating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                  Text(poi.averageRating!.toStringAsFixed(1)),
                ],
              ),
            Text(poi.priceRange, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
