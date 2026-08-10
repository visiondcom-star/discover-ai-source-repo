import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TripPlanScreen extends StatefulWidget {
  const TripPlanScreen({super.key});

  @override
  State<TripPlanScreen> createState() => _TripPlanScreenState();
}

class _TripPlanScreenState extends State<TripPlanScreen> {
  int _numDays = 3;
  String _budget = 'medium';
  String _style = 'balanced';
  String _group = 'solo';
  final List<String> _interests = [];
  bool _loading = false;

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      await ApiService().generateTrip(
        numDays: _numDays,
        budgetLevel: _budget,
        travelStyle: _style,
        groupType: _group,
        interests: _interests,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip generated successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan a Trip')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Number of days', style: TextStyle(fontWeight: FontWeight.bold)),
            Slider(
              value: _numDays.toDouble(),
              min: 1,
              max: 14,
              divisions: 13,
              label: '$_numDays days',
              onChanged: (v) => setState(() => _numDays = v.round()),
            ),
            const SizedBox(height: 16),
            const Text('Budget', style: TextStyle(fontWeight: FontWeight.bold)),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'low', label: Text('Low')),
                ButtonSegment(value: 'medium', label: Text('Medium')),
                ButtonSegment(value: 'high', label: Text('High')),
              ],
              selected: {_budget},
              onSelectionChanged: (s) => setState(() => _budget = s.first),
            ),
            const SizedBox(height: 16),
            const Text('Travel Style', style: TextStyle(fontWeight: FontWeight.bold)),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'relaxed', label: Text('Relaxed')),
                ButtonSegment(value: 'balanced', label: Text('Balanced')),
                ButtonSegment(value: 'intensive', label: Text('Intensive')),
              ],
              selected: {_style},
              onSelectionChanged: (s) => setState(() => _style = s.first),
            ),
            const SizedBox(height: 16),
            const Text('Group', style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButtonFormField<String>(
              initialValue: _group,
              items: ['solo', 'couple', 'family', 'friends']
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => _group = v!),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            const Text('Interests', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              children: ['historical', 'nature', 'culture', 'adventure', 'food']
                  .map((i) => FilterChip(
                    label: Text(i),
                    selected: _interests.contains(i),
                    onSelected: (sel) => setState(() {
                      sel ? _interests.add(i) : _interests.remove(i);
                    }),
                  ))
                  .toList(),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _generate,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Generate Itinerary'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
