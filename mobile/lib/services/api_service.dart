import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const String baseUrl = 'http://10.0.2.2:8000/api/v1';
  static const String tenantSlug = 'algeria';
  String _token = '';

  void setToken(String token) => _token = token;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-Tenant-Slug': tenantSlug,
    if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
  };

  Future<dynamic> _get(String path) async {
    final res = await http.get(Uri.parse('$baseUrl$path'), headers: _headers);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body);
    }
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body);
    }
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }

  Future<Map<String, dynamic>> getTenant() async => await _get('/tenants/current');

  Future<Map<String, dynamic>> login(String email, String password) async {
    return await _post('/auth/login', {'email': email, 'password': password});
  }

  Future<Map<String, dynamic>> register(String email, String password, {String? fullName}) async {
    return await _post('/auth/register', {
      'email': email,
      'password': password,
      if (fullName != null) 'full_name': fullName,
    });
  }

  Future<Map<String, dynamic>> getMe() async => await _get('/auth/me');

  Future<Map<String, dynamic>> getPOIs({String? city, String? category, String? search}) async {
    final params = <String, String>{};
    if (city != null) params['city'] = city;
    if (category != null) params['category'] = category;
    if (search != null) params['search'] = search;
    final query = params.isNotEmpty ? '?${params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}' : '';
    return await _get('/pois/$query');
  }

  Future<Map<String, dynamic>> generateTrip({
    required int numDays,
    required String budgetLevel,
    required String travelStyle,
    required String groupType,
    List<String>? interests,
  }) async {
    return await _post('/trips/generate', {
      'num_days': numDays,
      'budget_level': budgetLevel,
      'travel_style': travelStyle,
      'group_type': groupType,
      'interests': interests ?? [],
      'budget_currency': 'DZD',
    });
  }

  Future<Map<String, dynamic>> chat(String message) async {
    return await _post('/chat/', {'message': message});
  }
}
