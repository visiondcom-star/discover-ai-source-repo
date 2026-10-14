import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/partner_bookings_provider.dart';
import 'package:discover_ai/screens/partner_bookings_screen.dart';
import 'package:discover_ai/screens/profile_screen.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fakes.dart';

/// Widget tests for the Espace partenaire queue and its Profil entry point.
void main() {
  /// Boots the partner screen with an injected [FakePartnerApi].
  Future<FakePartnerApi> pumpScreen(
    WidgetTester tester, {
    List<Map<String, dynamic>>? bookings,
    ApiException? listError,
  }) async {
    final api = FakePartnerApi(bookings: bookings, listError: listError);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PartnerBookingsProvider(partnerApi: api),
        child: const MaterialApp(home: PartnerBookingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return api;
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
        child: const MaterialApp(home: PartnerBookingsScreen()),
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
      child: const MaterialApp(home: ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}
