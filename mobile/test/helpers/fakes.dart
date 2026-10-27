import 'package:discover_ai/services/api_service.dart';
import 'package:discover_ai/services/locale_store.dart';
import 'package:discover_ai/services/secure_storage_service.dart';
import 'package:discover_ai/models/research_job.dart';

/// Deterministic AuthApi fake for tests.
class FakeAuthApi implements AuthApi {
  FakeAuthApi({
    this.failLogin = false,
    this.failGetMe = false,
    this.userLocale,
    this.isPartner = false,
    this.isAdmin = false,
  });

  final bool failLogin;
  final bool failGetMe;
  final String? userLocale;
  final bool isPartner;
  final bool isAdmin;
  int loginCalls = 0;
  int updateMeCalls = 0;
  String? lastUpdatedLocale;
  String? lastToken;

  @override
  void setToken(String token) => lastToken = token;

  @override
  Future<Map<String, dynamic>> getMe() async {
    if (failGetMe) {
      throw ApiException(401, '{"detail":"Could not validate credentials"}');
    }
    return {
      'id': 'u-1',
      'email': 'demo@discoverai.dz',
      'full_name': 'Demo User',
      'locale': userLocale,
      'is_active': true,
      'is_admin': isAdmin,
      'is_partner': isPartner,
      'preferences': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    };
  }

  @override
  Future<Map<String, dynamic>> updateMe({required String locale}) async {
    updateMeCalls++;
    lastUpdatedLocale = locale;
    return {
      'id': 'u-1',
      'email': 'demo@discoverai.dz',
      'full_name': 'Demo User',
      'locale': locale,
      'is_active': true,
      'is_admin': false,
      'preferences': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    };
  }

  @override
  Future<Map<String, dynamic>> login(String email, String password) async {
    loginCalls++;
    if (failLogin) {
      throw ApiException(401, '{"detail":"Incorrect email or password"}');
    }
    return {
      'access_token': 'jwt-token-123',
      'token_type': 'bearer',
      'expires_in': 1800,
    };
  }

  @override
  Future<Map<String, dynamic>> register(
    String email,
    String password, {
    String? fullName,
  }) async =>
      {
        'id': 'u-new',
        'email': email,
        'full_name': fullName,
        'is_active': true,
        'is_admin': false,
        'preferences': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      };
}

const List<Map<String, dynamic>> samplePoisJson = [
  {
    'id': 'p-1',
    'slug': 'casbah-of-algiers',
    'tenant_id': 't-1',
    'name': 'Casbah of Algiers',
    'description': 'UNESCO world heritage medina.',
    'city': 'Algiers',
    'category': 'historical',
    'duration_minutes': 120,
    'price_range': 'free',
    'latitude': 36.7836,
    'longitude': 3.06,
    'images': [],
    'tags': ['unesco'],
    'accessibility': [],
    'opening_hours': {},
    'is_verified': true,
    'is_active': true,
    'average_rating': 4.5,
    'review_count': 12,
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-02T00:00:00Z',
  },
  {
    'id': 'p-2',
    'slug': 'notre-dame-dafrique',
    'tenant_id': 't-1',
    'name': "Notre-Dame d'Afrique",
    'city': 'Algiers',
    'category': 'culture',
    'duration_minutes': 90,
    'price_range': 'free',
    'average_rating': 4.7,
    'review_count': 8,
  },
];

class FakePoisApi implements PoisApi {
  FakePoisApi({this.itemsJson = samplePoisJson});

  final List<Map<String, dynamic>> itemsJson;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getPOIs({
    String? city,
    String? category,
    String? search,
  }) async {
    calls++;
    return {'items': itemsJson};
  }
}

/// Fresh copy each call so mutation-prone consumers can't corrupt the fixture.
/// Field-for-field mirror of the backend TripResponse schema.
Map<String, dynamic> sampleTripJson() => {
      'id': 'tr-1',
      'tenant_id': 't-1',
      'user_id': 'u-1',
      'title': 'Algiers highlights',
      'description': 'Two days through the white city.',
      'num_days': 2,
      'budget_level': 'medium',
      'budget_currency': 'DZD',
      'travel_style': 'balanced',
      'interests': ['history', 'food'],
      'group_type': 'solo',
      'children': false,
      'status': 'draft',
      'total_cost_estimate': 1200.5,
      'items': [
        {
          'id': 'i-1',
          'poi_id': 'p-1',
          'day_number': 1,
          'order_index': 0,
          'start_time': '2026-08-24T09:00:00Z',
          'end_time': '2026-08-24T11:00:00Z',
          'notes': 'Morning walk through the medina.',
          'poi': samplePoisJson[0],
        },
        {
          'id': 'i-2',
          'poi_id': 'p-2',
          'day_number': 1,
          'order_index': 1,
          'start_time': '2026-08-24T14:00:00Z',
          'end_time': null,
          'notes': null,
          'poi': samplePoisJson[1],
        },
        {
          'id': 'i-3',
          'poi_id': 'p-1',
          'day_number': 2,
          'order_index': 0,
          'start_time': null,
          'end_time': null,
          'notes': 'Second visit at a slower pace.',
          'poi': null,
        },
      ],
      'created_at': '2026-08-24T08:00:00Z',
      'updated_at': '2026-08-24T08:00:00Z',
    };

class FakeTripsApi implements TripsApi {
  FakeTripsApi({this.failGenerate = false, this.generateError});

  final bool failGenerate;
  final Object? generateError;
  int generateCalls = 0;
  int listCalls = 0;
  Map<String, dynamic>? lastGeneratePayload;

  @override
  Future<Map<String, dynamic>> generateTrip({
    required List<String> interests,
    required String budgetLevel,
    required int numDays,
  }) async {
    generateCalls++;
    lastGeneratePayload = {
      'interests': List<String>.from(interests),
      'budget_level': budgetLevel,
      'num_days': numDays,
    };
    if (generateError != null) {
      throw generateError!;
    }
    if (failGenerate) {
      throw ApiException(500, '{"detail":"trip planner failed"}');
    }
    return {
      ...sampleTripJson(),
      'budget_level': budgetLevel,
      'num_days': numDays,
      'interests': List<String>.from(interests),
    };
  }

  @override
  Future<List<Map<String, dynamic>>> listTrips() async {
    listCalls++;
    return [sampleTripJson()];
  }
}

/// Deterministic ChatApi fake for tests.
class FakeChatApi implements ChatApi {
  FakeChatApi({this.response, this.failReply = false});

  final Map<String, dynamic>? response;
  final bool failReply;
  int calls = 0;
  String? lastMessage;
  Map<String, dynamic>? lastContext;

  @override
  Future<Map<String, dynamic>> sendMessage(
    String message, {
    Map<String, dynamic>? context,
  }) async {
    calls++;
    lastMessage = message;
    lastContext = context;
    if (failReply) {
      throw ApiException(500, '{"detail":"chat service unavailable"}');
    }
    return Map<String, dynamic>.from(response ??
        {
          'message': 'Mocked assistant reply to: $message',
          'suggestions': <String>['Suggestion 1', 'Suggestion 2'],
          'context': <String, dynamic>{},
        });
  }
}

Map<String, dynamic> sampleBookingJson({
  String id = 'b-1',
  String poiId = 'p-1',
  String adapterType = 'hotel',
  String status = 'pending',
  bool consentGiven = false,
  String? externalId,
  String bookingMode = 'request',
  String? respondBy,
  String? partnerNote,
  String? respondedAt,
  Map<String, dynamic>? bookingData,
}) =>
    {
      'id': id,
      'tenant_id': 't-1',
      'user_id': 'u-1',
      'poi_id': poiId,
      'adapter_type': adapterType,
      'external_id': externalId,
      'status': status,
      'consent_given': consentGiven,
      'price': null,
      'currency': 'DZD',
      'booking_mode': bookingMode,
      'respond_by': respondBy,
      'partner_note': partnerNote,
      'responded_at': respondedAt,
      // Only when a booking was created with details: keeps every existing
      // fixture byte-for-byte identical.
      if (bookingData != null) 'booking_data': bookingData,
      'created_at': '2026-08-28T10:00:00Z',
    };

/// Deterministic BookingsApi fake reproducing the backend consent flow:
/// create → pending, consent true → confirmed + EXT-…, false → cancelled,
/// cancel → cancelled.
///
/// Reproduces the backend's Idempotency-Key contract (endpoint 0012):
/// same key + same poiId/adapterType replays the stored reservation without
/// adding a new one; same key + a different payload raises 409.
class FakeBookingsApi implements BookingsApi {
  FakeBookingsApi(
      {List<Map<String, dynamic>>? bookings,
      this.failCreate = false,
      this.createError,
      this.cancelError})
      : bookings =
            List<Map<String, dynamic>>.from(bookings ?? [sampleBookingJson()]);

  final bool failCreate;

  /// When set, createBooking throws it (before any replay logic) — lets a
  /// test simulate 422 / 5xx / network failures. Mutable so a test can clear
  /// it to model a successful retry in the same sheet.
  ApiException? createError;

  /// When set, cancelBooking throws it — lets a test simulate 409 / 5xx /
  /// network cancellation failures.
  ApiException? cancelError;

  final List<Map<String, dynamic>> bookings;
  int createCalls = 0;
  int consentCalls = 0;
  int cancelCalls = 0;
  String? lastCreatedPoiId;
  String? lastCreatedAdapter;

  /// Last `booking_data` received by [createBooking] — the traveller's
  /// details, as sent by the provider. Null when none were provided.
  Map<String, dynamic>? lastBookingData;
  String? lastConsentBookingId;
  bool? lastConsentValue;

  /// Idempotency-Key observability: last value received and full ordered
  /// history (null entries = no header sent).
  String? lastIdempotencyKey;
  final List<String?> idempotencyKeys = [];

  /// Key → stored response, to replay an already-created booking.
  final Map<String, Map<String, dynamic>> _byKey = {};

  static const Map<String, Map<String, dynamic>> _adapters = {
    'hotel': {'name': 'HotelBookingAdapter', 'status': 'active'},
    'restaurant': {'name': 'RestaurantAdapter', 'status': 'active'},
    'tour': {'name': 'TourGuideAdapter', 'status': 'beta'},
    'transport': {'name': 'TransportAdapter', 'status': 'active'},
  };

  Map<String, dynamic> _byId(String bookingId) => bookings.firstWhere(
        (b) => b['id'] == bookingId,
        orElse: () => throw ApiException(404, '{"detail":"Booking not found"}'),
      );

  @override
  Future<Map<String, dynamic>> createBooking({
    required String poiId,
    required String adapterType,
    Map<String, dynamic>? bookingData,
    String? idempotencyKey,
  }) async {
    createCalls++;
    lastCreatedPoiId = poiId;
    lastCreatedAdapter = adapterType;
    lastBookingData = bookingData;
    lastIdempotencyKey = idempotencyKey;
    idempotencyKeys.add(idempotencyKey);

    if (createError != null) {
      throw createError!;
    }
    if (failCreate) {
      throw ApiException(400, '{"detail":"Invalid adapter type"}');
    }

    // Backend contract: same key already seen…
    if (idempotencyKey != null && _byKey.containsKey(idempotencyKey)) {
      final stored = _byKey[idempotencyKey]!;
      final sameRequest =
          stored['poi_id'] == poiId && stored['adapter_type'] == adapterType;
      if (!sameRequest) {
        throw ApiException(409,
            '{"detail":"Idempotency-Key already used with a different request"}');
      }
      // Replay: same reservation, no new row — the list stays untouched.
      return Map<String, dynamic>.from(stored);
    }

    final json = sampleBookingJson(
      id: 'b-$createCalls',
      poiId: poiId,
      adapterType: adapterType,
      bookingData: bookingData,
    );
    bookings.add(json);
    if (idempotencyKey != null) {
      _byKey[idempotencyKey] = Map<String, dynamic>.from(json);
    }
    return Map<String, dynamic>.from(json);
  }

  @override
  Future<List<Map<String, dynamic>>> listBookings() async =>
      [for (final b in bookings.reversed) Map<String, dynamic>.from(b)];

  @override
  Future<Map<String, dynamic>> giveConsent(String bookingId,
      {required bool consent}) async {
    consentCalls++;
    lastConsentBookingId = bookingId;
    lastConsentValue = consent;
    final b = _byId(bookingId);
    if (consent) {
      b['consent_given'] = true;
      if (b['booking_mode'] == 'manual_confirm') {
        // Backend contract: manual_confirm consent ⇒ 'requested', no
        // external reference until the partner confirms.
        b['status'] = 'requested';
        b.remove('external_id');
      } else {
        b['status'] = 'confirmed';
        b['external_id'] = 'EXT-$bookingId';
      }
    } else {
      b['status'] = 'cancelled';
    }
    return Map<String, dynamic>.from(b);
  }

  @override
  Future<Map<String, dynamic>> cancelBooking(String bookingId) async {
    if (cancelError != null) throw cancelError!;
    final b = _byId(bookingId);
    if (b['booking_mode'] == 'manual_confirm' &&
        (b['status'] == 'declined' ||
            b['status'] == 'expired' ||
            b['status'] == 'cancelled')) {
      // Backend contract: cancel refused once the partner answered.
      throw ApiException(409, '{"detail":"Booking cannot be cancelled"}');
    }
    cancelCalls++;
    b['status'] = 'cancelled';
    return Map<String, dynamic>.from(b);
  }

  /// Simulates the partner answering 'declined' server-side.
  void partnerDecline(String id, {String? note}) {
    final b = _byId(id);
    b['status'] = 'declined';
    if (note != null) b['partner_note'] = note;
    b['responded_at'] = '2026-08-29T12:00:00Z';
  }

  /// Simulates the partner confirming server-side.
  void partnerConfirm(String id) {
    final b = _byId(id);
    b['status'] = 'confirmed';
    b['external_id'] = 'EXT-$id';
    b['responded_at'] = '2026-08-29T12:00:00Z';
  }

  /// Simulates the backend expiring an unanswered request server-side.
  void expire(String id) {
    _byId(id)['status'] = 'expired';
  }

  @override
  Future<Map<String, dynamic>> listAdapters() async =>
      {'adapters': Map<String, Map<String, dynamic>>.from(_adapters)};
}

/// Deterministic PromotionsApi fake for tests. Empty by default so tests
/// that don't care about the banner (most of them) stay unaffected; pass
/// [promotions] to exercise the banner rendering path explicitly.
class FakePromotionsApi implements PromotionsApi {
  FakePromotionsApi({List<Map<String, dynamic>>? promotions, this.fail = false})
      : promotions = List<Map<String, dynamic>>.from(promotions ?? []);

  final bool fail;
  final List<Map<String, dynamic>> promotions;

  @override
  Future<Map<String, dynamic>> getPromotions() async {
    if (fail) {
      throw ApiException(500, '{"detail":"Internal server error"}');
    }
    return {
      'items': [for (final p in promotions) Map<String, dynamic>.from(p)],
      'total': promotions.length,
    };
  }
}

/// A single sample promotion JSON, matching backend `PromotionResponse`.
Map<String, dynamic> samplePromotionJson({
  String id = 'promo-1',
  String title = "L'Algérie vous attend",
}) =>
    {
      'id': id,
      'tenant_id': 'tenant-1',
      'title': title,
      'subtitle':
          'Des paysages grandioses, une histoire millénaire, une hospitalité unique.',
      'image_url': 'https://example.com/algeria.jpg',
      'cta_label': 'Découvrir',
      'link_type': 'none',
      'link_target': null,
      'priority': 10,
      'is_active': true,
    };

/// In-memory TokenStore for tests (no platform channels involved).
class InMemoryTokenStore implements TokenStore {
  String? token;

  @override
  Future<void> deleteToken() async => token = null;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;
}

/// In-memory LocaleStore for tests, mirroring [InMemoryTokenStore].
class InMemoryLocaleStore implements LocaleStore {
  String? localeCode;

  @override
  Future<void> deleteLocaleCode() async => localeCode = null;

  @override
  Future<String?> readLocaleCode() async => localeCode;

  @override
  Future<void> writeLocaleCode(String code) async => localeCode = code;
}

class FakeTenantsApi implements TenantsApi {
  FakeTenantsApi({
    Map<String, dynamic>? tenant,
    this.fail = false,
    this.categorySlugs,
  }) : tenant = tenant ?? sampleTenantJson();

  final bool fail;
  final Map<String, dynamic> tenant;

  /// When non-null, `getTenantCategories` serves exactly these slugs (in this
  /// order) instead of the default 1:1-with-AppConfig catalog.
  ///
  /// Needed to model a category published *after* the app shipped: the default
  /// catalog mirrors `AppConfig.tripInterestOptions` exactly, so any test using
  /// it can never tell the compile-time list from the dynamic one — which is
  /// precisely the distinction the trip form got wrong.
  final List<String>? categorySlugs;

  /// Nombre d'appels à `getTenantCategories`. Permet de vérifier qu'un écran
  /// recharge le catalogue au bon moment (par exemple quand une collecte se
  /// termine) et pas à chaque notification du provider.
  int getCategoriesCalls = 0;

  @override
  Future<Map<String, dynamic>> getCurrentTenant() async {
    if (fail) {
      throw ApiException(500, '{"detail":"Internal server error"}');
    }
    return Map<String, dynamic>.from(tenant);
  }

  /// Field-complete Algeria fixture mirroring the backend
  /// TenantCategoryResponse: the 11 AppConfig slugs (thermal included —
  /// 1:1 parity with the compile-time fallback catalog), parent families
  /// and icon suggestions as the real API would advertise. `description`
  /// is deliberately present on some entries and absent on others so
  /// TenantCategory.fromJson exercises both its nullable paths.
  @override
  Future<List<Map<String, dynamic>>> getTenantCategories() async {
    getCategoriesCalls++;
    if (fail) {
      throw ApiException(500, '{"detail":"Internal server error"}');
    }
    const catalog = [
      (
        'culture',
        'Culture & Médinas',
        'museum',
        'culture',
        'Medinas, museums and living heritage.'
      ),
      (
        'history',
        'Histoire & Antiquité',
        'history_edu',
        'history',
        'Ruins and ancient civilizations.'
      ),
      (
        'nature',
        'Nature & Parcs',
        'forest',
        'nature',
        'National parks and natural landscapes.'
      ),
      (
        'desert',
        'Sahara & Oasis',
        'wb_sunny',
        'nature',
        'Sand dunes, oases and camel treks.'
      ),
      (
        'adventure',
        'Aventure & Trek',
        'hiking',
        'adventure',
        'Hiking, climbing and outdoor sports.'
      ),
      (
        'food',
        'Gastronomie',
        'restaurant',
        'food',
        'Local dishes and culinary traditions.'
      ),
      (
        'beaches',
        'Plages & Mer',
        'beach_access',
        'nature',
        'Mediterranean coastline and hidden coves.'
      ),
      (
        'monuments',
        'Monuments & Sites',
        'explore',
        'history',
        'Iconic landmarks and viewpoints.'
      ),
      ('crafts', 'Artisanat & Souks', 'shopping_bag', 'culture', null),
      ('thermal', 'Thermalisme', 'hot_tub', 'wellness', null),
      (
        'wellness',
        'Détente & Hammam',
        'spa',
        'wellness',
        'Hammams, spas and relaxation.'
      ),
    ];
    if (categorySlugs != null) {
      // Same response shape as the real API (TenantCategoryResponse), with
      // `status: active` since only active categories reach travellers.
      return [
        for (final (i, slug) in categorySlugs!.indexed)
          {
            'id': 'cat-$slug',
            'tenant_id': 'tenant-1',
            'slug': slug,
            'label': slug,
            'parent_family': 'nature',
            'status': 'active',
            'display_order': i + 1,
            'ai_generated': true,
          },
      ];
    }
    return [
      for (final (i, (slug, label, icon, family, description))
          in catalog.indexed)
        {
          'id': 'cat-$slug',
          'tenant_id': 'tenant-1',
          'slug': slug,
          'label': label,
          'parent_family': family,
          'icon_suggestion': icon,
          if (description != null) 'description': description,
          'display_order': i + 1,
          'ai_generated': true,
        },
    ];
  }
}

Map<String, dynamic> sampleTenantJson() => {
      'id': 'tenant-1',
      'slug': 'algeria',
      'name': 'Algeria',
      'default_language': 'fr',
      'supported_languages': ['fr', 'ar', 'en'],
      'default_currency': 'DZD',
      'primary_color': '#006233',
      'secondary_color': '#FFFFFF',
    };

// test/fakes/research_api_fake.dart
//
// À fusionner dans le fakes.dart existant du projet (mêmes conventions que
// les autres Fake*Api : contrôle manuel des réponses pour les widget tests
// et flutter drive, pas d'appel réseau réel).

class FakeResearchApi implements ResearchApi {
  /// File d'attente des jobs renvoyés successivement par runResearch().
  /// Permet de scripter une séquence pending -> processing -> done dans un test.
  final List<ResearchJob> jobsQueue;

  /// Réponses successives de getJobStatus(), indexées par appel (dans l'ordre).
  final List<ResearchJob> statusSequence;

  /// Si non-null, force une exception au prochain appel de runResearch().
  Object? runResearchError;

  /// Si non-null, `getJobStatus` lève cette exception au lieu de répondre.
  /// Simule une interruption réseau qui coupe le polling avant tout statut
  /// final — le cas où aucun rechargement de catalogue n'a de sens.
  Object? getStatusError;

  int _statusCallCount = 0;
  int _runResearchCallCount = 0;

  final List<Map<String, String>> runResearchCalls = [];
  final List<Map<String, String>> getJobStatusCalls = [];

  FakeResearchApi({
    List<ResearchJob>? jobsQueue,
    List<ResearchJob>? statusSequence,
    this.runResearchError,
    this.getStatusError,
  })  : jobsQueue = jobsQueue ?? [],
        statusSequence = statusSequence ?? [];

  @override
  Future<Map<String, dynamic>> runResearch({
    required String tenantId,
    required String triggerType,
  }) async {
    runResearchCalls.add({
      'tenantId': tenantId,
      'triggerType': triggerType,
    });

    if (runResearchError != null) {
      throw runResearchError!;
    }

    if (_runResearchCallCount >= jobsQueue.length) {
      throw StateError(
        'FakeResearchApi.runResearch appelé plus de fois que de jobs '
        'fournis dans jobsQueue (${jobsQueue.length})',
      );
    }

    return Map<String, dynamic>.from(
        jobsQueue[_runResearchCallCount++].toJson());
  }

  @override
  Future<Map<String, dynamic>> getJobStatus({
    required String tenantId,
    required String jobId,
  }) async {
    getJobStatusCalls.add({'tenantId': tenantId, 'jobId': jobId});

    if (getStatusError != null) {
      throw getStatusError!;
    }

    if (statusSequence.isEmpty) {
      throw StateError('FakeResearchApi.statusSequence est vide');
    }

    // Reste sur la dernière valeur une fois la séquence épuisée, pour
    // simuler un job resté "done"/"failed" si le polling continue d'appeler.
    final index = _statusCallCount < statusSequence.length
        ? _statusCallCount
        : statusSequence.length - 1;
    _statusCallCount++;

    return Map<String, dynamic>.from(statusSequence[index].toJson());
  }
}

/// Exemple d'usage dans un test :
///
/// final fake = FakeResearchApi(
///   jobsQueue: [
///     ResearchJob(id: 'job1', tenantId: 't1',
///       triggerType: ResearchTriggerType.manualRefresh,
///       status: ResearchJobStatus.pending),
///   ],
///   statusSequence: [
///     ResearchJob(id: 'job1', tenantId: 't1',
///       triggerType: ResearchTriggerType.manualRefresh,
///       status: ResearchJobStatus.processing),
///     ResearchJob(id: 'job1', tenantId: 't1',
///       triggerType: ResearchTriggerType.manualRefresh,
///       status: ResearchJobStatus.done,
///       categoriesProposed: 5, categoriesAutoPublished: 3,
///       categoriesPendingReview: 2),
///   ],
/// );
/// final provider = ResearchProvider(fake, pollInterval: Duration(milliseconds: 10));

/// Deterministic PartnerApi fake for tests. Records every call (booking id,
/// decision, note) so a test can assert the provider forwards exactly what the
/// partner chose. Replays the backend status codes the provider must map:
/// [respondError] (403/404/409) is thrown by [respondToPartnerBooking];
/// [listError] (403/404) by [listPartnerBookings].
class FakePartnerApi implements PartnerApi {
  FakePartnerApi({
    List<Map<String, dynamic>>? bookings,
    this.respondError,
    this.listError,
  }) : bookings = List<Map<String, dynamic>>.from(
            bookings ?? [samplePartnerBookingJson()]);

  /// When set, every [respondToPartnerBooking] throws it (mutable so a test
  /// can clear it to model a successful retry).
  ApiException? respondError;

  /// When set, [listPartnerBookings] throws it (e.g. 403 non-partner).
  ApiException? listError;

  final List<Map<String, dynamic>> bookings;

  int listCalls = 0;
  int getCalls = 0;
  int respondCalls = 0;

  String? lastRespondBookingId;
  String? lastRespondDecision;
  String? lastRespondNote;

  /// Full ordered history of responds (bookingId → decision, note), so a test
  /// can assert a double tap never sent two calls.
  final List<Map<String, String?>> respondHistory = [];

  @override
  Future<List<Map<String, dynamic>>> listPartnerBookings() async {
    listCalls++;
    if (listError != null) throw listError!;
    return [for (final b in bookings) Map<String, dynamic>.from(b)];
  }

  @override
  Future<Map<String, dynamic>> getPartnerBooking(String bookingId) async {
    getCalls++;
    return Map<String, dynamic>.from(_byId(bookingId));
  }

  @override
  Future<Map<String, dynamic>> respondToPartnerBooking(
    String bookingId, {
    required String decision,
    String? note,
  }) async {
    respondCalls++;
    lastRespondBookingId = bookingId;
    lastRespondDecision = decision;
    lastRespondNote = note;
    respondHistory.add({'id': bookingId, 'decision': decision, 'note': note});
    if (respondError != null) throw respondError!;
    final b = _byId(bookingId);
    b['status'] = decision == 'confirm' ? 'confirmed' : 'declined';
    if (note != null) b['partner_note'] = note;
    b['responded_at'] = '2026-08-29T12:00:00Z';
    return Map<String, dynamic>.from(b);
  }

  Map<String, dynamic> _byId(String bookingId) => bookings.firstWhere(
        (b) => b['id'] == bookingId,
        orElse: () => throw ApiException(404, '{"detail":"Booking not found"}'),
      );
}

/// A single `PartnerBookingResponse` JSON — the base booking fields plus the
/// partner-only `poi_name`, `traveller_name` and whitelisted `details`.
Map<String, dynamic> samplePartnerBookingJson({
  String id = 'b-1',
  String poiId = 'p-1',
  String adapterType = 'hotel',
  String status = 'requested',
  String? respondBy,
  String poiName = 'Hôtel El Djazaïr',
  String? travellerName = 'Amine',
  Map<String, dynamic>? details,
}) =>
    {
      ...sampleBookingJson(
        id: id,
        poiId: poiId,
        adapterType: adapterType,
        status: status,
        bookingMode: 'manual_confirm',
        respondBy: respondBy,
      ),
      'poi_name': poiName,
      'traveller_name': travellerName,
      'details': details ??
          <String, dynamic>{
            'date': '2026-09-15',
            'guests': 2,
            'notes': 'Chambre calme si possible.',
          },
    };

class FakeNotificationsApi implements NotificationsApi {
  FakeNotificationsApi({
    List<Map<String, dynamic>>? notifications,
    this.unreadCount = 0,
    this.total,
    this.getNotificationsError,
    this.markReadError,
    this.markAllReadError,
  }) : notifications = notifications ?? [];

  final List<Map<String, dynamic>> notifications;
  int unreadCount;
  int? total;
  Object? getNotificationsError;
  Object? markReadError;
  Object? markAllReadError;

  int getNotificationsCalls = 0;
  int markReadCalls = 0;
  int markAllReadCalls = 0;
  final List<String> markedReadIds = [];
  final List<Map<String, dynamic>> getNotificationsHistory = [];

  @override
  Future<Map<String, dynamic>> getNotifications({
    bool unreadOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    getNotificationsCalls++;
    getNotificationsHistory.add({
      'unreadOnly': unreadOnly,
      'limit': limit,
      'offset': offset,
    });
    if (getNotificationsError != null) throw getNotificationsError!;

    var filtered = notifications;
    if (unreadOnly) {
      filtered = filtered.where((n) => !(n['read'] as bool? ?? false)).toList();
    }

    final effectiveTotal = total ?? filtered.length;
    final paged = filtered.skip(offset).take(limit).toList();

    return {
      'notifications': paged,
      'unread_count': unreadCount,
      'total': effectiveTotal,
      'limit': limit,
      'offset': offset,
    };
  }

  @override
  Future<Map<String, dynamic>> markRead(String id) async {
    markReadCalls++;
    markedReadIds.add(id);
    if (markReadError != null) throw markReadError!;

    final index = notifications.indexWhere((n) => n['id'] == id);
    if (index != -1) {
      notifications[index]['read'] = true;
    }
    if (unreadCount > 0) unreadCount--;

    return {
      'id': id,
      'read': true,
      'read_at': '2026-10-27T10:00:00Z',
    };
  }

  @override
  Future<Map<String, dynamic>> markAllRead() async {
    markAllReadCalls++;
    if (markAllReadError != null) throw markAllReadError!;

    int count = 0;
    for (final n in notifications) {
      if (!(n['read'] as bool? ?? false)) {
        n['read'] = true;
        count++;
      }
    }
    unreadCount = 0;

    return {'marked_as_read': count};
  }
}

Map<String, dynamic> sampleNotificationJson({
  String id = 'notif-1',
  String title = 'Réservation confirmée',
  String message = 'Votre réservation pour Casbah a été confirmée.',
  String type = 'booking_confirmed',
  bool read = false,
  String? createdAt = '2026-10-27T10:00:00',
  String? bookingId = 'b-1',
  Map<String, dynamic>? payload = const {'poi_name': 'Casbah'},
}) =>
    {
      'id': id,
      'title': title,
      'message': message,
      'type': type,
      'read': read,
      'created_at': createdAt,
      'booking_id': bookingId,
      'payload': payload,
    };
