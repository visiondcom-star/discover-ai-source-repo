// test/helpers/fake_research_collection_api.dart

import 'dart:async';

import 'package:discover_ai/models/research_collection_job.dart';
import 'package:discover_ai/services/api_service.dart';

/// Faux d'API pour [ResearchCollectionProvider].
///
/// `jobsQueue` sert les réponses de `runCollection` (une par appel), tandis que
/// `statusSequence` est rejouée à chaque poll : une fois épuisée, la dernière
/// entrée est répétée indéfiniment, ce qui permet de tester le bornage de
/// l'attente de chaînage.
class FakeResearchCollectionApi implements ResearchCollectionApi {
  final List<ResearchCollectionJob> jobsQueue;
  final List<ResearchCollectionJob> statusSequence;
  final ApiException? runError;

  /// Si fourni, `getCollectionJobStatus` ne répond pas immédiatement : le test
  /// garde la main via [statusGate] pour invoquer `reset()`/`dispose()` au
  /// moment exact où la requête est partie mais pas encore revenue.
  final Completer<void>? statusGate;

  /// Latence injectée avant de répondre, pour simuler un serveur lent et
  /// vérifier qu'aucun sondage ne se chevauche.
  final Duration latency;

  int _runCount = 0;
  int _statusCount = 0;
  int _concurrentStatusCalls = 0;

  /// Nombre maximal de sondages simultanés observés. Doit rester à 1 : au-delà,
  /// le verrou `_pollInFlight` du provider a lâché.
  int maxConcurrentStatusCalls = 0;

  /// Monotonique : nombre d'appels partis. Ne redescend jamais, donc un test
  /// peut attendre un seuil sans rater la fenêtre pendant laquelle un poll est
  /// en vol. Un compteur « en vol » ne conviendrait pas : il retombe à 0 entre
  /// deux ticks.
  int startedStatusCalls = 0;

  /// Incrémenté dans le `finally` : compte les appels terminés, y compris ceux
  /// qui échouent (StateError par exemple). Sert à prouver qu'une réponse est
  /// bien revenue.
  int completedStatusCalls = 0;

  final List<Map<String, Object>> runCollectionCalls = [];
  final List<Map<String, String>> getStatusCalls = [];

  FakeResearchCollectionApi({
    List<ResearchCollectionJob>? jobsQueue,
    List<ResearchCollectionJob>? statusSequence,
    this.runError,
    this.statusGate,
    this.latency = const Duration(milliseconds: 0),
  })  : jobsQueue = jobsQueue ?? [],
        statusSequence = statusSequence ?? [];

  @override
  Future<Map<String, dynamic>> runCollection({
    required String tenantId,
    bool runPipeline = false,
  }) async {
    runCollectionCalls.add({'tenantId': tenantId, 'runPipeline': runPipeline});
    if (latency.inMilliseconds > 0) {
      await Future<void>.delayed(latency);
    }
    if (runError != null) throw runError!;
    if (_runCount >= jobsQueue.length) {
      throw StateError('runCollection appelé plus que jobsQueue');
    }
    return Map<String, dynamic>.from(jobsQueue[_runCount++].toJson());
  }

  @override
  Future<Map<String, dynamic>> getCollectionJobStatus({
    required String tenantId,
    required String jobId,
  }) async {
    getStatusCalls.add({'tenantId': tenantId, 'jobId': jobId});
    startedStatusCalls++;
    _concurrentStatusCalls++;
    maxConcurrentStatusCalls =
        maxConcurrentStatusCalls > _concurrentStatusCalls
            ? maxConcurrentStatusCalls
            : _concurrentStatusCalls;

    try {
      if (statusSequence.isEmpty) {
        throw StateError('statusSequence est vide');
      }

      // Le test garde la main : la réponse attend que le Completer soit ouvert.
      if (statusGate != null) {
        await statusGate!.future;
      }

      if (latency.inMilliseconds > 0) {
        await Future<void>.delayed(latency);
      }

      final index = _statusCount < statusSequence.length
          ? _statusCount
          : statusSequence.length - 1;
      _statusCount++;
      return Map<String, dynamic>.from(statusSequence[index].toJson());
    } finally {
      // En `finally` : un échec ci-dessus ne doit pas laisser le compteur en
      // vol, sinon maxConcurrentStatusCalls resterait faussement >= 2 et le
      // test d'absence de chevauchement deviendrait ininterprétable.
      _concurrentStatusCalls--;
      completedStatusCalls++;
    }
  }
}

