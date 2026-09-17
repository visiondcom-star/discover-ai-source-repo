// lib/providers/research_provider.dart
//
// Provider pour l'écran admin de recherche destination.
// Pattern aligné sur TenantProvider/PromotionProvider (ChangeNotifier + context.watch).

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../models/research_job.dart';

class ResearchProvider extends ChangeNotifier {
  final ResearchApi _api;
  final Duration pollInterval;

  ResearchProvider(this._api, {this.pollInterval = const Duration(seconds: 3)});

  ResearchJob? _currentJob;
  ResearchJob? get currentJob => _currentJob;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Timer? _pollTimer;

  bool get isRunning =>
      _currentJob != null && !_currentJob!.status.isTerminal;

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

      if (!job.status.isTerminal) {
        _startPolling(tenantId: tenantId, jobId: job.id);
      }
    } on ApiException catch (e) {
      _isLoading = false;
      _error = e.body;
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
        }
      } on ApiException catch (e) {
        _error = e.body;
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
