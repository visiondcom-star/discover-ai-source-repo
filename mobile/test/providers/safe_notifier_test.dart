import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:discover_ai/models/research_collection_job.dart';
import 'package:discover_ai/models/research_job.dart';
import 'package:discover_ai/providers/admin_categories_provider.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/providers/chat_provider.dart';
import 'package:discover_ai/providers/notifications_provider.dart';
import 'package:discover_ai/providers/research_collection_provider.dart';
import 'package:discover_ai/providers/research_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/services/api_service.dart';

import '../helpers/fakes.dart';

void main() {
  group('SafeNotifier mixin protects against notifyListeners after dispose',
      () {
    test('ChatProvider: dispose during inflight sendMessage does not throw',
        () async {
      final completer = Completer<Map<String, dynamic>>();
      final fakeApi = _DelayedChatApi(completer);
      final provider = ChatProvider(chatApi: fakeApi);

      final future = provider.sendMessage('Hello');
      expect(provider.isSending, isTrue);

      provider.dispose();
      expect(provider.disposed, isTrue);

      completer.complete({
        'message': 'Hi',
        'suggestions': <String>[],
        'context': <String, dynamic>{},
      });
      await expectLater(future, completes);
      expect(provider.isSending, isFalse);
    });

    test('TripProvider: dispose during inflight generate does not throw',
        () async {
      final completer = Completer<Map<String, dynamic>>();
      final fakeApi = _DelayedTripsApi(completer);
      final provider = TripProvider(tripsApi: fakeApi);

      final future = provider.generate(
        interests: ['culture'],
        budgetLevel: 'medium',
        numDays: 3,
      );
      expect(provider.isGenerating, isTrue);

      provider.dispose();
      expect(provider.disposed, isTrue);

      completer.complete(sampleTripJson());
      await expectLater(future, completes);
      expect(provider.isGenerating, isFalse);
    });

    test('BookingProvider: dispose during inflight loadBookings does not throw',
        () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      final fakeApi = _DelayedBookingsApi(completer);
      final provider = BookingProvider(bookingsApi: fakeApi);

      final future = provider.loadBookings();
      expect(provider.isLoading, isTrue);

      provider.dispose();
      expect(provider.disposed, isTrue);

      completer.complete([sampleBookingJson()]);
      await expectLater(future, completes);
      expect(provider.isLoading, isFalse);
    });

    test(
        'NotificationsProvider: dispose during inflight refreshUnreadCount does not throw',
        () async {
      final completer = Completer<Map<String, dynamic>>();
      final fakeApi = _DelayedNotificationsApi(completer);
      final provider = NotificationsProvider(api: fakeApi);

      final future = provider.refreshUnreadCount();

      provider.dispose();
      expect(provider.disposed, isTrue);

      completer.complete({'unread_count': 3});
      await expectLater(future, completes);
    });

    test(
        'ResearchProvider: dispose during inflight startResearch does not throw and cancels timer',
        () async {
      final completer = Completer<Map<String, dynamic>>();
      final fakeApi = _DelayedResearchApi(completer);
      final provider = ResearchProvider(fakeApi);

      final future = provider.startResearch(
        tenantId: 't-1',
        triggerType: ResearchTriggerType.manualRefresh,
      );
      expect(provider.isLoading, isTrue);

      provider.dispose();
      expect(provider.disposed, isTrue);

      completer.complete(
        const ResearchJob(
          id: 'job-1',
          tenantId: 't-1',
          triggerType: ResearchTriggerType.manualRefresh,
          status: ResearchJobStatus.processing,
        ).toJson(),
      );
      await expectLater(future, completes);
      expect(provider.isLoading, isFalse);
    });

    test(
        'ResearchCollectionProvider: dispose during inflight startCollection does not throw and cancels timer',
        () async {
      final completer = Completer<Map<String, dynamic>>();
      final fakeApi = _DelayedResearchCollectionApi(completer);
      final provider = ResearchCollectionProvider(fakeApi);

      final future = provider.startCollection(tenantId: 't-1');
      expect(provider.isLoading, isTrue);

      provider.dispose();
      expect(provider.disposed, isTrue);

      completer.complete(
        const ResearchCollectionJob(
          id: 'col-1',
          tenantId: 't-1',
          status: ResearchJobStatus.processing,
        ).toJson(),
      );
      await expectLater(future, completes);
    });

    test('AdminCategoriesProvider: dispose during inflight load does not throw',
        () async {
      final completer = Completer<List<Map<String, dynamic>>>();
      final fakeApi = _DelayedAdminCategoriesApi(completer);
      final provider = AdminCategoriesProvider(fakeApi);

      final future = provider.load();
      expect(provider.isLoading, isTrue);

      provider.dispose();
      expect(provider.disposed, isTrue);

      completer.complete([]);
      await expectLater(future, completes);
    });
  });
}

class _DelayedChatApi implements ChatApi {
  _DelayedChatApi(this.completer);
  final Completer<Map<String, dynamic>> completer;

  @override
  Future<Map<String, dynamic>> sendMessage(String message,
      {Map<String, dynamic>? context}) {
    return completer.future;
  }
}

class _DelayedTripsApi extends FakeTripsApi {
  _DelayedTripsApi(this.completer);
  final Completer<Map<String, dynamic>> completer;

  @override
  Future<Map<String, dynamic>> generateTrip({
    required List<String> interests,
    required String budgetLevel,
    required int numDays,
  }) {
    return completer.future;
  }
}

class _DelayedBookingsApi extends FakeBookingsApi {
  _DelayedBookingsApi(this.completer);
  final Completer<List<Map<String, dynamic>>> completer;

  @override
  Future<List<Map<String, dynamic>>> listBookings() {
    return completer.future;
  }
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

class _DelayedResearchApi implements ResearchApi {
  _DelayedResearchApi(this.completer);
  final Completer<Map<String, dynamic>> completer;

  @override
  Future<Map<String, dynamic>> runResearch({
    required String tenantId,
    required String triggerType,
  }) {
    return completer.future;
  }

  @override
  Future<Map<String, dynamic>> getJobStatus({
    required String tenantId,
    required String jobId,
  }) async {
    return {};
  }
}

class _DelayedResearchCollectionApi implements ResearchCollectionApi {
  _DelayedResearchCollectionApi(this.completer);
  final Completer<Map<String, dynamic>> completer;

  @override
  Future<Map<String, dynamic>> runCollection({
    required String tenantId,
    bool runPipeline = false,
  }) {
    return completer.future;
  }

  @override
  Future<Map<String, dynamic>> getCollectionJobStatus({
    required String tenantId,
    required String jobId,
  }) async {
    return {};
  }
}

class _DelayedAdminCategoriesApi implements AdminCategoriesApi {
  _DelayedAdminCategoriesApi(this.completer);
  final Completer<List<Map<String, dynamic>>> completer;

  @override
  Future<List<Map<String, dynamic>>> getAllCategories() {
    return completer.future;
  }

  @override
  Future<Map<String, dynamic>> updateCategoryStatus({
    required String categoryId,
    required String status,
  }) async {
    return {};
  }
}
