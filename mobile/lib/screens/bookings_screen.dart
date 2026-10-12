import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/booking.dart';
import '../models/poi.dart';
import '../providers/booking_provider.dart';
import '../providers/poi_provider.dart';
import '../utils/idempotency.dart';

/// Réservations tab — real consent-flow UI on the backend Booking-Agent
/// (architecture principle n°5): a booking is created PENDING, then consent
/// is EXPLICIT (recap dialog) — confirmed + `EXT-…` reference on accept,
/// cancelled on refusal. No auto-confirmation, ever; only backend-provided
/// data is rendered.
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  @override
  void initState() {
    super.initState();
    // Post-frame: providers cannot be read while the element tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  /// Initial load. A 'requested' booking may have been answered by the
  /// partner since the last visit: trigger one silent refresh (no spinner,
  /// no periodic polling).
  Future<void> _load() async {
    final provider = context.read<BookingProvider>();
    await provider.loadBookings();
    if (!mounted) return;
    if (provider.items.any((b) => b.isAwaitingPartner)) {
      await provider.loadBookings(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bookings = context.watch<BookingProvider>();
    final pois = context.watch<POIProvider>().items;
    return Scaffold(
      appBar: AppBar(title: const Text('Réservations')),
      body: _buildBody(context, bookings, pois, scheme),
    );
  }

  Widget _buildBody(
    BuildContext context,
    BookingProvider bookings,
    List<POI> pois,
    ColorScheme scheme,
  ) {
    if (bookings.items.isEmpty) {
      if (bookings.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (bookings.error != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('Impossible de charger les réservations'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: bookings.loadBookings,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          key: const Key('bookings_empty'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_month_outlined,
                size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text('Aucune réservation pour le moment'),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Réservez un hôtel, une table ou une visite depuis la fiche '
                'd’un lieu — chaque étape demandera votre confirmation '
                'explicite.',
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
      onRefresh: bookings.loadBookings,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: bookings.items.length,
        itemBuilder: (context, index) {
          final booking = bookings.items[index];
          var poiName = booking.poiId;
          for (final p in pois) {
            if (p.id == booking.poiId) {
              poiName = p.name;
              break;
            }
          }
          return _BookingCard(booking: booking, poiName: poiName);
        },
      ),
    );
  }
}

/// Centralized status presentation (label + color) for the booking card.
/// Single table per the spec: every status renders through this function,
/// unknown statuses fall back to the raw text on a neutral background.
class BookingStatusStyle {
  const BookingStatusStyle(this.label, this.color);

  final String label;
  final Color color;
}

BookingStatusStyle styleFor(Booking booking, ColorScheme scheme) {
  if (booking.isPending) {
    return BookingStatusStyle('En attente de consentement',
        scheme.secondaryContainer);
  }
  if (booking.isAwaitingPartner) {
    return BookingStatusStyle(
        'En attente du prestataire', scheme.secondaryContainer);
  }
  if (booking.isConfirmed) {
    return BookingStatusStyle(booking.status, scheme.primaryContainer);
  }
  if (booking.isDeclined) {
    return BookingStatusStyle(
        'Refusée par le prestataire', scheme.errorContainer);
  }
  if (booking.isExpired) {
    return BookingStatusStyle(
        'Demande expirée', scheme.errorContainer.withAlpha(150));
  }
  if (booking.isCancelled) {
    return BookingStatusStyle(booking.status, scheme.errorContainer);
  }
  // Unknown status: render the raw text, never crash.
  return BookingStatusStyle(booking.status, scheme.secondaryContainer);
}

String _dateFr(DateTime d) => '${d.day}/${d.month}/${d.year}';

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.poiName});

  final Booking booking;
  final String poiName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.read<BookingProvider>();
    final style = styleFor(booking, scheme);
    return Card(
      key: Key('booking_card_${booking.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(poiName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Container(
                key: Key('booking_status_${booking.id}'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: style.color,
                    borderRadius: BorderRadius.circular(999)),
                child: Text(style.label,
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ]),
            const SizedBox(height: 8),
            Text('Prestataire : ${booking.adapterType}',
                style: Theme.of(context).textTheme.bodySmall),
            if (booking.createdAt != null)
              Text(_dateFr(booking.createdAt!),
                  style: Theme.of(context).textTheme.bodySmall),
            if (booking.price != null)
              Text('${booking.price} ${booking.currency}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (booking.isPending && booking.respondBy != null)
              Text(
                'Réponse attendue avant le ${_dateFr(booking.respondBy!)}',
                key: Key('booking_respond_by_${booking.id}'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            if (booking.isAwaitingPartner)
              Text(
                booking.respondBy != null
                    ? 'Le prestataire doit confirmer avant le '
                        '${_dateFr(booking.respondBy!)}'
                    : 'Le prestataire doit confirmer votre demande',
                key: Key('booking_awaiting_${booking.id}'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            if (booking.isDeclined &&
                booking.partnerNote != null &&
                booking.partnerNote!.isNotEmpty)
              Text(
                'Message du prestataire : ${booking.partnerNote}',
                key: Key('booking_partner_note_${booking.id}'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (booking.isExpired)
              Text(
                "Le prestataire n'a pas répondu à temps. Vous pouvez "
                'refaire une demande.',
                key: Key('booking_expired_hint_${booking.id}'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            if (booking.isConfirmed && booking.externalId != null) ...[
              const SizedBox(height: 4),
              Text(booking.externalId!,
                  key: Key('booking_ref_${booking.id}'),
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: scheme.primary)),
            ],
            if (booking.canGiveConsent || booking.canCancel) ...[
              const SizedBox(height: 12),
              Row(children: [
                if (booking.canGiveConsent) ...[
                  FilledButton(
                    key: Key('booking_consent_${booking.id}'),
                    onPressed: () => showConsentDialog(context, booking),
                    child: const Text('Confirmer'),
                  ),
                  const SizedBox(width: 8),
                ],
                if (booking.canCancel)
                  TextButton(
                    key: Key('booking_cancel_${booking.id}'),
                    onPressed: provider.isActing
                        ? null
                        : () => provider.cancelBooking(booking),
                    child: const Text('Annuler'),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Explicit consent step (principle 5): recap → confirm (true → confirmed +
/// `EXT-…`) or refuse (false → cancelled). No auto-confirmation, ever.
Future<void> showConsentDialog(BuildContext context, Booking booking) {
  final provider = context.read<BookingProvider>();
  var poiName = booking.poiId;
  for (final p in context.read<POIProvider>().items) {
    if (p.id == booking.poiId) {
      poiName = p.name;
      break;
    }
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('booking_consent_dialog'),
      title: const Text('Confirmer la réservation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(poiName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Prestataire : ${booking.adapterType}'),
          if (booking.price != null)
            Text('${booking.price} ${booking.currency}'),
          const SizedBox(height: 12),
          const Text('En confirmant, le Booking-Agent générera une référence '
              'externe (EXT-…). Sans confirmation, la réservation reste '
              'sans effet et sera annulée.'),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('booking_consent_refuse'),
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await provider.giveConsent(booking, consent: false);
          },
          child: const Text('Refuser'),
        ),
        FilledButton(
          key: const Key('booking_consent_confirm'),
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await provider.giveConsent(booking, consent: true);
          },
          child: const Text('Confirmer'),
        ),
      ],
    ),
  );
}

/// Booking sheet opened from a POI detail: lists only the adapters the
/// backend advertises (GET /bookings/adapters/available — no invented
/// fallback), creates a PENDING booking, then walks the user through the
/// explicit consent dialog (principle 5).
///
/// Guard: a POI that is not bookable (info_only / unsupported mode) has no
/// Book button on its detail screen — this check is defence in depth, so the
/// sheet can never be opened for such a place even by a stale widget tree.
Future<void> showBookingSheet(BuildContext context, POI poi) {
  if (!poi.isBookable) return Future<void>.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BookingSheet(poi: poi),
  );
}

class _BookingSheet extends StatefulWidget {
  const _BookingSheet({required this.poi});

  final POI poi;

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  static const _adapterLabels = {
    'hotel': 'Hôtel',
    'restaurant': 'Restaurant',
    'tour': 'Visite guidée',
    'transport': 'Transport',
  };

  String? _selected;
  bool _loading = false;

  /// One key per logical attempt (mobile mirror of the backend contract):
  /// generated lazily on the first "Create" tap and reused verbatim on any
  /// network/5xx retry so the backend replays instead of duplicating. Cleared
  /// when the payload legitimately changes (adapter switch) or the backend
  /// rejects the key (409/422) — a fresh key then starts a fresh attempt.
  String? _idempotencyKey;

  @override
  void initState() {
    super.initState();
    // Post-frame: providers cannot be read while the element tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadAdapters();
    });
  }

  void _loadAdapters() {
    setState(() => _loading = true);
    context.read<BookingProvider>().loadAdapters().whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.watch<BookingProvider>();
    final adapters = provider.adapters.keys.toList()..sort();
    final soft = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        key: const Key('booking_sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Réserver — ${widget.poi.name}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'La réservation est créée en attente : elle ne devient ferme '
            'qu’après votre confirmation explicite.',
            style: soft,
          ),
          const SizedBox(height: 12),
          if (_loading && adapters.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!_loading && adapters.isEmpty && provider.error != null) ...[
            Text('Impossible de charger les prestataires',
                style: TextStyle(color: scheme.error)),
            TextButton(
              onPressed: _loadAdapters,
              child: const Text('Réessayer'),
            ),
          ] else if (!_loading && adapters.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Aucun prestataire disponible pour le moment'),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in adapters)
                  ChoiceChip(
                    key: Key('booking_adapter_$type'),
                    label: Text(_adapterLabels[type] ?? type),
                    selected: _selected == type,
                    onSelected: (_) => setState(() {
                      if (_selected != type) {
                        // Different payload → the old key would be a 409 on
                        // the backend: start a new logical attempt.
                        _idempotencyKey = null;
                      }
                      _selected = type;
                    }),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('booking_create_button'),
            onPressed:
                (_selected == null || provider.isActing) ? null : _create,
            child:
                Text(provider.isActing ? 'Création…' : 'Créer la réservation'),
          ),
          if (provider.actionError != null) ...[
            const SizedBox(height: 8),
            Text(provider.actionError!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Creates the PENDING booking, opens the explicit consent dialog over the
  /// sheet, then closes the sheet once the consent step is resolved.
  Future<void> _create() async {
    final provider = context.read<BookingProvider>();
    // Lazy: generated on first tap, reused on retry (network/5xx keeps the
    // key so the backend replays — no duplicate on a flaky connection).
    _idempotencyKey ??= newIdempotencyKey();
    final created = await provider.createBooking(
      poiId: widget.poi.id,
      adapterType: _selected!,
      idempotencyKey: _idempotencyKey,
    );
    if (!mounted) return;
    if (created == null) {
      final status = provider.actionStatusCode;
      if (status == 409 || status == 422) {
        // The key itself was refused: it can never succeed as-is.
        setState(() => _idempotencyKey = null);
      }
      // Network/5xx: the key is kept — the retry replays the same request.
      return;
    }
    // Success: the attempt is over; the next sheet starts with a fresh key.
    _idempotencyKey = null;
    await showConsentDialog(context, created);
    if (mounted) Navigator.of(context).pop();
  }
}
