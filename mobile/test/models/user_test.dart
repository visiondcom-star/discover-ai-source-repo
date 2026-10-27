import 'package:discover_ai/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

/// User.isPartner / canUsePartnerSpace — who may open the partner space.
void main() {
  Map<String, dynamic> meJson({
    bool? isAdmin,
    bool? isPartner,
  }) =>
      {
        'id': 'u-1',
        'email': 'partner@discoverai.dz',
        'full_name': 'Partner User',
        'is_active': true,
        'is_admin': isAdmin ?? false,
        if (isPartner != null) 'is_partner': isPartner,
        'preferences': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      };

  test('is_partner absent → false (payloads other than /auth/me)', () {
    final user = User.fromJson(meJson());
    expect(user.isPartner, isFalse);
    expect(user.canUsePartnerSpace, isFalse);
  });

  test('is_partner true → partner, may use the partner space', () {
    final user = User.fromJson(meJson(isPartner: true));
    expect(user.isPartner, isTrue);
    expect(user.canUsePartnerSpace, isTrue);
  });

  test('admin without attachment → not partner, but may use the space', () {
    final user = User.fromJson(meJson(isAdmin: true));
    expect(user.isPartner, isFalse);
    expect(user.isAdmin, isTrue);
    expect(user.canUsePartnerSpace, isTrue);
  });

  test('plain traveller → neither partner nor admin, no access', () {
    final user = User.fromJson(meJson());
    expect(user.isPartner, isFalse);
    expect(user.isAdmin, isFalse);
    expect(user.canUsePartnerSpace, isFalse);
  });

  test('toJson round-trips is_partner and is_admin', () {
    final user = User.fromJson(meJson(isAdmin: true, isPartner: true));
    final json = user.toJson();
    expect(json['is_partner'], isTrue);
    expect(json['is_admin'], isTrue);
    expect(User.fromJson(json).isPartner, isTrue);
    expect(User.fromJson(json).canUsePartnerSpace, isTrue);
  });

  test('locale field parses and round-trips correctly', () {
    final userWithLocale = User.fromJson({
      'id': 'u-2',
      'email': 'user@example.com',
      'locale': 'en',
    });
    expect(userWithLocale.locale, 'en');

    final json = userWithLocale.toJson();
    expect(json['locale'], 'en');
    expect(User.fromJson(json).locale, 'en');

    final userWithoutLocale = User.fromJson({
      'id': 'u-3',
      'email': 'user3@example.com',
    });
    expect(userWithoutLocale.locale, isNull);
  });
}
