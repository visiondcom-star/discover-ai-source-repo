// test/providers/research_collection_provider_test.dart

import 'dart:async';

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

    // ===== Concurrence : génération, double-tap, verrou de sondage =====

    test('double-tap : le second lancement est ignoré', () async {
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [_job(ResearchJobStatus.processing)],
        // Lente : le premier appel est encore en vol au moment du second.
        latency: const Duration(milliseconds: 60),
      );
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);

      final first = provider.startCollection(tenantId: 't1');
      final second = provider.startCollection(tenantId: 't1');
      await Future.wait([first, second]);
      await _pause();

      // Un seul POST : sinon le serveur répondrait 409 au second.
      expect(fake.runCollectionCalls.length, 1,
          reason: 'le garde anti double-tap doit bloquer le 2e lancement');
      provider.dispose();
    });

    test('reset pendant un POST en vol : la réponse tardive est ignorée',
        () async {
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [_job(ResearchJobStatus.processing)],
        latency: const Duration(milliseconds: 60),
      );
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);

      final pending = provider.startCollection(tenantId: 't1');
      provider.reset(); // generation++
      await pending;
      await _pause();

      // La réponse arrivée après reset ne doit pas ressusciter l'état.
      expect(provider.currentJob, isNull);
      expect(provider.error, isNull);
      // Et isLoading doit être false, sinon le garde anti double-tap
      // empêcherait toute relance ultérieure.
      expect(provider.isLoading, isFalse);
      provider.dispose();
    });

    test('relance après reset : le provider n\'est pas bloqué', () async {
      final fake = FakeResearchCollectionApi(
        jobsQueue: [
          _job(ResearchJobStatus.pending),
          _job(ResearchJobStatus.pending),
        ],
        statusSequence: [_job(ResearchJobStatus.processing)],
        latency: const Duration(milliseconds: 60),
      );
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);

      final first = provider.startCollection(tenantId: 't1');
      provider.reset();
      await first;
      await _pause();

      // Le garde anti double-tap ne doit pas empêcher cette relance.
      await provider.startCollection(tenantId: 't1');
      await _pause();

      expect(fake.runCollectionCalls.length, 2);
      expect(provider.currentJob, isNotNull);
      provider.dispose();
    });

    test('verrou de sondage : pas de polls chevauchants', () async {
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [_job(ResearchJobStatus.processing)],
        // Réponse plus lente que pollInterval : sans verrou, les requêtes
        // s'empileraient.
        latency: const Duration(milliseconds: 40),
      );
      final provider = ResearchCollectionProvider(
          fake, pollInterval: const Duration(milliseconds: 5));

      await provider.startCollection(tenantId: 't1');
      await _waitFor(() => fake.completedStatusCalls >= 2);
      final inFlightWhenNotified = fake.getStatusCalls.length;
      await _pause();

      // À chaque instant un seul poll est en cours : les appels démarrés ne
      // peuvent pas dépasser de plus d'1 les appels terminés.
      expect(fake.getStatusCalls.length - inFlightWhenNotified,
          lessThanOrEqualTo(2),
          reason: 'les polls ne doivent pas se chevaucher');
      provider.dispose();
    });

    test('reset pendant un poll en vol : la réponse tardive est ignorée',
        () async {
      // Un poll parti AVANT le reset qui reviendrait après ne doit ni écraser
      // l'état effacé, ni faire repartir le timer.
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [_job(ResearchJobStatus.done, documentsNew: 1)],
        latency: const Duration(milliseconds: 50),
      );
      final provider = ResearchCollectionProvider(
          fake, pollInterval: const Duration(milliseconds: 10));

      await provider.startCollection(tenantId: 't1');
      await _waitFor(() => fake.getStatusCalls.isNotEmpty);
      provider.reset(); // generation++ pendant que le poll est en vol
      await _pause();

      expect(provider.currentJob, isNull,
          reason: 'la réponse en vol ne doit pas ressusciter le job');
      expect(provider.error, isNull);
      final calls = fake.getStatusCalls.length;
      await _pause();
      expect(fake.getStatusCalls.length, calls,
          reason: 'le timer ne doit pas repartir après le reset');
      provider.dispose();
    });

    test('reset() pendant un sondage en vol : la réponse est ignorée',
        () async {
      // Le Completer garantit le moment exact : le poll est parti (compteur
      // incrémenté) mais n'a pas encore répondu quand reset() est appelé.
      final gate = Completer<void>();
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [_job(ResearchJobStatus.done, documentsNew: 7)],
        statusGate: gate,
      );
      final provider =
          ResearchCollectionProvider(fake, pollInterval: const Duration(milliseconds: 5));

      await provider.startCollection(tenantId: 't1');
      await _waitFor(() => fake.startedStatusCalls == 1);

      provider.reset();
      gate.complete();
      await _pause();

      expect(provider.currentJob, isNull,
          reason: 'currentJob doit rester null après un reset');
      expect(provider.error, isNull);
      provider.dispose();
    });

    test('dispose() pendant un sondage en vol : aucune exception', () async {
      // notifyListeners() après dispose() lève : le compteur de génération
      // doit empêcher la réponse tardive d'atteindre le ChangeNotifier mort.
      final gate = Completer<void>();
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [_job(ResearchJobStatus.done, documentsNew: 1)],
        statusGate: gate,
      );
      final provider =
          ResearchCollectionProvider(fake, pollInterval: const Duration(milliseconds: 5));

      await provider.startCollection(tenantId: 't1');
      await _waitFor(() => fake.startedStatusCalls == 1);

      provider.dispose();
      gate.complete();

      // Une exception ici remonterait dans la zone de test.
      await _pause();
      expect(fake.getStatusCalls.length, 1);
    });

    test('réponse plus lente que pollInterval : un seul appel à la fois',
        () async {
      // pollInterval (5ms) < latence (60ms) : sans _pollInFlight, chaque tick
      // repartirait et les requêtes s'empileraient.
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.pending)],
        statusSequence: [_job(ResearchJobStatus.processing)],
        latency: const Duration(milliseconds: 60),
      );
      final provider = ResearchCollectionProvider(
          fake, pollInterval: const Duration(milliseconds: 5));

      await provider.startCollection(tenantId: 't1');
      await _waitFor(() => fake.completedStatusCalls >= 3);
      await _pause();

      expect(fake.maxConcurrentStatusCalls, 1,
          reason: 'jamais plus d\'un getCollectionJobStatus en vol');
      provider.dispose();
    });

    test('le chaînage n\'est pas notifié deux fois', () async {
      // _chainNotified n'est atteignable que si _afterUpdate voit un
      // research_job_id alors que le job n'est PAS terminal (donc le polling
      // continue) : c'est le seul scénario où deux appels successifs
      // pourraient notifier. Sans le drapeau, le callback partirait 2 fois.
      final chained = <String>[];
      // processing + research_job_id : non terminal => polling maintenu.
      final processingWithId = _job(ResearchJobStatus.processing,
          documentsNew: 2, runPipeline: true, researchJobId: 'r1');
      final fake = FakeResearchCollectionApi(
        jobsQueue: [_job(ResearchJobStatus.processing, runPipeline: true)],
        statusSequence: [processingWithId, processingWithId],
      );
      final provider = ResearchCollectionProvider(
        fake,
        pollInterval: _fast,
        onPipelineChained: (tenantId, id) => chained.add(id),
      );

      await provider.startCollection(tenantId: 't1', runPipeline: true);
      await _waitFor(() => fake.completedStatusCalls >= 2);
      await _pause();

      expect(chained, ['r1'],
          reason: 'le callback ne doit être appelé qu\'une fois');
      provider.dispose();
    });

    test('FormatException au lancement : isLoading false et erreur renseignée',
        () async {
      // Une réponse mal formée (created_at illisible) lève une
      // FormatException : le catch de repli doit libérer isLoading, sinon le
      // garde anti double-tap bloque toute relance.
      final provider = ResearchCollectionProvider(
        _MalformedRunApi(),
        pollInterval: _fast,
      );

      await provider.startCollection(tenantId: 't1');

      expect(provider.isLoading, isFalse,
          reason: 'isLoading doit être libéré même sur erreur inattendue');
      expect(provider.error, 'Échec du lancement de la collecte.');
      provider.dispose();
    });

    test('statut illisible : le polling s\'arrête avec une erreur', () async {
      // fromJson lève ArgumentError sur un statut inconnu : le catch de repli
      // doit arrêter le timer au lieu de le laisser tourner.
      final fake = _BadStatusApi();
      final provider = ResearchCollectionProvider(fake, pollInterval: _fast);

      await provider.startCollection(tenantId: 't1');
      await _waitFor(() => provider.error != null);
      await _pause();

      expect(provider.error, 'Impossible de récupérer le statut de la collecte.');
      final calls = fake.calls;
      await _pause();
      expect(fake.calls, calls, reason: 'polling arrêté après erreur');
      provider.dispose();
    });
  });
}

/// Répond un `created_at` illisible : `DateTime.parse` lève une
/// FormatException, que le catch de repli doit absorber.
class _MalformedRunApi implements ResearchCollectionApi {
  @override
  Future<Map<String, dynamic>> runCollection({
    required String tenantId,
    bool runPipeline = false,
  }) async =>
      <String, dynamic>{
        'id': 'c1',
        'tenant_id': 't1',
        'status': 'pending',
        'documents_fetched': 0,
        'documents_new': 0,
        'documents_duplicate': 0,
        'documents_failed': 0,
        'created_at': 'pas-une-date',
      };

  @override
  Future<Map<String, dynamic>> getCollectionJobStatus({
    required String tenantId,
    required String jobId,
  }) async =>
      throw StateError('getCollectionJobStatus ne doit pas être appelé');
}

/// Répond `status: 'bizarre'`, que `ResearchCollectionJob.fromJson` refuse.
class _BadStatusApi implements ResearchCollectionApi {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> runCollection({
    required String tenantId,
    bool runPipeline = false,
  }) async =>
      _job(ResearchJobStatus.pending).toJson();

  @override
  Future<Map<String, dynamic>> getCollectionJobStatus({
    required String tenantId,
    required String jobId,
  }) async {
    calls++;
    return <String, dynamic>{
      'id': 'c1',
      'tenant_id': 't1',
      'status': 'bizarre',
      'documents_fetched': 0,
      'documents_new': 0,
      'documents_duplicate': 0,
      'documents_failed': 0,
      'created_at': '2026-10-02T10:00:00',
    };
  }
}