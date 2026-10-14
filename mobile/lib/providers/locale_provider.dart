import 'package:flutter/foundation.dart';

import '../services/locale_store.dart';

/// User-chosen app locale (FR/EN), persisted across restarts.
///
/// Resolution order, first hit wins:
/// 1. persisted choice ([LocaleStore]) — [setLocale] writes it;
/// 2. device locale ([deviceLocaleCode], fr/en only) — first launch;
/// 3. `'fr'` — absolute fallback, never null, never unsupported.
///
/// The tenant `defaultLanguage` stays a separate concern: it seeds branding
/// and theme via [TenantProvider], not the UI language. Tying the two would
/// make a tenant switch silently flip the user's explicit choice.
/// [setLocale] persists, notifies, and returns the new code. [clearLocale]
/// forgets the persisted choice (falls back to device/fr).
class LocaleProvider extends ChangeNotifier {
  LocaleProvider({
    LocaleStore? localeStore,
    String Function()? deviceLocaleCode,
  })  : _store = localeStore ?? SecureLocaleStorage(),
        _deviceLocaleCode = deviceLocaleCode ??
            (() =>
                PlatformDispatcher.instance.locale.languageCode.toLowerCase()) {
    _initialized = _restore();
  }

  final LocaleStore _store;
  final String Function() _deviceLocaleCode;

  late final Future<void> _initialized;

  String _code = kDefaultLocale;
  bool _isLoading = true;

  /// Resolves once the persisted choice was read (tests, splash UX).
  Future<void> get initialized => _initialized;

  static const String kDefaultLocale = 'fr';

  static const List<String> supportedCodes = ['fr', 'en'];

  String get localeCode => _code;
  bool get isLoading => _isLoading;
  bool get isFrench => _code == 'fr';

  static String normalize(String? code) {
    final c = (code ?? '').trim().toLowerCase();
    return supportedCodes.contains(c) ? c : kDefaultLocale;
  }

  Future<void> _restore() async {
    final stored = await _store.readLocaleCode();
    if (stored != null &&
        supportedCodes.contains(stored.trim().toLowerCase())) {
      _code = stored.trim().toLowerCase();
    } else {
      _code = normalize(_deviceLocaleCode());
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Persists [code], applies it immediately, notifies, and returns it.
  /// Unsupported codes are ignored (no write, no notify) and null is
  /// returned.
  Future<String?> setLocale(String code) async {
    final normalized = code.trim().toLowerCase();
    if (!supportedCodes.contains(normalized)) return null;
    if (normalized == _code) {
      await _store.writeLocaleCode(normalized);
      return normalized;
    }
    _code = normalized;
    await _store.writeLocaleCode(normalized);
    notifyListeners();
    return normalized;
  }

  /// Forgets the persisted choice; the next resolution falls back to
  /// device/fr.
  Future<void> clearLocale() async {
    await _store.deleteLocaleCode();
    _code = normalize(_deviceLocaleCode());
    notifyListeners();
  }
}
