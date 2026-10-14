import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/partner_bookings_provider.dart';
import 'package:discover_ai/screens/partner_bookings_screen.dart';
import 'package:discover_ai/screens/profile_screen.dart';
import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fakes.dart';

/// Widget tests for the Espace partenaire queue and its Profil entry point.
void main() {
  /// Boots the partner screen with an injected [FakePartnerApi], in French
  /// (the tenant default), so migrated UI strings keep their FR assertions.
  Future<FakePartnerApi> pumpScreen(
    WidgetTester tester, {
    List<Map<String, dynamic>>? bookings,
    ApiException? listError,
  }) async {
    final api = FakePartnerApi(bookings: bookings, listError: listError);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PartnerBookingsProvider(partnerApi: api),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('fr'),
          home: const PartnerBookingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  /// Boots the partner screen pinned to [locale] with a failing [listError],
  /// to verify the localized error text.
  Future<void> pumpScreenWithLocale(
    WidgetTester tester, {
    required Locale locale,
    ApiException? listError,
  }) async {
    final api = FakePartnerApi(listError: listError);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PartnerBookingsProvider(partnerApi: api),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: const PartnerBookingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('queue shows name, traveller, date, guests, notes',
      (tester) async {
    await pumpScreen(tester, bookings: [
      samplePartnerBookingJson(
        id: 'b-1',
        poiName: 'Dar Azef',
        travellerName: 'Sofia',
        details: <String, dynamic>{
          'date': '2026-09-15',
          'guests': 2,
          'notes': 'Table près de la fenêtre.',
        },
      ),
    ]);

    expect(find.text('Espace partenaire'), findsOneWidget);
    expect(find.byKey(const Key('partner_card_b-1')), findsOneWidget);
    expect(find.text('Dar Azef'), findsOneWidget);
    expect(find.text('Voyageur : Sofia'), findsOneWidget);
    expect(find.textContaining('Date : 2026-09-15'), findsOneWidget);
    expect(find.textContaining('Personnes : 2'), findsOneWidget);
    expect(find.text('Table près de la fenêtre.'), findsOneWidget);
    expect(find.byKey(const Key('partner_confirm_b-1')), findsOneWidget);
    expect(find.byKey(const Key('partner_decline_b-1')), findsOneWidget);
  });

  testWidgets('a full 50-item queue shows the limit notice', (tester) async {
    // The backend serves a default page of 50 (`limit=50`). When the queue is
    // exactly at that limit the screen must say so, since pagination is out of
    // scope — it never silently truncates.
    await pumpScreen(tester, bookings: [
      for (var i = 0; i < 50; i++) samplePartnerBookingJson(id: 'b-$i'),
    ]);

    // The notice is the last item of a lazily-built list: scroll it into view.
    await tester.scrollUntilVisible(
      find.byKey(const Key('partner_limit_notice')),
      200,
    );
    expect(
      find.text('Seules les 50 premières demandes sont affichées.'),
      findsOneWidget,
    );
  });

  testWidgets('a shorter queue shows no limit notice', (tester) async {
    await pumpScreen(tester, bookings: [
      for (var i = 0; i < 49; i++) samplePartnerBookingJson(id: 'b-$i'),
    ]);

    expect(find.byKey(const Key('partner_limit_notice')), findsNothing);
    expect(
      find.text('Seules les 50 premières demandes sont affichées.'),
      findsNothing,
    );
  });

  testWidgets('null traveller shows the neutral placeholder', (tester) async {
    await pumpScreen(tester, bookings: [
      samplePartnerBookingJson(id: 'b-1', travellerName: null),
    ]);
    expect(find.text('Voyageur : Voyageur'), findsOneWidget);
  });

  testWidgets('confirm flow: dialog → note → request leaves the queue',
      (tester) async {
    final api = await pumpScreen(tester, bookings: [
      samplePartnerBookingJson(id: 'b-1'),
      samplePartnerBookingJson(id: 'b-2'),
    ]);

    await tester.tap(find.byKey(const Key('partner_confirm_b-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('partner_note_dialog')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('partner_note_field')), 'À 20h');
    await tester.tap(find.byKey(const Key('partner_note_confirm')));
    await tester.pumpAndSettle();

    expect(api.respondCalls, 1);
    expect(api.lastRespondDecision, 'confirm');
    expect(api.lastRespondNote, 'À 20h');
    expect(find.byKey(const Key('partner_confirmed_snackbar')), findsOneWidget);
    // b-1 removed; b-2 still queued.
    expect(find.byKey(const Key('partner_card_b-1')), findsNothing);
    expect(find.byKey(const Key('partner_card_b-2')), findsOneWidget);
  });

  testWidgets('decline flow: dialog with a note, request leaves the queue',
      (tester) async {
    final api = await pumpScreen(tester, bookings: [
      samplePartnerBookingJson(id: 'b-1'),
    ]);

    await tester.tap(find.byKey(const Key('partner_decline_b-1')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('partner_note_field')), 'Complet');
    await tester.tap(find.byKey(const Key('partner_note_confirm')));
    await tester.pumpAndSettle();

    expect(api.respondCalls, 1);
    expect(api.lastRespondDecision, 'decline');
    expect(api.lastRespondNote, 'Complet');
    expect(find.byKey(const Key('partner_declined_snackbar')), findsOneWidget);
    expect(find.byKey(const Key('partner_empty')), findsOneWidget);
  });

  testWidgets('dismissing the dialog sends nothing', (tester) async {
    final api = await pumpScreen(tester, bookings: [
      samplePartnerBookingJson(id: 'b-1'),
    ]);

    await tester.tap(find.byKey(const Key('partner_confirm_b-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(api.respondCalls, 0);
    expect(find.byKey(const Key('partner_card_b-1')), findsOneWidget);
  });

  testWidgets('empty queue shows the explicit empty state', (tester) async {
    await pumpScreen(tester, bookings: []);
    expect(find.byKey(const Key('partner_empty')), findsOneWidget);
    expect(find.text('Aucune demande à traiter'), findsOneWidget);
  });

  testWidgets('error state + Réessayer reloads the queue', (tester) async {
    final api = FakePartnerApi(listError: ApiException(500, '{}'));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PartnerBookingsProvider(partnerApi: api),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PartnerBookingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('partner_error')), findsOneWidget);
    final callsBefore = api.listCalls;
    api.listError = null; // retry succeeds
    await tester.tap(find.byKey(const Key('partner_retry')));
    await tester.pumpAndSettle();

    expect(api.listCalls, callsBefore + 1);
    expect(find.byKey(const Key('partner_card_b-1')), findsOneWidget);
  });

  testWidgets('load error renders the FR text (default locale)',
      (tester) async {
    // 403 load → the screen shows the FR message from AppLocalizations.
    await pumpScreenWithLocale(tester,
        locale: const Locale('fr'), listError: ApiException(403, '{}'));

    expect(find.text('Vous n\'avez pas accès à l\'espace partenaire.'),
        findsOneWidget);
  });

  testWidgets('load error renders the EN text when locale is en',
      (tester) async {
    // 403 load → the screen shows the EN message from AppLocalizations.
    await pumpScreenWithLocale(tester,
        locale: const Locale('en'), listError: ApiException(403, '{}'));

    expect(find.text('You do not have access to the partner space.'),
        findsOneWidget);
  });

  testWidgets('pull-to-refresh reloads the queue', (tester) async {
    final api = await pumpScreen(tester, bookings: [
      samplePartnerBookingJson(id: 'b-1'),
    ]);
    final before = api.listCalls;
    await tester.fling(
        find.byKey(const Key('partner_refresh')), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(api.listCalls, before + 1);
  });

  testWidgets('failed refresh keeps the queue and shows an error snackbar',
      (tester) async {
    // A reload that fails while a queue is on screen must not blank it: the
    // list stays and the failure surfaces as `partner_refresh_error_snackbar`.
    final api = await pumpScreen(tester, bookings: [
      samplePartnerBookingJson(id: 'b-1'),
    ]);
    api.listError = ApiException(null, 'socket down');
    await tester.fling(
        find.byKey(const Key('partner_refresh')), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('partner_card_b-1')), findsOneWidget);
    expect(find.byKey(const Key('partner_refresh_error_snackbar')),
        findsOneWidget);
  });

  // ---- Profil entry point -------------------------------------------------

  testWidgets('partner sees the Espace partenaire entry', (tester) async {
    await pumpProfileWithRole(tester, isAdmin: false, isPartner: true);
    expect(find.byKey(const Key('partner_space_button')), findsOneWidget);
  });

  testWidgets('admin (no attachment) also sees the entry', (tester) async {
    await pumpProfileWithRole(tester, isAdmin: true, isPartner: false);
    expect(find.byKey(const Key('partner_space_button')), findsOneWidget);
  });

  testWidgets('plain traveller does not see the entry', (tester) async {
    await pumpProfileWithRole(tester, isAdmin: false, isPartner: false);
    expect(find.byKey(const Key('partner_space_button')), findsNothing);
  });
}

/// AuthApi whose `getMe` returns a traveller/partner/admin with the exact
/// `is_partner` / `is_admin` combination the Profil test needs.
class FakePartnerMeApi implements AuthApi {
  FakePartnerMeApi({this.isAdmin = false, this.isPartner = false});

  final bool isAdmin;
  final bool isPartner;

  @override
  void setToken(String token) {}

  @override
  Future<Map<String, dynamic>> getMe() async => {
        'id': 'u-1',
        'email': 'user@discoverai.dz',
        'full_name': 'Test User',
        'is_active': true,
        'is_admin': isAdmin,
        'is_partner': isPartner,
        'preferences': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      };

  @override
  Future<Map<String, dynamic>> login(String email, String password) async => {
        'access_token': 'jwt',
        'token_type': 'bearer',
        'expires_in': 1800,
      };

  @override
  Future<Map<String, dynamic>> register(String email, String password,
          {String? fullName}) async =>
      getMe();
}

/// Pumps Profil with an already-authenticated user of the given role.
Future<void> pumpProfileWithRole(
  WidgetTester tester, {
  required bool isAdmin,
  required bool isPartner,
}) async {
  final auth = AuthProvider(
    api: FakePartnerMeApi(isAdmin: isAdmin, isPartner: isPartner),
    tokenStore: InMemoryTokenStore(),
  );
  await auth.login('user@discoverai.dz', 'secret');
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ProfileScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
