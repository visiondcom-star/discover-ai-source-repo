// test/models/research_collection_job_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:discover_ai/models/research_collection_job.dart';
import 'package:discover_ai/models/research_job.dart';

void main() {
  group('ResearchCollectionJob', () {
    final complet = <String, dynamic>{
      'id': 'c1',
      'tenant_id': 't1',
      'status': 'done',
      'started_at': '2026-10-02T10:00:00',
      'finished_at': '2026-10-02T10:01:30',
      'documents_fetched': 8,
      'documents_new': 5,
      'documents_duplicate': 2,
      'documents_failed': 1,
      'error_message': null,
      'run_pipeline': true,
      'research_job_id': 'r1',
    };

    test('fromJson lit tous les champs', () {
      final job = ResearchCollectionJob.fromJson(complet);

      expect(job.id, 'c1');
      expect(job.tenantId, 't1');
      expect(job.status, ResearchJobStatus.done);
      expect(job.startedAt, DateTime.parse('2026-10-02T10:00:00'));
      expect(job.finishedAt, DateTime.parse('2026-10-02T10:01:30'));
      expect(job.documentsFetched, 8);
      expect(job.documentsNew, 5);
      expect(job.documentsDuplicate, 2);
      expect(job.documentsFailed, 1);
      expect(job.errorMessage, isNull);
      expect(job.runPipeline, isTrue);
      expect(job.researchJobId, 'r1');
    });

    test('valeurs par défaut quand les champs optionnels sont absents', () {
      final job = ResearchCollectionJob.fromJson({
        'id': 'c2',
        'tenant_id': 't1',
        'status': 'pending',
      });

      expect(job.startedAt, isNull);
      expect(job.finishedAt, isNull);
      expect(job.documentsFetched, 0);
      expect(job.documentsNew, 0);
      expect(job.documentsDuplicate, 0);
      expect(job.documentsFailed, 0);
      expect(job.runPipeline, isFalse);
      expect(job.researchJobId, isNull);
    });

    test('toJson puis fromJson redonne le même contenu', () {
      final job = ResearchCollectionJob.fromJson(complet);
      final copie = ResearchCollectionJob.fromJson(job.toJson());

      expect(copie.toJson(), job.toJson());
    });

    test('toJson conserve chaque clé de la réponse backend', () {
      // Contrôle du précédent : l'aller-retour seul ne suffit pas. fromJson
      // applique `?? 0` sur les compteurs, donc une clé omise par toJson
      // reviendrait à 0 des deux côtés et l'égalité passerait quand même.
      // On compare donc la forme brute du dictionnaire.
      final json = ResearchCollectionJob.fromJson(complet).toJson();

      expect(json.keys.toSet(), containsAll(<String>{
        'id',
        'tenant_id',
        'status',
        'started_at',
        'finished_at',
        'documents_fetched',
        'documents_new',
        'documents_duplicate',
        'documents_failed',
        'error_message',
        'run_pipeline',
        'research_job_id',
        'created_at',
      }));
      expect(json['documents_duplicate'], 2);
    });

    test('fromJson rejette un statut inconnu', () {
      expect(
        () => ResearchCollectionJob.fromJson({
          'id': 'c3',
          'tenant_id': 't1',
          'status': 'bizarre',
        }),
        throwsArgumentError,
      );
    });

    test('run_pipeline absent se lit false, jamais null', () {
      // Une collecte seule est un cas valide : la clé peut être omise et le
      // modèle doit rester un booléen, pas null.
      final job = ResearchCollectionJob.fromJson({
        'id': 'c4',
        'tenant_id': 't1',
        'status': 'pending',
      });
      expect(job.runPipeline, isFalse);
    });

    test('research_job_id reste null si la chaîne n a rien produit', () {
      final job = ResearchCollectionJob.fromJson({
        ...complet,
        'documents_new': 0,
        'research_job_id': null,
      });
      expect(job.runPipeline, isTrue);
      expect(job.researchJobId, isNull);
    });

    test('copyWith garde le run_pipeline lors du polling', () {
      final job = ResearchCollectionJob.fromJson(complet);
      final copie = job.copyWith(
        researchJobId: null,
        status: ResearchJobStatus.processing,
      );
      expect(copie.id, job.id);
      expect(copie.status, ResearchJobStatus.processing);
      // Le chaînage ne doit pas se perdre au fil des relances du polling.
      expect(copie.runPipeline, isTrue);
      expect(copie.documentsFetched, 8);
    });
  });

  group('aides de statut', () {
    test('isTerminal ne vaut que pour done et failed', () {
      expect(isTerminalCollectionStatus(ResearchJobStatus.pending), isFalse);
      expect(isTerminalCollectionStatus(ResearchJobStatus.processing), isFalse);
      expect(isTerminalCollectionStatus(ResearchJobStatus.done), isTrue);
      expect(isTerminalCollectionStatus(ResearchJobStatus.failed), isTrue);
    });

    test('isExternalCollectionFailure reconnaît les deux préfixes', () {
      const failed = ResearchJobStatus.failed;
      expect(
        isExternalCollectionFailure(failed, 'quota_exceeded: plus de crédit'),
        isTrue,
      );
      expect(
        isExternalCollectionFailure(failed, 'interrupted: redémarrage'),
        isTrue,
      );
    });

    test('isExternalCollectionFailure exclut une erreur technique', () {
      const failed = ResearchJobStatus.failed;
      expect(isExternalCollectionFailure(failed, 'timeout réseau'), isFalse);
      expect(isExternalCollectionFailure(failed, null), isFalse);
      expect(isExternalCollectionFailure(failed, ''), isFalse);
      // Un job non échoué n'est jamais une cause externe, même avec le préfixe.
      expect(
        isExternalCollectionFailure(
          ResearchJobStatus.processing,
          'interrupted: redémarrage',
        ),
        isFalse,
      );
    });
  });
}
