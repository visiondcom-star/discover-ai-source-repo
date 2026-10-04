import 'package:discover_ai/services/api_service.dart';

class FakeAdminCategoriesApi implements AdminCategoriesApi {
  FakeAdminCategoriesApi({
    List<Map<String, dynamic>>? categories,
    this.updateError,
  }) : categories = categories ?? [];

  final List<Map<String, dynamic>> categories;
  final ApiException? updateError;

  int getAllCalls = 0;
  final List<Map<String, String>> updateCalls = [];

  @override
  Future<List<Map<String, dynamic>>> getAllCategories() async {
    getAllCalls++;
    return categories.map((c) => Map<String, dynamic>.from(c)).toList();
  }

  @override
  Future<Map<String, dynamic>> updateCategoryStatus({
    required String categoryId,
    required String status,
  }) async {
    updateCalls.add({'categoryId': categoryId, 'status': status});
    if (updateError != null) throw updateError!;
    final i = categories.indexWhere((c) => c['id'] == categoryId);
    if (i < 0) throw ApiException(404, '{"detail":"not found"}');
    categories[i] = {...categories[i], 'status': status};
    return Map<String, dynamic>.from(categories[i]);
  }
}
