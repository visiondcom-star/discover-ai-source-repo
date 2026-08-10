import 'package:flutter/material.dart';

class TimelineItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? time;
  final bool isFirst;
  final bool isLast;

  const TimelineItem({
    super.key,
    required this.title,
    this.subtitle,
    this.time,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: time != null
                ? Text(time!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))
                : null,
          ),
          Column(
            children: [
              if (!isFirst) Container(width: 2, height: 20, color: Colors.grey[300]),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: Colors.grey[300])),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
