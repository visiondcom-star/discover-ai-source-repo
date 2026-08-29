import 'package:flutter/material.dart';

import '../models/poi.dart';
import 'bookings_screen.dart';
import 'trip_form_screen.dart';

/// Place detail screen (P3) — mobile counterpart of the web POI detail view.
///
/// Renders the [POI] object it is given — no extra network call, no hardcoded
/// market content. Optional sections (images, description, tags,
/// accessibility, opening hours, rating) appear only when the backend
/// provides them, so the screen stays honest for every tenant.
///
/// Booking walks the backend Booking-Agent consent flow (CLAUDE.md
/// principle 5): the secondary CTA opens the booking sheet defined in
/// bookings_screen.dart — create (pending) → explicit consent →
/// confirmed (EXT-… reference) or cancelled. The primary CTA opens the
/// real trip planner.
class PoiDetailScreen extends StatelessWidget {
  const PoiDetailScreen({super.key, required this.poi});

  final POI poi;

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
    final theme = Theme.of(context);
    final icon = _categoryIcons[poi.category] ?? Icons.place;
    final hasDescription =
        poi.description != null && poi.description!.trim().isNotEmpty;

    return Scaffold(
      key: const Key('poi_detail_screen'),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 180,
            title: Text(poi.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            flexibleSpace: FlexibleSpaceBar(
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.secondaryContainer,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: 72,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    poi.name,
                    key: const Key('poi_detail_name'),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.place, size: 16),
                        label: Text(poi.city),
                      ),
                      Chip(
                        avatar: Icon(icon, size: 16),
                        label: Text(poi.category),
                      ),
                      if (poi.isVerified)
                        const Chip(
                          avatar: Icon(Icons.verified, size: 16),
                          label: Text('Verified'),
                        ),
                    ],
                  ),
                  if (poi.averageRating != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      key: const Key('poi_detail_rating'),
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 20, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          poi.averageRating!.toStringAsFixed(1),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${poi.reviewCount} reviews)',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: _InfoTile(
                              icon: Icons.schedule,
                              label: 'Duration',
                              value: '${poi.durationMinutes} min',
                            ),
                          ),
                          Expanded(
                            child: _InfoTile(
                              icon: Icons.payments_outlined,
                              label: 'Price',
                              value: poi.priceRange,
                            ),
                          ),
                          if (poi.address != null &&
                              poi.address!.trim().isNotEmpty)
                            Expanded(
                              child: _InfoTile(
                                icon: Icons.location_on_outlined,
                                label: 'Address',
                                value: poi.address!,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (hasDescription) ...[
                    const SizedBox(height: 20),
                    Text('About', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      poi.description!,
                      key: const Key('poi_detail_description'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  if (poi.images.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 140,
                      child: ListView.separated(
                        key: const Key('poi_detail_images'),
                        scrollDirection: Axis.horizontal,
                        itemCount: poi.images.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            poi.images[index],
                            width: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 200,
                              color: theme.colorScheme.surfaceContainerHighest,
                              child:
                                  const Icon(Icons.image_not_supported_outlined),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (poi.tags.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Tags', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Wrap(
                      key: const Key('poi_detail_tags'),
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in poi.tags) Chip(label: Text(tag)),
                      ],
                    ),
                  ],
                  if (poi.accessibility.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Accessibility', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Wrap(
                      key: const Key('poi_detail_accessibility'),
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in poi.accessibility)
                          Chip(
                            avatar:
                                const Icon(Icons.accessible_forward, size: 16),
                            label: Text(item),
                          ),
                      ],
                    ),
                  ],
                  if (poi.openingHours.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Opening hours', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Card(
                      key: const Key('poi_detail_hours'),
                      child: Column(
                        children: [
                          for (final entry in poi.openingHours.entries)
                            ListTile(
                              dense: true,
                              leading:
                                  const Icon(Icons.schedule_outlined, size: 18),
                              title: Text(entry.key),
                              trailing: Text('${entry.value}'),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('poi_detail_plan_button'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const TripFormScreen()),
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Plan a visit'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('poi_detail_book_button'),
                      onPressed: () => showBookingSheet(context, poi),
                      icon: const Icon(Icons.verified_user_outlined),
                      label: const Text('Book'),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact icon + label + value cell used in the duration/price/address card.
class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}