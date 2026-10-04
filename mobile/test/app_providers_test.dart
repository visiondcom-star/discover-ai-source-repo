// test/app_providers_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/main.dart';
import 'package:discover_ai/providers/admin_categories_provider.dart';
import 'package:discover_ai/providers/research_provider.dart';
import 'package:discover_ai/providers/tenant_provider.dart';

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

    testWidgets(
        'le onJobDone branché résout TenantProvider et AdminCategoriesProvider',
        (tester) async {
      // AdminCategoriesProvider est déclaré APRÈS ResearchProvider dans
      // appProviders(). Le `ctx.read<AdminCategoriesProvider>()` du callback ne
      // s'exécute qu'à la fin d'un job, donc l'ordre ne devrait pas importer —
      // mais c'est exactement le genre de lien qui casse en silence (exception
      // au premier job terminé, sur un appareil réel). On déclenche le callback
      // pour de vrai et on vérifie qu'aucun ProviderNotFound n'est levé.
      await tester.pumpWidget(
        MultiProvider(
          providers: appProviders(),
          child: const MaterialApp(home: SizedBox()),
        ),
      );

      final context = tester.element(find.byType(SizedBox));
      final research = Provider.of<ResearchProvider>(context, listen: false);

      expect(research.onJobDone, isNotNull,
          reason: 'le callback doit être branché dans appProviders()');
      expect(() => research.onJobDone!(), returnsNormally,
          reason: 'le callback doit résoudre les deux providers de l\'arbre');

      // Les deux providers sont bien présents dans l'arbre.
      expect(Provider.of<TenantProvider>(context, listen: false),
          isA<TenantProvider>());
      expect(Provider.of<AdminCategoriesProvider>(context, listen: false),
          isA<AdminCategoriesProvider>());
    });
  });
}