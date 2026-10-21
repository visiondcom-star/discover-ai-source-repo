import 'package:discover_ai/providers/locale_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

/// LocaleProvider contract: persisted choice wins, then device locale
/// (fr/en), then the 'fr' default. Unsupported inputs never stick.
void main() {
  LocaleProvider _provider({
    InMemoryLocaleStore? store,
    String device = 'fr',
  }) =>
      LocaleProvider(
        localeStore: store ?? InMemoryLocaleStore(),
        deviceLocaleCode: () => device,
      );

  test('no persisted choice + device en → en', () async {
    final provider = _provider(device: 'en');
    await provider.initialized;

    expect(provider.isLoading, isFalse);
    expect(provider.localeCode, 'en');
    expect(provider.isFrench, isFalse);
  });

  test('no persisted choice + unsupported device → fr', () async {
    final provider = _provider(device: 'ar');
    await provider.initialized;

    expect(provider.localeCode, 'fr');
    expect(provider.isFrench, isTrue);
  });

  test('persisted choice wins over the device locale', () async {
    final store = InMemoryLocaleStore()..localeCode = 'en';
    final provider = _provider(store: store, device: 'fr');
    await provider.initialized;

    expect(provider.localeCode, 'en');
  });

  test('persisted garbage is ignored, device applies', () async {
    final store = InMemoryLocaleStore()..localeCode = 'xx';
    final provider = _provider(store: store, device: 'en');
    await provider.initialized;

    expect(provider.localeCode, 'en');
  });

  test('setLocale persists, applies and notifies', () async {
    final store = InMemoryLocaleStore();
    final provider = _provider(store: store, device: 'fr');
    await provider.initialized;
    var notified = 0;
    provider.addListener(() => notified++);

    final result = await provider.setLocale('en');

    expect(result, 'en');
    expect(provider.localeCode, 'en');
    expect(store.localeCode, 'en');
    expect(notified, 1);
  });

  test('setLocale rejects unsupported codes without writing', () async {
    final store = InMemoryLocaleStore();
    final provider = _provider(store: store, device: 'fr');
    await provider.initialized;
    var notified = 0;
    provider.addListener(() => notified++);

    final result = await provider.setLocale('ar');

    expect(result, isNull);
    expect(provider.localeCode, 'fr');
    expect(store.localeCode, isNull);
    expect(notified, 0);
  });

  test('clearLocale forgets the choice and falls back to device', () async {
    final store = InMemoryLocaleStore()..localeCode = 'en';
    final provider = _provider(store: store, device: 'fr');
    await provider.initialized;
    expect(provider.localeCode, 'en');

    await provider.clearLocale();

    expect(store.localeCode, isNull);
    expect(provider.localeCode, 'fr');
  });

  test('normalize maps null/unsupported/case variants to a supported code', () {
    expect(LocaleProvider.normalize(null), 'fr');
    expect(LocaleProvider.normalize(''), 'fr');
    expect(LocaleProvider.normalize('AR'), 'fr');
    expect(LocaleProvider.normalize('EN'), 'en');
    expect(LocaleProvider.normalize(' fr '), 'fr');
  });
}
