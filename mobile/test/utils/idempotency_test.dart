import 'package:discover_ai/utils/idempotency.dart';
import 'package:flutter_test/flutter_test.dart';

/// newIdempotencyKey — dependency-free UUID v4 used as `Idempotency-Key`.
void main() {
  test('generates 1000 unique RFC 4122 v4 keys', () {
    final keys = List.generate(1000, (_) => newIdempotencyKey());
    final v4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    for (final key in keys) {
      expect(key, matches(v4), reason: 'not an UUID v4: $key');
    }
    expect(keys.toSet(), hasLength(1000), reason: 'duplicate key generated');
  });
}
