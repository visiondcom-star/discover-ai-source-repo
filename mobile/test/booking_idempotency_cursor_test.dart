import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/models/poi.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/screens/poi_detail_screen.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fakes.dart';

void main() {
  Future<(FakeBookingsApi, BookingProvider)> openSheetAfterFailure(
      WidgetTester tester) async {
    final api = FakeBookingsApi(bookings: [])
      ..createError = ApiException(500, '{"detail":"backend unavailable"}');
    final provider = BookingProvider(bookingsApi: api);
    final pois = POIProvider(poisApi: FakePoisApi());
    await pois.loadPOIs();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BookingProvider>.value(value: provider),
          ChangeNotifierProvider<POIProvider>.value(value: pois),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: PoiDetailScreen(poi: POI.fromJson(samplePoisJson[0])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('poi_detail_book_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('poi_detail_book_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking_adapter_hotel')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('booking_date_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking_date_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('booking_notes_field')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('booking_notes_field')), 'Table calme');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('booking_create_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking_create_button')));
    await tester.pumpAndSettle();
    expect(provider.actionError, isNotNull, reason: 'first attempt failed');
    return (api, provider);
  }

  Future<void> retry(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('booking_create_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking_create_button')));
    await tester.pumpAndSettle();
  }

  testWidgets('moving only the cursor in notes keeps the idempotency key',
      (tester) async {
    final (api, _) = await openSheetAfterFailure(tester);

    final notes = tester
        .widget<TextField>(find.byKey(const Key('booking_notes_field')))
        .controller!;
    notes.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    expect(notes.text, 'Table calme', reason: 'text untouched, cursor only');

    api.createError = null;
    await retry(tester);

    expect(api.idempotencyKeys, hasLength(2));
    expect(api.idempotencyKeys[1], api.idempotencyKeys[0],
        reason: 'a cursor move must not start a new logical attempt');
    expect(api.bookings, hasLength(1),
        reason: 'one backend reservation despite two POST attempts');
  });

  testWidgets('editing the notes text starts a new idempotency key',
      (tester) async {
    final (api, _) = await openSheetAfterFailure(tester);

    await tester.ensureVisible(find.byKey(const Key('booking_notes_field')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('booking_notes_field')), 'Table calme, terrasse');
    await tester.pumpAndSettle();

    api.createError = null;
    await retry(tester);

    expect(api.idempotencyKeys, hasLength(2));
    expect(api.idempotencyKeys[1], isNot(api.idempotencyKeys[0]),
        reason: 'a different body must start a new logical attempt');
  });
}
