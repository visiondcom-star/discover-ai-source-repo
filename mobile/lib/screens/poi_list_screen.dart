import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/poi_provider.dart';
import '../widgets/poi_card.dart';
import 'poi_detail_screen.dart';
import 'poi_map_screen.dart';
import 'trip_form_screen.dart';

/// Explorer tab of the HomeShell — the current tenant's POI list.
///
/// Chat and logout moved to their dedicated tabs (Assistant / Profil) with
/// the five-tab shell; the map stays one tap away via `toggle_map_button`.
class POIListScreen extends StatefulWidget {
  const POIListScreen({super.key});

  @override
  State<POIListScreen> createState() => _POIListScreenState();
}

class _POIListScreenState extends State<POIListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<POIProvider>().loadPOIs();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Pull-to-refresh re-applies the active search so the field and the list
  /// never diverge.
  Future<void> _refresh() {
    final pois = context.read<POIProvider>();
    final q = pois.searchQuery;
    return pois.loadPOIs(search: q.isEmpty ? null : q);
  }

  @override
  Widget build(BuildContext context) {
    final pois = context.watch<POIProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover AI'),
        actions: [
          IconButton(
            key: const Key('toggle_map_button'),
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Show map',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PoiMapScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('plan_trip_fab'),
        icon: const Icon(Icons.map_outlined),
        label: const Text('Plan a trip'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TripFormScreen()),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const Key('poi_search_field'),
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (value) =>
                  context.read<POIProvider>().updateSearch(value),
              onSubmitted: (value) {
                final q = value.trim();
                context
                    .read<POIProvider>()
                    .loadPOIs(search: q.isEmpty ? null : q);
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search places, cities…',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (_, value, __) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          key: const Key('poi_search_clear'),
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            context.read<POIProvider>().updateSearch('');
                          },
                        ),
                ),
              ),
            ),
          ),
          // Keep the previous list visible while a search round-trip is in
          // flight — a thin progress bar beats a flashing empty state.
          if (pois.isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _buildBody(pois),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(POIProvider pois) {
    if (pois.isLoading && pois.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pois.error != null && pois.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text('Error: ${pois.error}')),
          ),
        ],
      );
    }
    // Distinguish "the tenant has no places at all" from "nothing matches
    // this search" — different empty states, different guidance.
    if (pois.items.isEmpty && pois.searchQuery.isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Center(
            child: Column(
              children: [
                const Icon(Icons.search_off, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  'No results for “${pois.searchQuery}”.',
                  key: const Key('poi_search_empty'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (pois.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(
            child: Column(
              children: [
                Icon(Icons.explore_off, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('No places yet.', key: Key('poi_empty')),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: pois.items.length,
      itemBuilder: (context, index) {
        final poi = pois.items[index];
        return POICard(
          key: Key('poi_card_${poi.id}'),
          poi: poi,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PoiDetailScreen(poi: poi)),
          ),
        );
      },
    );
  }
}