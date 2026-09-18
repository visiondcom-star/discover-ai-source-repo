import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/research_job.dart';
import '../providers/research_provider.dart';
import '../providers/tenant_provider.dart';

/// Admin screen for the AI destination-research pipeline (Niveau 2
/// dynamique par tenant). Lets an admin trigger a manual refresh, watch
/// the job progress (pending -> processing -> done|failed), and see the
/// tenant categories once the run completes.
class AdminResearchScreen extends StatelessWidget {
  const AdminResearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tenant = context.watch<TenantProvider>().tenant;
    final research = context.watch<ResearchProvider>();
    final job = research.currentJob;

    return Scaffold(
      appBar: AppBar(title: const Text('Recherche IA — destination')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Statut du pipeline',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _StatusRow(job: job, isLoading: research.isLoading),
                  if (research.error != null) ...[
                    const SizedBox(height: 12),
                    Text(research.error!,
                        style: TextStyle(color: scheme.error)),
                  ],
                  if (job != null && job.status.isTerminal) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${job.categoriesProposed} proposée(s) · '
                      '${job.categoriesAutoPublished} publiée(s) auto · '
                      '${job.categoriesPendingReview} en attente de revue',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('run_research_button'),
            onPressed: (research.isRunning || tenant == null)
                ? null
                : () {
                    context.read<ResearchProvider>().startResearch(
                          tenantId: tenant.id,
                          triggerType: ResearchTriggerType.manualRefresh,
                        );
                  },
            icon: research.isRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore),
            label: Text(research.isRunning
                ? 'Recherche en cours…'
                : 'Lancer la recherche IA'),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Catégories du territoire',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(
                key: const Key('refresh_categories_button'),
                tooltip: 'Actualiser',
                icon: const Icon(Icons.refresh),
                onPressed: () =>
                    context.read<TenantProvider>().loadCategories(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _CategoriesList(),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.job, required this.isLoading});

  final ResearchJob? job;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (isLoading || (job != null && !job!.status.isTerminal)) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(_statusLabel(job?.status)),
        ],
      );
    }

    if (job == null) {
      return Text('Aucun run lancé récemment',
          style: TextStyle(color: scheme.onSurfaceVariant));
    }

    final isFailed = job!.status == ResearchJobStatus.failed;
    return Row(
      children: [
        Icon(
          isFailed ? Icons.error_outline : Icons.check_circle_outline,
          color: isFailed ? scheme.error : Colors.green,
        ),
        const SizedBox(width: 8),
        Text(_statusLabel(job!.status)),
      ],
    );
  }

  String _statusLabel(ResearchJobStatus? status) {
    switch (status) {
      case ResearchJobStatus.pending:
        return 'En attente de démarrage…';
      case ResearchJobStatus.processing:
        return 'Traitement en cours…';
      case ResearchJobStatus.done:
        return 'Terminé';
      case ResearchJobStatus.failed:
        return 'Échec du run';
      case null:
        return 'Prêt';
    }
  }
}

class _CategoriesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final categories = context.watch<TenantProvider>().categories;

    if (categories.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          enabled: false,
          leading: const Icon(Icons.category_outlined),
          title: const Text('Aucune catégorie pour le moment'),
        ),
      );
    }

    return Column(
      children: categories.map((cat) {
        final scheme = Theme.of(context).colorScheme;
        final isProposed = cat.status == 'proposed';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              isProposed ? Icons.hourglass_top : Icons.check_circle,
              color: isProposed ? scheme.tertiary : Colors.green,
            ),
            title: Text(cat.label),
            subtitle: Text(cat.parentFamily ?? '—'),
            trailing: cat.confidence != null
                ? Text('${(cat.confidence! * 100).round()}%')
                : null,
          ),
        );
      }).toList(),
    );
  }
}
