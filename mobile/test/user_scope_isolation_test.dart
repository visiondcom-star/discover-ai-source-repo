import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:discover_ai/app.dart';
import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/providers/admin_categories_provider.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/providers/chat_provider.dart';
import 'package:discover_ai/providers/locale_provider.dart';
import 'package:discover_ai/providers/notifications_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/providers/promotion_provider.dart';
import 'package:discover_ai/providers/research_collection_provider.dart';
import 'package:discover_ai/providers/research_provider.dart';
import 'package:discover_ai/providers/tenant_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/screens/home_shell.dart';
import 'package:discover_ai/screens/login_screen.dart';
import 'package:discover_ai/screens/notifications_screen.dart';
import 'package:discover_ai/services/api_service.dart';
import 'package:discover_ai/user_scope.dart';

import 'helpers/fake_admin_categories_api.dart';
import 'helpers/fake_research_collection_api.dart';
import 'helpers/fakes.dart';

class _DelayedChatApi implements ChatApi {
  _DelayedChatApi(this.completer);
  final Completer<Map<String, dynamic>> completer;

  @override
  Future<Map<String, dynamic>> sendMessage(String message,
      {Map<String, dynamic>? context}) {
    return completer.future;
  }
}

class _TwoUserAuthApi implements AuthApi {
  _TwoUserAuthApi();

  String? currentToken;
  String currentUserEmail = 'user1@discoverai.dz';
  String currentUserId = 'u-1';
  String currentLocale = 'fr';

  @override
  void setToken(String token) => currentToken = token;

  @override
  Future<Map<String, dynamic>> getMe() async => {
        'id': currentUserId,
        'email': currentUserEmail,
        'full_name': 'Test User',
        'locale': currentLocale,
        'is_active': true,
        'is_admin': false,
        'is_partner': false,
        'preferences': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      };

  @override
  Future<Map<String, dynamic>> login(String email, String password) async {
    currentUserEmail = email;
    currentUserId = email.contains('user2') ? 'u-2' : 'u-1';
    return {
      'access_token': 'token-$currentUserId',
      'token_type': 'bearer',
      'expires_in': 3600,
    };
  }

  @override
  Future<Map<String, dynamic>> register(String email, String password,
          {String? fullName}) async =>
      getMe();

  @override
  Future<Map<String, dynamic>> updateMe({required String locale}) async {
    currentLocale = locale;
    return getMe();
  }
}

List<SingleChildWidget> testUserScopedProviders() => [
      ChangeNotifierProvider(
        create: (_) => TripProvider(tripsApi: FakeTripsApi()),
      ),
      ChangeNotifierProvider(
        create: (_) => ChatProvider(
          chatApi: FakeChatApi(
            response: {
              'message': 'Assistant reply',
              'suggestions': <String>[],
              'context': <String, dynamic>{},
            },
          ),
        ),
      ),
      ChangeNotifierProvider(
        create: (_) => BookingProvider(
          bookingsApi: FakeBookingsApi(bookings: []),
        ),
      ),
      ChangeNotifierProvider(
        create: (_) => NotificationsProvider(
          api: FakeNotificationsApi(
            notifications: [],
            unreadCount: 0,
          ),
        ),
      ),
      ChangeNotifierProvider(
        create: (_) => AdminCategoriesProvider(FakeAdminCategoriesApi()),
      ),
      ChangeNotifierProvider(
        create: (_) => ResearchProvider(FakeResearchApi()),
      ),
      ChangeNotifierProvider(
        create: (_) => ResearchCollectionProvider(FakeResearchCollectionApi()),
      ),
    ];

Widget _buildApp({
  required AuthProvider authProvider,
  Widget? child,
  List<SingleChildWidget> Function()? providersBuilder,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<LocaleProvider>(
        create: (_) => LocaleProvider(localeStore: InMemoryLocaleStore()),
      ),
      ChangeNotifierProvider<TenantProvider>(
        create: (_) => TenantProvider(tenantsApi: FakeTenantsApi()),
      ),
      ChangeNotifierProvider<POIProvider>(
        create: (_) => POIProvider(poisApi: FakePoisApi()),
      ),
      ChangeNotifierProvider<PromotionProvider>(
        create: (_) => PromotionProvider(promotionsApi: FakePromotionsApi()),
      ),
    ],
    child: UserScope(
      providersBuilder: providersBuilder ?? testUserScopedProviders,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child ?? const AuthGate(),
      ),
    ),
  );
}

void main() {
  group('UserScope isolation tests', () {
    testWidgets(
        '(1) & (2) state is cleared on logout and new user has empty state',
        (tester) async {
      final authApi = _TwoUserAuthApi();
      final authProvider =
          AuthProvider(api: authApi, tokenStore: InMemoryTokenStore());
      await authProvider.initialized;
      await authProvider.login('user1@discoverai.dz', 'secret');

      final fakeBookingApi = FakeBookingsApi(bookings: []);
      final fakeNotifApi =
          FakeNotificationsApi(notifications: [], unreadCount: 0);

      await tester.pumpWidget(
        _buildApp(
          authProvider: authProvider,
          providersBuilder: () => [
            ChangeNotifierProvider(
              create: (_) => TripProvider(tripsApi: FakeTripsApi()),
            ),
            ChangeNotifierProvider(
              create: (_) => ChatProvider(
                chatApi: FakeChatApi(
                  response: {
                    'message': 'Assistant reply',
                    'suggestions': <String>[],
                    'context': <String, dynamic>{},
                  },
                ),
              ),
            ),
            ChangeNotifierProvider(
              create: (_) => BookingProvider(bookingsApi: fakeBookingApi),
            ),
            ChangeNotifierProvider(
              create: (_) => NotificationsProvider(api: fakeNotifApi),
            ),
            ChangeNotifierProvider(
              create: (_) => AdminCategoriesProvider(FakeAdminCategoriesApi()),
            ),
            ChangeNotifierProvider(
              create: (_) => ResearchProvider(FakeResearchApi()),
            ),
            ChangeNotifierProvider(
              create: (_) =>
                  ResearchCollectionProvider(FakeResearchCollectionApi()),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);

      final BuildContext homeCtx = tester.element(find.byType(HomeShell));
      final chat1 = Provider.of<ChatProvider>(homeCtx, listen: false);
      final booking1 = Provider.of<BookingProvider>(homeCtx, listen: false);
      final trip1 = Provider.of<TripProvider>(homeCtx, listen: false);
      final notif1 = Provider.of<NotificationsProvider>(homeCtx, listen: false);

      // Populate all 4 providers
      await chat1.sendMessage('Hello user 1');
      expect(chat1.messages.isNotEmpty, isTrue);

      fakeBookingApi.bookings.add(sampleBookingJson());
      await booking1.loadBookings();
      expect(booking1.items.isNotEmpty, isTrue);

      await trip1.generate(
        interests: ['culture'],
        budgetLevel: 'medium',
        numDays: 2,
      );
      expect(trip1.currentTrip, isNotNull);
      expect(trip1.trips.isNotEmpty, isTrue);

      fakeNotifApi.notifications.add(sampleNotificationJson());
      fakeNotifApi.unreadCount = 1;
      await notif1.load();
      expect(notif1.items.isNotEmpty, isTrue);
      expect(notif1.unreadCount, 1);

      // Clear server-side fake stores before logout so user 2 gets empty data
      fakeBookingApi.bookings.clear();
      fakeNotifApi.notifications.clear();
      fakeNotifApi.unreadCount = 0;

      // (1) Logout: triggers ValueKey change in UserScope
      await authProvider.logout();
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);

      // Old instances are disposed
      expect(chat1.disposed, isTrue);
      expect(booking1.disposed, isTrue);
      expect(trip1.disposed, isTrue);
      expect(notif1.disposed, isTrue);

      // (2) Login as user 2
      await authProvider.login('user2@discoverai.dz', 'secret');
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);

      final BuildContext homeCtx2 = tester.element(find.byType(HomeShell));
      final chat2 = Provider.of<ChatProvider>(homeCtx2, listen: false);
      final booking2 = Provider.of<BookingProvider>(homeCtx2, listen: false);
      final trip2 = Provider.of<TripProvider>(homeCtx2, listen: false);
      final notif2 =
          Provider.of<NotificationsProvider>(homeCtx2, listen: false);

      // Brand new instances
      expect(identical(chat1, chat2), isFalse);
      expect(identical(booking1, booking2), isFalse);
      expect(identical(trip1, trip2), isFalse);
      expect(identical(notif1, notif2), isFalse);

      // Completely empty state, no data from user 1
      expect(chat2.messages, isEmpty);
      expect(trip2.trips, isEmpty);
      expect(trip2.currentTrip, isNull);
      expect(booking2.items, isEmpty);
      expect(notif2.items, isEmpty);
      expect(notif2.unreadCount, 0);
    });

    testWidgets(
        '(3) same user updating locale (syncLocale) keeps same provider instances without reconstruction',
        (tester) async {
      final authApi = _TwoUserAuthApi();
      final authProvider =
          AuthProvider(api: authApi, tokenStore: InMemoryTokenStore());
      await authProvider.initialized;
      await authProvider.login('user1@discoverai.dz', 'secret');

      await tester.pumpWidget(_buildApp(authProvider: authProvider));
      await tester.pumpAndSettle();

      final BuildContext homeCtx = tester.element(find.byType(HomeShell));
      final chatBefore = Provider.of<ChatProvider>(homeCtx, listen: false);
      final bookingBefore =
          Provider.of<BookingProvider>(homeCtx, listen: false);
      final tripBefore = Provider.of<TripProvider>(homeCtx, listen: false);
      final notifBefore =
          Provider.of<NotificationsProvider>(homeCtx, listen: false);

      // Same user changes locale
      await authProvider.syncLocale('en');
      await tester.pumpAndSettle();

      final BuildContext homeCtxAfter = tester.element(find.byType(HomeShell));
      final chatAfter = Provider.of<ChatProvider>(homeCtxAfter, listen: false);
      final bookingAfter =
          Provider.of<BookingProvider>(homeCtxAfter, listen: false);
      final tripAfter = Provider.of<TripProvider>(homeCtxAfter, listen: false);
      final notifAfter =
          Provider.of<NotificationsProvider>(homeCtxAfter, listen: false);

      expect(identical(chatBefore, chatAfter), isTrue);
      expect(identical(bookingBefore, bookingAfter), isTrue);
      expect(identical(tripBefore, tripAfter), isTrue);
      expect(identical(notifBefore, notifAfter), isTrue);
    });

    testWidgets(
        '(4) chat response arriving after logout does not throw and does not appear in new instance',
        (tester) async {
      final authApi = _TwoUserAuthApi();
      final authProvider =
          AuthProvider(api: authApi, tokenStore: InMemoryTokenStore());
      await authProvider.initialized;
      await authProvider.login('user1@discoverai.dz', 'secret');

      final completer = Completer<Map<String, dynamic>>();
      final delayedChatApi = _DelayedChatApi(completer);

      await tester.pumpWidget(
        _buildApp(
          authProvider: authProvider,
          providersBuilder: () => [
            ChangeNotifierProvider(
              create: (_) => ChatProvider(chatApi: delayedChatApi),
            ),
            ChangeNotifierProvider(
              create: (_) => TripProvider(tripsApi: FakeTripsApi()),
            ),
            ChangeNotifierProvider(
              create: (_) => BookingProvider(bookingsApi: FakeBookingsApi()),
            ),
            ChangeNotifierProvider(
              create: (_) => NotificationsProvider(api: FakeNotificationsApi()),
            ),
            ChangeNotifierProvider(
              create: (_) => AdminCategoriesProvider(FakeAdminCategoriesApi()),
            ),
            ChangeNotifierProvider(
              create: (_) => ResearchProvider(FakeResearchApi()),
            ),
            ChangeNotifierProvider(
              create: (_) =>
                  ResearchCollectionProvider(FakeResearchCollectionApi()),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final BuildContext homeCtx = tester.element(find.byType(HomeShell));
      final chat1 = Provider.of<ChatProvider>(homeCtx, listen: false);

      // Start sending message
      final future = chat1.sendMessage('Late message');
      expect(chat1.isSending, isTrue);

      // Logout before reply lands
      await authProvider.logout();
      await tester.pumpAndSettle();

      // Now server sends late response
      completer.complete({
        'message': 'Late assistant response',
        'suggestions': <String>[],
        'context': <String, dynamic>{},
      });
      await future;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(chat1.disposed, isTrue);

      // Login as user 2 and verify new ChatProvider instance has empty messages
      await authProvider.login('user2@discoverai.dz', 'secret');
      await tester.pumpAndSettle();

      final BuildContext homeCtx2 = tester.element(find.byType(HomeShell));
      final chat2 = Provider.of<ChatProvider>(homeCtx2, listen: false);
      expect(identical(chat1, chat2), isFalse);
      expect(chat2.messages, isEmpty);
    });

    testWidgets(
        '(5) route pushed before logout ceases to exist after logout (only LoginScreen remains)',
        (tester) async {
      final authApi = _TwoUserAuthApi();
      final authProvider =
          AuthProvider(api: authApi, tokenStore: InMemoryTokenStore());
      await authProvider.initialized;
      await authProvider.login('user1@discoverai.dz', 'secret');

      await tester.pumpWidget(_buildApp(authProvider: authProvider));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);

      // Push a route (NotificationsScreen)
      final BuildContext homeCtx = tester.element(find.byType(HomeShell));
      Navigator.of(homeCtx).push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);

      // Logout
      await authProvider.logout();
      await tester.pumpAndSettle();

      // Pushed route no longer exists, only LoginScreen remains
      expect(find.byType(NotificationsScreen), findsNothing);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
