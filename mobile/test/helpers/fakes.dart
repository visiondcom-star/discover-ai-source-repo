import 'package:discover_ai/services/api_service.dart';
import 'package:discover_ai/services/secure_storage_service.dart';

/// Deterministic AuthApi fake for tests.
class FakeAuthApi implements AuthApi {
  FakeAuthApi({this.failLogin = false, this.failGetMe = false});

  final bool failLogin;
  final bool failGetMe;
  int loginCalls = 0;
  String? lastToken;

  @override
  void setToken(String token) => lastToken = token;

  @override
  Future<Map<String, dynamic>> getMe() async {
    if (failGetMe) {
      throw ApiException(401, '{"detail":"Could not validate credentials"}');
    }
    return {
      'id': 'u-1',
      'email': 'demo@discoverai.dz',
      'full_name': 'Demo User',
      'is_active': true,
      'is_admin': false,
      'preferences': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    };
  }

  @override
  Future<Map<String, dynamic>> login(String email, String password) async {
    loginCalls++;
    if (failLogin) {
      throw ApiException(401, '{"detail":"Incorrect email or password"}');
    }
    return {
      'access_token': 'jwt-token-123',
      'token_type': 'bearer',
      'expires_in': 1800,
    };
  }

  @override
  Future<Map<String, dynamic>> register(
    String email,
    String password, {
    String? fullName,
  }) async =>
      {
        'id': 'u-new',
        'email': email,
        'full_name': fullName,
        'is_active': true,
        'is_admin': false,
        'preferences': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      };
}

const List<Map<String, dynamic>> samplePoisJson = [
  {
    'id': 'p-1',
    'slug': 'casbah-of-algiers',
    'tenant_id': 't-1',
    'name': 'Casbah of Algiers',
    'description': 'UNESCO world heritage medina.',
    'city': 'Algiers',
    'category': 'historical',
    'duration_minutes': 120,
    'price_range': 'free',
    'latitude': 36.7836,
    'longitude': 3.06,
    'images': [],
    'tags': ['unesco'],
    'accessibility': [],
    'opening_hours': {},
    'is_verified': true,
    'is_active': true,
    'average_rating': 4.5,
    'review_count': 12,
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-02T00:00:00Z',
  },
  {
    'id': 'p-2',
    'slug': 'notre-dame-dafrique',
    'tenant_id': 't-1',
    'name': "Notre-Dame d'Afrique",
    'city': 'Algiers',
    'category': 'culture',
    'duration_minutes': 90,
    'price_range': 'free',
    'average_rating': 4.7,
    'review_count': 8,
  },
];

class FakePoisApi implements PoisApi {
  FakePoisApi({this.itemsJson = samplePoisJson});

  final List<Map<String, dynamic>> itemsJson;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getPOIs({
    String? city,
    String? category,
    String? search,
  }) async {
    calls++;
    return {'items': itemsJson};
  }
}

/// Fresh copy each call so mutation-prone consumers can't corrupt the fixture.
/// Field-for-field mirror of the backend TripResponse schema.
Map<String, dynamic> sampleTripJson() => {
      'id': 'tr-1',
      'tenant_id': 't-1',
      'user_id': 'u-1',
      'title': 'Algiers highlights',
      'description': 'Two days through the white city.',
      'num_days': 2,
      'budget_level': 'medium',
      'budget_currency': 'DZD',
      'travel_style': 'balanced',
      'interests': ['history', 'food'],
      'group_type': 'solo',
      'children': false,
      'status': 'draft',
      'total_cost_estimate': 1200.5,
      'items': [
        {
          'id': 'i-1',
          'poi_id': 'p-1',
          'day_number': 1,
          'order_index': 0,
          'start_time': '2026-08-24T09:00:00Z',
          'end_time': '2026-08-24T11:00:00Z',
          'notes': 'Morning walk through the medina.',
          'poi': samplePoisJson[0],
        },
        {
          'id': 'i-2',
          'poi_id': 'p-2',
          'day_number': 1,
          'order_index': 1,
          'start_time': '2026-08-24T14:00:00Z',
          'end_time': null,
          'notes': null,
          'poi': samplePoisJson[1],
        },
        {
          'id': 'i-3',
          'poi_id': 'p-1',
          'day_number': 2,
          'order_index': 0,
          'start_time': null,
          'end_time': null,
          'notes': 'Second visit at a slower pace.',
          'poi': null,
        },
      ],
      'created_at': '2026-08-24T08:00:00Z',
      'updated_at': '2026-08-24T08:00:00Z',
    };

class FakeTripsApi implements TripsApi {
  FakeTripsApi({this.failGenerate = false});

  final bool failGenerate;
  int generateCalls = 0;
  int listCalls = 0;
  Map<String, dynamic>? lastGeneratePayload;

  @override
  Future<Map<String, dynamic>> generateTrip({
    required List<String> interests,
    required String budgetLevel,
    required int numDays,
  }) async {
    generateCalls++;
    lastGeneratePayload = {
      'interests': List<String>.from(interests),
      'budget_level': budgetLevel,
      'num_days': numDays,
    };
    if (failGenerate) {
      throw ApiException(500, '{"detail":"trip planner failed"}');
    }
    return sampleTripJson();
  }

    @override
  Future<List<Map<String, dynamic>>> listTrips() async {
    listCalls++;
    return [sampleTripJson()];
  }
}

/// Deterministic ChatApi fake for tests.
class FakeChatApi implements ChatApi {
  FakeChatApi({this.response, this.failReply = false});

  final Map<String, dynamic>? response;
  final bool failReply;
  int calls = 0;
  String? lastMessage;
  Map<String, dynamic>? lastContext;

  @override
  Future<Map<String, dynamic>> sendMessage(
    String message, {
    Map<String, dynamic>? context,
  }) async {
    calls++;
    lastMessage = message;
    lastContext = context;
    if (failReply) {
      throw ApiException(500, '{"detail":"chat service unavailable"}');
    }
    return Map<String, dynamic>.from(response ??
        {
          'message': 'Mocked assistant reply to: $message',
          'suggestions': <String>['Suggestion 1', 'Suggestion 2'],
          'context': <String, dynamic>{},
        });
  }
}

/// In-memory TokenStore for tests (no platform channels involved).
class InMemoryTokenStore implements TokenStore {
  String? token;

  @override
  Future<void> deleteToken() async => token = null;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;
}