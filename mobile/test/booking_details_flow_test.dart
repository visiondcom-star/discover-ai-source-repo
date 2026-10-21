import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/models/poi.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/screens/poi_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fakes.dart';

/// Booking sheet — date, guests and notes are collected and sent as
/// `booking_data`; the create action stays disabled until a date is chosen.
POI _poi(Map<String, dynamic> json) => POI.fromJson(json);

void main() {
  Future<POIProvider> loadedPois() async {
    final p = POIProvider(poisApi: FakePoisApi());
    await p.loadPOIs();
    return p;
  }

  Future<FakeBookingsApi> openSheet(WidgetTester tester) async {
    final api = FakeBookingsApi(bookings: []);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BookingProvider>.value(
              value: BookingProvider(bookingsApi: api)),
          ChangeNotifierProvider<POIProvider>.value(value: await loadedPois()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: PoiDetailScreen(poi: _poi(samplePoisJson[0])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('poi_detail_book_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('poi_detail_book_button')));
    await tester.pumpAndSettle();
    return api;
  }

  /// The sheet lives in a scrollable modal: bring a key into view first.
  Future<void> reveal(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  /// Picks today through the real picker and confirms.
  Future<void> pickToday(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('booking_date_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('confirm is disabled until a date is chosen', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('booking_adapter_hotel')));
    await tester.pumpAndSettle();

    final create = tester
        .widget<FilledButton>(find.byKey(const Key('booking_create_button')));
    expect(create.onPressed, isNull,
        reason: 'no date yet — the sheet must not allow a submission');

    await pickToday(tester);
    final after = tester
        .widget<FilledButton>(find.byKey(const Key('booking_create_button')));
    expect(after.onPressed, isNotNull, reason: 'date chosen — now enabled');
  });

  testWidgets('date + 3 guests + note → booking_data carries all three',
      (tester) async {
    final api = await openSheet(tester);

    await tester.tap(find.byKey(const Key('booking_adapter_hotel')));
    await tester.pumpAndSettle();
    await pickToday(tester);

    // 1 → 3
    await reveal(tester, 'booking_guests_plus');
    await tester.tap(find.byKey(const Key('booking_guests_plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking_guests_plus')));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('booking_notes_field')), 'Table calme');
    await tester.pumpAndSettle();

    await reveal(tester, 'booking_create_button');
    await tester.tap(find.byKey(const Key('booking_create_button')));
    await tester.pumpAndSettle();

    final data = api.lastBookingData!;
    expect(data['guests'], 3);
    expect(data['notes'], 'Table calme');
    expect(data['date'], isNotNull);
    expect(data.keys.toSet(), {'date', 'guests', 'notes'},
        reason: 'only the three whitelisted keys, never personal data');
  });

  testWidgets('empty notes → booking_data has no notes key', (tester) async {
    final api = await openSheet(tester);

    await tester.tap(find.byKey(const Key('booking_adapter_hotel')));
    await tester.pumpAndSettle();
    await pickToday(tester);
    await reveal(tester, 'booking_create_button');
    await tester.tap(find.byKey(const Key('booking_create_button')));
    await tester.pumpAndSettle();

    expect(api.lastBookingData!.containsKey('notes'), isFalse);
    expect(api.lastBookingData!['guests'], 1);
  });

  testWidgets('stepper is bounded 1..20 with disabled ends', (tester) async {
    await openSheet(tester);

    await reveal(tester, 'booking_guests_minus');
    final minus = tester
        .widget<IconButton>(find.byKey(const Key('booking_guests_minus')));
    expect(minus.onPressed, isNull, reason: 'cannot go below 1');
    expect(find.text('1'), findsOneWidget);

    for (var i = 0; i < 19; i++) {
      await tester.tap(find.byKey(const Key('booking_guests_plus')));
      await tester.pumpAndSettle();
    }
    expect(find.text('20'), findsOneWidget);
    final plus =
        tester.widget<IconButton>(find.byKey(const Key('booking_guests_plus')));
    expect(plus.onPressed, isNull, reason: 'cannot go above 20');
  });

  testWidgets('notes field shows the no-personal-data helper', (tester) async {
    await openSheet(tester);
    expect(
      find.text('Ne saisissez ni email ni numéro de téléphone.'),
      findsOneWidget,
    );
  });

  testWidgets('info_only POI shows no booking sheet and no fields',
      (tester) async {
    // An info_only POI has no Book button, so the sheet can never open —
    // and therefore none of its fields exist.
    final infoOnly = POI(
      id: 'p-9',
      slug: 'p-9',
      tenantId: 't-1',
      name: 'Info only place',
      city: 'Algiers',
      category: 'historical',
      durationMinutes: 30,
      priceRange: 'free',
      bookingMode: 'info_only',
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BookingProvider>.value(
              value: BookingProvider(bookingsApi: FakeBookingsApi())),
          ChangeNotifierProvider<POIProvider>.value(value: await loadedPois()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: PoiDetailScreen(poi: infoOnly),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('poi_detail_book_button')), findsNothing);
    expect(find.byKey(const Key('booking_sheet')), findsNothing);
    expect(find.byKey(const Key('booking_date_field')), findsNothing);
    expect(find.byKey(const Key('booking_notes_field')), findsNothing);
  });
}
