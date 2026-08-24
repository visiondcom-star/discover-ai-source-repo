import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../providers/trip_provider.dart';
import 'trip_timeline_screen.dart';

/// Trip generation form — the mobile counterpart of the web trip form:
/// interests (multi-select), number of days, budget level.
///
/// The interest catalog comes from [AppConfig] (`--dart-define`), never
/// hardcoded market content (CLAUDE.md principle 1).
class TripFormScreen extends StatefulWidget {
  const TripFormScreen({super.key});

  @override
  State<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends State<TripFormScreen> {
  final Set<String> _selectedInterests = <String>{};
  int _numDays = 3;
  String _budgetLevel = AppConfig.budgetLevels.first;

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
        content:
            Text('Trip generation failed: ${trips.error}', key: const Key('trip_error')),
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
                for (final interest in AppConfig.tripInterestOptions)
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
            Center(child: Text('$_numDays day(s)', key: const Key('days_value'))),
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
