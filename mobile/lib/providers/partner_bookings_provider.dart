import 'package:flutter/foundation.dart';

import '../models/partner_booking.dart';
import '../services/api_service.dart';

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
  String? _error;

  /// True while a confirm/decline is in flight; the screen disables both
  /// buttons so a double tap cannot send two decisions.
  bool _isActing = false;
  String? _actionError;

  List<PartnerBooking> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isActing => _isActing;
  String? get actionError => _actionError;

  /// Loads (or reloads) the decision queue.
  ///
  /// On 403 (neither partner nor admin) or 404 the queue is emptied and a
  /// dedicated message is shown; any other failure gets a generic message.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await _api.listPartnerBookings();
      _items = raw.map(PartnerBooking.fromPartnerJson).toList();
      _error = null;
    } on ApiException catch (e) {
      _items = [];
      _error = _loadErrorMessage(e);
    } catch (_) {
      _items = [];
      _error = 'Impossible de charger les demandes. Vérifiez votre connexion.';
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
      _actionError = null;
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        _actionError =
            'Cette demande a déjà été traitée ou a expiré.';
        // Someone else handled it (or it expired): resync silently so the
        // queue reflects reality, without surfacing a second error.
        await _reloadQuietly();
      } else {
        _actionError = _respondErrorMessage(e);
      }
      return false;
    } catch (_) {
      _actionError =
          'Impossible d\'envoyer votre réponse. Vérifiez votre connexion.';
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

  String _loadErrorMessage(ApiException e) {
    if (e.statusCode == 403) {
      return 'Vous n\'avez pas accès à l\'espace partenaire.';
    }
    if (e.statusCode == 404) {
      return 'Espace partenaire introuvable.';
    }
    return 'Impossible de charger les demandes. Vérifiez votre connexion.';
  }

  String _respondErrorMessage(ApiException e) {
    if (e.statusCode == 403) {
      return 'Vous n\'avez pas accès à cette demande.';
    }
    if (e.statusCode == 404) {
      return 'Cette demande est introuvable.';
    }
    return 'Impossible d\'envoyer votre réponse. Vérifiez votre connexion.';
  }
}
