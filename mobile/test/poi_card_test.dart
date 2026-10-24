import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/l10n/app_localizations_fr.dart';
import 'package:discover_ai/models/poi.dart';
import 'package:discover_ai/widgets/poi_card.dart';

void main() {
  testWidgets(
      'POICard FR avec find.textContaining(AppLocalizationsFr().poiDurationMinutes(90))',
      (tester) async {
    final poi = POI(
      id: 'p-2',
      slug: 'notre-dame-dafrique',
      tenantId: 't-1',
      name: "Notre-Dame d'Afrique",
      city: 'Algiers',
      category: 'culture',
      durationMinutes: 90,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: Scaffold(body: POICard(poi: poi)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Notre-Dame d'Afrique"), findsOneWidget);
    expect(
      find.textContaining(AppLocalizationsFr().poiDurationMinutes(90)),
      findsOneWidget,
    );
  });
}
