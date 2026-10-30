import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_notification.dart';
import '../services/api_service.dart';
import 'safe_notifier.dart';

/// Locale-agnostic failure codes for notifications operations.
enum NotificationsError {
  network,
  generic,
}

/// Maps an exception to a [NotificationsError].
NotificationsError _mapError(Object e) {
  if (e is ApiException) {
    return e.statusCode == null
        ? NotificationsError.network
        : NotificationsError.generic;
  }
  if (e is SocketException ||
      e is TimeoutException ||
      e is http.ClientException) {
    return NotificationsError.network;
  }
  return NotificationsError.generic;
}

/// Provider managing notification list, pagination, unread badge, and read actions.
class NotificationsProvider extends ChangeNotifier with SafeNotifier {
  NotificationsProvider({NotificationsApi? api}) : _api = api ?? ApiService();

  final NotificationsApi _api;

  List<AppNotification> _items = [];
  int _unreadCount = 0;
  int _total = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  NotificationsError? _error;

  static const int _pageSize = 20;

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _unreadCount;
  int get total => _total;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  NotificationsError? get error => _error;
  bool get hasMore => _items.length < _total;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Initial load or full refresh. Replaces items on success.
  /// If loading fails, preserves any already displayed items.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _api.getNotifications(
        limit: _pageSize,
        offset: 0,
      );
      final rawList = res['notifications'] as List? ?? [];
      _items = rawList
          .map((n) =>
              AppNotification.fromJson(Map<String, dynamic>.from(n as Map)))
          .toList();
      _unreadCount = (res['unread_count'] as num?)?.toInt() ?? 0;
      _total = (res['total'] as num?)?.toInt() ?? _items.length;
    } catch (e) {
      _error = _mapError(e);
      // Items are intentionally NOT cleared so previously loaded state stays visible.
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Offset-based pagination. Appends items without duplicates.
  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !hasMore || _error != null) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final res = await _api.getNotifications(
        limit: _pageSize,
        offset: _items.length,
      );
      final rawList = res['notifications'] as List? ?? [];
      final newItems = rawList
          .map((n) =>
              AppNotification.fromJson(Map<String, dynamic>.from(n as Map)))
          .toList();

      final existingIds = _items.map((i) => i.id).toSet();
      for (final item in newItems) {
        if (!existingIds.contains(item.id)) {
          _items.add(item);
          existingIds.add(item.id);
        }
      }
      _unreadCount = (res['unread_count'] as num?)?.toInt() ?? _unreadCount;
      _total = (res['total'] as num?)?.toInt() ?? _total;
      _error = null;
    } catch (e) {
      _error = _mapError(e);
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Refreshes only unread count via limit=1 call without modifying the loaded items list.
  Future<void> refreshUnreadCount() async {
    try {
      final res = await _api.getNotifications(limit: 1, offset: 0);
      if (disposed) return;
      final count = (res['unread_count'] as num?)?.toInt() ?? 0;
      if (count != _unreadCount) {
        _unreadCount = count;
        notifyListeners();
      }
    } catch (_) {
      // Swallowed silently so background checks never disrupt UI
    }
  }

  /// Marks a specific notification as read.
  /// Local state changes only after server success.
  Future<void> markRead(String id) async {
    final index = _items.indexWhere((n) => n.id == id);
    if (index == -1) {
      // Still attempt API call if not in list
      try {
        await _api.markRead(id);
      } catch (_) {}
      return;
    }

    if (_items[index].read) return;

    try {
      await _api.markRead(id);
      _items[index] = _items[index].copyWith(read: true);
      if (_unreadCount > 0) {
        _unreadCount--;
      }
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = _mapError(e);
      notifyListeners();
    }
  }

  /// Marks all unread notifications as read.
  /// Local state changes only after server success.
  Future<void> markAllRead() async {
    if (_unreadCount == 0 && _items.every((n) => n.read)) return;

    try {
      await _api.markAllRead();
      _items = _items.map((n) => n.copyWith(read: true)).toList();
      _unreadCount = 0;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = _mapError(e);
      notifyListeners();
    }
  }
}
