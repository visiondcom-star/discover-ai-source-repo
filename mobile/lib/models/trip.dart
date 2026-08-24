import 'trip_item.dart';

/// Mirrors the backend `TripResponse` schema (backend/app/schemas.py).
/// Keep fields in sync — no divergence between backend and mobile.
class Trip {
  Trip({
    required this.id,
    required this.tenantId,
    required this.userId,
    required this.title,
    this.description,
    this.numDays = 1,
    this.budgetLevel = 'medium',
    required this.budgetCurrency,
    this.travelStyle = 'balanced',
    this.interests = const [],
    this.groupType = 'solo',
    this.children = false,
    this.status = 'draft',
    this.totalCostEstimate,
    this.items = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String userId;
  final String title;
  final String? description;
  final int numDays;

  /// Backend schema values: low | medium | high.
  final String budgetLevel;

  /// Currency chosen server-side; the mobile app never decides market data.
  final String budgetCurrency;

  /// Backend schema values: relaxed | balanced | intensive.
  final String travelStyle;
  final List<String> interests;

  /// Backend schema values: solo | couple | family | friends.
  final String groupType;
  final bool children;
  final String status;
  final double? totalCostEstimate;
  final List<TripItem> items;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String? ?? '',
        tenantId: json['tenant_id'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        numDays: json['num_days'] as int? ?? 1,
        budgetLevel: json['budget_level'] as String? ?? 'medium',
        budgetCurrency: json['budget_currency'] as String? ?? '',
        travelStyle: json['travel_style'] as String? ?? 'balanced',
        interests:
            List<String>.from(json['interests'] as List? ?? const []),
        groupType: json['group_type'] as String? ?? 'solo',
        children: json['children'] as bool? ?? false,
        status: json['status'] as String? ?? 'draft',
        totalCostEstimate: (json['total_cost_estimate'] as num?)?.toDouble(),
        items: (json['items'] as List? ?? const [])
            .map((e) => TripItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
        updatedAt: json['updated_at'] == null
            ? null
            : DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'user_id': userId,
        'title': title,
        'description': description,
        'num_days': numDays,
        'budget_level': budgetLevel,
        'budget_currency': budgetCurrency,
        'travel_style': travelStyle,
        'interests': interests,
        'group_type': groupType,
        'children': children,
        'status': status,
        'total_cost_estimate': totalCostEstimate,
        'items': [for (final i in items) i.toJson()],
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };

  /// Items grouped by day, days sorted ascending, items ordered by
  /// [TripItem.orderIndex] within each day — drives the timeline screen.
  Map<int, List<TripItem>> get itemsByDay {
    final map = <int, List<TripItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.dayNumber, () => []).add(item);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    }
    final keys = map.keys.toList()..sort();
    return {for (final k in keys) k: map[k]!};
  }
}