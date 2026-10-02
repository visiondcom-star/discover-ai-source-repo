// lib/providers/research_collection_provider.dart
//
// Provider de la collecte automatique de documents (Wikivoyage/Wikipedia).
// Même pattern que ResearchProvider (ChangeNotifier + polling).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/research_collection_job.dart';
import '../models/research_job.dart';
import '../services/api_service.dart';

/// Appelé une seule fois quand le serveur a enchaîné un job de recherche IA
/// sur la collecte : l'appelant confie alors son suivi à ResearchProvider.
typedef PipelineChainedCallback = void Function(
    String tenantId, String researchJobId);

class ResearchCollectionProvider extends ChangeNotifier {
  final ResearchCollectionApi _api;
  final Duration pollInterval;

  /// Nombre de sondages supplémentaires une fois la collecte terminée, le
  /// temps que le serveur écrive research_job_id (ou y renonce).
  final int maxChainWaitPolls;
  final PipelineChainedCallback? onPipelineChained;

  ResearchCollectionProvider(
    this._api, {
    this.pollInterval = const Duration(seconds: 3),
    this.maxChainWaitPolls = 5,
    this.onPipelineChained,
  });

  ResearchCollectionJob? _currentJob;
  ResearchCollectionJob? get currentJob => _currentJob;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Timer? _pollTimer;
  int _chainWaitPolls = 0;
  bool _chainNotified = false;

  bool get isRunning =>
      _currentJob != null && !_currentJob!.status.isTerminal;

  Future<void> startCollection({
    required String tenantId,
    bool runPipeline = false,
  }) async {
    _pollTimer?.cancel();
    _isLoading = true;
    _error = null;
    _chainWaitPolls = 0;
    _chainNotified = false;
    notifyListeners();

    try {
      final job = ResearchCollectionJob.fromJson(await _api.runCollection(
        tenantId: tenantId,
        runPipeline: runPipeline,
      ));
      _currentJob = job;
      _isLoading = false;
      final keepPolling = _afterUpdate(tenantId, job);
      notifyListeners();

      if (keepPolling) {
        _startPolling(tenantId: tenantId, jobId: job.id);
      }
    } on ApiException catch (e) {
      _isLoading = false;
      if (e.statusCode == 409) {
        _error = 'Une collecte est déjà en cours pour ce tenant.';
      } else if (e.statusCode == 429) {
        _error =
            'Merci de patienter quelques minutes avant de relancer une collecte.';
      } else {
        _error = 'Échec du lancement de la collecte.';
      }
      notifyListeners();
    }
  }

  /// Notifie le chaînage s'il vient d'apparaître et dit s'il faut continuer
  /// à sonder le serveur.
  ///
  /// Le garde-fou `maxChainWaitPolls` est indispensable : côté serveur,
  /// `_run_collection_then_pipeline` marque la collecte `done` AVANT de créer
  /// le ResearchJob enchaîné, donc un poll peut lire `done` avec
  /// `research_job_id` encore null. Continuer à sonder évite de rater le
  /// chaînage. Mais le serveur saute parfois le chaînage (un autre ResearchJob
  /// actif), auquel cas l'identifiant n'arrivera jamais : on borne l'attente.
  bool _afterUpdate(String tenantId, ResearchCollectionJob job) {
    final researchJobId = job.researchJobId;
    if (researchJobId != null && !_chainNotified) {
      _chainNotified = true;
      onPipelineChained?.call(tenantId, researchJobId);
    }

    if (!job.status.isTerminal) return true;

    final chainExpected = job.runPipeline &&
        job.status == ResearchJobStatus.done &&
        job.documentsNew > 0 &&
        job.researchJobId == null;
    if (!chainExpected) return false;

    _chainWaitPolls++;
    return _chainWaitPolls <= maxChainWaitPolls;
  }

  void _startPolling({required String tenantId, required String jobId}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) async {
      try {
        final job = ResearchCollectionJob.fromJson(await _api
            .getCollectionJobStatus(tenantId: tenantId, jobId: jobId));
        _currentJob = job;
        final keepPolling = _afterUpdate(tenantId, job);
        if (!keepPolling) _pollTimer?.cancel();
        notifyListeners();
      } on ApiException {
        _error = 'Impossible de récupérer le statut de la collecte.';
        _pollTimer?.cancel();
        notifyListeners();
      }
    });
  }

  void reset() {
    _pollTimer?.cancel();
    _currentJob = null;
    _error = null;
    _chainWaitPolls = 0;
    _chainNotified = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}