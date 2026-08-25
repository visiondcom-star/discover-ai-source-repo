import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/poi_provider.dart';
import '../widgets/poi_card.dart';
import 'poi_map_screen.dart';
import 'trip_form_screen.dart';
import 'chat_screen.dart';

class POIListScreen extends StatefulWidget {
  const POIListScreen({super.key});

  @override
  State<POIListScreen> createState() => _POIListScreenState();
}

class _POIListScreenState extends State<POIListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<POIProvider>().loadPOIs();
    });
  }

  Future<void> _refresh() => context.read<POIProvider>().loadPOIs();

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
          IconButton(
            key: const Key('open_chat_button'),
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Chat assistant',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChatScreen()),
            ),
          ),
          IconButton(
            key: const Key('logout_button'),
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => context.read<AuthProvider>().logout(),
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(pois),
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
      itemBuilder: (context, index) => POICard(poi: pois.items[index]),
    );
  }
}