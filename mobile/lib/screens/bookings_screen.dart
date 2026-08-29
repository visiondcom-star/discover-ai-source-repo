import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/booking.dart';
import '../models/poi.dart';
import '../providers/booking_provider.dart';
import '../providers/poi_provider.dart';

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
      context.read<BookingProvider>().loadBookings();
    });
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
                style: Theme.of(context).textTheme.bodySmall
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

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.poiName});

  final Booking booking;
  final String poiName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.read<BookingProvider>();
    final pending = booking.status == 'pending';
    final confirmed = booking.status == 'confirmed';
    final cancelled = booking.status == 'cancelled';
    final statusColor = cancelled
        ? scheme.errorContainer
        : confirmed
            ? scheme.primaryContainer
            : scheme.secondaryContainer;
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
                    color: statusColor,
                    borderRadius: BorderRadius.circular(999)),
                child: Text(booking.status,
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ]),
            const SizedBox(height: 8),
            Text('Prestataire : ${booking.adapterType}',
                style: Theme.of(context).textTheme.bodySmall),
            if (booking.createdAt != null)
              Text(
                  '${booking.createdAt!.day}/${booking.createdAt!.month}/${booking.createdAt!.year}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (booking.price != null)
              Text('${booking.price} ${booking.currency}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (booking.externalId != null) ...[
              const SizedBox(height: 4),
              Text(booking.externalId!,
                  key: Key('booking_ref_${booking.id}'),
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: scheme.primary)),
            ],
            if ((pending && !booking.consentGiven) || confirmed) ...[
              const SizedBox(height: 12),
              Row(children: [
                if (pending && !booking.consentGiven) ...[
                  FilledButton(
                    key: Key('booking_consent_${booking.id}'),
                    onPressed: () => showConsentDialog(context, booking),
                    child: const Text('Confirmer'),
                  ),
                  const SizedBox(width: 8),
                ],
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
          const Text(
              'En confirmant, le Booking-Agent générera une référence '
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
Future<void> showBookingSheet(BuildContext context, POI poi) {
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
                    onSelected: (_) => setState(() => _selected = type),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('booking_create_button'),
            onPressed:
                (_selected == null || provider.isActing) ? null : _create,
            child: Text(
                provider.isActing ? 'Création…' : 'Créer la réservation'),
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
    final created = await provider.createBooking(
      poiId: widget.poi.id,
      adapterType: _selected!,
    );
    if (!mounted || created == null) return;
    await showConsentDialog(context, created);
    if (mounted) Navigator.of(context).pop();
  }
}
