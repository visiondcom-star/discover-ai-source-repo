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

  /// Incrémenté à chaque relance/reset/dispose : toute réponse HTTP en vol
  /// portant une génération antérieure est ignorée. Sans cela, un `dispose()`
  /// suivi d'une réponse tardive écrirait dans un provider détruit, et deux
  /// lancements concurrents se marcheraient dessus.
  int _generation = 0;

  /// Empêche deux polls de se chevaucher quand la réponse HTTP est plus lente
  /// que [pollInterval] (réseau lent) : sans ce verrou, les requêtes s'empilent
  /// et une réponse ancienne peut écraser une plus récente.
  bool _pollInFlight = false;

  Timer? _pollTimer;
  int _chainWaitPolls = 0;
  bool _chainNotified = false;

  bool get isRunning =>
      _currentJob != null && !_currentJob!.status.isTerminal;

  Future<void> startCollection({
    required String tenantId,
    bool runPipeline = false,
  }) async {
    // Anti double-tap : deux taps rapides ne doivent pas lancer deux collectes
    // concurrentes (le serveur répondrait 409 à la seconde de toute façon).
    if (_isLoading) return;
    _pollTimer?.cancel();
    final gen = ++_generation;
    _pollInFlight = false;
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
      if (gen != _generation) return;
      _currentJob = job;
      _isLoading = false;
      final keepPolling = _afterUpdate(tenantId, job);
      notifyListeners();

      if (keepPolling) {
        _startPolling(tenantId: tenantId, jobId: job.id);
      }
    } on ApiException catch (e) {
      if (gen != _generation) return;
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
    } catch (_) {
      // Repli : un StateError du faux d'API ou un FormatException de
      // fromJson ne doivent pas laisser le provider bloqué sur isLoading.
      if (gen != _generation) return;
      _isLoading = false;
      _error = 'Échec du lancement de la collecte.';
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
    final gen = _generation;
    _pollTimer = Timer.periodic(pollInterval, (_) async {
      if (_pollInFlight) return;
      _pollInFlight = true;
      try {
        final job = ResearchCollectionJob.fromJson(await _api
            .getCollectionJobStatus(tenantId: tenantId, jobId: jobId));
        if (gen != _generation) return;
        _currentJob = job;
        final keepPolling = _afterUpdate(tenantId, job);
        if (!keepPolling) _pollTimer?.cancel();
        notifyListeners();
      } catch (_) {
        // Couvre ApiException mais aussi un FormatException de fromJson : un
        // statut inconnu ne doit pas laisser le timer tourner indéfiniment.
        if (gen != _generation) return;
        _error = 'Impossible de récupérer le statut de la collecte.';
        _pollTimer?.cancel();
        notifyListeners();
      } finally {
        if (gen == _generation) _pollInFlight = false;
      }
    });
  }

  void reset() {
    // Invalide toute réponse en vol ET remet isLoading à false : sans ce
    // second point, le garde anti double-tap de startCollection bloquerait
    // toute relance future (isLoading resterait true pour toujours).
    _generation++;
    _pollInFlight = false;
    _pollTimer?.cancel();
    _currentJob = null;
    _error = null;
    _isLoading = false;
    _chainWaitPolls = 0;
    _chainNotified = false;
    notifyListeners();
  }

  @override
  void dispose() {
    // Invalide les réponses en vol : une réponse tardive après dispose()
    // appelerait notifyListeners() sur un ChangeNotifier détruit.
    _generation++;
    _pollTimer?.cancel();
    super.dispose();
  }
}