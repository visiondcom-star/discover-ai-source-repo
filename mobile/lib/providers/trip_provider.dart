import 'package:flutter/foundation.dart';

import '../models/trip.dart';
import '../services/api_service.dart';

/// Trip planning state. Same injectable-seam pattern as [POIProvider]:
/// tests run against a fake [TripsApi], never the network.
class TripProvider extends ChangeNotifier {
  TripProvider({TripsApi? tripsApi}) : _api = tripsApi ?? ApiService();

  final TripsApi _api;

  Trip? _currentTrip;
  List<Trip> _trips = [];
  bool _isGenerating = false;
  bool _isLoading = false;
  String? _error;

  Trip? get currentTrip => _currentTrip;
  List<Trip> get trips => _trips;
  bool get isGenerating => _isGenerating;
  bool get isLoading => _isLoading;
  String? get error => _error;

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
    } catch (e) {
      _error = e.toString();
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
      _trips =
          data.map(Trip.fromJson).toList();
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}