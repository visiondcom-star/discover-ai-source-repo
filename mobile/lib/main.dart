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
import 'providers/locale_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/poi_provider.dart';
import 'providers/promotion_provider.dart';
import 'providers/research_collection_provider.dart';
import 'providers/research_provider.dart';
import 'providers/tenant_provider.dart';
import 'providers/trip_provider.dart';
import 'services/api_service.dart';
import 'user_scope.dart';

/// Providers globaux indépendants de l'utilisateur connecté.
List<SingleChildWidget> appProviders() => [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      // LocaleProvider early: DiscoverAIApp watches it for `MaterialApp.locale`
      // — it must sit above, not beside, the app widget.
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider(
        create: (_) => TenantProvider()
          ..loadTenant()
          ..loadCategories(),
      ),
      ChangeNotifierProvider(create: (_) => POIProvider()),
      ChangeNotifierProvider(create: (_) => PromotionProvider()),
    ];

/// Providers instanciés par utilisateur (ou session anonyme), recréés
/// automatiquement à chaque changement d'utilisateur via [UserScope].
List<SingleChildWidget> userScopedProviders() => [
      ChangeNotifierProvider(create: (_) => TripProvider()),
      ChangeNotifierProvider(create: (_) => ChatProvider()),
      ChangeNotifierProvider(create: (_) => BookingProvider()),
      ChangeNotifierProvider(create: (_) => NotificationsProvider()),
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
      child: const UserScope(
        child: DiscoverAIApp(),
      ),
    ),
  );
}
