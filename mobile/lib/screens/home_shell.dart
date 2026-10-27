import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/notifications_provider.dart';
import 'bookings_screen.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'poi_list_screen.dart';
import 'profile_screen.dart';

/// Post-authentication shell — mobile counterpart of the web `AppShell.tsx`
/// five-tab structure (Accueil / Explorer / Réservations / Assistant IA /
/// Profil), per the "Discover AI" UX blueprint.
///
/// [IndexedStack] keeps every tab alive across switches (chat history, POI
/// list scroll position), matching the single-page web behaviour. Tab
/// destinations expose stable Keys (`tab_*`) — the integration suite uses
/// them for navigation.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.notificationsProvider});

  /// Optional injected provider (primarily for tests).
  final NotificationsProvider? notificationsProvider;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
  late final NotificationsProvider _notificationsProvider;
  late final bool _ownsProvider;

  @override
  void initState() {
    super.initState();
    if (widget.notificationsProvider != null) {
      _notificationsProvider = widget.notificationsProvider!;
      _ownsProvider = false;
    } else {
      _notificationsProvider = NotificationsProvider()..refreshUnreadCount();
      _ownsProvider = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final localeCode = context.read<LocaleProvider?>()?.localeCode;
      if (localeCode != null && localeCode.isNotEmpty) {
        context.read<AuthProvider>().syncLocale(localeCode);
      }
    });
  }

  @override
  void dispose() {
    if (_ownsProvider) {
      _notificationsProvider.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ChangeNotifierProvider<NotificationsProvider>.value(
      value: _notificationsProvider,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            HomeScreen(
              onExplore: () => setState(() => _currentIndex = 1),
              onOpenBookings: () => setState(() => _currentIndex = 2),
            ),
            const POIListScreen(),
            const BookingsScreen(),
            const ChatScreen(),
            const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) =>
              setState(() => _currentIndex = index),
          destinations: [
            NavigationDestination(
              key: const Key('tab_home'),
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: loc.shellTabHome,
            ),
            NavigationDestination(
              key: const Key('tab_explore'),
              icon: const Icon(Icons.explore_outlined),
              selectedIcon: const Icon(Icons.explore_rounded),
              label: loc.shellTabExplore,
            ),
            NavigationDestination(
              key: const Key('tab_bookings'),
              icon: const Icon(Icons.calendar_month_outlined),
              selectedIcon: const Icon(Icons.calendar_month_rounded),
              label: loc.shellTabBookings,
            ),
            NavigationDestination(
              key: const Key('tab_assistant'),
              icon: const Icon(Icons.chat_bubble_outline),
              selectedIcon: const Icon(Icons.chat_bubble_rounded),
              label: loc.shellTabAssistant,
            ),
            NavigationDestination(
              key: const Key('tab_profile'),
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person_rounded),
              label: loc.shellTabProfile,
            ),
          ],
        ),
      ),
    );
  }
}
