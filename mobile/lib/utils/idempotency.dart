import 'dart:math';

final Random _rng = Random.secure();

/// UUID v4 sans dépendance externe.
///
/// Utilisé comme `Idempotency-Key` lors de la création d'une réservation :
/// une clé par tentative logique, réutilisée telle quelle sur un retry
/// réseau pour que le backend rejoue (200) au lieu de dupliquer.
String newIdempotencyKey() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final s = List.generate(16, h).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20)}';
}
