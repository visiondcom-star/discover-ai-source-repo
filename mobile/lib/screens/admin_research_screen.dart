import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/research_job.dart';
import '../models/tenant_category.dart';
import '../providers/admin_categories_provider.dart';
import '../providers/research_provider.dart';
import '../providers/tenant_provider.dart';

/// Admin screen for the AI destination-research pipeline (Niveau 2
/// dynamique par tenant). Lets an admin trigger a manual refresh, watch
/// the job progress (pending -> processing -> done|failed), and see the
/// tenant categories once the run completes.
class AdminResearchScreen extends StatefulWidget {
  const AdminResearchScreen({super.key});

  @override
  State<AdminResearchScreen> createState() => _AdminResearchScreenState();
}

class _AdminResearchScreenState extends State<AdminResearchScreen> {
  @override
  void initState() {
    super.initState();
    // Charge la file de validation dès l'ouverture : sans cet appel, l'écran
    // resterait vide tant que l'admin n'a pas tapé « Actualiser ». On attend la
    // fin du premier frame pour ne pas notifier pendant le build initial.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminCategoriesProvider>().load();
    });
  }

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
              // Le rechargement n'est plus déclenché ici : le catalogue voyageur
              // se rafraîchit depuis `ResearchProvider.onJobDone` (branché dans
              // main.dart) et depuis `AdminCategoriesProvider.onChanged`. Ce
              // bouton ne rafraîchissait que si l'admin y pensez, ce qui laissait
              // la file de validation fausser dès la fin d'un run.
              IconButton(
                key: const Key('refresh_categories_button'),
                tooltip: 'Actualiser',
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<AdminCategoriesProvider>().load(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _CategoriesList(),
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
  const _CategoriesList();

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminCategoriesProvider>();
    final scheme = Theme.of(context).colorScheme;

    // proposed d'abord (à traiter), puis active, puis rejected. Trois passes
    // plutôt qu'un sort() : l'ordre du serveur est conservé dans chaque groupe.
    final ordered = [
      for (final s in const ['proposed', 'active', 'rejected'])
        ...admin.categories.where((c) => c.status == s),
    ];

    return Column(
      children: [
        if (admin.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(admin.error!, style: TextStyle(color: scheme.error)),
          ),
        if (ordered.isEmpty && !admin.isLoading)
          const Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              enabled: false,
              leading: Icon(Icons.category_outlined),
              title: Text('Aucune catégorie pour le moment'),
            ),
          ),
        for (final cat in ordered)
          _CategoryTile(category: cat, busy: admin.isUpdating(cat.id)),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.busy});

  final TenantCategory category;
  final bool busy;

  Future<void> _change(BuildContext context, String status) async {
    if (status == 'rejected') {
      // D'après le schéma, pas de retour arrière depuis `rejected`.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rejeter cette catégorie ?'),
          content: Text(category.status == 'active'
              ? 'Elle disparaîtra de l’app pour les voyageurs. '
                  'Cette action est définitive.'
              : 'Cette action est définitive.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    await context.read<AdminCategoriesProvider>().setStatus(category, status);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = category.id;

    final Widget? trailing;
    if (busy) {
      trailing = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (category.status == 'proposed') {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: Key('publish_$id'),
          tooltip: 'Publier',
          icon: const Icon(Icons.check_circle_outline, color: Colors.green),
          onPressed: () => _change(context, 'active'),
        ),
        IconButton(
          key: Key('reject_$id'),
          tooltip: 'Rejeter',
          icon: Icon(Icons.cancel_outlined, color: scheme.error),
          onPressed: () => _change(context, 'rejected'),
        ),
      ]);
    } else if (category.status == 'active') {
      trailing = IconButton(
        key: Key('retire_$id'),
        tooltip: 'Retirer',
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: () => _change(context, 'rejected'),
      );
    } else {
      trailing = Text('Rejetée', style: TextStyle(color: scheme.outline));
    }

    final confidence = category.confidence;
    final subtitle = [
      category.parentFamily ?? '—',
      if (confidence != null) '${(confidence * 100).round()}%',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          switch (category.status) {
            'proposed' => Icons.hourglass_top,
            'active' => Icons.check_circle,
            _ => Icons.block,
          },
          color: switch (category.status) {
            'proposed' => scheme.tertiary,
            'active' => Colors.green,
            _ => scheme.outline,
          },
        ),
        title: Text(category.label),
        subtitle: Text(subtitle),
        trailing: trailing,
      ),
    );
  }
}
