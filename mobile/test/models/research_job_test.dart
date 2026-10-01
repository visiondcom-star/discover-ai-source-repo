// test/models/research_job_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:discover_ai/models/research_job.dart';

void main() {
  group('ResearchTriggerType', () {
    test('collection trigger type round-trips', () {
      expect(
        ResearchTriggerType.fromJson('collection'),
        ResearchTriggerType.collection,
      );
      expect(ResearchTriggerType.collection.toJson(), 'collection');
    });

    test('fromJson rejette une valeur inconnue', () {
      expect(
        () => ResearchTriggerType.fromJson('inconnu'),
        throwsArgumentError,
      );
    });

    test('les autres types restent stables', () {
      const attendu = {
        'tenant_created': ResearchTriggerType.tenantCreated,
        'scheduled': ResearchTriggerType.scheduled,
        'manual_refresh': ResearchTriggerType.manualRefresh,
        'admin_replay': ResearchTriggerType.adminReplay,
      };
      attendu.forEach((json, type) {
        expect(ResearchTriggerType.fromJson(json), type);
        expect(type.toJson(), json);
      });
    });
  });
}
