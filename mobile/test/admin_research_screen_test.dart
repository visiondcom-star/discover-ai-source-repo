import 'package:discover_ai/models/research_job.dart';
import 'package:discover_ai/providers/research_provider.dart';
import 'package:discover_ai/providers/tenant_provider.dart';
import 'package:discover_ai/screens/admin_research_screen.dart';
import 'package:discover_ai/screens/profile_screen.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fakes.dart';

ResearchJob _job({
  required ResearchJobStatus status,
  int categoriesProposed = 0,
  int categoriesAutoPublished = 0,
  int categoriesPendingReview = 0,
}) {
  return ResearchJob(
    id: 'job1',
    tenantId: 'tenant-1',
    triggerType: ResearchTriggerType.manualRefresh,
    status: status,
    categoriesProposed: categoriesProposed,
    categoriesAutoPublished: categoriesAutoPublished,
    categoriesPendingReview: categoriesPendingReview,
  );
}

void main() {
  group('AdminResearchScreen', () {
    Future<TenantProvider> loadedTenant({FakeTenantsApi? api}) async {
      final provider = TenantProvider(tenantsApi: api ?? FakeTenantsApi());
      await provider.loadTenant();
      await provider.loadCategories();
      return provider;
    }

    Future<void> pumpScreen(
      WidgetTester tester, {
      required ResearchProvider researchProvider,
      required TenantProvider tenantProvider,
    }) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ResearchProvider>.value(
                value: researchProvider),
            ChangeNotifierProvider<TenantProvider>.value(
                value: tenantProvider),
          ],
          child: const MaterialApp(home: AdminResearchScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tapping "Lancer la recherche IA" calls runResearch with '
        'the current tenant id and shows the progressing status',
        (tester) async {
      final fake = FakeResearchApi(
        jobsQueue: [_job(status: ResearchJobStatus.processing)],
        statusSequence: [_job(status: ResearchJobStatus.processing)],
      );
      final researchProvider =
          ResearchProvider(fake, pollInterval: const Duration(seconds: 30));

      await pumpScreen(
        tester,
        researchProvider: researchProvider,
        tenantProvider: await loadedTenant(),
      );

      expect(find.byKey(const Key('run_research_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('run_research_button')));
      // Pas de pumpAndSettle : le job reste 'processing' (non terminal),
      // donc le bouton affiche un CircularProgressIndicator indéterminé
      // qui anime indéfiniment et ferait timeout pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fake.runResearchCalls.single['tenantId'], 'tenant-1');
      expect(fake.runResearchCalls.single['triggerType'], 'manual_refresh');
      expect(find.text('Traitement en cours…'), findsOneWidget);

      researchProvider.dispose();
    });

    testWidgets('shows the 429 cooldown error message on rate-limit',
        (tester) async {
      final fake = FakeResearchApi(
        runResearchError:
            ApiException(429, '{"detail":"cooldown"}'),
      );
      final researchProvider = ResearchProvider(fake);

      await pumpScreen(
        tester,
        researchProvider: researchProvider,
        tenantProvider: await loadedTenant(),
      );

      await tester.tap(find.byKey(const Key('run_research_button')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('actualisation manuelle'),
        findsOneWidget,
      );

      researchProvider.dispose();
    });

    testWidgets('once a run is done, shows category counters and the '
        'refresh button reloads TenantProvider.categories', (tester) async {
      final fake = FakeResearchApi(
        jobsQueue: [
          _job(
            status: ResearchJobStatus.done,
            categoriesProposed: 4,
            categoriesAutoPublished: 2,
            categoriesPendingReview: 2,
          ),
        ],
        statusSequence: [
          _job(
            status: ResearchJobStatus.done,
            categoriesProposed: 4,
            categoriesAutoPublished: 2,
            categoriesPendingReview: 2,
          ),
        ],
      );
      final researchProvider = ResearchProvider(fake);
      final tenantsApi = FakeTenantsApi();
      final tenantProvider = await loadedTenant(api: tenantsApi);

      await pumpScreen(
        tester,
        researchProvider: researchProvider,
        tenantProvider: tenantProvider,
      );

      await tester.tap(find.byKey(const Key('run_research_button')));
      await tester.pumpAndSettle();

      expect(find.text('Terminé'), findsOneWidget);
      expect(
        find.text('4 proposée(s) · 2 publiée(s) auto · 2 en attente de revue'),
        findsOneWidget,
      );

      expect(find.byKey(const Key('refresh_categories_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('refresh_categories_button')));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsWidgets);

      researchProvider.dispose();
    });

    testWidgets('the run button is disabled while a run is in progress',
        (tester) async {
      final fake = FakeResearchApi(
        jobsQueue: [_job(status: ResearchJobStatus.pending)],
        statusSequence: [_job(status: ResearchJobStatus.processing)],
      );
      final researchProvider =
          ResearchProvider(fake, pollInterval: const Duration(seconds: 30));

      await pumpScreen(
        tester,
        researchProvider: researchProvider,
        tenantProvider: await loadedTenant(),
      );

      await tester.tap(find.byKey(const Key('run_research_button')));
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('run_research_button')),
      );
      expect(button.onPressed, isNull,
          reason: 'disabled while ResearchProvider.isRunning is true');

      researchProvider.dispose();
    });
  });

  group('ProfileScreen navigation', () {
    testWidgets(
        'tapping the admin research entry navigates to AdminResearchScreen',
        (tester) async {
      final fake = FakeResearchApi();
      final researchProvider = ResearchProvider(fake);
      final tenantProvider = TenantProvider(tenantsApi: FakeTenantsApi());
      await tenantProvider.loadTenant();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(
              create: (_) => AuthProvider(
                api: FakeAuthApi(),
                tokenStore: InMemoryTokenStore(),
              ),
            ),
            ChangeNotifierProvider<ResearchProvider>.value(
                value: researchProvider),
            ChangeNotifierProvider<TenantProvider>.value(
                value: tenantProvider),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin_research_button')));
      await tester.pumpAndSettle();

      expect(find.byType(AdminResearchScreen), findsOneWidget);

      researchProvider.dispose();
    });
  });
}
