import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/poi_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  @override
  void initState() {
    super.initState();
    context.read<POIProvider>().loadPOIs();
  }

  @override
  Widget build(BuildContext context) {
    final pois = context.watch<POIProvider>().pois;
    final validPois = pois.where((p) => p.latitude != null && p.longitude != null).toList();

    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(36.7, 3.0),
        initialZoom: 6,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c'],
        ),
        MarkerLayer(
          markers: validPois.map((poi) => Marker(
            point: LatLng(poi.latitude!, poi.longitude!),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  builder: (_) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(poi.name, style: Theme.of(context).textTheme.titleLarge),
                        Text('${poi.city} • ${poi.category}'),
                        if (poi.description != null) Text(poi.description!),
                      ],
                    ),
                  ),
                );
              },
              child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
            ),
          )).toList(),
        ),
      ],
    );
  }
}
