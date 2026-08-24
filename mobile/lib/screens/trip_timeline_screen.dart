import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/trip.dart';
import '../providers/trip_provider.dart';
import '../widgets/timeline_item.dart';

/// Day-by-day itinerary display — the mobile equivalent of `TripTimeline.tsx`.
class TripTimelineScreen extends StatelessWidget {
  const TripTimelineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final trip = context.watch<TripProvider>().currentTrip;

    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Itinerary')),
        body: const Center(
          child: Text('No trip generated yet.', key: Key('trip_empty')),
        ),
      );
    }
    return _TripTimelineView(trip: trip);
  }
}

class _TripTimelineView extends StatelessWidget {
  const _TripTimelineView({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final byDay = trip.itemsByDay;
    return Scaffold(
      appBar: AppBar(title: Text(trip.title)),
      body: trip.items.isEmpty
          ? const Center(
              child: Text('This trip has no stops yet.',
                  key: Key('trip_items_empty')),
            )
          : ListView(
              key: const Key('trip_timeline'),
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(trip.title,
                            style: Theme.of(context).textTheme.titleLarge),
                        if (trip.description != null &&
                            trip.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(trip.description!),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Chip(label: Text('${trip.numDays} day(s)')),
                            Chip(label: Text('Budget: ${trip.budgetLevel}')),
                            for (final i in trip.interests) Chip(label: Text(i)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                for (final entry in byDay.entries)
                  Card(
                    key: Key('day_card_${entry.key}'),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                child: Text('${entry.key}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13)),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Day ${entry.key}',
                                key: Key('day_header_${entry.key}'),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          for (final item in entry.value)
                            TimelineItemWidget(item: item),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}