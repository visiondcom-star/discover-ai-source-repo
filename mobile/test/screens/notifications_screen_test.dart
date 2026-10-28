import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:discover_ai/l10n/app_localizations.dart';
import 'package:discover_ai/providers/auth_provider.dart';
import 'package:discover_ai/providers/booking_provider.dart';
import 'package:discover_ai/providers/chat_provider.dart';
import 'package:discover_ai/providers/locale_provider.dart';
import 'package:discover_ai/providers/notifications_provider.dart';
import 'package:discover_ai/providers/poi_provider.dart';
import 'package:discover_ai/providers/promotion_provider.dart';
import 'package:discover_ai/providers/tenant_provider.dart';
import 'package:discover_ai/providers/trip_provider.dart';
import 'package:discover_ai/screens/home_screen.dart';
import 'package:discover_ai/screens/home_shell.dart';
import 'package:discover_ai/screens/notifications_screen.dart';
import 'package:discover_ai/screens/partner_bookings_screen.dart';
import 'package:discover_ai/services/api_service.dart';

import '../helpers/fakes.dart';

Widget _buildTestApp({
  required Widget child,
  Locale locale = const Locale('fr'),
  NotificationsProvider? notificationsProvider,
  AuthProvider? authProvider,
  TenantProvider? tenantProvider,
  PromotionProvider? promotionProvider,
}) {
  return MultiProvider(
    providers: [
      if (notificationsProvider != null)
        ChangeNotifierProvider<NotificationsProvider>.value(
          value: notificationsProvider,
        ),
      if (authProvider != null)
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
        ),
      if (tenantProvider != null)
        ChangeNotifierProvider<TenantProvider>.value(
          value: tenantProvider,
        ),
      if (promotionProvider != null)
        ChangeNotifierProvider<PromotionProvider>.value(
          value: promotionProvider,
        ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: child,
    ),
  );
}

void main() {
  group('NotificationsScreen widget tests (FR and EN)', () {
    testWidgets('empty state displays localized message in FR and EN',
        (tester) async {
      final fakeApiFr = FakeNotificationsApi(notifications: [], unreadCount: 0);
      final providerFr = NotificationsProvider(api: fakeApiFr);

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: providerFr,
        locale: const Locale('fr'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
      expect(find.text('Aucune notification pour le moment'), findsOneWidget);
      expect(find.byKey(const Key('notifications_mark_all_button')),
          findsOneWidget);
      final markAllButtonFr = tester.widget<TextButton>(
        find.byKey(const Key('notifications_mark_all_button')),
      );
      expect(markAllButtonFr.onPressed, isNull); // Disabled when no unread

      // EN check
      final fakeApiEn = FakeNotificationsApi(notifications: [], unreadCount: 0);
      final providerEn = NotificationsProvider(api: fakeApiEn);

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: providerEn,
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
      expect(find.text('No notifications yet'), findsOneWidget);
    });

    testWidgets('error state with retry button recovers cleanly',
        (tester) async {
      final fakeApi = FakeNotificationsApi(
        getNotificationsError: const SocketException('No network'),
      );
      final provider = NotificationsProvider(api: fakeApi);

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: provider,
        locale: const Locale('fr'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_error')), findsOneWidget);
      expect(
          find.text(
              'Impossible de charger les notifications. Vérifiez votre connexion.'),
          findsOneWidget);
      expect(
          find.byKey(const Key('notifications_retry_button')), findsOneWidget);

      // Now clear error and provide notification
      fakeApi.getNotificationsError = null;
      fakeApi.notifications.add(sampleNotificationJson(
        id: 'n-1',
        title: 'Nouvelle alerte',
      ));

      await tester.tap(find.byKey(const Key('notifications_retry_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_error')), findsNothing);
      expect(find.byKey(const Key('notification_tile_n-1')), findsOneWidget);
      expect(find.text('Nouvelle alerte'), findsOneWidget);
    });

    testWidgets('error state with retry button recovers cleanly in EN',
        (tester) async {
      final fakeApi = FakeNotificationsApi(
        getNotificationsError: const SocketException('No network'),
      );
      final provider = NotificationsProvider(api: fakeApi);

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: provider,
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_error')), findsOneWidget);
      expect(find.text('Could not load notifications. Check your connection.'),
          findsOneWidget);
      expect(
          find.byKey(const Key('notifications_retry_button')), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      fakeApi.getNotificationsError = null;
      fakeApi.notifications.add(sampleNotificationJson(
        id: 'n-1',
        title: 'New alert',
      ));

      await tester.tap(find.byKey(const Key('notifications_retry_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_error')), findsNothing);
      expect(find.byKey(const Key('notification_tile_n-1')), findsOneWidget);
      expect(find.text('New alert'), findsOneWidget);
    });

    testWidgets(
        'notifications list renders items, dates, and tapping marks as read in EN',
        (tester) async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(
            id: 'notif-1',
            title: 'Casbah Booking',
            message: 'Confirmed for 2 guests.',
            type: 'system',
            read: false,
            createdAt: '2026-10-27T10:00:00',
          ),
          sampleNotificationJson(
            id: 'notif-2',
            title: 'Request received',
            message: 'For restaurant.',
            type: 'system',
            read: true,
            createdAt: null,
          ),
        ],
        unreadCount: 1,
      );
      final provider = NotificationsProvider(api: fakeApi);

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: provider,
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_list')), findsOneWidget);
      expect(
          find.byKey(const Key('notification_tile_notif-1')), findsOneWidget);
      expect(
          find.byKey(const Key('notification_tile_notif-2')), findsOneWidget);
      expect(find.text('Casbah Booking'), findsOneWidget);
      expect(find.text('Confirmed for 2 guests.'), findsOneWidget);
      expect(find.textContaining('Oct 27, 2026'), findsOneWidget);
      expect(
          find.descendant(
            of: find.byKey(const Key('notification_tile_notif-2')),
            matching: find.textContaining('2026'),
          ),
          findsNothing);

      await tester.tap(find.byKey(const Key('notification_tile_notif-1')));
      await tester.pumpAndSettle();

      expect(fakeApi.markReadCalls, 1);
      expect(fakeApi.markedReadIds, contains('notif-1'));
      expect(provider.items.first.read, isTrue);
      expect(provider.unreadCount, 0);
    });

    testWidgets(
        'notifications list renders items, dates, and tapping marks as read',
        (tester) async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(
            id: 'notif-1',
            title: 'Réservation Casbah',
            message: 'Confirmée pour 2 personnes.',
            type: 'booking_confirmed',
            read: false,
            createdAt: '2026-10-27T10:00:00',
          ),
          sampleNotificationJson(
            id: 'notif-2',
            title: 'Demande reçue',
            message: 'Pour le restaurant.',
            type: 'booking_request_received',
            read: true,
            createdAt: null, // Null date test
          ),
        ],
        unreadCount: 1,
      );
      final provider = NotificationsProvider(api: fakeApi);

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: provider,
        locale: const Locale('fr'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_list')), findsOneWidget);
      expect(
          find.byKey(const Key('notification_tile_notif-1')), findsOneWidget);
      expect(
          find.byKey(const Key('notification_tile_notif-2')), findsOneWidget);
      expect(find.text('Réservation Casbah'), findsOneWidget);
      expect(find.text('Confirmée pour 2 personnes.'), findsOneWidget);
      expect(find.textContaining('27 oct. 2026'), findsOneWidget);
      expect(
          find.descendant(
            of: find.byKey(const Key('notification_tile_notif-2')),
            matching: find.textContaining('2026'),
          ),
          findsNothing);

      // Tap unread notification tile marks as read
      await tester.tap(find.byKey(const Key('notification_tile_notif-1')));
      await tester.pumpAndSettle();

      expect(fakeApi.markReadCalls, 1);
      expect(fakeApi.markedReadIds, contains('notif-1'));
      expect(provider.items.first.read, isTrue);
      expect(provider.unreadCount, 0);
    });

    testWidgets('mark all as read button triggers provider.markAllRead',
        (tester) async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(id: 'n-1', read: false),
          sampleNotificationJson(id: 'n-2', read: false),
        ],
        unreadCount: 2,
      );
      final provider = NotificationsProvider(api: fakeApi);

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: provider,
        locale: const Locale('fr'),
      ));
      await tester.pumpAndSettle();

      final markAllFinder =
          find.byKey(const Key('notifications_mark_all_button'));
      expect(markAllFinder, findsOneWidget);
      await tester.tap(markAllFinder);
      await tester.pumpAndSettle();

      expect(fakeApi.markAllReadCalls, 1);
      expect(provider.unreadCount, 0);
      expect(provider.items.every((n) => n.read), isTrue);
    });

    testWidgets('mark all as read button triggers provider.markAllRead in EN',
        (tester) async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(id: 'n-1', read: false),
          sampleNotificationJson(id: 'n-2', read: false),
        ],
        unreadCount: 2,
      );
      final provider = NotificationsProvider(api: fakeApi);

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: provider,
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();

      final markAllFinder =
          find.byKey(const Key('notifications_mark_all_button'));
      expect(markAllFinder, findsOneWidget);
      expect(find.text('Mark all as read'), findsOneWidget);
      await tester.tap(markAllFinder);
      await tester.pumpAndSettle();

      expect(fakeApi.markAllReadCalls, 1);
      expect(provider.unreadCount, 0);
      expect(provider.items.every((n) => n.read), isTrue);
    });

    testWidgets('pull to refresh reloads notifications', (tester) async {
      final fakeApi = FakeNotificationsApi(
        notifications: [sampleNotificationJson(id: 'n-1')],
      );
      final provider = NotificationsProvider(api: fakeApi);

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: provider,
        locale: const Locale('fr'),
      ));
      await tester.pumpAndSettle();

      expect(fakeApi.getNotificationsCalls, 1);

      // Pull down to trigger RefreshIndicator
      await tester.fling(find.byKey(const Key('notifications_list')),
          const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(fakeApi.getNotificationsCalls, 2);
    });
  });

  group('HomeScreen notification bell and badge tests', () {
    testWidgets('badge hidden when unreadCount == 0', (tester) async {
      final fakeApi = FakeNotificationsApi(unreadCount: 0);
      final provider = NotificationsProvider(api: fakeApi);
      final fakeTenantsApi = FakeTenantsApi();
      final tenantProvider = TenantProvider(tenantsApi: fakeTenantsApi);
      final authProvider =
          AuthProvider(api: FakeAuthApi(), tokenStore: InMemoryTokenStore());
      await authProvider.initialized;
      await authProvider.login('test@example.com', 'pw');

      await tester.pumpWidget(_buildTestApp(
        child: const HomeScreen(),
        notificationsProvider: provider,
        authProvider: authProvider,
        tenantProvider: tenantProvider,
        promotionProvider:
            PromotionProvider(promotionsApi: FakePromotionsApi()),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_bell')), findsOneWidget);
      expect(find.byKey(const Key('notifications_badge')), findsNothing);
    });

    testWidgets('badge displays exact count for 3 and capped at 99+ for 120',
        (tester) async {
      final fakeApi = FakeNotificationsApi(unreadCount: 3);
      final provider = NotificationsProvider(api: fakeApi);
      await provider.refreshUnreadCount();
      final fakeTenantsApi = FakeTenantsApi();
      final tenantProvider = TenantProvider(tenantsApi: fakeTenantsApi);
      final authProvider =
          AuthProvider(api: FakeAuthApi(), tokenStore: InMemoryTokenStore());
      await authProvider.initialized;
      await authProvider.login('test@example.com', 'pw');

      await tester.pumpWidget(_buildTestApp(
        child: const HomeScreen(),
        notificationsProvider: provider,
        authProvider: authProvider,
        tenantProvider: tenantProvider,
        promotionProvider:
            PromotionProvider(promotionsApi: FakePromotionsApi()),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_badge')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // Change count to 120 and refresh
      fakeApi.unreadCount = 120;
      await provider.refreshUnreadCount();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_badge')), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('tapping bell opens NotificationsScreen', (tester) async {
      final fakeApi = FakeNotificationsApi(unreadCount: 1);
      final provider = NotificationsProvider(api: fakeApi);
      final fakeTenantsApi = FakeTenantsApi();
      final tenantProvider = TenantProvider(tenantsApi: fakeTenantsApi);
      final authProvider =
          AuthProvider(api: FakeAuthApi(), tokenStore: InMemoryTokenStore());
      await authProvider.initialized;
      await authProvider.login('test@example.com', 'pw');

      await tester.pumpWidget(_buildTestApp(
        child: const HomeScreen(),
        notificationsProvider: provider,
        authProvider: authProvider,
        tenantProvider: tenantProvider,
        promotionProvider:
            PromotionProvider(promotionsApi: FakePromotionsApi()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notifications_bell')));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
    });

    testWidgets(
        'tapping notifications_bell in real HomeShell provides NotificationsProvider to pushed route',
        (tester) async {
      final authProvider =
          AuthProvider(api: FakeAuthApi(), tokenStore: InMemoryTokenStore());
      await authProvider.initialized;
      await authProvider.login('test@example.com', 'pw');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<TenantProvider>(
              create: (_) => TenantProvider(tenantsApi: FakeTenantsApi()),
            ),
            ChangeNotifierProvider<PromotionProvider>(
              create: (_) =>
                  PromotionProvider(promotionsApi: FakePromotionsApi()),
            ),
            ChangeNotifierProvider<BookingProvider>(
              create: (_) =>
                  BookingProvider(bookingsApi: FakeBookingsApi(bookings: [])),
            ),
            ChangeNotifierProvider<POIProvider>(
              create: (_) => POIProvider(poisApi: FakePoisApi()),
            ),
            ChangeNotifierProvider<TripProvider>(
              create: (_) => TripProvider(),
            ),
            ChangeNotifierProvider<ChatProvider>(
              create: (_) => ChatProvider(),
            ),
            ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider(localeStore: InMemoryLocaleStore()),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomeShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notifications_bell')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });
  });

  group('HomeShell provides NotificationsProvider', () {
    testWidgets(
        'HomeShell wraps tree in NotificationsProvider and renders child',
        (tester) async {
      final authProvider =
          AuthProvider(api: FakeAuthApi(), tokenStore: InMemoryTokenStore());
      await authProvider.initialized;
      await authProvider.login('test@example.com', 'pw');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<TenantProvider>(
              create: (_) => TenantProvider(tenantsApi: FakeTenantsApi()),
            ),
            ChangeNotifierProvider<PromotionProvider>(
              create: (_) =>
                  PromotionProvider(promotionsApi: FakePromotionsApi()),
            ),
            ChangeNotifierProvider<BookingProvider>(
              create: (_) =>
                  BookingProvider(bookingsApi: FakeBookingsApi(bookings: [])),
            ),
            ChangeNotifierProvider<POIProvider>(
              create: (_) => POIProvider(poisApi: FakePoisApi()),
            ),
            ChangeNotifierProvider<TripProvider>(
              create: (_) => TripProvider(),
            ),
            ChangeNotifierProvider<ChatProvider>(
              create: (_) => ChatProvider(),
            ),
            ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider(localeStore: InMemoryLocaleStore()),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomeShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // NotificationsProvider should be accessible in the tree
      final BuildContext homeContext = tester.element(find.byType(HomeScreen));
      final notifProvider =
          Provider.of<NotificationsProvider>(homeContext, listen: false);
      expect(notifProvider, isNotNull);
    });
  });

  group('Notifications tapping navigation according to type', () {
    testWidgets('booking_request_received opens partner space for partner user',
        (tester) async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(
            id: 'n-partner',
            type: 'booking_request_received',
            read: false,
          ),
        ],
        unreadCount: 1,
      );
      final notifProvider = NotificationsProvider(api: fakeApi);

      final authProvider = AuthProvider(
        api: FakeAuthApi(isPartner: true),
        tokenStore: InMemoryTokenStore(),
      );
      await authProvider.initialized;
      await authProvider.login('partner@discoverai.dz', 'secret');

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: notifProvider,
        authProvider: authProvider,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notification_tile_n-partner')));
      await tester.pumpAndSettle();

      expect(find.byType(PartnerBookingsScreen), findsOneWidget);
      expect(fakeApi.markedReadIds, contains('n-partner'));
    });

    testWidgets(
        'booking_request_received does NOT open partner space for ordinary user',
        (tester) async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(
            id: 'n-ordinary',
            type: 'booking_request_received',
            read: false,
          ),
        ],
        unreadCount: 1,
      );
      final notifProvider = NotificationsProvider(api: fakeApi);

      final authProvider = AuthProvider(
        api: FakeAuthApi(
          failLogin: false,
          failGetMe: false,
          userLocale: 'fr',
        ),
        tokenStore: InMemoryTokenStore(),
      );
      await authProvider.initialized;
      await authProvider.login('traveller@discoverai.dz', 'secret');

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: notifProvider,
        authProvider: authProvider,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notification_tile_n-ordinary')));
      await tester.pumpAndSettle();

      expect(find.byType(PartnerBookingsScreen), findsNothing);
      expect(fakeApi.markedReadIds, contains('n-ordinary'));
    });

    testWidgets(
        'booking_confirmed, declined, expired closes notifications and selects tab_bookings in HomeShell',
        (tester) async {
      for (final type in [
        'booking_confirmed',
        'booking_declined',
        'booking_expired'
      ]) {
        final fakeApi = FakeNotificationsApi(
          notifications: [
            sampleNotificationJson(id: 'n-$type', type: type, read: false),
          ],
          unreadCount: 1,
        );
        final notifProvider = NotificationsProvider(api: fakeApi);

        final authProvider = AuthProvider(
          api: FakeAuthApi(),
          tokenStore: InMemoryTokenStore(),
        );
        await authProvider.initialized;
        await authProvider.login('user@discoverai.dz', 'secret');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<NotificationsProvider>.value(
                value: notifProvider,
              ),
              ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
              ChangeNotifierProvider<TenantProvider>(
                create: (_) => TenantProvider(tenantsApi: FakeTenantsApi()),
              ),
              ChangeNotifierProvider<PromotionProvider>(
                create: (_) =>
                    PromotionProvider(promotionsApi: FakePromotionsApi()),
              ),
              ChangeNotifierProvider<BookingProvider>(
                create: (_) =>
                    BookingProvider(bookingsApi: FakeBookingsApi(bookings: [])),
              ),
              ChangeNotifierProvider<POIProvider>(
                create: (_) => POIProvider(poisApi: FakePoisApi()),
              ),
              ChangeNotifierProvider<TripProvider>(
                create: (_) => TripProvider(),
              ),
              ChangeNotifierProvider<ChatProvider>(
                create: (_) => ChatProvider(),
              ),
              ChangeNotifierProvider<LocaleProvider>(
                create: (_) =>
                    LocaleProvider(localeStore: InMemoryLocaleStore()),
              ),
            ],
            child: MaterialApp(
              key: UniqueKey(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: HomeShell(notificationsProvider: notifProvider),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially tab_home is selected (index 0)
        final navBarBefore =
            tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(navBarBefore.selectedIndex, 0);

        // Open notifications screen
        await tester.tap(find.byKey(const Key('notifications_bell')));
        await tester.pumpAndSettle();
        expect(find.byType(NotificationsScreen), findsOneWidget);

        // Tap the booking notification tile
        await tester.tap(find.byKey(Key('notification_tile_n-$type')));
        await tester.pumpAndSettle();

        // NotificationsScreen closed
        expect(find.byType(NotificationsScreen), findsNothing);

        // Shell switched to tab_bookings (index 2)
        final navBarAfter =
            tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(navBarAfter.selectedIndex, 2);
        expect(find.byKey(const Key('tab_bookings')), findsOneWidget);

        // Marked as read
        expect(fakeApi.markedReadIds, contains('n-$type'));
      }
    });

    testWidgets('other notification type marks read without navigation',
        (tester) async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(
            id: 'n-other',
            type: 'system_announcement',
            read: false,
          ),
        ],
        unreadCount: 1,
      );
      final notifProvider = NotificationsProvider(api: fakeApi);

      final authProvider = AuthProvider(
        api: FakeAuthApi(),
        tokenStore: InMemoryTokenStore(),
      );
      await authProvider.initialized;
      await authProvider.login('user@discoverai.dz', 'secret');

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: notifProvider,
        authProvider: authProvider,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notification_tile_n-other')));
      await tester.pumpAndSettle();

      // NotificationsScreen stays open, no navigation
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(fakeApi.markedReadIds, contains('n-other'));
    });
  });

  group('HomeShell lifecycle resumed unread count refresh', () {
    testWidgets(
        'refreshUnreadCount called on resumed, not on paused, not after dispose',
        (tester) async {
      final fakeApi = FakeNotificationsApi(unreadCount: 1);
      final notifProvider = NotificationsProvider(api: fakeApi);

      final authProvider = AuthProvider(
        api: FakeAuthApi(),
        tokenStore: InMemoryTokenStore(),
      );
      await authProvider.initialized;
      await authProvider.login('user@discoverai.dz', 'secret');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NotificationsProvider>.value(
              value: notifProvider,
            ),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<TenantProvider>(
              create: (_) => TenantProvider(tenantsApi: FakeTenantsApi()),
            ),
            ChangeNotifierProvider<PromotionProvider>(
              create: (_) =>
                  PromotionProvider(promotionsApi: FakePromotionsApi()),
            ),
            ChangeNotifierProvider<BookingProvider>(
              create: (_) =>
                  BookingProvider(bookingsApi: FakeBookingsApi(bookings: [])),
            ),
            ChangeNotifierProvider<POIProvider>(
              create: (_) => POIProvider(poisApi: FakePoisApi()),
            ),
            ChangeNotifierProvider<TripProvider>(
              create: (_) => TripProvider(),
            ),
            ChangeNotifierProvider<ChatProvider>(
              create: (_) => ChatProvider(),
            ),
            ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider(localeStore: InMemoryLocaleStore()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomeShell(notificationsProvider: notifProvider),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Transition to inactive -> hidden -> paused: no refresh call
      fakeApi.getNotificationsCalls = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(fakeApi.getNotificationsCalls, 0);

      // 2. Transition back to hidden -> inactive -> resumed: triggers exactly 1 refresh call
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(fakeApi.getNotificationsCalls, 1);

      // 3. Dispose HomeShell: replace with empty container
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      fakeApi.getNotificationsCalls = 0;

      // 4. Transition to inactive -> hidden -> paused -> hidden -> inactive -> resumed after dispose: no calls
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(fakeApi.getNotificationsCalls, 0);
    });
  });

  group('Notification error banner tests', () {
    testWidgets(
        'error banner appears on reload failure with non-empty list and disappears after retry',
        (tester) async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(id: 'n-1', title: 'Notification 1'),
        ],
        unreadCount: 1,
      );
      final provider = NotificationsProvider(api: fakeApi);

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: provider,
        locale: const Locale('fr'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_list')), findsOneWidget);
      expect(find.byKey(const Key('notifications_error_banner')), findsNothing);

      // Trigger reload error
      fakeApi.getNotificationsError = const SocketException('offline');
      await provider.load();
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('notifications_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('notifications_banner_retry_button')),
          findsOneWidget);
      expect(
          find.text(
              'Impossible de charger les notifications. Vérifiez votre connexion.'),
          findsOneWidget);
      // Items still displayed
      expect(find.byKey(const Key('notifications_list')), findsOneWidget);

      // Tap retry with working API
      fakeApi.getNotificationsError = null;
      await tester
          .tap(find.byKey(const Key('notifications_banner_retry_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_error_banner')), findsNothing);
    });

    testWidgets(
        'error banner appears on reload failure with non-empty list and disappears after retry in EN',
        (tester) async {
      final fakeApi = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(id: 'n-1', title: 'Notification 1'),
        ],
        unreadCount: 1,
      );
      final provider = NotificationsProvider(api: fakeApi);

      await tester.pumpWidget(_buildTestApp(
        child: const NotificationsScreen(),
        notificationsProvider: provider,
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_list')), findsOneWidget);
      expect(find.byKey(const Key('notifications_error_banner')), findsNothing);

      // Trigger reload error
      fakeApi.getNotificationsError = const SocketException('offline');
      await provider.load();
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('notifications_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('notifications_banner_retry_button')),
          findsOneWidget);
      expect(find.text('Could not load notifications. Check your connection.'),
          findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Items still displayed
      expect(find.byKey(const Key('notifications_list')), findsOneWidget);

      // Tap retry with working API
      fakeApi.getNotificationsError = null;
      await tester
          .tap(find.byKey(const Key('notifications_banner_retry_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notifications_error_banner')), findsNothing);
    });

    testWidgets('markRead and markAllRead failures show banner in FR and EN',
        (tester) async {
      // 1. markRead failure in FR
      final fakeApiFr = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(
            id: 'n-1',
            title: 'Notif 1',
            type: 'system',
            read: false,
          ),
        ],
        unreadCount: 1,
      );
      final providerFr = NotificationsProvider(api: fakeApiFr);

      await tester.pumpWidget(_buildTestApp(
        child: NotificationsScreen(key: UniqueKey()),
        notificationsProvider: providerFr,
        locale: const Locale('fr'),
      ));
      await tester.pumpAndSettle();

      fakeApiFr.markReadError = const SocketException('offline');
      await tester.tap(find.byKey(const Key('notification_tile_n-1')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('notifications_error_banner')), findsOneWidget);
      expect(
          find.text(
              'Impossible de charger les notifications. Vérifiez votre connexion.'),
          findsOneWidget);

      // 2. markRead failure in EN
      final fakeApiEn = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(
            id: 'n-2',
            title: 'Notif 2',
            type: 'system',
            read: false,
          ),
        ],
        unreadCount: 1,
      );
      final providerEn = NotificationsProvider(api: fakeApiEn);

      await tester.pumpWidget(_buildTestApp(
        child: NotificationsScreen(key: UniqueKey()),
        notificationsProvider: providerEn,
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();

      fakeApiEn.markReadError = const SocketException('offline');
      await tester.tap(find.byKey(const Key('notification_tile_n-2')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('notifications_error_banner')), findsOneWidget);
      expect(find.text('Could not load notifications. Check your connection.'),
          findsOneWidget);

      // 3. markAllRead failure in FR (generic)
      final fakeApiAllFr = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(
            id: 'n-3',
            title: 'Notif 3',
            type: 'system',
            read: false,
          ),
        ],
        unreadCount: 1,
      );
      final providerAllFr = NotificationsProvider(api: fakeApiAllFr);

      await tester.pumpWidget(_buildTestApp(
        child: NotificationsScreen(key: UniqueKey()),
        notificationsProvider: providerAllFr,
        locale: const Locale('fr'),
      ));
      await tester.pumpAndSettle();

      fakeApiAllFr.markAllReadError = ApiException(500, 'Server error');
      await tester.tap(find.byKey(const Key('notifications_mark_all_button')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('notifications_error_banner')), findsOneWidget);
      expect(
          find.text(
              'Une erreur est survenue lors du chargement des notifications.'),
          findsOneWidget);

      // 4. markAllRead failure in EN (generic)
      final fakeApiAllEn = FakeNotificationsApi(
        notifications: [
          sampleNotificationJson(
            id: 'n-4',
            title: 'Notif 4',
            type: 'system',
            read: false,
          ),
        ],
        unreadCount: 1,
      );
      final providerAllEn = NotificationsProvider(api: fakeApiAllEn);

      await tester.pumpWidget(_buildTestApp(
        child: NotificationsScreen(key: UniqueKey()),
        notificationsProvider: providerAllEn,
        locale: const Locale('en'),
      ));
      await tester.pumpAndSettle();

      fakeApiAllEn.markAllReadError = ApiException(500, 'Server error');
      await tester.tap(find.byKey(const Key('notifications_mark_all_button')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('notifications_error_banner')), findsOneWidget);
      expect(find.text('An error occurred while loading notifications.'),
          findsOneWidget);
    });
  });
}
