import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/poi.dart';
import '../providers/poi_provider.dart';
import 'poi_detail_screen.dart';

/// Full-screen map of the current tenant's POIs — the mobile counterpart of
/// the web `Map.tsx`. Tiles come from OpenStreetMap; markers come from the
/// shared [POIProvider] (same data as the POI list — never re-fetched).
///
/// No country-specific default center is hardcoded: the camera is fitted to
/// the geolocated POIs; with none, an explicit empty state is shown instead
/// (the web Map.tsx hardcodes a fallback center — deliberately not mirrored).
class PoiMapScreen extends StatelessWidget {
  const PoiMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pois = context.watch<POIProvider>();
    final geolocated = pois.items
        .where((p) => p.latitude != null && p.longitude != null)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: geolocated.isEmpty
          ? const Center(
              child: Text('No geolocated places yet.',
                  key: Key('map_empty')),
            )
          : _PoiMapView(pois: geolocated),
    );
  }
}

class _PoiMapView extends StatelessWidget {
  const _PoiMapView({required this.pois});

  final List<POI> pois;

  /// Mobile equivalent of the web Leaflet Popup: name + city (plus category).
  void _showPoiSheet(BuildContext context, POI poi) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                poi.name,
                key: Key('poi_sheet_${poi.id}'),
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.place, size: 16),
                  const SizedBox(width: 4),
                  Text(poi.city),
                  const SizedBox(width: 12),
                  Text(poi.category,
                      style: Theme.of(sheetContext).textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                key: Key('poi_sheet_details_${poi.id}'),
                icon: const Icon(Icons.info_outline),
                label: const Text('View details'),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PoiDetailScreen(poi: poi),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        // Camera derived from the data — never a hardcoded market center.
        initialCameraFit: CameraFit.coordinates(
          coordinates:
              pois.map((p) => LatLng(p.latitude!, p.longitude!)).toList(),
          padding: const EdgeInsets.all(48),
        ),
      ),
      children: [
        TileLayer(
          // Same tile source as specified for the mobile increment.
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.discoverai.mobile',
        ),
        MarkerLayer(
          markers: [
            for (final poi in pois)
              Marker(
                point: LatLng(poi.latitude!, poi.longitude!),
                width: 40,
                height: 40,
                child: IconButton(
                  key: Key('poi_marker_${poi.id}'),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.location_on),
                  iconSize: 36,
                  color: Theme.of(context).colorScheme.primary,
                  tooltip: poi.name,
                  onPressed: () => _showPoiSheet(context, poi),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
