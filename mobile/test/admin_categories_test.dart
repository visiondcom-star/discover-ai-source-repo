import 'package:discover_ai/providers/admin_categories_provider.dart';
import 'package:discover_ai/providers/research_provider.dart';
import 'package:discover_ai/providers/tenant_provider.dart';
import 'package:discover_ai/screens/admin_research_screen.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fake_admin_categories_api.dart';
import 'helpers/fakes.dart';

Map<String, dynamic> _cat(String id, String status, {double? confidence}) => {
      'id': id,
      'tenant_id': 'tenant-1',
      'slug': 'slug_$id',
      'label': 'Catégorie $id',
      'parent_family': 'culture',
      'status': status,
      'confidence': confidence,
      'display_order': 0,
      'ai_generated': true,
    };

void main() {
  group('AdminCategoriesProvider', () {
    test('load récupère tous les statuts', () async {
      final fake = FakeAdminCategoriesApi(categories: [
        _cat('a', 'proposed'),
        _cat('b', 'active'),
        _cat('c', 'rejected'),
      ]);
      final provider = AdminCategoriesProvider(fake);

      await provider.load();

      expect(provider.categories.map((c) => c.status),
          ['proposed', 'active', 'rejected']);
      provider.dispose();
    });

    test('setStatus remplace la catégorie et déclenche onChanged', () async {
      final fake = FakeAdminCategoriesApi(categories: [_cat('a', 'proposed')]);
      var changed = 0;
      final provider = AdminCategoriesProvider(fake, onChanged: () => changed++);
      await provider.load();

      await provider.setStatus(provider.categories.single, 'active');

      expect(fake.updateCalls.single, {'categoryId': 'a', 'status': 'active'});
      expect(provider.categories.single.status, 'active');
      expect(changed, 1);
      expect(provider.error, isNull);
      provider.dispose();
    });

    test('un échec garde la liste, expose une erreur, sans onChanged',
        () async {
      final fake = FakeAdminCategoriesApi(
        categories: [_cat('a', 'proposed')],
        updateError: ApiException(409, '{"detail":"invalid transition"}'),
      );
      var changed = 0;
      final provider = AdminCategoriesProvider(fake, onChanged: () => changed++);
      await provider.load();

      await provider.setStatus(provider.categories.single, 'active');

      expect(provider.categories.single.status, 'proposed');
      expect(provider.error, isNotNull);
      expect(provider.isUpdating('a'), isFalse);
      expect(changed, 0);
      provider.dispose();
    });
  });

  testWidgets('publier une proposition appelle le PATCH et met la ligne à jour',
      (tester) async {
    final fake = FakeAdminCategoriesApi(
        categories: [_cat('c1', 'proposed', confidence: 0.82)]);
    final tenants = TenantProvider(tenantsApi: FakeTenantsApi());
    await tenants.loadTenant();
    final admin = AdminCategoriesProvider(fake);
    final research = ResearchProvider(FakeResearchApi());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ResearchProvider>.value(value: research),
          ChangeNotifierProvider<TenantProvider>.value(value: tenants),
          ChangeNotifierProvider<AdminCategoriesProvider>.value(value: admin),
        ],
        child: const MaterialApp(home: AdminResearchScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Catégorie c1'), findsOneWidget);
    expect(find.text('culture · 82%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('publish_c1')));
    await tester.pumpAndSettle();

    expect(fake.updateCalls.single, {'categoryId': 'c1', 'status': 'active'});
    expect(find.byKey(const Key('publish_c1')), findsNothing);
    expect(find.byKey(const Key('retire_c1')), findsOneWidget);

    admin.dispose();
    research.dispose();
  });
}
