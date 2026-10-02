// lib/models/research_collection_job.dart
//
// Modèle du job de collecte de documents destination (Wiktionary/Wikipedia).
// Miroir du schéma backend `research_collection_jobs` et de
// `ResearchCollectionJobResponse`.
//
// Le statut réutilise `ResearchJobStatus` (research_job.dart) : les deux tables
// partagent le même cycle de vie côté backend
// (RESEARCH_JOB_STATUSES == RESEARCH_COLLECTION_JOB_STATUSES), et le chaînage
// fait circuler un `collection` entre les deux. Un enum séparé obligerait à
// convertir à chaque passage et risquerait de diverger.
import 'research_job.dart';

/// Vrai si le job a atteint un statut terminal : le polling peut s'arrêter.
///
/// `failed` reste terminal malgré le préfixe `interrupted:` posé au démarrage
/// (backend `fail_orphan_jobs`) : le job ne sera jamais repris, l'admin doit
/// donc pouvoir en relancer un.
bool isTerminalCollectionStatus(ResearchJobStatus status) =>
    status.isTerminal;

/// Vrai si l'échec est dû à l'environnement (quota épuisé, redémarrage) et non
/// à la collecte elle-même.
///
/// Les préfixes sont posés par le backend (`quota_exceeded:`, `interrupted:`) et
/// le message en est le seul porteur : une UI peut alors proposer « réessayer
/// plus tard » plutôt qu'un échec technique. Un message vide ou nul n'est pas
/// une cause externe.
bool isExternalCollectionFailure(
  ResearchJobStatus status,
  String? errorMessage,
) {
  if (status != ResearchJobStatus.failed) return false;
  if (errorMessage == null) return false;
  return errorMessage.startsWith('quota_exceeded:') ||
      errorMessage.startsWith('interrupted:');
}

class ResearchCollectionJob {
  final String id;
  final String tenantId;
  final ResearchJobStatus status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int documentsFetched;
  final int documentsNew;
  final int documentsDuplicate;
  final int documentsFailed;
  final String? errorMessage;

  /// Drapeau de chaînage demandé au POST. Miroir de `params.run_pipeline`.
  ///
  /// Défaut `false` : la clé peut manquer sur une réponse d'un serveur
  /// antérieur, et une collecte seule est un cas valide.
  final bool runPipeline;

  /// Job de recherche enchaîné sur cette collecte. `null` tant que le
  /// chaînage n'a pas eu lieu — notamment si la collecte n'a rien trouvé de
  /// nouveau, ou si elle a échoué.
  final String? researchJobId;

  final DateTime? createdAt;

  const ResearchCollectionJob({
    required this.id,
    required this.tenantId,
    required this.status,
    this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.documentsFetched = 0,
    this.documentsNew = 0,
    this.documentsDuplicate = 0,
    this.documentsFailed = 0,
    this.errorMessage,
    this.runPipeline = false,
    this.researchJobId,
  });

  factory ResearchCollectionJob.fromJson(Map<String, dynamic> json) {
    return ResearchCollectionJob(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      status: ResearchJobStatus.fromJson(json['status'] as String),
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      finishedAt: json['finished_at'] != null
          ? DateTime.parse(json['finished_at'] as String)
          : null,
      documentsFetched: json['documents_fetched'] as int? ?? 0,
      documentsNew: json['documents_new'] as int? ?? 0,
      documentsDuplicate: json['documents_duplicate'] as int? ?? 0,
      documentsFailed: json['documents_failed'] as int? ?? 0,
      errorMessage: json['error_message'] as String?,
      runPipeline: json['run_pipeline'] as bool? ?? false,
      researchJobId: json['research_job_id'] as String?,
      // Optionnel : le backend l'envoie bien (ResearchCollectionJobResponse), mais il
// n'est pas nécessaire au polling ni à l'affichage. Un serveur plus ancien ou
// une réponse tronquée ne doit pas faire échouer la désérialisation entière.
createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'status': status.toJson(),
        'started_at': startedAt?.toIso8601String(),
        'finished_at': finishedAt?.toIso8601String(),
        'documents_fetched': documentsFetched,
        'documents_new': documentsNew,
        'documents_duplicate': documentsDuplicate,
        'documents_failed': documentsFailed,
        'error_message': errorMessage,
        'run_pipeline': runPipeline,
        'research_job_id': researchJobId,
        'created_at': createdAt?.toIso8601String(),
      };

  ResearchCollectionJob copyWith({
    ResearchJobStatus? status,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? documentsFetched,
    int? documentsNew,
    int? documentsDuplicate,
    int? documentsFailed,
    String? errorMessage,
    bool? runPipeline,
    String? researchJobId,
  }) {
    return ResearchCollectionJob(
      id: id,
      tenantId: tenantId,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      documentsFetched: documentsFetched ?? this.documentsFetched,
      documentsNew: documentsNew ?? this.documentsNew,
      documentsDuplicate: documentsDuplicate ?? this.documentsDuplicate,
      documentsFailed: documentsFailed ?? this.documentsFailed,
      errorMessage: errorMessage ?? this.errorMessage,
      runPipeline: runPipeline ?? this.runPipeline,
      researchJobId: researchJobId ?? this.researchJobId,
      createdAt: createdAt,
    );
  }
}