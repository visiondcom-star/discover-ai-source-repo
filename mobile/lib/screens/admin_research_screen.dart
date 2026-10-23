import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
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
  String _errorText(AppLocalizations loc, ResearchError? error) {
    switch (error) {
      case ResearchError.rateLimited:
        return loc.adminResearchErrorRateLimited;
      case ResearchError.pollFailed:
        return loc.adminResearchErrorPollFailed;
      case ResearchError.network:
        return loc.adminResearchErrorNetwork;
      case ResearchError.generic:
      case null:
        return loc.adminResearchErrorGeneric;
    }
  }

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
    final loc = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tenant = context.watch<TenantProvider>().tenant;
    final research = context.watch<ResearchProvider>();
    final job = research.currentJob;

    return Scaffold(
      appBar: AppBar(title: Text(loc.adminResearchTitle)),
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
                  Text(loc.adminResearchStatusTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _StatusRow(job: job, isLoading: research.isLoading),
                  if (research.error != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorText(loc, research.error),
                        style: TextStyle(color: scheme.error)),
                  ],
                  if (job != null && job.status.isTerminal) ...[
                    const SizedBox(height: 8),
                    Text(
                      loc.adminResearchSummary(
                        job.categoriesProposed,
                        job.categoriesAutoPublished,
                        job.categoriesPendingReview,
                      ),
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
                ? loc.adminResearchRunning
                : loc.adminResearchRunButton),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(loc.adminResearchCategoriesTitle,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(
                key: const Key('refresh_categories_button'),
                tooltip: loc.adminResearchRefreshTooltip,
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

  String _statusLabel(AppLocalizations loc, ResearchJobStatus? status) {
    switch (status) {
      case ResearchJobStatus.pending:
        return loc.adminResearchStatusPending;
      case ResearchJobStatus.processing:
        return loc.adminResearchStatusProcessing;
      case ResearchJobStatus.done:
        return loc.adminResearchStatusDone;
      case ResearchJobStatus.failed:
        return loc.adminResearchStatusFailed;
      case null:
        return loc.adminResearchStatusReady;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
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
          Text(_statusLabel(loc, job?.status)),
        ],
      );
    }

    if (job == null) {
      return Text(loc.adminResearchNoRecentRun,
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
        Text(_statusLabel(loc, job!.status)),
      ],
    );
  }
}

class _CategoriesList extends StatelessWidget {
  const _CategoriesList();

  String _categoriesErrorText(
      AppLocalizations loc, AdminCategoriesError? error) {
    switch (error) {
      case AdminCategoriesError.network:
        return loc.adminCategoriesErrorNetwork;
      case AdminCategoriesError.generic:
      case null:
        return loc.adminCategoriesErrorGeneric;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final admin = context.watch<AdminCategoriesProvider>();
    final scheme = Theme.of(context).colorScheme;

    final ordered = [
      for (final s in const ['proposed', 'active', 'rejected'])
        ...admin.categories.where((c) => c.status == s),
    ];

    return Column(
      children: [
        if (admin.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_categoriesErrorText(loc, admin.error),
                style: TextStyle(color: scheme.error)),
          ),
        if (ordered.isEmpty && !admin.isLoading)
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              enabled: false,
              leading: const Icon(Icons.category_outlined),
              title: Text(loc.adminResearchNoCategories),
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
    final loc = AppLocalizations.of(context);
    if (status == 'rejected') {
      // D'après le schéma, pas de retour arrière depuis `rejected`.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.adminResearchRejectDialogTitle),
          content: Text(category.status == 'active'
              ? loc.adminResearchRejectActiveContent
              : loc.adminResearchRejectContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.adminResearchCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.adminResearchConfirm),
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
    final loc = AppLocalizations.of(context);
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
          tooltip: loc.adminResearchPublish,
          icon: const Icon(Icons.check_circle_outline, color: Colors.green),
          onPressed: () => _change(context, 'active'),
        ),
        IconButton(
          key: Key('reject_$id'),
          tooltip: loc.adminResearchReject,
          icon: Icon(Icons.cancel_outlined, color: scheme.error),
          onPressed: () => _change(context, 'rejected'),
        ),
      ]);
    } else if (category.status == 'active') {
      trailing = IconButton(
        key: Key('retire_$id'),
        tooltip: loc.adminResearchRetire,
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: () => _change(context, 'rejected'),
      );
    } else {
      trailing = Text(loc.adminResearchRejected,
          style: TextStyle(color: scheme.outline));
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
