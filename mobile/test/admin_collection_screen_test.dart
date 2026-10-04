// test/providers/admin_collection_screen_test.dart

import 'package:discover_ai/models/research_collection_job.dart';
import 'package:discover_ai/models/research_job.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/research_collection_provider.dart';
import 'package:discover_ai/providers/research_provider.dart';
import 'package:discover_ai/providers/tenant_provider.dart';
import 'package:discover_ai/screens/admin_collection_screen.dart';
import 'package:discover_ai/screens/profile_screen.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fake_research_collection_api.dart';
import 'helpers/fakes.dart';

ResearchCollectionJob _job(
  ResearchJobStatus status, {
  int fetched = 0,
  int newDocs = 0,
  int duplicate = 0,
  int failed = 0,
}) {
  return ResearchCollectionJob(
    id: 'c1',
    tenantId: 'tenant-1',
    status: status,
    documentsFetched: fetched,
    documentsNew: newDocs,
    documentsDuplicate: duplicate,
    documentsFailed: failed,
  );
}

void main() {
  group('AdminCollectionScreen', () {
    Future<FakeTenantsApi> pumpScreen(
      WidgetTester tester, {
      required ResearchCollectionProvider collection,
      required ResearchProvider research,
    }) async {
      final tenantsApi = FakeTenantsApi();
      final tenants = TenantProvider(tenantsApi: tenantsApi);
      await tenants.loadTenant();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ResearchCollectionProvider>.value(
                value: collection),
            ChangeNotifierProvider<ResearchProvider>.value(value: research),
            ChangeNotifierProvider<TenantProvider>.value(value: tenants),
          ],
          child: const MaterialApp(home: AdminCollectionScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return tenantsApi;
    }
testWidgets('lance la collecte avec le tenant courant et l’enchaînement '
        'activé par défaut', (tester) async {
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.processing)],
        statusSequence: [_job(ResearchJobStatus.processing)],
      );
      final collection = ResearchCollectionProvider(fake,
          pollInterval: const Duration(seconds: 30));
      final research = ResearchProvider(FakeResearchApi());

      await pumpScreen(tester, collection: collection, research: research);
      await tester.tap(find.byKey(const Key('run_collection_button')));
      // Pas de pumpAndSettle : le spinner du job non terminal anime en continu.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fake.runCollectionCalls.single['tenantId'], 'tenant-1');
      expect(fake.runCollectionCalls.single['runPipeline'], true);
      expect(find.text('Collecte en cours…'), findsWidgets);

      collection.dispose();
      research.dispose();
    });

    testWidgets('le switch désactivé envoie runPipeline=false',
        (tester) async {
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.processing)],
        statusSequence: [_job(ResearchJobStatus.processing)],
      );
      final collection = ResearchCollectionProvider(fake,
          pollInterval: const Duration(seconds: 30));
      final research = ResearchProvider(FakeResearchApi());

      await pumpScreen(tester, collection: collection, research: research);
      await tester.tap(find.byKey(const Key('run_pipeline_switch')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('run_collection_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fake.runCollectionCalls.single['runPipeline'], false);

      collection.dispose();
      research.dispose();
    });

    testWidgets('affiche le message du 409 (collecte déjà en cours)',
        (tester) async {
      final fake = FakeResearchCollectionApi(
        runError: ApiException(409, '{"detail":"running"}'),
      );
      final collection = ResearchCollectionProvider(fake);
      final research = ResearchProvider(FakeResearchApi());

      await pumpScreen(tester, collection: collection, research: research);
      await tester.tap(find.byKey(const Key('run_collection_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('déjà en cours'), findsOneWidget);

      collection.dispose();
      research.dispose();
    });

    testWidgets('une collecte terminée affiche ses compteurs',
        (tester) async {
      final done =
          _job(ResearchJobStatus.done, fetched: 5, newDocs: 3, duplicate: 2);
      final fake = FakeResearchCollectionApi(
        jobsQueue: [done],
        statusSequence: [done],
      );
      final collection = ResearchCollectionProvider(fake);
      final research = ResearchProvider(FakeResearchApi());

      await pumpScreen(tester, collection: collection, research: research);
      await tester.tap(find.byKey(const Key('run_collection_button')));
      await tester.pumpAndSettle();

      expect(find.text('Collecte terminée'), findsOneWidget);
      expect(
        find.text('5 récupéré(s) · 3 nouveau(x) · 2 doublon(s) · 0 en échec'),
        findsOneWidget,
      );

      collection.dispose();
      research.dispose();
    });
  });

  group('ProfileScreen navigation', () {
    testWidgets(
        'tapping the admin collection entry navigates to AdminCollectionScreen',
        (tester) async {
      // Sans cette entrée, l'écran de collecte était inatteignable depuis
      // l'app : aucun `lib/` ne naviguait vers AdminCollectionScreen.
      final tenants = TenantProvider(tenantsApi: FakeTenantsApi());
      await tenants.loadTenant();
      final collection = ResearchCollectionProvider(
          FakeResearchCollectionApi(),
          pollInterval: const Duration(seconds: 30));
      final research = ResearchProvider(FakeResearchApi());

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => AuthProvider(
                api: FakeAuthApi(),
                tokenStore: InMemoryTokenStore(),
              ),
            ),
            ChangeNotifierProvider<ResearchCollectionProvider>.value(
                value: collection),
            ChangeNotifierProvider<ResearchProvider>.value(value: research),
            ChangeNotifierProvider<TenantProvider>.value(value: tenants),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
          find.byKey(const Key('admin_collection_button')), 200);
      await tester.tap(find.byKey(const Key('admin_collection_button')));
      await tester.pumpAndSettle();

      expect(find.byType(AdminCollectionScreen), findsOneWidget);

      collection.dispose();
      research.dispose();
    });
  });
}