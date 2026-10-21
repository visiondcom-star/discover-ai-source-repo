import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../models/partner_booking.dart';
import '../providers/partner_bookings_provider.dart';
import '../l10n/app_localizations.dart';

/// Formats the raw ISO date string from the backend (`YYYY-MM-DD`) using the
/// current locale's medium-length format. Falls back to the raw string when
/// the input is not a parseable date — older bookings or migrated data with
/// a non-ISO format must still render instead of crashing the card.
String _formatDateForLocale(BuildContext context, String raw, String locale) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return intl.DateFormat.yMMMd(locale).format(parsed);
}

/// Espace partenaire — the decision queue for `manual_confirm` bookings.
///
/// The provider is created **inside the route's builder**
/// (`ChangeNotifierProvider` on the [MaterialPageRoute]), not at app level:
/// this way a partner's queue never survives a logout — the next login of a
/// different user gets a fresh, empty queue. Tests inject their own
/// `PartnerBookingsProvider` (holding a `FakePartnerApi`) through the same
/// seam, so the screen itself takes no API parameter.
///
/// The screen renders exactly the `requested` bookings the backend serves
/// (date / guests / notes read from `details`, missing keys tolerated) and
/// lets the partner confirm or decline each one, with an optional note. The
/// provider owns the data; the screen only displays and forwards decisions.
class PartnerBookingsScreen extends StatefulWidget {
  const PartnerBookingsScreen({super.key});

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
    final loc = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          key: Key(decision == 'confirm'
              ? 'partner_confirmed_snackbar'
              : 'partner_declined_snackbar'),
          content: Text(
            decision == 'confirm'
                ? loc.partnerBookingConfirmed
                : loc.partnerBookingDeclined,
          ),
        ),
      );
    } else if (provider.actionError != null) {
      messenger.showSnackBar(
        SnackBar(
          key: const Key('partner_action_error_snackbar'),
          content: Text(_actionErrorText(context, provider.actionError!)),
        ),
      );
    }
  }

  /// Reloads the queue after a pull-to-refresh. When the reload fails while a
  /// queue is already on screen, the provider keeps the list — the failure is
  /// surfaced here as a discreet SnackBar (key `partner_refresh_error_snackbar`)
  /// instead of blanking what the partner is working through.
  Future<void> _refresh() async {
    final provider = context.read<PartnerBookingsProvider>();
    await provider.load();
    if (!mounted) return;
    final error = provider.error;
    if (error != null && provider.items.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('partner_refresh_error_snackbar'),
          content: Text(_loadErrorText(context, error)),
        ),
      );
    }
  }

  Future<void> _openNoteDialog(PartnerBooking booking, String decision) async {
    final loc = AppLocalizations.of(context);
    final confirmLabel =
        decision == 'confirm' ? loc.partnerConfirm : loc.partnerDecline;
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
    final loc = AppLocalizations.of(context);
    final provider = context.watch<PartnerBookingsProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(loc.partnerTitle)),
      body: _buildBody(context, provider, scheme),
    );
  }

  Widget _buildBody(
    BuildContext context,
    PartnerBookingsProvider provider,
    ColorScheme scheme,
  ) {
    final loc = AppLocalizations.of(context);
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
                child: Text(
                  _loadErrorText(context, provider.error!),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('partner_retry'),
                onPressed: provider.load,
                child: Text(loc.partnerRetry),
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
            Text(loc.partnerEmpty),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                loc.partnerEmptyHint,
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
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        // One extra slot for the "50 premières" notice when the page is full.
        itemCount: provider.items.length + (provider.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (provider.hasMore && index == provider.items.length) {
            return const _PartnerLimitNotice();
          }
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

  /// Translates a load-error [PartnerBookingError] code into a user-facing
  /// string. The provider is locale-agnostic (it holds a code), so the
  /// translation lives here — never in the provider, which has no
  /// `BuildContext`.
  String _loadErrorText(BuildContext context, PartnerBookingError error) {
    final loc = AppLocalizations.of(context);
    switch (error) {
      case PartnerBookingError.forbidden:
        return loc.errorLoadForbidden;
      case PartnerBookingError.notFound:
        return loc.errorLoadNotFound;
      case PartnerBookingError.network:
        return loc.errorLoadNetwork;
      case PartnerBookingError.generic:
      case PartnerBookingError.alreadyHandled:
        return loc.errorLoadGeneric;
    }
  }

  /// Translates an action-error [PartnerBookingError] code into a user-facing
  /// string (SnackBar after a confirm/decline).
  String _actionErrorText(BuildContext context, PartnerBookingError error) {
    final loc = AppLocalizations.of(context);
    switch (error) {
      case PartnerBookingError.alreadyHandled:
        return loc.errorActionAlreadyHandled;
      case PartnerBookingError.forbidden:
        return loc.errorActionForbidden;
      case PartnerBookingError.notFound:
        return loc.errorActionNotFound;
      case PartnerBookingError.network:
        return loc.errorActionNetwork;
      case PartnerBookingError.generic:
        return loc.errorActionGeneric;
    }
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
    final loc = AppLocalizations.of(context);
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
              loc.partnerTraveller(traveller ?? loc.partnerTravellerFallback),
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
                  Text(
                      loc.partnerDate(
                          _formatDateForLocale(context, date, loc.localeName)),
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
                  Text(loc.partnerGuests(guests),
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
                loc.partnerRespondBy(
                  intl.DateFormat.yMMMd(loc.localeName)
                      .format(booking.respondBy!),
                ),
                key: Key('partner_respond_by_${booking.id}'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: (overdue || dueSoon)
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                      fontWeight: (overdue || dueSoon)
                          ? FontWeight.bold
                          : FontWeight.normal,
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
                    child: Text(loc.partnerDecline),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: Key('partner_confirm_${booking.id}'),
                    onPressed: isActing ? null : onConfirm,
                    child: Text(loc.partnerConfirm),
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

/// Discreet footer shown when the queue is at the API page limit (50): more
/// requests may exist beyond what this screen loads, but pagination is out of
/// scope for now — we simply say so instead of silently truncating.
class _PartnerLimitNotice extends StatelessWidget {
  const _PartnerLimitNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    return Padding(
      key: const Key('partner_limit_notice'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Text(
        loc.partnerLimitNotice(PartnerBookingsProvider.pageLimit),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
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
    final loc = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.confirmLabel),
      content: TextField(
        key: const Key('partner_note_field'),
        controller: _controller,
        maxLines: 3,
        maxLength: 500,
        decoration: InputDecoration(
          labelText: loc.partnerNoteLabel,
          hintText: loc.partnerNoteHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(loc.partnerCancel),
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
