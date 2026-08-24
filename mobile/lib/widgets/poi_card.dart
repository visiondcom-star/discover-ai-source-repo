import 'package:flutter/material.dart';

import '../models/poi.dart';

/// Reusable POI card — the mobile equivalent of the web `POICard.tsx`.
class POICard extends StatelessWidget {
  const POICard({super.key, required this.poi, this.onTap});

  final POI poi;
  final VoidCallback? onTap;

  static const Map<String, IconData> _categoryIcons = {
    'historical': Icons.account_balance,
    'nature': Icons.forest,
    'culture': Icons.museum,
    'adventure': Icons.hiking,
    'food': Icons.restaurant,
    'shopping': Icons.shopping_bag,
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
        subtitle:
            Text('${poi.city} • ${poi.category} • ${poi.durationMinutes} min'),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (poi.averageRating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded,
                      size: 16, color: Colors.amber),
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