// test/providers/research_collection_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:discover_ai/models/research_collection_job.dart';
import 'package:discover_ai/models/research_job.dart';
import 'package:discover_ai/providers/research_collection_provider.dart';
import 'package:discover_ai/services/api_service.dart';

import '../helpers/fake_research_collection_api.dart';

const _fast = Duration(milliseconds: 10);

ResearchCollectionJob _job(
  ResearchJobStatus status, {
  int documentsNew = 0,
  bool runPipeline = false,
  String? researchJobId,
}) =>
    ResearchCollectionJob(
      id: 'c1',
      tenantId: 't1',
      status: status,
      documentsNew: documentsNew,
      runPipeline: runPipeline,
      researchJobId: researchJobId,
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

Future<void> _pause() =>
    Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  group('ResearchCollectionProvider', () {
    test('lance la collecte puis suit le job jusqu\'à son terme', () async {
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [
          _job(ResearchJobStatus.processing),
          _job(ResearchJobStatus.done, documentsNew: 3),
        ],
      );
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);

      await provider.startCollection(tenantId: 't1');
      expect(provider.currentJob!.status, ResearchJobStatus.pending);
      expect(provider.isRunning, isTrue);

      await _waitFor(
          () => provider.currentJob!.status == ResearchJobStatus.done);
      expect(provider.currentJob!.documentsNew, 3);
      expect(provider.isRunning, isFalse);
      expect(fake.runCollectionCalls.single,
          {'tenantId': 't1', 'runPipeline': false});

      final calls = fake.getStatusCalls.length;
      await _pause();
      expect(fake.getStatusCalls.length, calls, reason: 'polling arrêté');
      provider.dispose();
    });

    test('409 : message « déjà en cours »', () async {
      final fake = FakeResearchCollectionApi(runError: ApiException(409, 'x'));
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);

      await provider.startCollection(tenantId: 't1');

      expect(provider.error, contains('déjà en cours'));
      expect(provider.currentJob, isNull);
      expect(provider.isLoading, isFalse);
      provider.dispose();
    });

    test('429 : message « patienter »', () async {
      final fake = FakeResearchCollectionApi(runError: ApiException(429, 'x'));
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);

      await provider.startCollection(tenantId: 't1');

      expect(provider.error, contains('patienter'));
      provider.dispose();
    });

    test('chaînage : continue de sonder après done et notifie une seule fois',
        () async {
      final chained = <String>[];
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending, runPipeline: true)],
        statusSequence: [
          // done mais research_job_id pas encore écrit par le serveur
          _job(ResearchJobStatus.done, documentsNew: 2, runPipeline: true),
          _job(ResearchJobStatus.done,
              documentsNew: 2, runPipeline: true, researchJobId: 'r1'),
        ],
      );
      final provider = ResearchCollectionProvider(
        fake,
        pollInterval: _fast,
        onPipelineChained: (tenantId, id) => chained.add('$tenantId:$id'),
      );

      await provider.startCollection(tenantId: 't1', runPipeline: true);
      await _waitFor(() => chained.isNotEmpty);
      expect(chained, ['t1:r1']);
      expect(provider.currentJob!.researchJobId, 'r1');

      final calls = fake.getStatusCalls.length;
      await _pause();
      expect(chained.length, 1);
      expect(fake.getStatusCalls.length, calls, reason: 'polling arrêté');
      provider.dispose();
    });

    test('rien de nouveau : pas d\'attente de chaînage', () async {
      final chained = <String>[];
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending, runPipeline: true)],
        statusSequence: [
          _job(ResearchJobStatus.done, documentsNew: 0, runPipeline: true),
        ],
      );
      final provider = ResearchCollectionProvider(
        fake,
        pollInterval: _fast,
        onPipelineChained: (tenantId, id) => chained.add(id),
      );

      await provider.startCollection(tenantId: 't1', runPipeline: true);
      await _waitFor(
          () => provider.currentJob!.status == ResearchJobStatus.done);
      await _pause();

      expect(fake.getStatusCalls.length, 1);
      expect(chained, isEmpty);
      provider.dispose();
    });

    test('chaînage jamais confirmé : le polling finit par s\'arrêter',
        () async {
      final chained = <String>[];
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending, runPipeline: true)],
        statusSequence: [
          _job(ResearchJobStatus.done, documentsNew: 2, runPipeline: true),
        ],
      );
      final provider = ResearchCollectionProvider(
        fake,
        pollInterval: _fast,
        maxChainWaitPolls: 2,
        onPipelineChained: (tenantId, id) => chained.add(id),
      );

      await provider.startCollection(tenantId: 't1', runPipeline: true);
      await _waitFor(() => fake.getStatusCalls.length >= 3);
      await _pause();

      expect(fake.getStatusCalls.length, 3);
      expect(chained, isEmpty);
      provider.dispose();
    });

    test('reset annule le suivi et efface l\'état', () async {
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [_job(ResearchJobStatus.processing)],
      );
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);

      await provider.startCollection(tenantId: 't1');
      provider.reset();
      await _pause();

      expect(provider.currentJob, isNull);
      expect(provider.error, isNull);
      expect(fake.getStatusCalls, isEmpty);
      provider.dispose();
    });

    test('autre erreur : message générique', () async {
      final fake = FakeResearchCollectionApi(runError: ApiException(500, 'x'));
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);

      await provider.startCollection(tenantId: 't1');

      expect(provider.error, 'Échec du lancement de la collecte.');
      provider.dispose();
    });
  });
}