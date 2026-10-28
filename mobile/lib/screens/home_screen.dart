import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/promotion_provider.dart';
import '../providers/tenant_provider.dart';
import '../widgets/promo_banner.dart';
import 'notifications_screen.dart';
import 'trip_form_screen.dart';

/// Accueil tab — P2 of the UX blueprint ("Discover AI" home mockup):
/// personalized greeting, travel-type grid feeding the trip wizard, promo
/// banner, then shortcuts to the Planner and the Explorer tab.
///
/// The travel-type catalog comes from [TenantProvider.categories]
/// (fetched from GET /tenants/categories/), falling back to
/// [AppConfig.tripInterestOptions] when the provider is unavailable or
/// has not yet loaded — never hardcoded market content (principle n°1).
/// The icon map degrades gracefully (generic activity icon) for config
/// values it doesn't know, so any tenant catalog renders.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onExplore, this.onOpenBookings});

  /// Switches the shell to the Explorer tab.
  final VoidCallback? onExplore;

  /// Switches the shell to the Bookings tab.
  final VoidCallback? onOpenBookings;

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
    'history': Icons.history_edu,
    'nature': Icons.forest_outlined,
    'desert': Icons.wb_sunny_outlined,
    'adventure': Icons.hiking_outlined,
    'food': Icons.restaurant_outlined,
    'beaches': Icons.beach_access_outlined,
    'monuments': Icons.explore_outlined,
    'crafts': Icons.shopping_bag_outlined,
    'thermal': Icons.hot_tub_outlined,
    'wellness': Icons.spa_outlined,
    'shopping': Icons.shopping_bag_outlined,
    'nightlife': Icons.nightlife_outlined,
  };

  /// First name for the greeting: full name if present, else the email
  /// local part, else [fallback] — never a hardcoded market name.
  static String _firstName(User? user, String fallback) {
    final name = user?.fullName?.trim();
    if (name != null && name.isNotEmpty) {
      return name.split(RegExp(r'\s+')).first;
    }
    final local = (user?.email ?? '').split('@').first.trim();
    return local.isEmpty ? fallback : local;
  }

  /// Localized label for a catalog slug. Known slugs map to their
  /// [AppLocalizations] key; unknown slugs keep the historical fallback
  /// (capitalised slug), so any tenant catalog renders — the value sent to
  /// the API is never altered.
  static String _typeLabel(AppLocalizations loc, String interest) {
    switch (interest) {
      case 'culture':
        return loc.homeTravelTypeCulture;
      case 'history':
        return loc.homeTravelTypeHistory;
      case 'nature':
        return loc.homeTravelTypeNature;
      case 'desert':
        return loc.homeTravelTypeDesert;
      case 'adventure':
        return loc.homeTravelTypeAdventure;
      case 'food':
        return loc.homeTravelTypeFood;
      case 'beaches':
        return loc.homeTravelTypeBeaches;
      case 'monuments':
        return loc.homeTravelTypeMonuments;
      case 'crafts':
        return loc.homeTravelTypeCrafts;
      case 'thermal':
        return loc.homeTravelTypeThermal;
      case 'wellness':
        return loc.homeTravelTypeWellness;
      default:
        return interest.isEmpty
            ? interest
            : interest[0].toUpperCase() + interest.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final user = context.watch<AuthProvider>().user;
    final promotions = context.watch<PromotionProvider>().items;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    /// Catalog comes from the tenant provider (GET /tenants/categories/),
    /// falling back to [AppConfig.tripInterestOptions] when the provider
    /// is absent, still loading, or returned nothing. Nullable watch so a
    /// missing TenantProvider can never crash the Accueil tab.
    final categories = context.watch<TenantProvider?>()?.categories ?? const [];
    final interests = categories.isNotEmpty
        ? categories.map((c) => c.slug).toList(growable: false)
        : AppConfig.tripInterestOptions;
    final notifsProvider = context.watch<NotificationsProvider?>();
    final unreadCount = notifsProvider?.unreadCount ?? 0;
    final badgeText = unreadCount > 99 ? '99+' : unreadCount.toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.appName),
        actions: [
          IconButton(
            key: const Key('notifications_bell'),
            tooltip: loc.notificationsBellA11y,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined),
                if (unreadCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      key: const Key('notifications_badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: scheme.onError,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NotificationsScreen(
                  onOpenBookings: widget.onOpenBookings,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            loc.homeGreeting(_firstName(user, loc.homeTravellerFallback)),
            key: const Key('home_greeting'),
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            loc.homeSubtitle,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Text(
            loc.homeTravelTypeTitle,
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
              for (final interest in interests)
                _TravelTypeCard(
                  key: Key('home_type_$interest'),
                  icon: _typeIcons[interest] ?? Icons.local_activity_outlined,
                  label: _typeLabel(loc, interest),
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
              title: Text(loc.homePlanTripTitle),
              subtitle: Text(loc.homePlanTripSubtitle),
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
              title: Text(loc.homeExploreTitle),
              subtitle: Text(loc.homeExploreSubtitle),
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
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
