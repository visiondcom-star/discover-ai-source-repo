// lib/screens/admin_collection_screen.dart
//
// Écran admin de la collecte automatique de documents (Wikivoyage/Wikipedia).
// Miroir de AdminResearchScreen : l'admin lance une collecte, suit sa
// progression, et voit les compteurs une fois terminée.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/research_collection_provider.dart';
import '../providers/tenant_provider.dart';

/// Écran de lancement et de suivi de la collecte, pour l'admin du tenant.
///
/// Le chaînage vers le pipeline IA est activé par défaut : le cas courant est
/// collecte → analyse en un seul tap. Chaque analyse consomme du quota LLM,
/// donc l'admin peut le désactiver et ne payer que la collecte (gratuite).
class AdminCollectionScreen extends StatefulWidget {
  const AdminCollectionScreen({super.key});

  @override
  State<AdminCollectionScreen> createState() => _AdminCollectionScreenState();
}

class _AdminCollectionScreenState extends State<AdminCollectionScreen> {
  bool _runPipeline = true;

  String _errorText(AppLocalizations loc, ResearchCollectionError? error) {
    switch (error) {
      case ResearchCollectionError.conflict:
        return loc.adminCollectionErrorConflict;
      case ResearchCollectionError.rateLimited:
        return loc.adminCollectionErrorRateLimited;
      case ResearchCollectionError.pollFailed:
        return loc.adminCollectionErrorPollFailed;
      case ResearchCollectionError.network:
        return loc.adminCollectionErrorNetwork;
      case ResearchCollectionError.generic:
      case null:
        return loc.adminCollectionErrorGeneric;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final tenants = context.watch<TenantProvider>();
    final collection = context.watch<ResearchCollectionProvider>();
    final job = collection.currentJob;
    final tenantId = tenants.tenant?.id ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(loc.adminCollectionTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              key: const Key('run_pipeline_switch'),
              title: Text(loc.adminCollectionRunPipeline),
              subtitle: Text(loc.adminCollectionRunPipelineSubtitle),
              value: _runPipeline,
              onChanged: (value) => setState(() => _runPipeline = value),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('run_collection_button'),
            onPressed: tenantId.isEmpty
                ? null
                : () => collection.startCollection(
                      tenantId: tenantId,
                      runPipeline: _runPipeline,
                    ),
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(loc.adminCollectionRunButton),
          ),
          if (collection.error != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText(loc, collection.error),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (job != null) ...[
            const SizedBox(height: 12),
            if (!job.status.isTerminal)
              Text(loc.adminCollectionRunning)
            else if (job.status.name == 'done')
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.adminCollectionDone),
                  Text(
                    loc.adminCollectionSummary(
                      job.documentsFetched,
                      job.documentsNew,
                      job.documentsDuplicate,
                      job.documentsFailed,
                    ),
                  ),
                ],
              )
            else
              Text(
                job.errorMessage ?? loc.adminCollectionJobFailed,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
