import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:discover_ai/models/app_notification.dart';
import 'package:discover_ai/providers/notifications_provider.dart';
import 'package:discover_ai/services/api_service.dart';

import '../helpers/fakes.dart';

void main() {
  group('AppNotification model', () {
    test('parses complete json correctly', () {
      final json = sampleNotificationJson(
        id: 'n-123',
        title: 'Titre',
        message: 'Contenu',
        type: 'booking_request_received',
        read: true,
        createdAt: '2026-10-27T10:00:00',
        bookingId: 'b-999',
        payload: {'poi_name': 'Tipaza', 'price': 100},
      );

      final notif = AppNotification.fromJson(json);

      expect(notif.id, 'n-123');
      expect(notif.title, 'Titre');
      expect(notif.message, 'Contenu');
      expect(notif.type, 'booking_request_received');
      expect(notif.read, isTrue);
      expect(notif.bookingId, 'b-999');
      expect(notif.payload, {'poi_name': 'Tipaza', 'price': 100});
      expect(notif.createdAt, isNotNull);
      expect(notif.createdAt!.isUtc, isTrue);
      expect(notif.createdAt!.hour, 10);
    });

    test('parses created_at without timezone by appending Z (UTC)', () {
      final json = sampleNotificationJson(
        createdAt: '2026-10-27T14:30:00',
      );
      final notif = AppNotification.fromJson(json);
      expect(notif.createdAt, isNotNull);
      expect(notif.createdAt!.isUtc, isTrue);
      expect(notif.createdAt!.year, 2026);
      expect(notif.createdAt!.month, 10);
      expect(notif.createdAt!.day, 27);
      expect(notif.createdAt!.hour, 14);
      expect(notif.createdAt!.minute, 30);
    });

    test('parses created_at with explicit timezone Z or offset', () {
      final jsonZ = sampleNotificationJson(
        createdAt: '2026-10-27T14:30:00Z',
      );
      final notifZ = AppNotification.fromJson(jsonZ);
      expect(notifZ.createdAt, isNotNull);
      expect(notifZ.createdAt!.isUtc, isTrue);
      expect(notifZ.createdAt!.hour, 14);

      final jsonOffset = sampleNotificationJson(
        createdAt: '2026-10-27T16:30:00+02:00',
      );
      final notifOffset = AppNotification.fromJson(jsonOffset);
      expect(notifOffset.createdAt, isNotNull);
      expect(notifOffset.createdAt!.isUtc, isTrue);
      expect(notifOffset.createdAt!.hour, 14); // 16:30 +02:00 -> 14:30 UTC
    });

    test('handles null created_at, null booking_id, absent payload', () {
      final json = {
        'id': 'n-null',
        'title': 'Test',
        'message': 'Msg',
        'type': 'system',
        'read': false,
        'created_at': null,
        'booking_id': null,
        'payload': null,
      };

      final notif = AppNotification.fromJson(json);
      expect(notif.id, 'n-null');
      expect(notif.createdAt, isNull);
      expect(notif.bookingId, isNull);
      expect(notif.payload, isEmpty);
    });

    test('toJson round-trips fields', () {
      final notif = AppNotification(
        id: 'n-round',
        title: 'T',
        message: 'M',
        type: 'booking_confirmed',
        read: false,
        createdAt: DateTime.utc(2026, 10, 27, 8, 0, 0),
        bookingId: 'b-round',
        payload: {'foo': 'bar'},
      );

      final json = notif.toJson();
      expect(json['id'], 'n-round');
      expect(json['booking_id'], 'b-round');
      expect(json['payload'], {'foo': 'bar'});
      expect(json['created_at'], '2026-10-27T08:00:00.000Z');

      final reloaded = AppNotification.fromJson(json);
      expect(reloaded.id, 'n-round');
      expect(reloaded.bookingId, 'b-round');
      expect(reloaded.payload, {'foo': 'bar'});
      expect(reloaded.createdAt, DateTime.utc(2026, 10, 27, 8, 0, 0));
    });
  });

  group('NotificationsProvider', () {
    test('load populates items, unreadCount, total and clears error', () async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(id: 'n-1', read: false),
          sampleNotificationJson(id: 'n-2', read: true),
        ],
        unreadCount: 1,
        total: 2,
      );
      final provider = NotificationsProvider(api: fakeApi);

      expect(provider.isLoading, isFalse);
      final future = provider.load();
      expect(provider.isLoading, isTrue);
      await future;

      expect(provider.isLoading, isFalse);
      expect(provider.items.length, 2);
      expect(provider.items[0].id, 'n-1');
      expect(provider.items[1].id, 'n-2');
      expect(provider.unreadCount, 1);
      expect(provider.total, 2);
      expect(provider.error, isNull);
      expect(provider.hasMore, isFalse);
    });

    test('loadMore paginates and appends items without duplicates', () async {
      final allNotifs = List.generate(
        35,
        (i) => sampleNotificationJson(id: 'notif-$i', title: 'Notif $i'),
      );
      final fakeApi = FakeNotificationsApi(
        notifications: allNotifs,
        unreadCount: 35,
        total: 35,
      );
      final provider = NotificationsProvider(api: fakeApi);

      await provider.load(); // Loads first 20 items (0..19)
      expect(provider.items.length, 20);
      expect(provider.hasMore, isTrue);

      await provider.loadMore(); // Loads remaining 15 items (20..34)
      expect(provider.items.length, 35);
      expect(provider.hasMore, isFalse);

      // Verify no duplicates
      final ids = provider.items.map((n) => n.id).toSet();
      expect(ids.length, 35);
    });

    test('failed reload preserves existing items list', () async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(id: 'n-keep-1'),
          sampleNotificationJson(id: 'n-keep-2'),
        ],
        unreadCount: 2,
        total: 2,
      );
      final provider = NotificationsProvider(api: fakeApi);

      await provider.load();
      expect(provider.items.length, 2);

      // Next call fails with a network error
      fakeApi.getNotificationsError = const SocketException('No route to host');
      await provider.load();

      // List is preserved, error code set to network
      expect(provider.items.length, 2);
      expect(provider.error, NotificationsError.network);
    });

    test(
        'error mapping: ApiException without status, SocketException, TimeoutException -> network',
        () async {
      final fakeApi = FakeNotificationsApi();
      final provider = NotificationsProvider(api: fakeApi);

      // ApiException null status
      fakeApi.getNotificationsError = ApiException(null, 'Network down');
      await provider.load();
      expect(provider.error, NotificationsError.network);

      // SocketException
      fakeApi.getNotificationsError = const SocketException('offline');
      await provider.load();
      expect(provider.error, NotificationsError.network);
    });

    test(
        'error mapping: ApiException with status code or FormatException -> generic',
        () async {
      final fakeApi = FakeNotificationsApi();
      final provider = NotificationsProvider(api: fakeApi);

      // 500 error
      fakeApi.getNotificationsError = ApiException(500, 'Server error');
      await provider.load();
      expect(provider.error, NotificationsError.generic);

      // FormatException
      fakeApi.getNotificationsError = const FormatException('Bad JSON');
      await provider.load();
      expect(provider.error, NotificationsError.generic);
    });

    test('refreshUnreadCount updates unreadCount without altering items',
        () async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(id: 'n-1', read: false),
        ],
        unreadCount: 1,
        total: 1,
      );
      final provider = NotificationsProvider(api: fakeApi);
      await provider.load();

      expect(provider.unreadCount, 1);
      expect(provider.items.length, 1);

      // Simulating new incoming unread notifications on backend
      fakeApi.unreadCount = 5;
      await provider.refreshUnreadCount();

      expect(provider.unreadCount, 5);
      expect(provider.items.length, 1); // Items untouched
    });

    test('markRead changes local state only after server success', () async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(id: 'n-read-me', read: false),
        ],
        unreadCount: 1,
        total: 1,
      );
      final provider = NotificationsProvider(api: fakeApi);
      await provider.load();

      expect(provider.items.first.read, isFalse);
      expect(provider.unreadCount, 1);

      await provider.markRead('n-read-me');

      expect(fakeApi.markReadCalls, 1);
      expect(provider.items.first.read, isTrue);
      expect(provider.unreadCount, 0);

      // Marking again does not issue redundant API call (guard)
      await provider.markRead('n-read-me');
      expect(fakeApi.markReadCalls, 1);
    });

    test('markRead failure leaves state unread and surfaces error', () async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(id: 'n-fail-me', read: false),
        ],
        unreadCount: 1,
        total: 1,
      );
      final provider = NotificationsProvider(api: fakeApi);
      await provider.load();

      fakeApi.markReadError = ApiException(500, 'Error');
      await provider.markRead('n-fail-me');

      expect(provider.items.first.read, isFalse);
      expect(provider.unreadCount, 1);
      expect(provider.error, NotificationsError.generic);
    });

    test('markAllRead changes all items to read after server success',
        () async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(id: 'n-1', read: false),
          sampleNotificationJson(id: 'n-2', read: false),
          sampleNotificationJson(id: 'n-3', read: true),
        ],
        unreadCount: 2,
        total: 3,
      );
      final provider = NotificationsProvider(api: fakeApi);
      await provider.load();

      expect(provider.unreadCount, 2);
      expect(provider.items.where((n) => !n.read).length, 2);

      await provider.markAllRead();

      expect(fakeApi.markAllReadCalls, 1);
      expect(provider.unreadCount, 0);
      expect(provider.items.every((n) => n.read), isTrue);

      // Calling markAllRead when already all read does not issue redundant API call
      await provider.markAllRead();
      expect(fakeApi.markAllReadCalls, 1);
    });

    test('markAllRead failure leaves unread items untouched and surfaces error',
        () async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(id: 'n-1', read: false),
        ],
        unreadCount: 1,
        total: 1,
      );
      final provider = NotificationsProvider(api: fakeApi);
      await provider.load();

      fakeApi.markAllReadError = const SocketException('Network down');
      await provider.markAllRead();

      expect(provider.unreadCount, 1);
      expect(provider.items.first.read, isFalse);
      expect(provider.error, NotificationsError.network);
    });

    test('loadMore does not run while error != null', () async {
      final fakeApi = FakeNotificationsApi(
        notifications: List.generate(
          25,
          (i) => sampleNotificationJson(id: 'n-$i'),
        ),
        unreadCount: 25,
        total: 25,
      );
      final provider = NotificationsProvider(api: fakeApi);
      await provider.load();
      expect(provider.items.length, 20);
      expect(fakeApi.getNotificationsCalls, 1);

      fakeApi.getNotificationsError = const SocketException('offline');
      await provider.loadMore();
      expect(provider.error, NotificationsError.network);
      expect(fakeApi.getNotificationsCalls, 2);

      // Subsequent call does not call API
      await provider.loadMore();
      expect(fakeApi.getNotificationsCalls, 2);
    });

    test('dispose during inflight refreshUnreadCount does not throw', () async {
      final completer = Completer<Map<String, dynamic>>();
      final fakeApi = _DelayedNotificationsApi(completer);
      final provider = NotificationsProvider(api: fakeApi);

      final future = provider.refreshUnreadCount();
      provider.dispose();

      completer.complete({'unread_count': 5});
      await expectLater(future, completes);
    });

    test('error cleared after successful markRead, markAllRead, loadMore',
        () async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(id: 'n-1', read: false),
          sampleNotificationJson(id: 'n-2', read: false),
        ],
        unreadCount: 2,
        total: 2,
      );
      final provider = NotificationsProvider(api: fakeApi);
      await provider.load();

      // Trigger error via failed markRead
      fakeApi.markReadError = const SocketException('offline');
      await provider.markRead('n-1');
      expect(provider.error, NotificationsError.network);

      // Successful markRead clears error
      fakeApi.markReadError = null;
      await provider.markRead('n-1');
      expect(provider.error, isNull);

      // Trigger error via failed markAllRead
      fakeApi.markAllReadError = const SocketException('offline');
      await provider.markAllRead();
      expect(provider.error, NotificationsError.network);

      // Successful markAllRead clears error
      fakeApi.markAllReadError = null;
      await provider.markAllRead();
      expect(provider.error, isNull);
    });
  });
}

class _DelayedNotificationsApi extends FakeNotificationsApi {
  _DelayedNotificationsApi(this.completer);
  final Completer<Map<String, dynamic>> completer;

  @override
  Future<Map<String, dynamic>> getNotifications({
    bool unreadOnly = false,
    int limit = 20,
    int offset = 0,
  }) {
    return completer.future;
  }
}
