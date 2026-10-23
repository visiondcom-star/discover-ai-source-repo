import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/trip.dart';
import '../services/api_service.dart';

/// Locale-agnostic failure codes for trip planning operations. The provider has
/// no `BuildContext`, so it never renders text itself — the screen maps these
/// to localized strings via `AppLocalizations`.
enum TripError {
  network,
  generic,
}

/// Trip planning state. Same injectable-seam pattern as [POIProvider]:
/// tests run against a fake [TripsApi], never the network.
class TripProvider extends ChangeNotifier {
  TripProvider({TripsApi? tripsApi}) : _api = tripsApi ?? ApiService();

  final TripsApi _api;

  Trip? _currentTrip;
  List<Trip> _trips = [];
  bool _isGenerating = false;
  bool _isLoading = false;
  TripError? _error;

  Trip? get currentTrip => _currentTrip;
  List<Trip> get trips => _trips;
  bool get isGenerating => _isGenerating;
  bool get isLoading => _isLoading;
  TripError? get error => _error;

  /// Generates a trip and stores it as [currentTrip]. Returns the trip, or
  /// null on failure ([error] then carries the reason).
  Future<Trip?> generate({
    required List<String> interests,
    required String budgetLevel,
    required int numDays,
  }) async {
    _isGenerating = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.generateTrip(
        interests: interests,
        budgetLevel: budgetLevel,
        numDays: numDays,
      );
      _currentTrip = Trip.fromJson(data);
      _trips.insert(0, _currentTrip!);
      return _currentTrip;
    } on ApiException catch (e) {
      _error = e.statusCode == null ? TripError.network : TripError.generic;
      return null;
    } on SocketException catch (_) {
      _error = TripError.network;
      return null;
    } on TimeoutException catch (_) {
      _error = TripError.network;
      return null;
    } on http.ClientException catch (_) {
      _error = TripError.network;
      return null;
    } catch (_) {
      _error = TripError.generic;
      return null;
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> loadTrips() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.listTrips();
      _trips = data.map(Trip.fromJson).toList();
    } on ApiException catch (e) {
      _error = e.statusCode == null ? TripError.network : TripError.generic;
    } on SocketException catch (_) {
      _error = TripError.network;
    } on TimeoutException catch (_) {
      _error = TripError.network;
    } on http.ClientException catch (_) {
      _error = TripError.network;
    } catch (_) {
      _error = TripError.generic;
    }
    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
