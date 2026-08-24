import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/auth_provider.dart';
import 'providers/poi_provider.dart';
import 'providers/trip_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => POIProvider()),
        ChangeNotifierProvider(create: (_) => TripProvider()),
      ],
      child: const DiscoverAIApp(),
    ),
  );
}