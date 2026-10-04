// test/app_providers_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/main.dart';
import 'package:discover_ai/providers/research_provider.dart';

void main() {
  group('appProviders', () {
    testWidgets('expose ResearchProvider, requis par AdminResearchScreen',
        (tester) async {
      // AdminResearchScreen fait `context.watch<ResearchProvider>()` et est
      // atteignable depuis le Profil (« Recherche IA — destination »). Si
      // l'entrée disparaît de la liste, le premier tap lève une
      // ProviderNotFoundException sur un appareil réel — c'est exactement ce
      // qui se produisait. Les tests d'écran ne le voyaient pas : ils
      // injectent leur propre ResearchProvider.
      await tester.pumpWidget(
        MultiProvider(
          providers: appProviders(),
          child: const MaterialApp(home: SizedBox()),
        ),
      );

      final context = tester.element(find.byType(SizedBox));
      expect(
        Provider.of<ResearchProvider>(context, listen: false),
        isA<ResearchProvider>(),
      );
    });
  });
}