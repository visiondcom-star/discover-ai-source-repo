import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/partner_booking.dart';
import '../providers/partner_bookings_provider.dart';
import '../services/api_service.dart';

/// Espace partenaire — the decision queue for `manual_confirm` bookings.
///
/// The provider is created **inside the route's builder**
/// (`ChangeNotifierProvider` on the [MaterialPageRoute]), not at app level:
/// this way a partner's queue never survives a logout — the next login of a
/// different user gets a fresh, empty queue. [partnerApi] is injectable for
/// tests.
///
/// The screen renders exactly the `requested` bookings the backend serves
/// (date / guests / notes read from `details`, missing keys tolerated) and
/// lets the partner confirm or decline each one, with an optional note. The
/// provider owns the data; the screen only displays and forwards decisions.
class PartnerBookingsScreen extends StatefulWidget {
  const PartnerBookingsScreen({super.key, this.partnerApi});

  /// Injectable seam for tests; defaults to the real [ApiService].
  final PartnerApi? partnerApi;

  @override
  State<PartnerBookingsScreen> createState() => _PartnerBookingsScreenState();
}

class _PartnerBookingsScreenState extends State<PartnerBookingsScreen> {
  @override
  void initState() {
    super.initState();
    // Post-frame: providers cannot be read while the element tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PartnerBookingsProvider>().load();
    });
  }

  Future<void> _respond(
    PartnerBooking booking,
    String decision, {
    String? note,
  }) async {
    final provider = context.read<PartnerBookingsProvider>();
    final ok = await provider.respond(booking, decision, note: note);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          key: Key(decision == 'confirm'
              ? 'partner_confirmed_snackbar'
              : 'partner_declined_snackbar'),
          content: Text(
              decision == 'confirm' ? 'Demande confirmée' : 'Demande refusée'),
        ),
      );
    } else if (provider.actionError != null) {
      messenger.showSnackBar(
        SnackBar(
          key: const Key('partner_action_error_snackbar'),
          content: Text(provider.actionError!),
        ),
      );
    }
  }

  Future<void> _openNoteDialog(PartnerBooking booking, String decision) async {
    final confirmLabel = decision == 'confirm' ? 'Confirmer' : 'Refuser';
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(
        key: const Key('partner_note_dialog'),
        confirmLabel: confirmLabel,
      ),
    );
    // null = dismissed (back button); '' = confirmed with no note.
    if (note == null) return;
    await _respond(booking, decision, note: note.isEmpty ? null : note);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.watch<PartnerBookingsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Espace partenaire')),
      body: _buildBody(context, provider, scheme),
    );
  }

  Widget _buildBody(
    BuildContext context,
    PartnerBookingsProvider provider,
    ColorScheme scheme,
  ) {
    if (provider.items.isEmpty) {
      if (provider.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (provider.error != null) {
        return Center(
          child: Column(
            key: const Key('partner_error'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(provider.error!, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('partner_retry'),
                onPressed: provider.load,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          key: const Key('partner_empty'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text('Aucune demande à traiter'),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Les nouvelles demandes de réservation apparaîtront ici.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      key: const Key('partner_refresh'),
      onRefresh: provider.load,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: provider.items.length,
        itemBuilder: (context, index) {
          final booking = provider.items[index];
          return _PartnerCard(
            booking: booking,
            isActing: provider.isActing,
            onConfirm: () => _openNoteDialog(booking, 'confirm'),
            onDecline: () => _openNoteDialog(booking, 'decline'),
          );
        },
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({
    required this.booking,
    required this.isActing,
    required this.onConfirm,
    required this.onDecline,
  });

  final PartnerBooking booking;
  final bool isActing;
  final VoidCallback onConfirm;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final traveller = booking.travellerName;
    final date = booking.dateLabel;
    final guests = booking.guestsLabel;
    final notes = booking.notes;
    final overdue = booking.isOverdue(now);
    final dueSoon = booking.isDueSoon(now);

    return Card(
      key: Key('partner_card_${booking.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              booking.poiName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              'Voyageur : ${traveller ?? 'Voyageur'}',
              key: Key('partner_traveller_${booking.id}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (date != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('Date : $date',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
            if (guests != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.people_outline,
                      size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('Personnes : $guests',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
            if (notes != null) ...[
              const SizedBox(height: 6),
              Text(
                notes,
                key: Key('partner_notes_${booking.id}'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (booking.respondBy != null) ...[
              const SizedBox(height: 6),
              Text(
                'Réponse attendue avant le ${_dateFr(booking.respondBy!)}',
                key: Key('partner_respond_by_${booking.id}'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: (overdue || dueSoon)
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                      fontWeight:
                          (overdue || dueSoon) ? FontWeight.bold : FontWeight.normal,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('partner_decline_${booking.id}'),
                    onPressed: isActing ? null : onDecline,
                    child: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: Key('partner_confirm_${booking.id}'),
                    onPressed: isActing ? null : onConfirm,
                    child: const Text('Confirmer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// Optional-note dialog for confirm/decline. Returns the typed note ('' when
/// left empty), or null when dismissed — the caller only acts on a non-null
/// result, so dismissing never sends a decision.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({super.key, required this.confirmLabel});

  final String confirmLabel;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.confirmLabel),
      content: TextField(
        key: const Key('partner_note_field'),
        controller: _controller,
        maxLines: 3,
        maxLength: 500,
        decoration: const InputDecoration(
          labelText: 'Note (facultative)',
          hintText: 'Précisez un horaire, un motif de refus…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('partner_note_confirm'),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

String _dateFr(DateTime d) => '${d.day}/${d.month}/${d.year}';

