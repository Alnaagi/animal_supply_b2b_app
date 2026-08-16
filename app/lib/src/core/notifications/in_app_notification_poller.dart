import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_notification.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../features/auth/auth_controller.dart';
import 'browser_local_notifications.dart';
import 'browser_page_visibility.dart';
import 'local_alert_coordinator.dart';

class InAppNotificationPoller extends ConsumerStatefulWidget {
  const InAppNotificationPoller({
    this.interval = const Duration(seconds: 10),
    this.adminOrdersOnly = false,
    super.key,
  });

  final Duration interval;
  final bool adminOrdersOnly;

  @override
  ConsumerState<InAppNotificationPoller> createState() =>
      _InAppNotificationPollerState();
}

class _InAppNotificationPollerState
    extends ConsumerState<InAppNotificationPoller> with WidgetsBindingObserver {
  Timer? _timer;
  void Function()? _visibilityCancel;
  bool _hasBaseline = false;
  final Set<String> _seenIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visibilityCancel = subscribeBrowserVisibility((_) {
      unawaited(_poll());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_poll(establishBaseline: true));
      _start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _visibilityCancel?.call();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep polling while the PWA/tab is alive in the background so the OS
    // tray can still be raised. A fully killed process cannot poll.
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      unawaited(_poll(playSound: false));
    }
  }

  void _start() {
    _timer?.cancel();
    if (widget.interval <= Duration.zero) return;
    _timer = Timer.periodic(widget.interval, (_) {
      unawaited(_poll());
    });
  }

  Future<void> _poll({
    bool establishBaseline = false,
    bool playSound = true,
  }) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null || user.isDemo) return;
    try {
      final notifications =
          await ref.read(notificationsRepositoryProvider).list(limit: 40);
      final relevant = [
        for (final notification in notifications)
          if (_include(notification)) notification,
      ];
      final ids = {for (final notification in relevant) notification.id};
      if (!_hasBaseline || establishBaseline) {
        _seenIds
          ..clear()
          ..addAll(ids);
        _hasBaseline = true;
        return;
      }
      final fresh = [
        for (final notification in relevant)
          if (!_seenIds.contains(notification.id)) notification,
      ];
      _seenIds.addAll(ids);
      if (fresh.isEmpty) return;
      ref.invalidate(unreadNotificationsCountProvider);
      ref.read(notificationInboxEpochProvider.notifier).state++;
      final coordinator = ref.read(localAlertCoordinatorProvider);
      final adminLike =
          ref.read(authControllerProvider).user?.isAdminLike == true;
      for (final notification in fresh.take(3)) {
        await coordinator.announce(
          id: notification.id,
          title: notification.title,
          body: notification.body,
          playSound: playSound,
          target: osTrayNotificationTarget(
            adminLike: adminLike,
            orderId: notification.orderId,
            productId: notification.productId,
          ),
        );
      }
    } catch (_) {
      // In-app history remains available from the notification center.
    }
  }

  bool _include(AppNotification notification) {
    if (!widget.adminOrdersOnly) return true;
    return notification.type == 'new_order';
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
