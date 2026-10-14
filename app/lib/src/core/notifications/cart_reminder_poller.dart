import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/cart/cart_controller.dart';
import 'browser_page_visibility.dart';
import 'cart_reminder_coordinator.dart';

class CartReminderPoller extends ConsumerStatefulWidget {
  const CartReminderPoller({
    this.checkInterval = const Duration(seconds: 60),
    super.key,
  });

  final Duration checkInterval;

  @override
  ConsumerState<CartReminderPoller> createState() => _CartReminderPollerState();
}

class _CartReminderPollerState extends ConsumerState<CartReminderPoller>
    with WidgetsBindingObserver {
  Timer? _periodicTimer;
  void Function()? _visibilityCancel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visibilityCancel = subscribeBrowserVisibility((_) {
      _checkDue();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hasItems = ref.read(cartControllerProvider).isNotEmpty;
      ref
          .read(cartReminderCoordinatorProvider)
          .syncCartState(hasItems: hasItems);
      _startPeriodicTimer();
    });
  }

  void _startPeriodicTimer() {
    _periodicTimer?.cancel();
    if (widget.checkInterval <= Duration.zero) return;
    _periodicTimer = Timer.periodic(widget.checkInterval, (_) {
      _checkDue();
    });
  }

  void _checkDue() {
    final hasItems = ref.read(cartControllerProvider).isNotEmpty;
    unawaited(
      ref
          .read(cartReminderCoordinatorProvider)
          .checkDueReminders(hasItems: hasItems),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _checkDue();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _visibilityCancel?.call();
    _periodicTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<dynamic>>(cartControllerProvider, (previous, next) {
      final wasEmpty = previous == null || previous.isEmpty;
      final isEmpty = next.isEmpty;
      if (wasEmpty != isEmpty) {
        ref
            .read(cartReminderCoordinatorProvider)
            .syncCartState(hasItems: !isEmpty);
      }
    });
    return const SizedBox.shrink();
  }
}
