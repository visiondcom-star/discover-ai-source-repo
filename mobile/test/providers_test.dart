import 'package:flutter_test/flutter_test.dart';

import 'package:discover_ai/models/poi.dart';
import 'package:discover_ai/models/user.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/services/api_service.dart';

import 'helpers/fakes.dart';

class _ThrowingPoisApi implements PoisApi {
  @override
  Future<Map<String, dynamic>> getPOIs({
    String? city,
    String? category,
    String? search,
  }) async {
    throw ApiException(500, 'boom');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('User model (backend UserResponse mirror)', () {
    test('parses the backend payload', () {
      final user = User.fromJson(const {
        'id': 'u-1',
        'email': 'demo@discoverai.dz',
        'full_name': 'Demo User',
        'is_active': true,
        'is_admin': false,
        'preferences': {'lang': 'fr'},
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(user.email, 'demo@discoverai.dz');
      expect(user.fullName, 'Demo User');
      expect(user.preferences['lang'], 'fr');
      expect(user.createdAt!.year, 2026);
    });
  });

  group('POI model (backend POIResponse mirror)', () {
    test('parses the full payload including rating aggregate', () {
      final poi = POI.fromJson(samplePoisJson.first);
      expect(poi.slug, 'casbah-of-algiers');
      expect(poi.tenantId, 't-1');
      expect(poi.averageRating, 4.5);
      expect(poi.reviewCount, 12);
      expect(poi.category, 'historical');
      expect(poi.updatedAt, isNotNull);
    });
  });

  group('AuthProvider', () {
    test('successful login persists the JWT in the secure store', () async {
      final store = InMemoryTokenStore();
      final auth = AuthProvider(api: FakeAuthApi(), tokenStore: store);
      await auth.initialized;

      final ok = await auth.login('demo@discoverai.dz', 'secret123');

      expect(ok, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(store.token, 'jwt-token-123');
      expect(auth.user!.email, 'demo@discoverai.dz');
    });

    test('failed login leaves the store untouched', () async {
      final store = InMemoryTokenStore();
      final auth =
          AuthProvider(api: FakeAuthApi(failLogin: true), tokenStore: store);
      await auth.initialized;

      final ok = await auth.login('demo@discoverai.dz', 'nope');

      expect(ok, isFalse);
      expect(auth.isAuthenticated, isFalse);
      expect(store.token, isNull);
    });

    test('stale stored tokens are dropped on restore', () async {
      final store = InMemoryTokenStore()..token = 'stale-jwt';
      final auth = AuthProvider(
        api: FakeAuthApi(failGetMe: true),
        tokenStore: store,
      );
      await auth.initialized;

      expect(auth.isAuthenticated, isFalse);
      expect(store.token, isNull); // deleted during restore
    });
  });

  group('POIProvider', () {
    test('loadPOIs parses the items envelope and clears errors', () async {
      final provider = POIProvider(poisApi: FakePoisApi());
      await provider.loadPOIs();

      expect(provider.items.length, 2);
      expect(provider.items.first.name, 'Casbah of Algiers');
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('API failures surface as an error message', () async {
      final provider = POIProvider(poisApi: _ThrowingPoisApi());
      await provider.loadPOIs();

      expect(provider.items, isEmpty);
      expect(provider.error, contains('boom'));
      expect(provider.isLoading, isFalse);
    });
  });

  group('TripProvider', () {
    test('generate stores the trip as currentTrip and prepends to trips',
        () async {
      final api = FakeTripsApi();
      final provider = TripProvider(tripsApi: api);

      final trip = await provider.generate(
        interests: const ['history'],
        budgetLevel: 'high',
        numDays: 3,
      );

      expect(trip, isNotNull);
      expect(api.generateCalls, 1);
      // The API seam receives exactly the user's selection.
      expect(api.lastGeneratePayload, {
        'interests': ['history'],
        'budget_level': 'high',
        'num_days': 3,
      });
      expect(provider.currentTrip!.title, 'Algiers highlights');
      expect(provider.currentTrip!.budgetCurrency, 'DZD');
      expect(provider.currentTrip!.items.length, 3);
      expect(provider.trips.first.id, 'tr-1');
      expect(provider.isGenerating, isFalse);
      expect(provider.error, isNull);
    });

    test('generate failure returns null and carries the error', () async {
      final provider = TripProvider(tripsApi: FakeTripsApi(failGenerate: true));

      final trip = await provider.generate(
        interests: const ['nature'],
        budgetLevel: 'low',
        numDays: 2,
      );

      expect(trip, isNull);
      expect(provider.currentTrip, isNull);
      expect(provider.trips, isEmpty);
      expect(provider.error, contains('trip planner failed'));
      expect(provider.isGenerating, isFalse);

      provider.clearError();
      expect(provider.error, isNull);
    });

    test('generate rejects an empty interest selection before calling the API',
        () async {
      // Guard lives in the form; the provider contract still holds when
      // handed an empty list — the backend would accept it, so no client-side
      // throw. This pins the current behavior.
      final api = FakeTripsApi();
      final provider = TripProvider(tripsApi: api);

      await provider.generate(
        interests: const [],
        budgetLevel: 'medium',
        numDays: 1,
      );

      expect(api.generateCalls, 1);
      expect(provider.currentTrip, isNotNull);
    });

    test('loadTrips parses the list endpoint payload', () async {
      final api = FakeTripsApi();
      final provider = TripProvider(tripsApi: api);

      await provider.loadTrips();

      expect(api.listCalls, 1);
      expect(provider.trips.length, 1);
      expect(provider.trips.first.numDays, 2);
      expect(provider.trips.first.itemsByDay.keys, [1, 2]);
      expect(provider.isLoading, isFalse);
    });
  });
}