import 'package:flutter/foundation.dart';

import '../models/partner_booking.dart';
import '../services/api_service.dart';

/// Error codes a partner can hit when loading or acting on the queue. Exposed
/// as a typed enum (no `BuildContext`, no French copy), so the view layer
/// translates them via [AppLocalizations].
enum PartnerBookingError {
  /// 409 — the request was already handled or expired server-side.
  alreadyHandled,

  /// 403 — the caller is not authorized.
  forbidden,

  /// 404 — the resource does not exist (stale id).
  notFound,

  /// Network / timeout — the server could not be reached.
  network,

  /// Any other server error (5xx, unknown).
  generic,
}

/// Partner decision queue state (Espace partenaire).
///
/// Loads the `requested` bookings awaiting an answer and lets the partner
/// confirm or decline them. Deliberately thin: the server response is the
/// single source of truth — a successful respond simply drops the request
/// from the queue, and any rejected decision reloads the queue silently so
/// what the user sees always matches the backend.
///
/// No polling: the queue is loaded on open and on pull-to-refresh only.
class PartnerBookingsProvider extends ChangeNotifier {
  PartnerBookingsProvider({PartnerApi? partnerApi})
      : _api = partnerApi ?? ApiService();

  final PartnerApi _api;

  List<PartnerBooking> _items = [];
  bool _isLoading = false;
  PartnerBookingError? _error;

  /// True while a confirm/decline is in flight; the screen disables both
  /// buttons so a double tap cannot send two decisions.
  bool _isActing = false;
  PartnerBookingError? _actionError;

  List<PartnerBooking> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  PartnerBookingError? get error => _error;
  bool get isActing => _isActing;
  PartnerBookingError? get actionError => _actionError;

  /// Page size the backend serves by default (`GET /partner/bookings`,
  /// `limit=50`). When a full page comes back, more requests may exist beyond
  /// it — pagination is out of scope, so the screen just says so.
  static const int pageLimit = 50;

  /// True when the queue is at the API page limit, i.e. the display may be
  /// truncated. Lets the screen show a discreet "50 premières" notice.
  bool get hasMore => _items.length >= pageLimit;

  /// Loads (or reloads) the decision queue.
  ///
  /// A **reload** that fails keeps the queue already on screen — the error is
  /// exposed (403/404 get a dedicated message, anything else a generic one)
  /// but the list is untouched, so a pull-to-refresh on a flaky connection
  /// never blanks a queue the partner is working through. Only the first load
  /// starts from (and on failure returns to) an empty list.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await _api.listPartnerBookings();
      _items = raw.map(PartnerBooking.fromPartnerJson).toList();
      _error = null;
    } on ApiException catch (e) {
      _error = _errorCode(e);
    } catch (_) {
      _error = PartnerBookingError.network;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Confirms or declines [booking]. [decision] is `'confirm'` or `'decline'`;
  /// [note] is an optional partner note (≤ 500 chars).
  ///
  /// Returns true when the decision was accepted (the request is dropped from
  /// the queue), false otherwise with [actionError] set. A 409 (already
  /// handled / expired) also reloads the queue silently — another actor, or a
  /// stale screen, got there first.
  Future<bool> respond(
    PartnerBooking booking,
    String decision, {
    String? note,
  }) async {
    // Guard against a double tap racing two responds for the same booking.
    if (_isActing) return false;
    _isActing = true;
    _actionError = null;
    notifyListeners();
    try {
      await _api.respondToPartnerBooking(booking.id,
          decision: decision, note: note);
      // Server response is authoritative: drop the handled request from the
      // queue. On a replay the booking is already gone — removeWhere is a
      // no-op then, which is exactly right.
      _items = _items.where((b) => b.id != booking.id).toList();
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        _actionError = PartnerBookingError.alreadyHandled;
        // Someone else handled it (or it expired): resync silently so the
        // queue reflects reality, without surfacing a second error.
        await _reloadQuietly();
      } else {
        _actionError = _errorCode(e);
      }
      return false;
    } catch (_) {
      _actionError = PartnerBookingError.network;
      return false;
    } finally {
      _isActing = false;
      notifyListeners();
    }
  }

  /// Reloads the queue without touching [_error] (used after a 409): the user
  /// already sees the "already handled" message on [actionError].
  Future<void> _reloadQuietly() async {
    try {
      final raw = await _api.listPartnerBookings();
      _items = raw.map(PartnerBooking.fromPartnerJson).toList();
    } catch (_) {
      // Keep the current queue: the authoritative error (409) is already shown.
    }
  }

  /// Maps an [ApiException] to a [PartnerBookingError] code. The screen
  /// translates the code — the provider never holds French copy.
  PartnerBookingError _errorCode(ApiException e) {
    switch (e.statusCode) {
      case 403:
        return PartnerBookingError.forbidden;
      case 404:
        return PartnerBookingError.notFound;
      case 409:
        return PartnerBookingError.alreadyHandled;
      case null:
        return PartnerBookingError.network;
      default:
        return PartnerBookingError.generic;
    }
  }
}
