// test/providers/research_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:discover_ai/models/research_job.dart';
import 'package:discover_ai/providers/research_provider.dart';
import 'package:discover_ai/services/api_service.dart';
import '../helpers/fakes.dart';

ResearchJob _job({
  required ResearchJobStatus status,
  int categoriesProposed = 0,
  int categoriesAutoPublished = 0,
  int categoriesPendingReview = 0,
  String? errorMessage,
}) {
  return ResearchJob(
    id: 'job1',
    tenantId: 'tenant1',
    triggerType: ResearchTriggerType.manualRefresh,
    status: status,
    categoriesProposed: categoriesProposed,
    categoriesAutoPublished: categoriesAutoPublished,
    categoriesPendingReview: categoriesPendingReview,
    errorMessage: errorMessage,
  );
}

void main() {
  group('ResearchProvider', () {
    test('startResearch lance le job puis poll jusqu\'à done', () async {
      final fake = FakeResearchApi(
        jobsQueue: [_job(status: ResearchJobStatus.pending)],
        statusSequence: [
          _job(status: ResearchJobStatus.processing),
          _job(
            status: ResearchJobStatus.done,
            categoriesProposed: 5,
            categoriesAutoPublished: 3,
            categoriesPendingReview: 2,
          ),
        ],
      );

      final provider = ResearchProvider(
        fake,
        pollInterval: const Duration(milliseconds: 10),
      );

      await provider.startResearch(
        tenantId: 'tenant1',
        triggerType: ResearchTriggerType.manualRefresh,
      );

      expect(provider.currentJob?.status, ResearchJobStatus.pending);
      expect(provider.isRunning, isTrue);
      expect(provider.error, isNull);

      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 15));
        return !provider.currentJob!.status.isTerminal;
      }).timeout(const Duration(seconds: 2));

      expect(provider.currentJob?.status, ResearchJobStatus.done);
      expect(provider.currentJob?.categoriesProposed, 5);
      expect(provider.currentJob?.categoriesAutoPublished, 3);
      expect(provider.currentJob?.categoriesPendingReview, 2);
      expect(provider.isRunning, isFalse);

      provider.dispose();
    });

    test('propage l\'erreur si runResearch échoue (ex: rate-limit 429)',
        () async {
      final fake = FakeResearchApi(
        runResearchError:
            ApiException(429, 'Déjà actualisé ce mois-ci'),
      );

      final provider = ResearchProvider(fake);

      await provider.startResearch(
        tenantId: 'tenant1',
        triggerType: ResearchTriggerType.manualRefresh,
      );

      expect(provider.error, 'Une actualisation manuelle a déjà été effectuée ce mois-ci.');
      expect(provider.currentJob, isNull);
      expect(provider.isLoading, isFalse);

      provider.dispose();
    });

    test('resumeTracking reprend le polling d\'un job déjà en cours',
        () async {
      final fake = FakeResearchApi(
        statusSequence: [
          _job(status: ResearchJobStatus.processing),
          _job(status: ResearchJobStatus.done, categoriesProposed: 1),
        ],
      );

      final provider = ResearchProvider(
        fake,
        pollInterval: const Duration(milliseconds: 10),
      );

      provider.resumeTracking(tenantId: 'tenant1', jobId: 'job1');

      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 15));
        return provider.currentJob == null ||
            !provider.currentJob!.status.isTerminal;
      }).timeout(const Duration(seconds: 2));

      expect(provider.currentJob?.status, ResearchJobStatus.done);
      expect(fake.getJobStatusCalls.first, {
        'tenantId': 'tenant1',
        'jobId': 'job1',
      });

      provider.dispose();
    });

    test('reset() efface le job courant et annule le polling', () async {
      final fake = FakeResearchApi(
        jobsQueue: [_job(status: ResearchJobStatus.done)],
        statusSequence: [_job(status: ResearchJobStatus.done)],
      );

      final provider = ResearchProvider(fake);
      await provider.startResearch(
        tenantId: 'tenant1',
        triggerType: ResearchTriggerType.manualRefresh,
      );

      provider.reset();

      expect(provider.currentJob, isNull);
      expect(provider.error, isNull);
      expect(provider.isRunning, isFalse);

      provider.dispose();
    });

    test('onJobDone est appelé une fois le job terminé par le polling',
        () async {
      final fake = FakeResearchApi(
        jobsQueue: [_job(status: ResearchJobStatus.pending)],
        statusSequence: [
          _job(status: ResearchJobStatus.processing),
          _job(status: ResearchJobStatus.done, categoriesProposed: 2),
        ],
      );

      var calls = 0;
      final provider = ResearchProvider(
        fake,
        pollInterval: const Duration(milliseconds: 10),
        onJobDone: () => calls++,
      );

      await provider.startResearch(
        tenantId: 'tenant1',
        triggerType: ResearchTriggerType.manualRefresh,
      );
      expect(calls, 0, reason: 'rien avant la fin du job');

      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 15));
        return !provider.currentJob!.status.isTerminal;
      }).timeout(const Duration(seconds: 2));

      expect(calls, 1);

      provider.dispose();
    });

    test('onJobDone est appelé aussi quand le job est déjà terminé au lancement',
        () async {
      // Pas de polling dans ce cas : sans appel ici, le catalogue voyageur ne
      // serait jamais rechargé et l'app resterait sur des données périmées.
      final fake = FakeResearchApi(
        jobsQueue: [_job(status: ResearchJobStatus.done, categoriesProposed: 1)],
        statusSequence: [_job(status: ResearchJobStatus.done)],
      );

      var calls = 0;
      final provider = ResearchProvider(fake, onJobDone: () => calls++);

      await provider.startResearch(
        tenantId: 'tenant1',
        triggerType: ResearchTriggerType.manualRefresh,
      );

      expect(calls, 1);
      expect(provider.isRunning, isFalse);

      provider.dispose();
    });

    test('onJobDone est appelé aussi sur un job en échec', () async {
      // `failed` est terminal au même titre que `done`, et un run interrompu
      // peut avoir écrit des propositions avant de planter : le catalogue doit
      // donc être rechargé aussi dans ce cas, sinon l'admin ne voit jamais ce
      // qui a été proposé.
      final fake = FakeResearchApi(
        jobsQueue: [_job(status: ResearchJobStatus.pending)],
        statusSequence: [
          _job(status: ResearchJobStatus.failed, errorMessage: 'boom'),
        ],
      );

      var calls = 0;
      final provider = ResearchProvider(
        fake,
        pollInterval: const Duration(milliseconds: 10),
        onJobDone: () => calls++,
      );

      await provider.startResearch(
        tenantId: 'tenant1',
        triggerType: ResearchTriggerType.manualRefresh,
      );
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 15));
        return !provider.currentJob!.status.isTerminal;
      }).timeout(const Duration(seconds: 2));

      expect(provider.currentJob?.status, ResearchJobStatus.failed);
      expect(calls, 1);

      provider.dispose();
    });

    test("onJobDone n'est pas appelé quand une erreur de polling interrompt",
        () async {
      // Ici le job n'a pas de statut final connu : on ne peut pas affirmer
      // qu'il a produit des catégories, donc pas de rechargement.
      final fake = FakeResearchApi(
        jobsQueue: [_job(status: ResearchJobStatus.pending)],
        statusSequence: [_job(status: ResearchJobStatus.pending)],
      );
      fake.getStatusError = ApiException(500, '{"detail":"boom"}');

      var calls = 0;
      final provider = ResearchProvider(
        fake,
        pollInterval: const Duration(milliseconds: 10),
        onJobDone: () => calls++,
      );

      await provider.startResearch(
        tenantId: 'tenant1',
        triggerType: ResearchTriggerType.manualRefresh,
      );
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 15));
        return provider.error == null;
      }).timeout(const Duration(seconds: 2));

      expect(provider.error, isNotNull);
      expect(calls, 0);

      provider.dispose();
    });

    test('onJobDone est optionnel : le provider fonctionne sans callback',
        () async {
      final fake = FakeResearchApi(
        jobsQueue: [_job(status: ResearchJobStatus.pending)],
        statusSequence: [_job(status: ResearchJobStatus.done)],
      );

      final provider = ResearchProvider(
        fake,
        pollInterval: const Duration(milliseconds: 10),
      );

      await provider.startResearch(
        tenantId: 'tenant1',
        triggerType: ResearchTriggerType.manualRefresh,
      );
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 15));
        return !provider.currentJob!.status.isTerminal;
      }).timeout(const Duration(seconds: 2));

      expect(provider.currentJob?.status, ResearchJobStatus.done);

      provider.dispose();
    });
  });
}
