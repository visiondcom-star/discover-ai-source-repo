// test/helpers/fake_research_collection_api.dart

import 'dart:async';

import 'package:discover_ai/models/research_collection_job.dart';
import 'package:discover_ai/services/api_service.dart';

/// Faux d'API pour [ResearchCollectionProvider].
///
/// `jobsQueue` sert les réponses de `runCollection` (une par appel), tandis que
/// `statusSequence` est rejouée à chaque poll : une fois épuisée, la dernière
/// entrée est répétée indefinitely, ce qui permet de tester le bornage de
/// l'attente de chaînage.
class FakeResearchCollectionApi implements ResearchCollectionApi {
  final List<ResearchCollectionJob> jobsQueue;
  final List<ResearchCollectionJob> statusSequence;
  final ApiException? runError;

  /// Latence injectée avant de répondre, pour tester les réponses en vol :
  ///generation, double-tap, verrou de sondage.
  final Duration latency;

  /// Si fourni, `getCollectionJobStatus` n répond pas immédiatement : le test
  /// garde la main via [statusGate] pour invoquer `reset()`/`dispose()` au
  /// moment exact où la requête est partie mais pas encore revenue.
  final Completer<void>? statusGate;

  /// Nombre d'appels polls effectivement menés à leur terme. Permet de vérifier
  /// qu'un [ResearchCollectionProvider] n'a pas empilé des requêtes.
  int completedStatusCalls = 0;

  /// true tant qu'un poll est parti et n'a pas encore rendu la main.
  int inFlightStatusCalls = 0;
  int maxConcurrentStatusCalls = 0;

  /// Monotonique : nombre d'appels partis. Contrairement à inFlightStatusCalls,
  /// il ne redescend jamais, donc un test peut attendre un seuil sans rater
  /// la fenêtre pendant laquelle un poll est en vol.
  int startedStatusCalls = 0;

  int _runCount = 0;
  int _statusCount = 0;

  final List<Map<String, Object>> runCollectionCalls = [];
  final List<Map<String, String>> getStatusCalls = [];

  FakeResearchCollectionApi({
    List<ResearchCollectionJob>? jobsQueue,
    List<ResearchCollectionJob>? statusSequence,
    this.runError,
    this.latency = Duration.zero,
    this.statusGate,
  })  : jobsQueue = jobsQueue ?? [],
        statusSequence = statusSequence ?? [];

  @override
  Future<Map<String, dynamic>> runCollection({
    required String tenantId,
    bool runPipeline = false,
  }) async {
    runCollectionCalls.add({'tenantId': tenantId, 'runPipeline': runPipeline});
    if (latency > Duration.zero) await Future<void>.delayed(latency);
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
    inFlightStatusCalls++;
    if (inFlightStatusCalls > maxConcurrentStatusCalls) {
      maxConcurrentStatusCalls = inFlightStatusCalls;
    }
    // Le test garde la main : la réponse attend que le Completer soit ouvert.
    await statusGate?.future;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    inFlightStatusCalls--;
    completedStatusCalls++;
    if (statusSequence.isEmpty) {
      throw StateError('statusSequence est vide');
    }
    // Reste sur la dernière valeur une fois la séquence épuisée.
    final index = _statusCount < statusSequence.length
        ? _statusCount
        : statusSequence.length - 1;
    _statusCount++;
    return Map<String, dynamic>.from(statusSequence[index].toJson());
  }
}