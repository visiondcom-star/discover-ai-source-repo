import 'dart:async';

import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/screens/poi_list_screen.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// PoisApi whose responses are held back until the test releases them.
/// Lets tests resolve fetches OUT OF ORDER and prove the provider's
/// sequence guard discards stale answers — untestable with canned fakes.
class _GatePoisApi implements PoisApi {
  final List<Completer<Map<String, dynamic>>> gates = [];
  final List<String?> searchArgs = [];

  @override
  Future<Map<String, dynamic>> getPOIs({
    String? city,
    String? category,
    String? search,
  }) {
    searchArgs.add(search);
    final gate = Completer<Map<String, dynamic>>();
    gates.add(gate);
    return gate.future;
  }

  /// Resolves the in-flight fetch at [index] with [names] as the POI list.
  void respond(int index, List<String> names) =>
      gates[index].complete(_payload(names));

  void fail(int index, Object error) => gates[index].completeError(error);
}

Map<String, dynamic> _payload(List<String> names) => {
      'items': [
        for (final name in names)
          {
            'id': name.toLowerCase().replaceAll(' ', '-'),
            'slug': name.toLowerCase().replaceAll(' ', '-'),
            'tenant_id': 't-1',
            'name': name,
            'city': 'Algiers',
            'category': 'historical',
          }
      ],
      'total': names.length,
      'page': 1,
      'page_size': 20,
    };

void main() {
  group('POIProvider search contract', () {
    test('updateSearch debounces keystrokes and trims the query', () {
      fakeAsync((async) {
        final api = _GatePoisApi();
        final provider = POIProvider(poisApi: api);

        provider.updateSearch('  casbah  ');
        async.elapse(const Duration(milliseconds: 299));
        expect(api.searchArgs, isEmpty,
            reason: 'no request before the debounce window elapses');

        async.elapse(const Duration(milliseconds: 1));
        expect(api.searchArgs, ['casbah'],
            reason: 'exactly one trimmed request after the window');

        api.respond(0, ['Casbah of Algiers']);
        async.elapse(const Duration(milliseconds: 1));
        expect(provider.items.map((p) => p.name), ['Casbah of Algiers']);
        expect(provider.isLoading, isFalse);
      });
    });

    test('a stale slow response can never overwrite a fresher one', () async {
      final api = _GatePoisApi();
      final provider = POIProvider(poisApi: api);

      final first = provider.loadPOIs(); // seq 1 — resolves last
      final second = provider.loadPOIs(search: 'djemila'); // seq 2 — resolves first
      expect(api.gates.length, 2);

      api.respond(1, ['Tiddis']);
      api.respond(0, ['Stale A', 'Stale B']);
      await Future.wait([first, second]);

      expect(provider.items.map((p) => p.name), ['Tiddis'],
          reason: 'the stale payload must be discarded by the seq guard');
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('clearing the query resets to the full list immediately', () {
      fakeAsync((async) {
        final api = _GatePoisApi();
        final provider = POIProvider(poisApi: api);

        provider.updateSearch('djemila');
        async.elapse(POIProvider.searchDebounce);
        expect(api.searchArgs, ['djemila']);

        provider.updateSearch('');
        expect(api.searchArgs, ['djemila', null],
            reason: 'reset fires synchronously with search=null (full list)');
        expect(provider.searchQuery, isEmpty);
      });
    });

    test('an explicit loadPOIs cancels a pending debounced search', () {
      fakeAsync((async) {
        final api = _GatePoisApi();
        final provider = POIProvider(poisApi: api);

        provider.updateSearch('ghost');
        provider.loadPOIs();
        async.elapse(const Duration(seconds: 2));

        expect(api.searchArgs, [null],
            reason: 'only the explicit reload fired — the ghost was cancelled');
        expect(provider.searchQuery, isEmpty,
            reason: 'loadPOIs() without search resets the query');
      });
    });

    test('a failed search surfaces the error and clears the loading flag',
        () async {
      final api = _GatePoisApi();
      final provider = POIProvider(poisApi: api);

      final fetch = provider.loadPOIs(search: 'nowhere');
      api.fail(0, ApiException(500, '{"detail":"boom"}'));
      await fetch;

      expect(provider.error, contains('boom'));
      expect(provider.items, isEmpty);
      expect(provider.isLoading, isFalse);
    });
  });

  group('Explorer search wiring', () {
    Future<void> pumpExplorer(WidgetTester tester, POIProvider provider) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<POIProvider>.value(
          value: provider,
          child: const MaterialApp(home: POIListScreen()),
        ),
      );
      await tester.pump(); // post-frame callback → initial loadPOIs()
    }

    testWidgets('typing fires one debounced request and renders the results',
        (tester) async {
      final api = _GatePoisApi();
      final provider = POIProvider(poisApi: api);

      await pumpExplorer(tester, provider);
      expect(api.searchArgs, [null]);
      api.respond(0, ['Casbah of Algiers', 'Djemila']);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('poi_card_casbah-of-algiers')), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('poi_search_field')), 'casbah');
      await tester.pump(const Duration(milliseconds: 299));
      expect(api.searchArgs, [null],
          reason: 'still inside the debounce window');
      await tester.pump(const Duration(milliseconds: 1));
      expect(api.searchArgs, [null, 'casbah']);

      api.respond(1, ['Casbah of Algiers']);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('poi_card_casbah-of-algiers')), findsOneWidget);
      expect(find.byKey(const Key('poi_card_djemila')), findsNothing);
    });

    testWidgets('the clear button resets the list instantly', (tester) async {
      final api = _GatePoisApi();
      final provider = POIProvider(poisApi: api);

      await pumpExplorer(tester, provider);
      api.respond(0, ['Casbah of Algiers']);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('poi_search_field')), 'casbah');
      await tester.pump(POIProvider.searchDebounce);
      api.respond(1, ['Casbah of Algiers']);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('poi_search_clear')));
      await tester.pump();
      expect(api.searchArgs, [null, 'casbah', null],
          reason: 'clear resets immediately, no debounce');
      expect(provider.searchQuery, isEmpty);
    });
  });
}
