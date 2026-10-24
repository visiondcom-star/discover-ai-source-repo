import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/l10n/app_localizations_fr.dart';
import 'package:discover_ai/models/poi.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/tenant_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/screens/poi_detail_screen.dart';
import 'package:discover_ai/screens/trip_form_screen.dart';

import 'helpers/fakes.dart';

/// PoiDetailScreen — sections render only when the backend provides them,
/// and the CTA opens the real trip wizard.
void main() {
  POI poi({
    String? description,
    List<String> tags = const [],
    List<String> accessibility = const [],
    Map<String, dynamic> openingHours = const {},
    String? address,
    double? rating,
    bool verified = false,
    String bookingMode = 'request',
  }) =>
      POI(
        id: 'poi-1',
        slug: 'poi-1',
        tenantId: 't1',
        name: 'Casbah of Algiers',
        description: description,
        city: 'Algiers',
        category: 'historical',
        durationMinutes: 90,
        priceRange: 'free',
        address: address,
        tags: tags,
        accessibility: accessibility,
        openingHours: openingHours,
        isVerified: verified,
        averageRating: rating,
        reviewCount: rating == null ? 0 : 12,
        bookingMode: bookingMode,
      );

  Widget wrap(POI poi) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider(
              api: FakeAuthApi(),
              tokenStore: InMemoryTokenStore(),
            ),
          ),
          ChangeNotifierProvider<TripProvider>(create: (_) => TripProvider()),
          ChangeNotifierProvider<TenantProvider>(
            create: (_) => TenantProvider(tenantsApi: FakeTenantsApi()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: PoiDetailScreen(poi: poi),
        ),
      );

  /// Idem wrap(), mais avec la locale FR pour couvrir les chaînes migrées.
  Widget wrapFr(POI poi) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider(
              api: FakeAuthApi(),
              tokenStore: InMemoryTokenStore(),
            ),
          ),
          ChangeNotifierProvider<TripProvider>(create: (_) => TripProvider()),
          ChangeNotifierProvider<TenantProvider>(
            create: (_) => TenantProvider(tenantsApi: FakeTenantsApi()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('fr'),
          home: PoiDetailScreen(poi: poi),
        ),
      );

  testWidgets('renders every section the backend provides', (tester) async {
    await tester.pumpWidget(wrap(poi(
      description: 'A UNESCO-listed medina overlooking the bay.',
      tags: const ['unesco', 'medina'],
      accessibility: const ['wheelchair ramp'],
      openingHours: const {'Mon-Sun': '09:00-17:00'},
      address: 'Rue Djamaa el Djedid',
      rating: 4.5,
      verified: true,
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_screen')), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_name')), findsOneWidget);
    expect(find.text('Casbah of Algiers'), findsWidgets);
    expect(find.byKey(const Key('poi_detail_rating')), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('(12 reviews)'), findsOneWidget);
    expect(find.text('90 min'), findsOneWidget);
    expect(find.text('free'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_description')), findsOneWidget);
    expect(find.text('unesco'), findsOneWidget);
    expect(find.text('wheelchair ramp'), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_hours')), findsOneWidget);
    expect(find.text('09:00-17:00'), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_plan_button')), findsOneWidget);
  });

  testWidgets('omits sections the backend does not provide', (tester) async {
    await tester.pumpWidget(wrap(poi()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_screen')), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_name')), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_rating')), findsNothing);
    expect(find.byKey(const Key('poi_detail_description')), findsNothing);
    expect(find.byKey(const Key('poi_detail_images')), findsNothing);
    expect(find.byKey(const Key('poi_detail_tags')), findsNothing);
    expect(find.byKey(const Key('poi_detail_accessibility')), findsNothing);
    expect(find.byKey(const Key('poi_detail_hours')), findsNothing);
    expect(find.byKey(const Key('poi_detail_plan_button')), findsOneWidget);
  });

  testWidgets('Plan a visit opens the trip wizard', (tester) async {
    await tester.pumpWidget(wrap(poi()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('poi_detail_plan_button')));
    await tester.pumpAndSettle();

    expect(find.byType(TripFormScreen), findsOneWidget);
  });

  testWidgets('info_only POI hides the Book button and shows the notice',
      (tester) async {
    await tester.pumpWidget(wrap(poi(bookingMode: 'info_only')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_book_button')), findsNothing);
    expect(find.byKey(const Key('poi_detail_info_only')), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_booking_soon')), findsNothing);
  });

  testWidgets('unsupported mode POI hides Book and shows "coming soon"',
      (tester) async {
    await tester.pumpWidget(wrap(poi(bookingMode: 'deposit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_book_button')), findsNothing);
    expect(find.byKey(const Key('poi_detail_booking_soon')), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_info_only')), findsNothing);
  });

  testWidgets('default request POI keeps its Book button (non-regression)',
      (tester) async {
    await tester.pumpWidget(wrap(poi()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_book_button')), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_info_only')), findsNothing);
    expect(find.byKey(const Key('poi_detail_booking_soon')), findsNothing);
  });

  testWidgets('POI détail rend ses chaînes FR après la migration i18n',
      (tester) async {
    await tester.pumpWidget(wrapFr(poi(
      description: 'Une médina classée UNESCO surplombant la baie.',
      tags: const ['unesco', 'médina'],
      accessibility: const ['rampe pour fauteuil roulant'],
      openingHours: const {'Lun-Dim': '09:00-17:00'},
      address: 'Rue Djamaa el Djedid',
      rating: 4.5,
      verified: true,
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_screen')), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_name')), findsOneWidget);
    expect(find.text('Casbah of Algiers'), findsWidgets);
    expect(find.byKey(const Key('poi_detail_rating')), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('(12 avis)'), findsOneWidget);
    expect(find.text('Durée'), findsOneWidget);
    expect(find.text('90 min'), findsOneWidget);
    expect(find.text('Prix'), findsOneWidget);
    expect(find.text('free'), findsOneWidget);
    expect(find.text('Vérifié'), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_description')), findsOneWidget);
    expect(find.text('unesco'), findsOneWidget);
    expect(find.text('rampe pour fauteuil roulant'), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_hours')), findsOneWidget);
    expect(find.text('09:00-17:00'), findsOneWidget);
    expect(find.byKey(const Key('poi_detail_plan_button')), findsOneWidget);
    expect(find.text('Planifier une visite'), findsOneWidget);
  });

  testWidgets('POI détail FR pour pay_on_site', (tester) async {
    await tester.pumpWidget(wrapFr(poi(bookingMode: 'pay_on_site')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_book_button')), findsOneWidget);
    expect(find.text(AppLocalizationsFr().poiDetailBook), findsOneWidget);
    expect(
      find.byKey(const Key('poi_detail_booking_mode_pay_on_site')),
      findsOneWidget,
    );
    expect(find.text(AppLocalizationsFr().poiDetailPayOnSite), findsOneWidget);
  });

  testWidgets(
      'POI détail FR pour un mode autre que request (provider_confirmation)',
      (tester) async {
    await tester.pumpWidget(wrapFr(poi(bookingMode: 'manual_confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_book_button')), findsOneWidget);
    expect(find.text(AppLocalizationsFr().poiDetailBook), findsOneWidget);
    expect(
      find.byKey(const Key('poi_detail_booking_mode_manual_confirm')),
      findsOneWidget,
    );
    expect(
      find.text(AppLocalizationsFr().poiDetailProviderConfirmation),
      findsOneWidget,
    );
  });

  testWidgets('POI détail FR pour info_only', (tester) async {
    await tester.pumpWidget(wrapFr(poi(bookingMode: 'info_only')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_book_button')), findsNothing);
    expect(find.byKey(const Key('poi_detail_info_only')), findsOneWidget);
    expect(find.text(AppLocalizationsFr().poiDetailInfoOnly), findsOneWidget);
  });

  testWidgets('POI détail FR pour un mode non réservable (deposit)',
      (tester) async {
    await tester.pumpWidget(wrapFr(poi(bookingMode: 'deposit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_book_button')), findsNothing);
    expect(find.byKey(const Key('poi_detail_booking_soon')), findsOneWidget);
    expect(
        find.text(AppLocalizationsFr().poiDetailBookingSoon), findsOneWidget);
  });
}
