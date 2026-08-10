import 'package:flutter/material.dart';
import '../models/poi.dart';

class POIDetailScreen extends StatelessWidget {
  final POI poi;
  const POIDetailScreen({super.key, required this.poi});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(poi.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.image, size: 64, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Chip(label: Text(poi.category)),
                const SizedBox(width: 8),
                Chip(label: Text(poi.city)),
              ],
            ),
            const SizedBox(height: 16),
            Text(poi.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (poi.description != null)
              Text(poi.description!, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            _InfoRow(icon: Icons.timer, label: 'Duration', value: '${poi.durationMinutes} min'),
            _InfoRow(icon: Icons.attach_money, label: 'Price', value: poi.priceRange),
            if (poi.latitude != null && poi.longitude != null)
              _InfoRow(icon: Icons.location_on, label: 'Location', value: '${poi.latitude}, ${poi.longitude}'),
            const SizedBox(height: 16),
            if (poi.tags.isNotEmpty) ...[
              Text('Tags', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: poi.tags.map((t) => Chip(label: Text(t), visualDensity: VisualDensity.compact)).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }
}
