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