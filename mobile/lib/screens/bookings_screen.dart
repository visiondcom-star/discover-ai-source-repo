import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/booking.dart';
import '../models/booking_details.dart';
import '../models/poi.dart';
import '../providers/booking_provider.dart';
import '../providers/poi_provider.dart';
import '../utils/idempotency.dart';

/// Booking tab — real consent-flow UI on the backend Booking-Agent
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
      appBar: AppBar(title: Text(AppLocalizations.of(context).bookingsTitle)),
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
      final loc = AppLocalizations.of(context);
      if (bookings.loadError != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                bookings.loadError == BookingLoadError.network
                    ? loc.bookingsLoadErrorNetwork
                    : loc.bookingsLoadErrorGeneric,
                style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: bookings.loadBookings,
                child: Text(loc.bookingsRetry),
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
            Text(loc.bookingsEmpty),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                loc.bookingsEmptyHint,
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

BookingStatusStyle styleFor(
  Booking booking,
  ColorScheme scheme,
  AppLocalizations loc,
) {
  if (booking.isPending) {
    return BookingStatusStyle(loc.bookingStatusPendingConsent, scheme.secondaryContainer);
  }
  if (booking.isAwaitingPartner) {
    return BookingStatusStyle(loc.bookingStatusAwaitingPartner, scheme.secondaryContainer);
  }
  if (booking.isConfirmed) {
    return BookingStatusStyle(booking.status, scheme.primaryContainer);
  }
  if (booking.isDeclined) {
    return BookingStatusStyle(loc.bookingStatusDeclined, scheme.errorContainer);
  }
  if (booking.isExpired) {
    return BookingStatusStyle(loc.bookingStatusExpired, scheme.errorContainer.withAlpha(150));
  }
  if (booking.isCancelled) {
    return BookingStatusStyle(booking.status, scheme.errorContainer);
  }
  // Unknown status: render the raw text, never crash.
  return BookingStatusStyle(booking.status, scheme.secondaryContainer);
}

/// Formats [d] with the active locale's medium-long date format
/// (e.g. « 2 nov. 2026 » in FR, « Nov 2, 2026 » in EN). Unknown values fall
/// back to the raw ISO day/month/year shape so a malformed date never
/// crashes the card.
String formatDate(BuildContext context, DateTime d) {
  final loc = AppLocalizations.of(context);
  try {
    return intl.DateFormat.yMMMd(loc.localeName).format(d);
  } catch (_) {
    return '${d.day}/${d.month}/${d.year}';
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
    final loc = AppLocalizations.of(context);
    final style = styleFor(booking, scheme, loc);
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
            Text(loc.bookingPartnerLabel(booking.adapterType),
                style: Theme.of(context).textTheme.bodySmall),
            if (booking.createdAt != null)
              Text(formatDate(context, booking.createdAt!),
                  style: Theme.of(context).textTheme.bodySmall),
            if (booking.price != null)
              Text(
                loc.bookingPrice(booking.price!, booking.currency),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (booking.isPending && booking.respondBy != null)
              Text(
                loc.bookingRespondBy(
                    formatDate(context, booking.respondBy!)),
                key: Key('booking_respond_by_${booking.id}'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            if (booking.isAwaitingPartner)
              Text(
                booking.respondBy != null
                    ? loc.bookingAwaitingPartnerBy(
                        formatDate(context, booking.respondBy!))
                    : loc.bookingAwaitingPartner,
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
                loc.bookingPartnerNote(booking.partnerNote!),
                key: Key('booking_partner_note_${booking.id}'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (booking.isExpired)
              Text(
                loc.bookingExpiredHint,
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
                    child: Text(loc.bookingConfirmAction),
                  ),
                  const SizedBox(width: 8),
                ],
                if (booking.canCancel)
                  TextButton(
                    key: Key('booking_cancel_${booking.id}'),
                    onPressed: provider.isActing
                        ? null
                        : () async {
                            await provider.cancelBooking(booking);
                            if (provider.cancelError != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  key: const Key(
                                      'booking_cancel_error_snackbar'),
                                  content: Text(
                                      _cancelErrorMessage(
                                          loc, provider.cancelError!)),
                                ),
                              );
                            }
                          },
                    child: Text(loc.bookingCancelAction),
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
  final loc = AppLocalizations.of(context);
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
      title: Text(loc.bookingConsentTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(poiName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(loc.bookingPartnerLabel(booking.adapterType)),
          if (booking.price != null)
            Text(loc.bookingPrice(booking.price!, booking.currency)),
          const SizedBox(height: 12),
          Text(booking.bookingMode == 'manual_confirm'
              ? loc.bookingConsentManualConfirm
              : loc.bookingConsentExternalRef),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('booking_consent_refuse'),
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await provider.giveConsent(booking, consent: false);
          },
          child: Text(loc.bookingRefuseAction),
        ),
        FilledButton(
          key: const Key('booking_consent_confirm'),
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            // The server response is used as-is: a manual_confirm consent
            // comes back as 'requested', never forced to 'confirmed'.
            final updated = await provider.giveConsent(booking, consent: true);
            if (updated != null &&
                updated.isAwaitingPartner &&
                context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  key: const Key('booking_requested_snackbar'),
                  content: Text(loc.bookingRequestedSnackbar),
                ),
              );
            }
          },
          child: Text(loc.bookingConfirmAction),
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
  String? _selected;
  bool _loading = false;

  /// Traveller details (date, people, notes) sent as `booking_data`. The date
  /// is mandatory; until one is picked, "Créer la réservation" stays disabled.
  DateTime? _date;
  int _guests = BookingDetails.kMinGuests;
  late final TextEditingController _notes = TextEditingController()
    ..addListener(_onDetailsChanged);

  /// Last notes text seen by [_onDetailsChanged]. The controller also notifies
  /// on cursor/selection moves, which do not change the request body.
  String _lastNotes = '';

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Any change to the details changes the request body: the previous
  /// idempotency key would be a 409 server-side, so a new attempt must mint a
  /// fresh one. Mirrors the adapter-switch rule.
  void _onDetailsChanged() {
    // Cursor/selection only: same body, same logical attempt — keep the key so
    // a retry after a network failure replays instead of duplicating.
    if (_notes.text == _lastNotes) return;
    _lastNotes = _notes.text;
    if (_idempotencyKey != null) setState(() => _idempotencyKey = null);
  }

  /// Builds the details to send, or null while the mandatory date is missing.
  BookingDetails? get _details => _date == null
      ? null
      : BookingDetails(date: _date!, guests: _guests, notes: _notes.text);

  /// Localized label for an adapter type, from the ARB (never hardcoded).
  String _adapterLabel(AppLocalizations loc, String type) {
    switch (type) {
      case 'hotel':
        return loc.bookingAdapterHotel;
      case 'restaurant':
        return loc.bookingAdapterRestaurant;
      case 'tour':
        return loc.bookingAdapterTour;
      case 'transport':
        return loc.bookingAdapterTransport;
      default:
        return type;
    }
  }

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
    final loc = AppLocalizations.of(context);
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
      child: SingleChildScrollView(
        child: Column(
          key: const Key('booking_sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.bookingSheetTitle(widget.poi.name),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              loc.bookingSheetPendingHint,
              style: soft,
            ),
            const SizedBox(height: 12),
            if (_loading && adapters.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!_loading &&
                adapters.isEmpty &&
                provider.loadError != null) ...[
              Text(loc.bookingAdaptersError,
                  style: TextStyle(color: scheme.error)),
              TextButton(
                onPressed: _loadAdapters,
                child: Text(loc.bookingsRetry),
              ),
            ] else if (!_loading && adapters.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(loc.bookingAdaptersEmpty),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in adapters)
                    ChoiceChip(
                      key: Key('booking_adapter_$type'),
                      label: Text(_adapterLabel(loc, type)),
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
            _DetailsFields(
              date: _date,
              guests: _guests,
              notesController: _notes,
              onPickDate: _pickDate,
              onGuestsChanged: _onGuestsChanged,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('booking_create_button'),
              // The date is mandatory: no date, no submission.
              onPressed:
                  (_selected == null || _date == null || provider.isActing)
                      ? null
                      : _create,
              child: Text(
                  provider.isActing ? loc.bookingCreatingAction : loc.bookingCreateAction),
            ),
            if (provider.actionError != null) ...[
              const SizedBox(height: 8),
              Text(_actionErrorMessage(loc, provider.actionError!)),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  /// A new guest count is a new body: drop any pending idempotency key.
  void _onGuestsChanged(int value) {
    setState(() {
      _guests = value;
      _idempotencyKey = null;
    });
  }

  /// Opens the date picker (bottom bound: today). A picked date is a content
  /// change, so any pending idempotency key is dropped — a fresh body needs a
  /// fresh key.
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: today,
      lastDate: DateTime(today.year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      _idempotencyKey = null;
    });
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
      details: _details,
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

  /// Maps a typed [BookingError] to its localized user-facing message.
  String _actionErrorMessage(AppLocalizations loc, BookingError error) {
    switch (error) {
      case BookingError.conflict:
        return loc.bookingErrorConflict;
      case BookingError.unavailable:
        return loc.bookingErrorUnavailable;
      case BookingError.network:
        return loc.bookingErrorNetwork;
      case BookingError.generic:
        return loc.bookingErrorGeneric;
    }
  }

}

/// Maps a typed [BookingCancelError] to its localized user-facing message.
String _cancelErrorMessage(AppLocalizations loc, BookingCancelError error) {
  switch (error) {
    case BookingCancelError.notCancellable:
      return loc.bookingCancelErrorNotCancellable;
    case BookingCancelError.network:
      return loc.bookingCancelErrorNetwork;
    case BookingCancelError.generic:
      return loc.bookingCancelErrorGeneric;
  }
}

/// Date, people and free-text notes collected by the booking sheet and sent
/// to the partner as `booking_data` (only `date`, `guests`, `notes` — never
/// personal data, hence the explicit helper line under the notes field).
///
/// Bounds and the 500-char ceiling come from [BookingDetails] so the UI and
/// the validation share one source of truth.
class _DetailsFields extends StatelessWidget {
  const _DetailsFields({
    required this.date,
    required this.guests,
    required this.notesController,
    required this.onPickDate,
    required this.onGuestsChanged,
  });

  final DateTime? date;
  final int guests;
  final TextEditingController notesController;
  final VoidCallback onPickDate;
  final ValueChanged<int> onGuestsChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          key: const Key('booking_date_field'),
          onPressed: onPickDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(
            date == null
                ? loc.bookingDatePick
                : loc.bookingDateLabel(formatDate(context, date!)),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text(loc.bookingGuests, style: Theme.of(context).textTheme.bodyLarge),
          const Spacer(),
          IconButton(
            key: const Key('booking_guests_minus'),
            onPressed: guests <= BookingDetails.kMinGuests
                ? null
                : () => onGuestsChanged(guests - 1),
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: loc.bookingRemoveGuest,
          ),
          Text('$guests',
              key: const Key('booking_guests_value'),
              style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            key: const Key('booking_guests_plus'),
            onPressed: guests >= BookingDetails.kMaxGuests
                ? null
                : () => onGuestsChanged(guests + 1),
            icon: const Icon(Icons.add_circle_outline),
            tooltip: loc.bookingAddGuest,
          ),
        ]),
        const SizedBox(height: 4),
        TextField(
          key: const Key('booking_notes_field'),
          controller: notesController,
          maxLines: 3,
          maxLength: BookingDetails.kMaxNotesLength,
          decoration: InputDecoration(
            labelText: loc.bookingNotesLabel,
            helperText: loc.bookingNotesHelper,
            helperStyle: TextStyle(color: scheme.onSurfaceVariant),
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
