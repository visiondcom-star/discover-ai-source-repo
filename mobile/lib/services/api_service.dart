import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// Abstraction seams so providers/screens can be tested with fakes instead
/// of hitting the network.
abstract class AuthApi {
  /// Attaches (or clears) the bearer token used on subsequent requests.
  void setToken(String token);

  Future<Map<String, dynamic>> login(String email, String password);
  Future<Map<String, dynamic>> register(
    String email,
    String password, {
    String? fullName,
  });
  Future<Map<String, dynamic>> getMe();
}

abstract class PoisApi {
  Future<Map<String, dynamic>> getPOIs({
    String? city,
    String? category,
    String? search,
  });
}

abstract class TripsApi {
  /// Generates an itinerary; mirrors POST /trips/generate (201).
  Future<Map<String, dynamic>> generateTrip({
    required List<String> interests,
    required String budgetLevel,
    required int numDays,
  });

  /// Lists the current user's trips; mirrors GET /trips/.
  Future<List<Map<String, dynamic>>> listTrips();
}

/// AI Chat seam — mirrors POST /chat/ (backend/app/schemas.py →
/// ChatRequest{message, context} → ChatResponse{message, suggestions, context}).
abstract class ChatApi {
  Future<Map<String, dynamic>> sendMessage(
    String message, {
    Map<String, dynamic>? context,
  });
}

/// Booking-Agent seam — mirrors POST /bookings/ (201), GET /bookings/,
/// POST /bookings/{id}/consent, POST /bookings/{id}/cancel and
/// GET /bookings/adapters/available
/// (backend/app/api/v1/endpoints/bookings.py).
abstract class BookingsApi {
  /// Creates a PENDING booking; mirrors POST /bookings/ (201).
  Future<Map<String, dynamic>> createBooking({
    required String poiId,
    required String adapterType,
    Map<String, dynamic> bookingData,
  });

  /// Lists the current user's bookings; mirrors GET /bookings/.
  Future<List<Map<String, dynamic>>> listBookings();

  /// Explicit consent step; mirrors POST /bookings/{id}/consent.
  /// consent=true → confirmed + EXT-… reference, false → cancelled.
  Future<Map<String, dynamic>> giveConsent(String bookingId,
      {required bool consent});

  /// Mirrors POST /bookings/{id}/cancel.
  Future<Map<String, dynamic>> cancelBooking(String bookingId);

  /// Adapter catalogue advertised by the backend.
  Future<Map<String, dynamic>> listAdapters();
}

/// HTTP failure carrying status code and body.
class ApiException implements Exception {
  ApiException(this.statusCode, this.body);

  final int? statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}

/// Thin HTTP client speaking the same contract as the web frontend:
/// `X-Tenant-Slug` on every request, `Authorization: Bearer` once a token is
/// attached.
///
/// Host and tenant slug come exclusively from [AppConfig]
/// (`--dart-define`) — never hardcoded in business code.
class ApiService implements AuthApi, PoisApi, TripsApi, ChatApi, BookingsApi {
  ApiService._internal()
      : baseUrl = AppConfig.apiBaseUrl,
        tenantSlug = AppConfig.tenantSlug;

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  /// Explicit-configuration constructor (tests / tooling).
  ApiService.withConfig({String? baseUrl, String? tenantSlug})
      : baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        tenantSlug = tenantSlug ?? AppConfig.tenantSlug;

  final String baseUrl;
  final String tenantSlug;

  String _token = '';

  @override
  void setToken(String token) => _token = token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Tenant-Slug': tenantSlug,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

    Future<dynamic> _get(String path) async {
    final url = '$baseUrl$path';
    debugPrint('[API] GET $url');
    final res = await http.get(Uri.parse(url), headers: _headers);
    debugPrint('[API] GET $path → ${res.statusCode}');
    return _decode(res);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final url = '$baseUrl$path';
    debugPrint('[API] POST $url body=$body');
    final res = await http.post(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode(body),
    );
    debugPrint('[API] POST $path → ${res.statusCode}');
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body);
    }
    throw ApiException(res.statusCode, res.body);
  }

  @override
  Future<Map<String, dynamic>> getMe() async =>
      Map<String, dynamic>.from(await _get('/auth/me') as Map);

  @override
  Future<Map<String, dynamic>> login(String email, String password) async =>
      Map<String, dynamic>.from(await _post('/auth/login', {
        'email': email,
        'password': password,
      }) as Map);

  @override
  Future<Map<String, dynamic>> register(
    String email,
    String password, {
    String? fullName,
  }) async =>
      Map<String, dynamic>.from(await _post('/auth/register', {
        'email': email,
        'password': password,
        if (fullName != null) 'full_name': fullName,
      }) as Map);

  @override
  Future<Map<String, dynamic>> getPOIs({
    String? city,
    String? category,
    String? search,
  }) async {
    final params = <String, String>{
      if (city != null && city.isNotEmpty) 'city': city,
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    // Keep the trailing-slash form the backend has always served.
    final suffix = params.isEmpty
        ? '/'
        : '/?${params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    return Map<String, dynamic>.from(await _get('/pois$suffix') as Map);
  }

  @override
  Future<Map<String, dynamic>> generateTrip({
    required List<String> interests,
    required String budgetLevel,
    required int numDays,
  }) async =>
      Map<String, dynamic>.from(await _post('/trips/generate', {
        'interests': interests,
        'budget_level': budgetLevel,
        'num_days': numDays,
      }) as Map);

    @override
  Future<List<Map<String, dynamic>>> listTrips() async {
    final data = await _get('/trips/');
    return (data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

    @override
  Future<Map<String, dynamic>> sendMessage(
    String message, {
    Map<String, dynamic>? context,
  }) async {
    final body = <String, dynamic>{'message': message};
    if (context != null) body['context'] = context;
    final result = await _post('/chat/', body);
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<Map<String, dynamic>> createBooking({
    required String poiId,
    required String adapterType,
    Map<String, dynamic> bookingData = const {},
  }) async =>
      Map<String, dynamic>.from(await _post('/bookings/', {
        'poi_id': poiId,
        'adapter_type': adapterType,
        'booking_data': bookingData,
      }) as Map);

  @override
  Future<List<Map<String, dynamic>>> listBookings() async {
    final data = await _get('/bookings/');
    return (data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> giveConsent(String bookingId,
          {required bool consent}) async =>
      Map<String, dynamic>.from(await _post('/bookings/$bookingId/consent', {
        'consent': consent,
      }) as Map);

  @override
  Future<Map<String, dynamic>> cancelBooking(String bookingId) async =>
      Map<String, dynamic>.from(
          await _post('/bookings/$bookingId/cancel', {}) as Map);

  @override
  Future<Map<String, dynamic>> listAdapters() async =>
      Map<String, dynamic>.from(await _get('/bookings/adapters/available') as Map);
}
