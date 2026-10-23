import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/booking.dart';
import '../models/booking_details.dart';
import '../services/api_service.dart';
import '../utils/idempotency.dart';

/// Locale-agnostic failure codes for the initial listings (bookings list /
/// adapters). The provider has no `BuildContext`, so it never renders text
/// itself — the screen maps these to localized strings via
/// `AppLocalizations` (same contract as [POIError] / [AuthError] /
/// [PartnerBookingError]).
enum BookingLoadError {
  /// Transport-level failure (no HTTP status): SocketException,
  /// TimeoutException, DNS resolution error…
  network,

  /// Any other server error (5xx, unexpected payload shape).
  generic,
}

/// Locale-agnostic failure codes for the booking actions. The provider has
/// no `BuildContext`, so it never renders text itself — the screen maps these
/// to localized strings via `AppLocalizations` (same contract as [POIError] /
/// [AuthError] / [PartnerBookingError]).
enum BookingError {
  /// 409 — an idempotency key was reused with a different payload (e.g. the
  /// user switched adapter mid-retry). The sheet must mint a fresh key.
  conflict,

  /// 422 — the place is not bookable (`info_only`) or the mode is not
  /// supported yet (deposit / online_payment) and was refused by the backend.
  unavailable,

  /// Transport-level failure (no HTTP status): SocketException,
  /// TimeoutException, DNS resolution error…
  network,

  /// Any other server error (5xx, unexpected payload shape).
  generic,
}

/// Maps a failed listing call to a locale-agnostic code.
BookingLoadError _loadErrorCode(Object e) {
  if (e is ApiException) {
    return e.statusCode == null
        ? BookingLoadError.network
        : BookingLoadError.generic;
  }
  if (e is SocketException ||
      e is TimeoutException ||
      e is http.ClientException) {
    return BookingLoadError.network;
  }
  return BookingLoadError.generic;
}

/// Maps a failed create/consent call to a locale-agnostic code.
///
/// The 409 case can only happen when an idempotency key was reused with a
/// different payload (e.g. the user switched adapter mid-retry) — the sheet
/// must be reopened with a fresh key. 422 covers `info_only` and the
/// not-yet-supported modes (deposit / online_payment) refused by the backend.
BookingError _bookingErrorCode(ApiException e) {
  switch (e.statusCode) {
    case 409:
      return BookingError.conflict;
    case 422:
      return BookingError.unavailable;
    default:
      return e.statusCode == null ? BookingError.network : BookingError.generic;
  }
}

/// Maps a failed cancellation to a locale-agnostic code.
///
/// 409 means the booking left the cancellable window (backend: cancel refused
/// from declined / expired / cancelled) — the UI must not offer a retry.
BookingCancelError _cancelErrorCode(ApiException e) {
  if (e.statusCode == 409) return BookingCancelError.notCancellable;
  return e.statusCode == null
      ? BookingCancelError.network
      : BookingCancelError.generic;
}

/// Locale-agnostic failure codes for a refused cancellation.
///
/// Kept separate from [BookingError] so the creation cases (409/422) stay
/// untouched: a 409 here means the booking left the cancellable window
/// (backend: cancel refused from declined / expired / cancelled) — the UI
/// must not offer a retry.
enum BookingCancelError {
  /// 409 — the booking can no longer be cancelled.
  notCancellable,

  /// Transport-level failure (no HTTP status).
  network,

  /// Any other server error (5xx, unknown).
  generic,
}

/// Booking state, mirroring the backend consent flow exactly:
/// create → pending → explicit consent (true → confirmed + `EXT-…`
/// reference, false → cancelled) → optional cancel.
/// The API seam is injectable so tests run without network.
class BookingProvider extends ChangeNotifier {
  BookingProvider({BookingsApi? bookingsApi})
      : _api = bookingsApi ?? ApiService();

  final BookingsApi _api;

  List<Booking> _items = [];
  Map<String, Map<String, dynamic>> _adapters = {};
  bool _isLoading = false;
  bool _isActing = false;
  BookingLoadError? _loadError;
  BookingError? _actionError;
  BookingCancelError? _cancelError;
  int? _actionStatusCode;

  /// Idempotency state of the last create attempt: the key sent and the
  /// content it was bound to. Same signature on the next attempt ⇒ the same
  /// key is replayed (network retry); a different one ⇒ a fresh key, because
  /// the backend answers 409 to a reused key with a different body.
  String? _lastIdempotencyKey;
  String? _lastCreateSignature;

  List<Booking> get items => _items;

  /// Only the adapters the backend advertises — the booking sheet never
  /// invents a fallback list.
  Map<String, Map<String, dynamic>> get adapters => _adapters;
  bool get isLoading => _isLoading;
  bool get isActing => _isActing;

  /// Code for the last failed listing (null on success). The screen turns it
  /// into a localized message — the provider stays text-free.
  BookingLoadError? get loadError => _loadError;

  /// Code for the last failed create/consent action (null on success). The
  /// screen turns it into a localized message — the provider stays text-free.
  BookingError? get actionError => _actionError;

  /// Code for the last failed cancellation (null on success). Kept apart from
  /// [actionError] so the two flows never share a message.
  BookingCancelError? get cancelError => _cancelError;

  /// HTTP status of the last failed action (ApiException only) — lets the
  /// booking sheet decide whether an idempotency key is still valid
  /// (409/422 → discard it) or must be kept for the retry (network/5xx).
  int? get actionStatusCode => _actionStatusCode;

  /// [silent] reloads without touching the loading flag / error state —
  /// used on screen open when a 'requested' booking may have changed
  /// server-side (single refresh, no polling).
  Future<void> loadBookings({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _loadError = null;
      notifyListeners();
    }
    try {
      final data = await _api.listBookings();
      _items = data.map(Booking.fromJson).toList();
    } catch (e) {
      if (!silent) _loadError = _loadErrorCode(e);
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Mirrors GET /bookings/adapters/available.
  Future<void> loadAdapters() async {
    _loadError = null;
    notifyListeners();
    try {
      final data = await _api.listAdapters();
      final raw = data['adapters'] as Map? ?? {};
      _adapters = raw.map<String, Map<String, dynamic>>(
          (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)));
    } catch (e) {
      _loadError = _loadErrorCode(e);
    }
    notifyListeners();
  }

  /// Creates a PENDING booking (201). Never confirms it — the caller must
  /// walk the user through [giveConsent] next (principle 5).
  ///
  /// [details] is the traveller's date/guests/notes; it becomes the request's
  /// `booking_data` via `BookingDetails.toBookingData` (only `date`, `guests`
  /// and `notes`, never personal data). When null the body stays exactly the
  /// historical one.
  ///
  /// [idempotencyKey] is forwarded to the backend's `Idempotency-Key`
  /// header: the same key + same body replays the original booking (200)
  /// instead of creating a duplicate. On a replay, the existing item is
  /// replaced in place rather than inserted twice.
  ///
  /// Key ownership, in order of precedence:
  /// 1. an explicit [idempotencyKey] is always sent verbatim;
  /// 2. otherwise the key is kept across attempts while the *content*
  ///    (POI + adapter + details) is unchanged — that is the network-retry
  ///    case, where the backend must replay rather than duplicate;
  /// 3. any change of content mints a new key, because the server would
  ///    answer 409 for the same key with a different body;
  /// 4. the key is dropped after a success, and after a 409/422, which by
  ///    definition starts a new logical attempt (pre-existing rules).
  Future<Booking?> createBooking({
    required String poiId,
    required String adapterType,
    BookingDetails? details,
    String? idempotencyKey,
  }) async {
    _isActing = true;
    _actionError = null;
    _actionStatusCode = null;
    notifyListeners();
    // An explicit key wins; otherwise the key is bound to the content so a
    // retry with unchanged details replays instead of duplicating.
    final content = _contentSignature(poiId, adapterType, details);
    final key = idempotencyKey ??
        (_lastCreateSignature == content ? _lastIdempotencyKey : null) ??
        newIdempotencyKey();
    _lastCreateSignature = content;
    _lastIdempotencyKey = key;
    Booking? created;
    try {
      final json = await _api.createBooking(
        poiId: poiId,
        adapterType: adapterType,
        bookingData: details?.toBookingData(),
        idempotencyKey: key,
      );
      created = Booking.fromJson(json);
      // Idempotent replay: same id already known → replace, never duplicate.
      final known = _items.any((b) => b.id == created!.id);
      _items = known
          ? [
              for (final b in _items)
                if (b.id == created.id) created else b
            ]
          : [created, ..._items];
      // The logical attempt is over: forget the key, a later booking is a
      // new one even with identical details.
      _lastIdempotencyKey = null;
      _lastCreateSignature = null;
    } on ApiException catch (e) {
      _actionStatusCode = e.statusCode;
      _actionError = _bookingErrorCode(e);
      // 409/422 means the backend rejected this attempt's key or body: the
      // next try must be a fresh attempt, never the same key again.
      if (e.statusCode == 409 || e.statusCode == 422) {
        _lastIdempotencyKey = null;
        _lastCreateSignature = null;
      }
    } on SocketException catch (_) {
      // Transport failure: keep the key and its signature so the next tap
      // replays instead of creating a second booking.
      _actionError = BookingError.network;
    } on TimeoutException catch (_) {
      _actionError = BookingError.network;
    } on http.ClientException catch (_) {
      _actionError = BookingError.network;
    } catch (_) {
      _actionError = BookingError.generic;
    }
    _isActing = false;
    notifyListeners();
    return created;
  }

  /// Explicit consent step — mirrors POST /bookings/{id}/consent:
  /// true → confirmed + external reference, false → cancelled.
  Future<Booking?> giveConsent(Booking booking, {required bool consent}) async {
    _isActing = true;
    _actionError = null;
    notifyListeners();
    Booking? updated;
    try {
      final json = await _api.giveConsent(booking.id, consent: consent);
      updated = Booking.fromJson(json);
    } on ApiException catch (e) {
      _actionError = _bookingErrorCode(e);
    } on SocketException catch (_) {
      _actionError = BookingError.network;
    } on TimeoutException catch (_) {
      _actionError = BookingError.network;
    } on http.ClientException catch (_) {
      _actionError = BookingError.network;
    } catch (_) {
      _actionError = BookingError.generic;
    }
    _isActing = false;
    final u = updated;
    if (u != null) {
      _items = [
        for (final b in _items)
          if (b.id == u.id) u else b
      ];
    }
    notifyListeners();
    return updated;
  }

  /// Mirrors POST /bookings/{id}/cancel. The server response is used as-is
  /// (a 409 from a non-cancellable booking keeps the current status).
  Future<Booking?> cancelBooking(Booking booking) async {
    _isActing = true;
    _actionError = null;
    _cancelError = null;
    notifyListeners();
    Booking? updated;
    try {
      final json = await _api.cancelBooking(booking.id);
      updated = Booking.fromJson(json);
    } on ApiException catch (e) {
      _cancelError = _cancelErrorCode(e);
    } on SocketException catch (_) {
      _cancelError = BookingCancelError.network;
    } on TimeoutException catch (_) {
      _cancelError = BookingCancelError.network;
    } on http.ClientException catch (_) {
      _cancelError = BookingCancelError.network;
    } catch (_) {
      _cancelError = BookingCancelError.generic;
    }
    _isActing = false;
    final u = updated;
    if (u != null) {
      _items = [
        for (final b in _items)
          if (b.id == u.id) u else b
      ];
    }
    notifyListeners();
    return updated;
  }

  /// Content fingerprint of the last create attempt. Two attempts with the
  /// same signature are the same logical request (a retry: the server must
  /// replay); any difference means a different body, which would be answered
  /// 409 under the previous key — so a new key is minted.
  String _contentSignature(
    String poiId,
    String adapterType,
    BookingDetails? details,
  ) {
    final data = details?.toBookingData() ?? const <String, dynamic>{};
    final notes = data['notes'];
    return '$poiId|$adapterType|${data['date']}|${data['guests']}|$notes';
  }
}
