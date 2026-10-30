import 'package:flutter/foundation.dart';

/// Mixin ensuring a [ChangeNotifier] never calls [notifyListeners] after being
/// disposed, preventing `FlutterError: A ChangeNotifier was used after being disposed`.
mixin SafeNotifier on ChangeNotifier {
  bool _disposed = false;

  /// True once [dispose] has been called on this notifier.
  bool get disposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}
