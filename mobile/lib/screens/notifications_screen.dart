import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/partner_bookings_provider.dart';
import 'partner_bookings_screen.dart';

/// Notifications screen displaying user notifications with pull-to-refresh,
/// infinite scrolling pagination, read status toggling, and mark-all-read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.onOpenBookings});

  /// Callback to switch shell to the Bookings tab when tapping a booking status notification.
  final VoidCallback? onOpenBookings;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationsProvider>().load();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<NotificationsProvider>().loadMore();
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'booking_request_received':
        return Icons.inbox_outlined;
      case 'booking_confirmed':
        return Icons.check_circle_outline;
      case 'booking_declined':
        return Icons.cancel_outlined;
      case 'booking_expired':
        return Icons.hourglass_empty;
      default:
        return Icons.notifications_none;
    }
  }

  String? _formatDate(DateTime? dt, String localeName) {
    if (dt == null) return null;
    try {
      final local = dt.toLocal();
      return intl.DateFormat.yMMMd(localeName).add_jm().format(local);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final provider = context.watch<NotificationsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final hasUnread =
        provider.unreadCount > 0 || provider.items.any((n) => !n.read);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.notificationsTitle),
        actions: [
          TextButton(
            key: const Key('notifications_mark_all_button'),
            onPressed: hasUnread ? () => provider.markAllRead() : null,
            child: Text(loc.notificationsMarkAllRead),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (provider.isLoading && provider.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null && provider.items.isEmpty) {
            final errorText = provider.error == NotificationsError.network
                ? loc.notificationsErrorNetwork
                : loc.notificationsErrorGeneric;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: scheme.error),
                    const SizedBox(height: 16),
                    Text(
                      errorText,
                      key: const Key('notifications_error'),
                      textAlign: TextAlign.center,
                      style: textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('notifications_retry_button'),
                      onPressed: () => provider.load(),
                      child: Text(loc.notificationsRetry),
                    ),
                  ],
                ),
              ),
            );
          }

          if (provider.items.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => provider.load(),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          loc.notificationsEmpty,
                          key: const Key('notifications_empty'),
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.load(),
            child: ListView.separated(
              key: const Key('notifications_list'),
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount:
                  provider.items.length + (provider.isLoadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index >= provider.items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final notif = provider.items[index];
                final formattedDate =
                    _formatDate(notif.createdAt, loc.localeName);

                return ListTile(
                  key: Key('notification_tile_${notif.id}'),
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        backgroundColor: notif.read
                            ? scheme.surfaceContainerHighest
                            : scheme.primaryContainer,
                        child: Icon(
                          _iconForType(notif.type),
                          color: notif.read
                              ? scheme.onSurfaceVariant
                              : scheme.primary,
                        ),
                      ),
                      if (!notif.read)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(
                    notif.title,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight:
                          notif.read ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (notif.message.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          notif.message,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (formattedDate != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          formattedDate,
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                      ],
                    ],
                  ),
                  onTap: () {
                    if (!notif.read) {
                      provider.markRead(notif.id);
                    }

                    if (notif.type == 'booking_request_received') {
                      final user = context.read<AuthProvider?>()?.user;
                      if (user?.canUsePartnerSpace ?? false) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider(
                              create: (_) => PartnerBookingsProvider(),
                              child: const PartnerBookingsScreen(),
                            ),
                          ),
                        );
                      }
                    } else if (notif.type == 'booking_confirmed' ||
                        notif.type == 'booking_declined' ||
                        notif.type == 'booking_expired') {
                      Navigator.of(context).pop();
                      widget.onOpenBookings?.call();
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
