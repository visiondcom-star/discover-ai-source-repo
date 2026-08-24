import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/app.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets('app boots to the login gate when unauthenticated',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider(
              api: FakeAuthApi(),
              tokenStore: InMemoryTokenStore(),
            ),
          ),
          ChangeNotifierProvider<POIProvider>(
            create: (_) => POIProvider(poisApi: FakePoisApi()),
          ),
        ],
        child: const DiscoverAIApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_email')), findsOneWidget);
    expect(find.text('Discover AI'), findsOneWidget);
  });
}