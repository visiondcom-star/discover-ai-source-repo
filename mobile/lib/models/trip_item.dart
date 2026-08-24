import 'poi.dart';

/// Mirrors the backend `TripItemResponse` schema (backend/app/schemas.py).
/// Keep fields in sync — no divergence between backend and mobile.
class TripItem {
  TripItem({
    required this.id,
    required this.poiId,
    required this.dayNumber,
    required this.orderIndex,
    this.startTime,
    this.endTime,
    this.notes,
    this.poi,
  });

  final String id;
  final String poiId;
  final int dayNumber;

  /// Display order of this stop within its day.
  final int orderIndex;

  final DateTime? startTime;
  final DateTime? endTime;
  final String? notes;

  /// Embedded POI payload from the backend (`TripItemResponse.poi`).
  final POI? poi;

  factory TripItem.fromJson(Map<String, dynamic> json) => TripItem(
        id: json['id'] as String? ?? '',
        poiId: json['poi_id'] as String? ?? '',
        dayNumber: json['day_number'] as int? ?? 1,
        orderIndex: json['order_index'] as int? ?? 0,
        startTime: json['start_time'] == null
            ? null
            : DateTime.parse(json['start_time'] as String),
        endTime: json['end_time'] == null
            ? null
            : DateTime.parse(json['end_time'] as String),
        notes: json['notes'] as String?,
        poi: json['poi'] == null
            ? null
            : POI.fromJson(Map<String, dynamic>.from(json['poi'] as Map)),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'poi_id': poiId,
        'day_number': dayNumber,
        'order_index': orderIndex,
        'start_time': startTime?.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'notes': notes,
        'poi': poi?.toJson(),
      };
}
