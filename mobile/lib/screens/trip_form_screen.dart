import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../providers/tenant_provider.dart';
import '../providers/trip_provider.dart';
import 'trip_timeline_screen.dart';

/// Trip generation form — the mobile counterpart of the web trip form:
/// interests (multi-select), number of days, budget level.
///
/// The interest catalog comes from [TenantProvider.categories]
/// (fetched from GET /tenants/categories/), falling back to
/// [AppConfig.tripInterestOptions] when the provider hasn't loaded yet —
/// never hardcoded market content (CLAUDE.md principle 1).
class TripFormScreen extends StatefulWidget {
  const TripFormScreen({super.key, this.initialInterests = const <String>{}});

  /// Interests pre-selected on open (home travel-type grid shortcut).
  /// Values that are not in the catalog actually displayed are ignored, so a
  /// stale or unknown slug cannot reach `generate()`.
  final Set<String> initialInterests;

  @override
  State<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends State<TripFormScreen> {
  int _numDays = 3;
  String _budgetLevel = AppConfig.budgetLevels.first;

  /// Slugs the form is actually offering, from the dynamic tenant catalog and
  /// falling back to the compile-time list while it is still loading.
  ///
  /// Single source of truth for both the visible chips and the validation of
  /// pre-selected interests.
  List<String> _visibleCatalog(BuildContext context) {
    final categories = context.watch<TenantProvider?>()?.categories ?? const [];
    return categories.isNotEmpty
        ? categories.map((c) => c.slug).toList(growable: false)
        : AppConfig.tripInterestOptions;
  }

  /// Anti-invalid-value filter on the pre-selected interests, validated against
  /// the catalog this form displays.
  ///
  /// Validating against [AppConfig.tripInterestOptions] instead was wrong: the
  /// home travel-type grid hands over a slug read from the *dynamic* catalog, so
  /// a category published after the app shipped (`oasis_tam`, say) rendered as a
  /// selectable chip but was silently dropped from the initial selection — the
  /// shortcut from Accueil appeared to do nothing. Only this form knows which
  /// catalog it is showing, so the filter has to live here.
  Set<String> _initialSelection(List<String> catalog) =>
      widget.initialInterests.where(catalog.contains).toSet();

  /// Interests the user has selected, seeded from [TripFormScreen.initialInterests]
  /// and kept in sync with the displayed catalog.
  ///
  /// Held as state rather than a `late final` field because the catalog is
  /// fetched: the form is usually built before it has arrived, and a value
  /// dropped on that first (fallback) pass must be recoverable once the real
  /// catalog lands. [_syncWithCatalog] re-applies the pending request on every
  /// build instead of validating once against whatever happened to be loaded.
  /// Mutable on purpose: the chips add/remove from this set. A `const {}`
  /// would throw `UnsupportedError` on the first tap.
  Set<String> _selectedInterests = <String>{};

  /// The selection as requested by the caller, kept until the catalog that will
  /// display it is known.
  late Set<String> _requestedInterests = widget.initialInterests.toSet();

  /// Reconciles the requested selection against [catalog] the first time the
  /// catalog is available, then keeps the user's own toggles authoritative.
  void _syncWithCatalog(List<String> catalog) {
    if (_requestedInterests.isEmpty) return;
    final accepted = _initialSelection(catalog);
    if (accepted.isEmpty && _requestedInterests.isNotEmpty) {
      // Catalog still on the compile-time fallback, or nothing matched yet.
      return;
    }
    _requestedInterests = const {};
    if (_selectedInterests.isEmpty) _selectedInterests = accepted;
  }

  Future<void> _submit() async {
    if (_selectedInterests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pick at least one interest.',
            key: Key('trip_form_validation')),
      ));
      return;
    }
    final trips = context.read<TripProvider>();
    final trip = await trips.generate(
      interests: _selectedInterests.toList(),
      budgetLevel: _budgetLevel,
      numDays: _numDays,
    );
    if (!mounted) return;
    if (trip == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Trip generation failed: ${trips.error}',
            key: const Key('trip_error')),
      ));
      trips.clearError();
      return;
    }
    // Replace the form so Back from the timeline returns to the POI list.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const TripTimelineScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trips = context.watch<TripProvider>();
    final tripInterestOptions = _visibleCatalog(context);
    _syncWithCatalog(tripInterestOptions);
    return Scaffold(
      appBar: AppBar(title: const Text('Plan a trip')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Interests', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final interest in tripInterestOptions)
                  FilterChip(
                    key: Key('interest_chip_$interest'),
                    label: Text(interest),
                    selected: _selectedInterests.contains(interest),
                    onSelected: (selected) => setState(() => selected
                        ? _selectedInterests.add(interest)
                        : _selectedInterests.remove(interest)),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Number of days',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              key: const Key('days_slider'),
              min: 1,
              max: AppConfig.maxTripDays.toDouble(),
              divisions: AppConfig.maxTripDays - 1,
              label: '$_numDays day(s)',
              value: _numDays.toDouble(),
              onChanged: (v) => setState(() => _numDays = v.round()),
            ),
            Center(
                child: Text('$_numDays day(s)', key: const Key('days_value'))),
            const SizedBox(height: 24),
            Text('Budget level',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              key: const Key('budget_selector'),
              segments: [
                for (final level in AppConfig.budgetLevels)
                  ButtonSegment(value: level, label: Text(level)),
              ],
              selected: {_budgetLevel},
              onSelectionChanged: (selection) =>
                  setState(() => _budgetLevel = selection.first),
            ),
            const SizedBox(height: 32),
            FilledButton(
              key: const Key('generate_trip_button'),
              onPressed: trips.isGenerating ? null : _submit,
              child: trips.isGenerating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Generate itinerary'),
            ),
          ],
        ),
      ),
    );
  }
}
