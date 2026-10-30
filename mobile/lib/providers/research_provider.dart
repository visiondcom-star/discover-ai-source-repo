// lib/providers/research_provider.dart
//
// Provider pour l'écran admin de recherche destination.
// Pattern aligné sur TenantProvider/PromotionProvider (ChangeNotifier + context.watch).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/research_job.dart';
import '../services/api_service.dart';
import 'safe_notifier.dart';

/// Locale-agnostic failure codes for destination research operations.
enum ResearchError {
  rateLimited,
  pollFailed,
  network,
  generic,
}

class ResearchProvider extends ChangeNotifier with SafeNotifier {
  final ResearchApi _api;
  final Duration pollInterval;

  /// Appelé une fois qu'un job atteint un statut terminal.
  ///
  /// C'est le crochet qui permet à l'application de rafraîchir le catalogue
  /// voyageur sans que l'écran admin ait à s'en charge : la publication d'une
  /// catégorie est décidée dans `AdminCategoriesProvider.onChanged`, mais un job
  /// terminé peut aussi créer de nouvelles propositions que l'admin doit voir
  /// sans represser « Actualiser ».
  final VoidCallback? onJobDone;

  ResearchProvider(
    this._api, {
    this.pollInterval = const Duration(seconds: 3),
    this.onJobDone,
  });

  ResearchJob? _currentJob;
  ResearchJob? get currentJob => _currentJob;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  ResearchError? _error;
  ResearchError? get error => _error;

  Timer? _pollTimer;

  bool get isRunning => _currentJob != null && !_currentJob!.status.isTerminal;

  Future<void> startResearch({
    required String tenantId,
    required ResearchTriggerType triggerType,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final job = ResearchJob.fromJson(await _api.runResearch(
        tenantId: tenantId,
        triggerType: triggerType.toJson(),
      ));
      _currentJob = job;
      _isLoading = false;
      notifyListeners();

      if (job.status.isTerminal) {
        // Déjà terminé au lancement : pas de polling, donc le crochet doit
        // être appelé ici aussi, sinon le catalogue ne serait jamais rafraîchi.
        onJobDone?.call();
      } else {
        _startPolling(tenantId: tenantId, jobId: job.id);
      }
    } on ApiException catch (e) {
      _isLoading = false;
      if (e.statusCode == 429) {
        _error = ResearchError.rateLimited;
      } else if (e.statusCode == null) {
        _error = ResearchError.network;
      } else {
        _error = ResearchError.generic;
      }
      notifyListeners();
    } on SocketException catch (_) {
      _isLoading = false;
      _error = ResearchError.network;
      notifyListeners();
    } on TimeoutException catch (_) {
      _isLoading = false;
      _error = ResearchError.network;
      notifyListeners();
    } on http.ClientException catch (_) {
      _isLoading = false;
      _error = ResearchError.network;
      notifyListeners();
    } catch (_) {
      _isLoading = false;
      _error = ResearchError.generic;
      notifyListeners();
    }
  }

  void _startPolling({required String tenantId, required String jobId}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) async {
      try {
        final job = ResearchJob.fromJson(
            await _api.getJobStatus(tenantId: tenantId, jobId: jobId));
        _currentJob = job;
        notifyListeners();

        if (job.status.isTerminal) {
          _pollTimer?.cancel();
          // Après le polling, pas avant : l'appelant recharge alors un
          // catalogue déjà à jour, et une seule fois par job.
          onJobDone?.call();
        }
      } on ApiException catch (e) {
        _error = e.statusCode == null
            ? ResearchError.network
            : ResearchError.pollFailed;
        _pollTimer?.cancel();
        notifyListeners();
      } on SocketException catch (_) {
        _error = ResearchError.network;
        _pollTimer?.cancel();
        notifyListeners();
      } on TimeoutException catch (_) {
        _error = ResearchError.network;
        _pollTimer?.cancel();
        notifyListeners();
      } on http.ClientException catch (_) {
        _error = ResearchError.network;
        _pollTimer?.cancel();
        notifyListeners();
      } catch (_) {
        _error = ResearchError.generic;
        _pollTimer?.cancel();
        notifyListeners();
      }
    });
  }

  /// Reprend le suivi d'un job déjà en cours (ex: retour sur l'écran admin
  /// après navigation, ou job démarré par un `tenant_created` en arrière-plan).
  void resumeTracking({required String tenantId, required String jobId}) {
    _startPolling(tenantId: tenantId, jobId: jobId);
  }

  void reset() {
    _pollTimer?.cancel();
    _currentJob = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
