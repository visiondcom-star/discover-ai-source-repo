import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/providers/chat_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/screens/home_shell.dart';

import 'helpers/fakes.dart';

/// HomeShell tab navigation — all five tabs stay alive across switches
/// (IndexedStack) and expose the stable `tab_*` Keys used by the
/// integration suite for navigation.
void main() {
  Widget boot() => MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider(
              api: FakeAuthApi(),
              tokenStore: InMemoryTokenStore(),
            ),
          ),
          ChangeNotifierProvider<POIProvider>(
            create: (_) => POIProvider(poisApi: FakePoisApi()),
          ),
          ChangeNotifierProvider(create: (_) => TripProvider()),
          ChangeNotifierProvider(create: (_) => ChatProvider()),
          // IndexedStack mounts every tab eagerly → Réservations needs a
          // BookingProvider; the empty fake keeps boot deterministic
          // (bookings_empty) without any fake booking content.
          ChangeNotifierProvider<BookingProvider>(
            create: (_) =>
                BookingProvider(bookingsApi: FakeBookingsApi(bookings: [])),
          ),
        ],
        child: const MaterialApp(home: HomeShell()),
      );

  testWidgets('shell boots on Accueil with the greeting placeholder',
      (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tab_home')), findsOneWidget);
    expect(find.byKey(const Key('home_greeting')), findsOneWidget);
    // No login in this test → user is null → neutral fallback, never a
    // hardcoded market name.
    expect(find.text('Bonjour, voyageur 👋'), findsOneWidget);
  });

  testWidgets('every tab is reachable and keeps its content mounted',
      (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    // Explorer — FakePoisApi serves the two fixture POIs.
    await tester.tap(find.byKey(const Key('tab_explore')));
    await tester.pumpAndSettle();
    expect(find.text('Casbah of Algiers'), findsOneWidget);

    // Réservations — empty fake bookings → explicit empty state.
    await tester.tap(find.byKey(const Key('tab_bookings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookings_empty')), findsOneWidget);

    // Assistant — chat input ready with the empty state.
    await tester.tap(find.byKey(const Key('tab_assistant')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat_input')), findsOneWidget);
    expect(find.byKey(const Key('chat_empty')), findsOneWidget);

    // Profil — hosts the explicit logout action.
    await tester.tap(find.byKey(const Key('tab_profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logout_button')), findsOneWidget);

    // Back to Accueil — state preserved (IndexedStack).
    await tester.tap(find.byKey(const Key('tab_home')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home_greeting')), findsOneWidget);
  });

  testWidgets('travel-type card opens the wizard with the interest preselected',
      (tester) async {
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();

    // Home grid → wizard, interest chip already selected.
    await tester.tap(find.byKey(const Key('home_type_history')));
    await tester.pumpAndSettle();

    expect(tester.widget<FilterChip>(
      find.byKey(const Key('interest_chip_history')),
    ).selected, isTrue, reason: 'grid shortcut must preselect the interest');

    // Untouched catalog entries stay unselected.
    expect(tester.widget<FilterChip>(
      find.byKey(const Key('interest_chip_culture')),
    ).selected, isFalse);
  });
}
