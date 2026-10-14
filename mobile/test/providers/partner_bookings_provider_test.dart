import 'package:discover_ai/providers/partner_bookings_provider.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// PartnerBookingsProvider contract: the server response is authoritative — a
/// successful respond drops the request from the queue, a rejected one (409)
/// reloads it silently, and status codes map to dedicated messages.
void main() {
  test('load() parses the queue into PartnerBooking items', () async {
    final api = FakePartnerApi(bookings: [
      samplePartnerBookingJson(id: 'b-1'),
      samplePartnerBookingJson(id: 'b-2', travellerName: null),
    ]);
    final provider = PartnerBookingsProvider(partnerApi: api);
    await provider.load();

    expect(provider.isLoading, isFalse);
    expect(provider.error, isNull);
    expect(provider.items, hasLength(2));
    expect(provider.items.first.id, 'b-1');
    expect(provider.items.last.travellerName, isNull);
  });

  test('confirm removes the request from the queue', () async {
    final api = FakePartnerApi(bookings: [
      samplePartnerBookingJson(id: 'b-1'),
      samplePartnerBookingJson(id: 'b-2'),
    ]);
    final provider = PartnerBookingsProvider(partnerApi: api);
    await provider.load();

    final ok = await provider.respond(provider.items.first, 'confirm');

    expect(ok, isTrue);
    expect(provider.actionError, isNull);
    expect(provider.items.map((b) => b.id), ['b-2']);
    expect(api.respondCalls, 1);
    expect(api.lastRespondDecision, 'confirm');
  });

  test('decline forwards the optional note', () async {
    final api = FakePartnerApi(bookings: [samplePartnerBookingJson(id: 'b-1')]);
    final provider = PartnerBookingsProvider(partnerApi: api);
    await provider.load();

    final ok = await provider.respond(provider.items.single, 'decline',
        note: 'Complet ce soir-là');

    expect(ok, isTrue);
    expect(api.lastRespondDecision, 'decline');
    expect(api.lastRespondNote, 'Complet ce soir-là');
    expect(provider.items, isEmpty);
  });

  test('409 → dedicated message and a silent queue reload', () async {
    final api = FakePartnerApi(bookings: [
      samplePartnerBookingJson(id: 'b-1'),
      samplePartnerBookingJson(id: 'b-2'),
    ]);
    final provider = PartnerBookingsProvider(partnerApi: api);
    await provider.load();
    // Someone else handled b-1 server-side: the next respond 409s, and the
    // fake no longer serves b-1 (it moved to 'confirmed').
    api.respondError =
        ApiException(409, '{"detail":"Booking already handled or expired"}');
    api.bookings.removeWhere((b) => b['id'] == 'b-1');

    final ok = await provider.respond(provider.items.first, 'confirm');

    expect(ok, isFalse);
    expect(provider.actionError, 'Cette demande a déjà été traitée ou a expiré.');
    // Reload ran: b-1 is gone from the queue, b-2 remains.
    expect(api.listCalls, 2);
    expect(provider.items.map((b) => b.id), ['b-2']);
  });

  test('403 on respond → dedicated message, no reload', () async {
    final api = FakePartnerApi(bookings: [samplePartnerBookingJson(id: 'b-1')]);
    final provider = PartnerBookingsProvider(partnerApi: api);
    await provider.load();
    api.respondError = ApiException(403, '{"detail":"Not allowed"}');

    final ok = await provider.respond(provider.items.single, 'confirm');

    expect(ok, isFalse);
    expect(provider.actionError, 'Vous n\'avez pas accès à cette demande.');
    expect(api.listCalls, 1, reason: '403 is not a 409: no silent reload');
  });

  test('403 on load → dedicated load message', () async {
    final api = FakePartnerApi(listError: ApiException(403, '{}'));
    final provider = PartnerBookingsProvider(partnerApi: api);
    await provider.load();

    expect(provider.items, isEmpty);
    expect(provider.error, 'Vous n\'avez pas accès à l\'espace partenaire.');
  });

  test('network failure → generic message', () async {
    final api = FakePartnerApi(listError: ApiException(null, 'socket down'));
    final provider = PartnerBookingsProvider(partnerApi: api);
    await provider.load();
    expect(provider.error, contains('Vérifiez votre connexion'));
  });

  test('isActing guards against a double tap (one respond, not two)', () async {
    final api = FakePartnerApi(bookings: [samplePartnerBookingJson(id: 'b-1')]);
    final provider = PartnerBookingsProvider(partnerApi: api);
    await provider.load();
    final booking = provider.items.single;

    // Fire two responds concurrently: the second must be rejected while the
    // first is in flight.
    final first = provider.respond(booking, 'confirm');
    final second = await provider.respond(booking, 'confirm');

    expect(second, isFalse);
    await first;
    expect(api.respondCalls, 1);
    expect(provider.isActing, isFalse);
  });
}
