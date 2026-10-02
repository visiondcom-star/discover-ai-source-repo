// test/providers/research_collection_provider_concurrency_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:discover_ai/models/research_collection_job.dart';
import 'package:discover_ai/models/research_job.dart';
import 'package:discover_ai/providers/research_collection_provider.dart';
import 'package:discover_ai/services/api_service.dart';

import '../helpers/fake_research_collection_api.dart';

const _fast = Duration(milliseconds: 10);

ResearchCollectionJob _job(ResearchJobStatus status) => ResearchCollectionJob(
      id: 'c1',
      tenantId: 't1',
      status: status,
      documentsNew: 0,
      runPipeline: false,
      researchJobId: null,
    );

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition non atteinte dans le délai');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _pause() => Future<void>.delayed(const Duration(milliseconds: 80));

/// API dont le lancement échoue avec une erreur autre qu'ApiException.
class _BrokenApi implements ResearchCollectionApi {
  @override
  Future<Map<String, dynamic>> runCollection({
    required String tenantId,
    bool runPipeline = false,
  }) async =>
      throw const FormatException('réponse illisible');

  @override
  Future<Map<String, dynamic>> getCollectionJobStatus({
    required String tenantId,
    required String jobId,
  }) async =>
      throw UnimplementedError();
}

void main() {
  group('ResearchCollectionProvider - concurrence', () {
    test('reset() pendant un sondage en vol : la réponse tardive est ignorée',
        () async {
      final gate = Completer<void>();
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [_job(ResearchJobStatus.done)],
        statusGate: gate,
      );
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);
      addTearDown(provider.dispose);

      await provider.startCollection(tenantId: 't1');
      await _waitFor(() => fake.startedStatusCalls >= 1);

      provider.reset();
      gate.complete();
      await _pause();

      expect(fake.completedStatusCalls, greaterThanOrEqualTo(1),
          reason: 'la réponse doit bien être arrivée');
      expect(provider.currentJob, isNull);
      expect(provider.error, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('dispose() pendant un sondage en vol : aucune exception', () async {
      final gate = Completer<void>();
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [_job(ResearchJobStatus.done)],
        statusGate: gate,
      );
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);

      await provider.startCollection(tenantId: 't1');
      await _waitFor(() => fake.startedStatusCalls >= 1);

      provider.dispose();
      gate.complete();
      await _pause();

      // Sans garde de génération, notifyListeners() après dispose() lève une
      // erreur dans le Timer, que flutter_test fait échouer.
      expect(fake.completedStatusCalls, greaterThanOrEqualTo(1));
    });

    test('un serveur lent ne provoque jamais deux sondages simultanés',
        () async {
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [_job(ResearchJobStatus.processing)],
        latency: const Duration(milliseconds: 50),
      );
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);
      addTearDown(provider.dispose);

      await provider.startCollection(tenantId: 't1');
      await _waitFor(() => fake.completedStatusCalls >= 2);
      provider.reset();

      expect(fake.maxConcurrentStatusCalls, 1);
    });

    test('erreur inattendue au lancement : isLoading retombe et un message '
        'est affiché', () async {
      final provider =
          ResearchCollectionProvider(_BrokenApi(), pollInterval: _fast);
      addTearDown(provider.dispose);

      await provider.startCollection(tenantId: 't1');

      expect(provider.isLoading, isFalse);
      expect(provider.error, 'Échec du lancement de la collecte.');
      expect(provider.currentJob, isNull);
    });

    test('double-tap : un seul appel de lancement', () async {
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.done)],
        statusSequence: [_job(ResearchJobStatus.done)],
        latency: const Duration(milliseconds: 40),
      );
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);
      addTearDown(provider.dispose);

      final first = provider.startCollection(tenantId: 't1');
      final second = provider.startCollection(tenantId: 't1');
      await Future.wait([first, second]);

      expect(fake.runCollectionCalls.length, 1);
    });

    test('reset() pendant le lancement : la réponse tardive est ignorée',
        () async {
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [_job(ResearchJobStatus.done)],
        latency: const Duration(milliseconds: 40),
      );
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);
      addTearDown(provider.dispose);

      final launching = provider.startCollection(tenantId: 't1');
      provider.reset();
      await launching;
      await _pause();

      expect(provider.currentJob, isNull);
      expect(provider.isLoading, isFalse);
      expect(fake.startedStatusCalls, 0,
          reason: 'aucun polling ne doit démarrer après reset()');
    });
  });
}