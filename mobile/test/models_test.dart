import 'package:flutter_test/flutter_test.dart';
import 'package:discover_ai/models/tenant.dart';
import 'package:discover_ai/models/user.dart';
import 'package:discover_ai/models/poi.dart';
import 'package:discover_ai/models/trip.dart' hide POI;

void main() {
  group('Tenant Model', () {
    test('parses from JSON', () {
      final json = {
        'id': '1', 'slug': 'algeria', 'name': 'Discover Algeria',
        'default_language': 'fr', 'supported_languages': ['fr', 'ar'],
        'default_currency': 'DZD', 'primary_color': '#006233',
        'secondary_color': '#FFFFFF',
      };
      final t = Tenant.fromJson(json);
      expect(t.slug, 'algeria');
      expect(t.name, 'Discover Algeria');
      expect(t.supportedLanguages.length, 2);
    });

    test('serializes to JSON', () {
      final t = Tenant(id: '1', slug: 'test', name: 'Test', defaultLanguage: 'fr',
        supportedLanguages: ['fr'], defaultCurrency: 'DZD',
        primaryColor: '#000', secondaryColor: '#FFF');
      final json = t.toJson();
      expect(json['slug'], 'test');
    });
  });

  group('User Model', () {
    test('parses from JSON', () {
      final u = User.fromJson({'id': '1', 'email': 'test@test.com', 'full_name': 'Test'});
      expect(u.email, 'test@test.com');
      expect(u.fullName, 'Test');
      expect(u.isAdmin, false);
    });
  });

  group('POI Model', () {
    test('parses from JSON', () {
      final json = {
        'id': '1', 'slug': 'casbah', 'name': 'Casbah', 'city': 'Alger',
        'category': 'historical', 'duration_minutes': 120,
        'price_range': 'free', 'tags': ['unesco'],
      };
      final p = POI.fromJson(json);
      expect(p.name, 'Casbah');
      expect(p.durationMinutes, 120);
      expect(p.tags, ['unesco']);
    });

    test('handles null coordinates', () {
      final p = POI.fromJson({'id': '1', 'slug': 'x', 'name': 'X', 'city': 'Y', 'category': 'z'});
      expect(p.latitude, null);
      expect(p.longitude, null);
    });
  });

  group('Trip Model', () {
    test('parses from JSON with items', () {
      final json = {
        'id': '1', 'title': 'Trip', 'num_days': 3,
        'items': [
          {'id': 'i1', 'poi_id': 'p1', 'day_number': 1, 'order_index': 0},
        ],
      };
      final t = Trip.fromJson(json);
      expect(t.items.length, 1);
      expect(t.items[0].dayNumber, 1);
    });
  });
}
