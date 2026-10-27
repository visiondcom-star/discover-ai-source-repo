/// Notification model mirroring the backend NotificationResponse.
///
/// Exposes:
/// - [id]: Notification unique ID.
/// - [title]: Localized title computed by the server.
/// - [message]: Localized message computed by the server.
/// - [type]: Notification type string (e.g. `booking_confirmed`).
/// - [read]: True if the notification has been marked as read.
/// - [createdAt]: Date parsed as UTC (append 'Z' if missing timezone), stored
///   as UTC DateTime, or null if absent/null.
/// - [bookingId]: Related booking ID (String?), if any.
/// - [payload]: Raw payload map, defaults to empty map if absent/null.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.read,
    this.createdAt,
    this.bookingId,
    this.payload = const {},
  });

  final String id;
  final String title;
  final String message;
  final String type;
  final bool read;
  final DateTime? createdAt;
  final String? bookingId;
  final Map<String, dynamic> payload;

  AppNotification copyWith({
    String? id,
    String? title,
    String? message,
    String? type,
    bool? read,
    DateTime? createdAt,
    String? bookingId,
    Map<String, dynamic>? payload,
  }) =>
      AppNotification(
        id: id ?? this.id,
        title: title ?? this.title,
        message: message ?? this.message,
        type: type ?? this.type,
        read: read ?? this.read,
        createdAt: createdAt ?? this.createdAt,
        bookingId: bookingId ?? this.bookingId,
        payload: payload ?? this.payload,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    DateTime? parsedCreatedAt;
    final rawCreatedAt = json['created_at'];
    if (rawCreatedAt is String && rawCreatedAt.isNotEmpty) {
      final hasTimezone = rawCreatedAt.endsWith('Z') ||
          rawCreatedAt.contains('+') ||
          (rawCreatedAt.length > 19 &&
              (rawCreatedAt.substring(19).contains('-')));
      final normalized = hasTimezone ? rawCreatedAt : '${rawCreatedAt}Z';
      parsedCreatedAt = DateTime.parse(normalized).toUtc();
    }

    final rawPayload = json['payload'];
    final Map<String, dynamic> parsedPayload = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : const <String, dynamic>{};

    return AppNotification(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      type: json['type'] as String? ?? '',
      read: json['read'] as bool? ?? false,
      createdAt: parsedCreatedAt,
      bookingId: json['booking_id'] as String?,
      payload: parsedPayload,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'type': type,
        'read': read,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        'booking_id': bookingId,
        'payload': payload,
      };
}
