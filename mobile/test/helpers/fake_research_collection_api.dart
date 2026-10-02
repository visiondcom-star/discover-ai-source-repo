// test/helpers/fake_research_collection_api.dart

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

  int _runCount = 0;
  int _statusCount = 0;

  final List<Map<String, Object>> runCollectionCalls = [];
  final List<Map<String, String>> getStatusCalls = [];

  FakeResearchCollectionApi({
    List<ResearchCollectionJob>? jobsQueue,
    List<ResearchCollectionJob>? statusSequence,
    this.runError,
  })  : jobsQueue = jobsQueue ?? [],
        statusSequence = statusSequence ?? [];

  @override
  Future<Map<String, dynamic>> runCollection({
    required String tenantId,
    bool runPipeline = false,
  }) async {
    runCollectionCalls.add({'tenantId': tenantId, 'runPipeline': runPipeline});
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