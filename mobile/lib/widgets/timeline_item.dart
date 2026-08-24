import 'package:flutter/material.dart';

import '../models/trip_item.dart';

/// Reusable timeline row — the mobile equivalent of one entry in the web
/// `TripTimeline.tsx`: time slot, marker, POI name/city/duration, notes.
class TimelineItemWidget extends StatelessWidget {
  const TimelineItemWidget({super.key, required this.item});

  final TripItem item;

  static String _hhmm(DateTime? t) => t == null
      ? '--:--'
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              _hhmm(item.startTime),
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.poi?.name ?? 'Point of interest',
                  key: Key('timeline_poi_${item.poiId}'),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (item.poi?.city != null && item.poi!.city.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.place,
                            size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(item.poi!.city,
                              style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
                if (item.poi?.durationMinutes != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.schedule,
                            size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text('${item.poi!.durationMinutes} min',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                if (item.notes != null && item.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item.notes!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}