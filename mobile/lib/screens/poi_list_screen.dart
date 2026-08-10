import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/poi_provider.dart';
import 'poi_detail_screen.dart';

class POIListScreen extends StatefulWidget {
  const POIListScreen({super.key});

  @override
  State<POIListScreen> createState() => _POIListScreenState();
}

class _POIListScreenState extends State<POIListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<POIProvider>().loadPOIs();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<POIProvider>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search POIs...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        provider.filter('');
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
            onChanged: provider.filter,
          ),
        ),
        Expanded(
          child: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : provider.error != null
                  ? Center(child: Text('Error: ${provider.error}'))
                  : ListView.builder(
                      itemCount: provider.pois.length,
                      itemBuilder: (context, index) {
                        final poi = provider.pois[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(poi.name[0]),
                          ),
                          title: Text(poi.name),
                          subtitle: Text('${poi.city} • ${poi.category} • ${poi.durationMinutes}min'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => POIDetailScreen(poi: poi)),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
