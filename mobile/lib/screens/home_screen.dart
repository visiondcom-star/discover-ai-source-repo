import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/promotion_provider.dart';
import '../widgets/promo_banner.dart';
import 'trip_form_screen.dart';

/// Accueil tab — P2 of the UX blueprint ("Discover AI" home mockup):
/// personalized greeting, travel-type grid feeding the trip wizard, promo
/// banner, then shortcuts to the Planner and the Explorer tab.
///
/// The travel-type catalog comes from [AppConfig.tripInterestOptions]
/// (`--dart-define`) — never hardcoded market content (principle n°1).
/// The icon map degrades gracefully (generic activity icon) for config
/// values it doesn't know, so any tenant catalog renders.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onExplore});

  /// Switches the shell to the Explorer tab.
  final VoidCallback? onExplore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Decorative content: fetched after first frame like every other list
    // on this screen, and its own provider already swallows errors so a
    // failed fetch just means no banner — never a broken Accueil tab.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PromotionProvider>().loadPromotions();
    });
  }

  /// Icon per known catalog value; anything else falls back to a generic
  /// activity icon instead of crashing on an unknown tenant entry.
  static const Map<String, IconData> _typeIcons = {
    'culture': Icons.museum_outlined,
    'food': Icons.restaurant_outlined,
    'history': Icons.history_edu,
    'nature': Icons.forest_outlined,
    'beaches': Icons.beach_access_outlined,
    'adventure': Icons.hiking_outlined,
    'shopping': Icons.shopping_bag_outlined,
    'nightlife': Icons.nightlife_outlined,
  };

  /// First name for the greeting: full name if present, else the email
  /// local part, else a neutral fallback — never a hardcoded market name.
  static String _firstName(User? user) {
    final name = user?.fullName?.trim();
    if (name != null && name.isNotEmpty) {
      return name.split(RegExp(r'\s+')).first;
    }
    final local = (user?.email ?? '').split('@').first.trim();
    return local.isEmpty ? 'voyageur' : local;
  }

  /// Catalog values are lowercase slugs ('food'); display them capitalized
  /// without altering the value sent to the API.
  static String _typeLabel(String interest) => interest.isEmpty
      ? interest
      : interest[0].toUpperCase() + interest.substring(1);

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final promotions = context.watch<PromotionProvider>().items;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Discover AI')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Bonjour, ${_firstName(user)} 👋',
            key: const Key('home_greeting'),
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Que souhaitez-vous découvrir aujourd’hui ?',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Text(
            'Type de voyage',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: [
              for (final interest in AppConfig.tripInterestOptions)
                _TravelTypeCard(
                  key: Key('home_type_$interest'),
                  icon: _typeIcons[interest] ?? Icons.local_activity_outlined,
                  label: _typeLabel(interest),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TripFormScreen(initialInterests: <String>{interest}),
                    ),
                  ),
                ),
            ],
          ),
          if (promotions.isNotEmpty) ...[
            const SizedBox(height: 20),
            PromoBanner(promotion: promotions.first),
          ],
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              key: const Key('home_plan_trip_button'),
              leading: Icon(Icons.map_outlined, color: scheme.primary),
              title: const Text('Planifier un voyage'),
              subtitle: const Text('Générez un itinéraire personnalisé'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TripFormScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              key: const Key('home_explore_button'),
              leading: Icon(Icons.explore_outlined, color: scheme.primary),
              title: const Text('Explorer les lieux'),
              subtitle: const Text('Les incontournables de votre destination'),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onExplore,
            ),
          ),
        ],
      ),
    );
  }
}

/// One travel-type tile of the home grid. Opens the trip wizard with the
/// matching interest already selected.
class _TravelTypeCard extends StatelessWidget {
  const _TravelTypeCard({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: scheme.primary, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
