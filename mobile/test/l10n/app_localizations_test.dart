import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:discover_ai/l10n/app_localizations.dart';

/// Phase 0 du chantier i18n FR/EN : l'infrastructure seule, sans écran migré.
///
/// Ce test verrouille la garantie additive — avant toute migration d'écran,
/// les delegates/localisations se résolvent correctement dans un MaterialApp
/// réel, et le template FR (langue par défaut du tenant) est complet. Il ne
/// dépend d'aucune chaîne migrée : il ne peut donc pas casser quand les
/// écrans basculent vers AppLocalizations.of(context).
void main() {
  test('supportedLocales couvre fr et en', () {
    final codes =
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
    expect(codes, containsAll(<String>['fr', 'en']));
  });

  test('localizationsDelegates inclut le delegate app + les Global*', () {
    // AppLocalizations.localizationsDelegates bundle déjà les delegates
    // GlobalMaterial/Cupertino/Widgets : MaterialApp n'a besoin de rien
    // d'autre pour les date pickers, etc.
    expect(AppLocalizations.localizationsDelegates, isNotEmpty);
    expect(
      AppLocalizations.localizationsDelegates
          .any((d) => d is LocalizationsDelegate<AppLocalizations>),
      isTrue,
      reason: 'le delegate AppLocalizations doit être dans la liste',
    );
    expect(
      AppLocalizations.localizationsDelegates
          .any((d) => d == GlobalMaterialLocalizations.delegate),
      isTrue,
    );
  });

  test('chaque locale supportée se charge et traduit appName', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final loc = await AppLocalizations.delegate.load(locale);
      expect(loc.appName, 'Discover AI',
          reason: 'appName manquant pour ${locale.languageCode}');
    }
  });

  testWidgets('AppLocalizations.of se résout dans un MaterialApp câblé',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          final loc = AppLocalizations.of(context);
          return Text('name=${loc.appName}');
        }),
      ),
    );
    await tester.pumpAndSettle();
    // La locale du système de test peut être fr ou en ; appName est « Discover
    // AI » dans les deux, donc l'assertion est stable quelle que soit la locale.
    expect(find.text('name=Discover AI'), findsOneWidget);
  });

  test('parité des clés : fr et en couvrent exactement le même ensemble', () {
    // Verrouille que chaque clé traduite existe dans les deux langues. Si
    // un écran migré appelle `AppLocalizations.of(context).maCle` et que la
    // langue est forcée sur l'autre locale, on aurait un crash à l'exécution
    // — ce test détecte la divergence au moment du build.
    //
    // On lit directement les .arb (la source) : c'est plus fiable
    // qu'introspecter la classe générée, et le diff entre les deux langues
    // saute aux yeux.
    final fr = _arbKeys(_frPath);
    final en = _arbKeys(_enPath);

    final missingInEn = fr.difference(en);
    final missingInFr = en.difference(fr);
    expect(missingInEn, isEmpty,
        reason: 'clés présentes en FR mais absentes en EN : $missingInEn');
    expect(missingInFr, isEmpty,
        reason: 'clés présentes en EN mais absentes en FR : $missingInFr');
  });
}

/// Reads the top-level translation keys from an ARB file. Metadata keys
/// (prefixed with `@`, like `@partnerTraveller`) and the `@@locale`
/// directive are filtered out — they aren't user-facing strings.
Set<String> _arbKeys(String path) {
  final raw = File(path).readAsStringSync();
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return {
    for (final entry in json.entries)
      if (!entry.key.startsWith('@')) entry.key,
  };
}

/// Resolves an ARB path relative to the package root (this file lives in
/// `test/l10n/`). When the test is run from the project root, Flutter sets
/// the working directory to the package root, so a relative `lib/l10n/...`
/// path works — but the test also documents the full path it expects.
const _frPath = 'lib/l10n/app_fr.arb';
const _enPath = 'lib/l10n/app_en.arb';
