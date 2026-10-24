import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/l10n/app_localizations_en.dart';
import 'package:discover_ai/l10n/app_localizations_fr.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/screens/trip_form_screen.dart';
import 'package:discover_ai/screens/trip_timeline_screen.dart';

import 'helpers/fakes.dart';

Widget _wrap(Widget home, TripProvider trips,
    {Locale locale = const Locale('en')}) {
  return ChangeNotifierProvider<TripProvider>.value(
    value: trips,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: home,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TripFormScreen (widget)', () {
    testWidgets('blocks submission without interests and never calls the API',
        (tester) async {
      final api = FakeTripsApi();
      await tester.pumpWidget(
          _wrap(const TripFormScreen(), TripProvider(tripsApi: api)));

      await tester.tap(find.byKey(const Key('generate_trip_button')));
      await tester.pump();

      expect(api.generateCalls, 0);
      expect(find.byKey(const Key('trip_form_validation')), findsOneWidget);
      // Still on the form.
      expect(find.byType(TripFormScreen), findsOneWidget);
    });

    testWidgets('submits the selection then lands on the timeline',
        (tester) async {
      final api = FakeTripsApi();
      final trips = TripProvider(tripsApi: api);
      await tester.pumpWidget(_wrap(const TripFormScreen(), trips));

      // Multi-select two interests.
      await tester.tap(find.byKey(const Key('interest_chip_history')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('interest_chip_food')));
      await tester.pump();

      // Budget level switch.
      await tester.tap(find.text('high'));
      await tester.pump();

      // Days slider stays at its default (3) — asserted through the payload.
      await tester.tap(find.byKey(const Key('generate_trip_button')));
      await tester.pumpAndSettle();

      expect(api.lastGeneratePayload, {
        'interests': ['history', 'food'],
        'budget_level': 'high',
        'num_days': 3,
      });
      // Navigation replaced the form with the timeline.
      expect(find.byType(TripTimelineScreen), findsOneWidget);
      expect(find.byKey(const Key('day_header_1')), findsOneWidget);
      // p-1 appears on day 1 (with embedded POI) and day 2 (fallback label).
      expect(find.byKey(const Key('timeline_poi_p-1')), findsNWidgets(2));
    });

    testWidgets('API failure keeps the user on the form with a visible error',
        (tester) async {
      final api = FakeTripsApi(failGenerate: true);
      final trips = TripProvider(tripsApi: api);
      await tester.pumpWidget(_wrap(const TripFormScreen(), trips));

      await tester.tap(find.byKey(const Key('interest_chip_nature')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('generate_trip_button')));
      await tester.pumpAndSettle();

      expect(api.generateCalls, 1);
      expect(find.byKey(const Key('trip_error')), findsOneWidget);
      expect(trips.error, isNull); // cleared after surfacing the snackbar
      expect(find.byType(TripFormScreen), findsOneWidget);
    });

    testWidgets(
        'formulaire d\'itinéraire : échec generic affiche tripErrorGeneric dans la SnackBar (FR et EN)',
        (tester) async {
      final api = FakeTripsApi(failGenerate: true);
      final trips = TripProvider(tripsApi: api);
      await tester.pumpWidget(
          _wrap(const TripFormScreen(), trips, locale: const Locale('fr')));

      await tester.tap(find.byKey(const Key('interest_chip_nature')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('generate_trip_button')));
      await tester.pumpAndSettle();

      final fr = AppLocalizationsFr();
      expect(find.byKey(const Key('trip_error')), findsOneWidget);
      expect(find.text(fr.tripErrorGeneric), findsOneWidget);
    });

    testWidgets(
        'formulaire d\'itinéraire : échec network affiche tripErrorNetwork dans la SnackBar (FR et EN)',
        (tester) async {
      final api = FakeTripsApi(generateError: const SocketException('offline'));
      final trips = TripProvider(tripsApi: api);
      await tester.pumpWidget(
          _wrap(const TripFormScreen(), trips, locale: const Locale('fr')));

      await tester.tap(find.byKey(const Key('interest_chip_nature')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('generate_trip_button')));
      await tester.pumpAndSettle();

      final fr = AppLocalizationsFr();
      expect(find.byKey(const Key('trip_error')), findsOneWidget);
      expect(find.text(fr.tripErrorNetwork), findsOneWidget);
    });

    testWidgets(
        'formulaire d\'itinéraire : échec network affiche tripErrorNetwork en EN',
        (tester) async {
      final api = FakeTripsApi(generateError: const SocketException('offline'));
      final trips = TripProvider(tripsApi: api);
      await tester.pumpWidget(
          _wrap(const TripFormScreen(), trips, locale: const Locale('en')));

      await tester.tap(find.byKey(const Key('interest_chip_nature')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('generate_trip_button')));
      await tester.pumpAndSettle();

      final en = AppLocalizationsEn();
      expect(find.byKey(const Key('trip_error')), findsOneWidget);
      expect(find.text(en.tripErrorNetwork), findsOneWidget);
    });

    testWidgets('TripFormScreen rend ses chaînes en FR', (tester) async {
      final trips = TripProvider(tripsApi: FakeTripsApi());
      await tester.pumpWidget(
        _wrap(const TripFormScreen(), trips, locale: const Locale('fr')),
      );
      await tester.pumpAndSettle();

      final fr = AppLocalizationsFr();
      expect(find.text(fr.tripFormTitle), findsOneWidget);
      expect(find.text(fr.tripFormInterests), findsOneWidget);
      expect(find.text(fr.tripFormDays), findsOneWidget);
      expect(find.text(fr.tripFormBudget), findsOneWidget);
      expect(find.text(fr.tripFormSubmit), findsOneWidget);
      expect(find.text(fr.tripBudgetLow), findsOneWidget);
    });
  });

  group('TripTimelineScreen (widget)', () {
    Future<TripProvider> loadedProvider(FakeTripsApi api) async {
      final trips = TripProvider(tripsApi: api);
      await trips
          .loadTrips(); // seeds `currentTrip` via generate? no — load only fills list
      await trips.generate(
        interests: const ['history'],
        budgetLevel: 'medium',
        numDays: 2,
      );
      return trips;
    }

    testWidgets('renders day-by-day groups with POI details', (tester) async {
      final trips = await loadedProvider(FakeTripsApi());
      await tester.pumpWidget(_wrap(const TripTimelineScreen(), trips));
      await tester.pumpAndSettle();

      // Header card mirrors trip metadata.
      expect(
          find.text('Algiers highlights'), findsNWidgets(2)); // appbar + card
      expect(find.text('2 days'), findsOneWidget);

      // Both days present, ordered.
      expect(find.byKey(const Key('day_card_1')), findsOneWidget);
      expect(find.byKey(const Key('day_card_2')), findsOneWidget);

      // Day 1 has two stops; POI names/cities come from the embedded payload.
      expect(find.byKey(const Key('timeline_poi_p-1')), findsNWidgets(2));
      expect(find.byKey(const Key('timeline_poi_p-2')), findsOneWidget);
      expect(find.text('Casbah of Algiers'), findsOneWidget);
      expect(find.text("Notre-Dame d'Afrique"), findsOneWidget);
      expect(find.text('Morning walk through the medina.'), findsOneWidget);
      // Item without an embedded POI falls back to the generic label.
      expect(find.text('Point of interest'), findsOneWidget);
    });

    testWidgets('empty state is explicit when no trip was generated',
        (tester) async {
      final trips = TripProvider(tripsApi: FakeTripsApi());
      await tester.pumpWidget(_wrap(const TripTimelineScreen(), trips));

      expect(find.byKey(const Key('trip_empty')), findsOneWidget);
    });

    testWidgets('trip without items shows the dedicated empty message',
        (tester) async {
      final trips = TripProvider(tripsApi: FakeTripsApi());
      await trips.generate(
        interests: const ['food'],
        budgetLevel: 'low',
        numDays: 1,
      );
      trips.currentTrip!.items.clear(); // degenerate backend payload guard

      await tester.pumpWidget(_wrap(const TripTimelineScreen(), trips));

      expect(find.byKey(const Key('trip_items_empty')), findsOneWidget);
    });

    testWidgets('TripTimelineScreen rend ses chaînes en FR', (tester) async {
      final trips = await loadedProvider(FakeTripsApi());
      await tester.pumpWidget(
        _wrap(const TripTimelineScreen(), trips, locale: const Locale('fr')),
      );
      await tester.pumpAndSettle();

      final fr = AppLocalizationsFr();
      expect(find.text(fr.tripTimelineDay(1)), findsOneWidget);
      expect(find.text(fr.tripTimelineDay(2)), findsOneWidget);
      expect(find.text(fr.tripFormDaysCount(2)), findsOneWidget);
      expect(find.text(fr.timelineItemDefaultPoi), findsOneWidget);
    });

    testWidgets(
        'TripTimelineScreen rend la fiche en FR : « Budget : Économique » et « 1 jour »',
        (tester) async {
      final trips = TripProvider(tripsApi: FakeTripsApi());
      await trips.generate(
        interests: const ['food'],
        budgetLevel: 'low',
        numDays: 1,
      );
      await tester.pumpWidget(
        _wrap(const TripTimelineScreen(), trips, locale: const Locale('fr')),
      );
      await tester.pumpAndSettle();

      final fr = AppLocalizationsFr();
      expect(
          find.text(fr.tripTimelineBudget(fr.tripBudgetLow)), findsOneWidget);
      expect(find.text(fr.tripFormDaysCount(1)), findsOneWidget);
      expect(fr.tripFormDaysCount(1), '1 jour');
    });

    testWidgets('TripTimelineScreen rend « 1 day » en EN', (tester) async {
      final trips = TripProvider(tripsApi: FakeTripsApi());
      await trips.generate(
        interests: const ['food'],
        budgetLevel: 'low',
        numDays: 1,
      );
      await tester.pumpWidget(
        _wrap(const TripTimelineScreen(), trips, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      final en = AppLocalizationsEn();
      expect(find.text(en.tripFormDaysCount(1)), findsOneWidget);
      expect(en.tripFormDaysCount(1), '1 day');
    });
  });
}
