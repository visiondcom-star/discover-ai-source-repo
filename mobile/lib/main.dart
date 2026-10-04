import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// SingleChildWidget (type de `MultiProvider.providers`) n'est pas réexporté par
// provider.dart : il vient de package:nested, réexposé ici par provider.
import 'package:provider/single_child_widget.dart';

import 'app.dart';
import 'providers/admin_categories_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/booking_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/poi_provider.dart';
import 'providers/promotion_provider.dart';
import 'providers/research_collection_provider.dart';
import 'providers/research_provider.dart';
import 'providers/tenant_provider.dart';
import 'providers/trip_provider.dart';
import 'services/api_service.dart';

/// Providers fournis à l'arbre applicatif.
///
/// Extrait de [main] pour que les tests puissent vérifier qu'un provider
/// réellement consommé par un écran y figure. C'est la garantie qui manquait :
/// `AdminResearchScreen` fait `context.watch<ResearchProvider>()` et est
/// atteignable depuis le Profil (« Recherche IA — destination »). Tant que
/// l'entrée n'était pas enregistrée ici, le premier tap levait une
/// ProviderNotFoundException sur un appareil réel — alors que les tests
/// d'écran passaient, puisqu'ils injectent leur propre provider.
List<SingleChildWidget> appProviders() => [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(
        create: (_) => TenantProvider()
          ..loadTenant()
          ..loadCategories(),
      ),
      ChangeNotifierProvider(create: (_) => POIProvider()),
      ChangeNotifierProvider(create: (_) => TripProvider()),
      ChangeNotifierProvider(create: (_) => ChatProvider()),
      ChangeNotifierProvider(create: (_) => BookingProvider()),
      ChangeNotifierProvider(create: (_) => PromotionProvider()),
      // AdminCategoriesProvider est déclaré AVANT ResearchProvider : le
      // `onJobDone` de celui-ci fait `ctx.read<AdminCategoriesProvider>()`, et
      // le `ctx` fourni à `create` ne voit que les providers déjà déclarés
      // au-dessus. Dans l'ordre inverse, le callback levait
      // ProviderNotFoundException au premier job terminé — invisible en CI, car
      // les tests d'écran injectent leurs propres providers.
      ChangeNotifierProvider(
        create: (ctx) => AdminCategoriesProvider(
          ApiService(),
          onChanged: () => ctx.read<TenantProvider>().loadCategories(),
        ),
      ),
      // ResearchProvider(ApiService()) : l'API est passée explicitement, ce
      // provider ne prenant pas de paramètre nommé avec défaut comme les
      // autres (ChatProvider({ChatApi? chatApi}), etc.).
      //
      // onJobDone recharge les deux catalogues touchés par un run : le
      // catalogue voyageur (une catégorie peut passer à `active` si
      // RESEARCH_AUTO_PUBLISH est actif) et la file de validation (des
      // propositions `proposed` viennent d'apparaître). Sans cela, l'admin
      // devait represser « Actualiser » pour voir ce que le run venait de
      // produire. Le rechargement est branché ici, au niveau de
      // l'application : l'écran admin affiche, il ne décide pas de quand les
      // données changent.
      ChangeNotifierProvider(
        create: (ctx) => ResearchProvider(
          ApiService(),
          onJobDone: () {
            ctx.read<TenantProvider>().loadCategories();
            ctx.read<AdminCategoriesProvider>().load();
          },
        ),
      ),
      ChangeNotifierProvider(
        create: (ctx) => ResearchCollectionProvider(
          ApiService(),
          // Le serveur a enchaîné une analyse : ResearchProvider prend le
          // relais, même si l'écran de collecte est fermé.
          onPipelineChained: (tenantId, jobId) => ctx
              .read<ResearchProvider>()
              .resumeTracking(tenantId: tenantId, jobId: jobId),
        ),
      ),
    ];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: appProviders(),
      child: const DiscoverAIApp(),
    ),
  );
}
