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
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  LocaleProvider? _observedLocaleProvider;
  VoidCallback? _localeSyncListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationsProvider?>()?.refreshUnreadCount();
      _initLocaleSync();
    });
  }

  void _initLocaleSync() {
    final localeProvider = context.read<LocaleProvider?>();
    if (localeProvider == null) return;
    if (!localeProvider.isLoading) {
      _doSyncLocale(localeProvider.localeCode);
    } else {
      _observedLocaleProvider = localeProvider;
      void onLocaleChanged() {
        if (!localeProvider.isLoading) {
          localeProvider.removeListener(onLocaleChanged);
          _observedLocaleProvider = null;
          _localeSyncListener = null;
          if (mounted) {
            _doSyncLocale(localeProvider.localeCode);
          }
        }
      }

      _localeSyncListener = onLocaleChanged;
      localeProvider.addListener(onLocaleChanged);
    }
  }

  void _doSyncLocale(String code) {
    if (code.isNotEmpty) {
      context.read<AuthProvider>().syncLocale(code);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<NotificationsProvider?>()?.refreshUnreadCount();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_localeSyncListener != null && _observedLocaleProvider != null) {
      _observedLocaleProvider!.removeListener(_localeSyncListener!);
      _localeSyncListener = null;
      _observedLocaleProvider = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
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
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
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
    );
  }
}
