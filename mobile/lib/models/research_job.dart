// lib/models/research_job.dart
//
// Modèle du job de recherche IA destination (pipeline Niveau 2 dynamique).
// Miroir du schéma backend `research_jobs`.

enum ResearchTriggerType {
  tenantCreated,
  scheduled,
  manualRefresh,
  adminReplay;

  static ResearchTriggerType fromJson(String value) {
    switch (value) {
      case 'tenant_created':
        return ResearchTriggerType.tenantCreated;
      case 'scheduled':
        return ResearchTriggerType.scheduled;
      case 'manual_refresh':
        return ResearchTriggerType.manualRefresh;
      case 'admin_replay':
        return ResearchTriggerType.adminReplay;
      default:
        throw ArgumentError('Unknown trigger_type: $value');
    }
  }

  String toJson() {
    switch (this) {
      case ResearchTriggerType.tenantCreated:
        return 'tenant_created';
      case ResearchTriggerType.scheduled:
        return 'scheduled';
      case ResearchTriggerType.manualRefresh:
        return 'manual_refresh';
      case ResearchTriggerType.adminReplay:
        return 'admin_replay';
    }
  }
}

enum ResearchJobStatus {
  pending,
  processing,
  done,
  failed;

  static ResearchJobStatus fromJson(String value) {
    switch (value) {
      case 'pending':
        return ResearchJobStatus.pending;
      case 'processing':
        return ResearchJobStatus.processing;
      case 'done':
        return ResearchJobStatus.done;
      case 'failed':
        return ResearchJobStatus.failed;
      default:
        throw ArgumentError('Unknown status: $value');
    }
  }

  String toJson() {
    switch (this) {
      case ResearchJobStatus.pending:
        return 'pending';
      case ResearchJobStatus.processing:
        return 'processing';
      case ResearchJobStatus.done:
        return 'done';
      case ResearchJobStatus.failed:
        return 'failed';
    }
  }

  bool get isTerminal =>
      this == ResearchJobStatus.done || this == ResearchJobStatus.failed;
}

class ResearchJob {
  final String id;
  final String tenantId;
  final ResearchTriggerType triggerType;
  final ResearchJobStatus status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int categoriesProposed;
  final int categoriesAutoPublished;
  final int categoriesPendingReview;
  final String? errorMessage;

  const ResearchJob({
    required this.id,
    required this.tenantId,
    required this.triggerType,
    required this.status,
    this.startedAt,
    this.finishedAt,
    this.categoriesProposed = 0,
    this.categoriesAutoPublished = 0,
    this.categoriesPendingReview = 0,
    this.errorMessage,
  });

  factory ResearchJob.fromJson(Map<String, dynamic> json) {
    return ResearchJob(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      triggerType: ResearchTriggerType.fromJson(json['trigger_type'] as String),
      status: ResearchJobStatus.fromJson(json['status'] as String),
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      finishedAt: json['finished_at'] != null
          ? DateTime.parse(json['finished_at'] as String)
          : null,
      categoriesProposed: json['categories_proposed'] as int? ?? 0,
      categoriesAutoPublished: json['categories_auto_published'] as int? ?? 0,
      categoriesPendingReview: json['categories_pending_review'] as int? ?? 0,
      errorMessage: json['error_message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tenant_id': tenantId,
    'trigger_type': triggerType.toJson(),
    'status': status.toJson(),
    'started_at': startedAt?.toIso8601String(),
    'finished_at': finishedAt?.toIso8601String(),
    'categories_proposed': categoriesProposed,
    'categories_auto_published': categoriesAutoPublished,
    'categories_pending_review': categoriesPendingReview,
    'error_message': errorMessage,
  };

  ResearchJob copyWith({
    ResearchJobStatus? status,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? categoriesProposed,
    int? categoriesAutoPublished,
    int? categoriesPendingReview,
    String? errorMessage,
  }) {
    return ResearchJob(
      id: id,
      tenantId: tenantId,
      triggerType: triggerType,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      categoriesProposed: categoriesProposed ?? this.categoriesProposed,
      categoriesAutoPublished:
          categoriesAutoPublished ?? this.categoriesAutoPublished,
      categoriesPendingReview:
          categoriesPendingReview ?? this.categoriesPendingReview,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
