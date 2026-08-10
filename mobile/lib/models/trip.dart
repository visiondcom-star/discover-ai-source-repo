class Trip {
  final String id;
  final String title;
  final String? description;
  final int numDays;
  final String budgetLevel;
  final String travelStyle;
  final String status;
  final List<TripItem> items;

  Trip({
    required this.id,
    required this.title,
    this.description,
    required this.numDays,
    required this.budgetLevel,
    required this.travelStyle,
    required this.status,
    required this.items,
  });

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    description: json['description'],
    numDays: json['num_days'] ?? 1,
    budgetLevel: json['budget_level'] ?? 'medium',
    travelStyle: json['travel_style'] ?? 'balanced',
    status: json['status'] ?? 'draft',
    items: (json['items'] as List? ?? [])
        .map((i) => TripItem.fromJson(i))
        .toList(),
  );
}

class TripItem {
  final String id;
  final String poiId;
  final int dayNumber;
  final int orderIndex;
  final String? notes;
  final POI? poi;

  TripItem({
    required this.id,
    required this.poiId,
    required this.dayNumber,
    required this.orderIndex,
    this.notes,
    this.poi,
  });

  factory TripItem.fromJson(Map<String, dynamic> json) => TripItem(
    id: json['id'] ?? '',
    poiId: json['poi_id'] ?? '',
    dayNumber: json['day_number'] ?? 1,
    orderIndex: json['order_index'] ?? 0,
    notes: json['notes'],
    poi: json['poi'] != null ? POI.fromJson(json['poi']) : null,
  );
}

class POI {
  final String id;
  final String name;
  final String? description;

  POI({
    required this.id,
    required this.name,
    this.description,
  });

  factory POI.fromJson(Map<String, dynamic> json) => POI(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    description: json['description'],
  );
}
