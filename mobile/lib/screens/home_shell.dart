import 'package:flutter/material.dart';

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

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(onExplore: () => setState(() => _currentIndex = 1)),
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
        destinations: const [
          NavigationDestination(
            key: Key('tab_home'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Accueil',
          ),
          NavigationDestination(
            key: Key('tab_explore'),
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Explorer',
          ),
          NavigationDestination(
            key: Key('tab_bookings'),
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Réservations',
          ),
          NavigationDestination(
            key: Key('tab_assistant'),
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Assistant',
          ),
          NavigationDestination(
            key: Key('tab_profile'),
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
