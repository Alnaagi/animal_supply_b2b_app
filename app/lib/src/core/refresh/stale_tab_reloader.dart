import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/remote/supabase_clients.dart';
import '../../features/auth/auth_controller.dart';
import '../notifications/browser_page_visibility.dart';
import 'screen_reload.dart';

/// Reloads the visible screen when a browser tab/PWA window is focused again,
/// and drops a local session if another tab already signed out.
class StaleTabReloader extends ConsumerStatefulWidget {
  const StaleTabReloader({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<StaleTabReloader> createState() => _StaleTabReloaderState();
}

class _StaleTabReloaderState extends ConsumerState<StaleTabReloader>
    with WidgetsBindingObserver {
  void Function()? _visibilityCancel;
  DateTime? _lastReloadAt;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visibilityCancel = subscribeBrowserVisibility((hidden) {
      if (!hidden) unawaited(_onBecameVisible());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ready = true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _visibilityCancel?.call();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onBecameVisible());
    }
  }

  Future<void> _onBecameVisible() async {
    if (!_ready) return;
    final now = DateTime.now();
    final last = _lastReloadAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastReloadAt = now;

    final client = supabaseClient;
    if (client != null) {
      final authUser = client.auth.currentUser;
      final session = client.auth.currentSession;
      final localUser = ref.read(authControllerProvider).user;
      if ((authUser == null || session == null) &&
          localUser != null &&
          localUser.isDemo != true) {
        await ref.read(authControllerProvider.notifier).logout();
        return;
      }
    }

    if (!mounted) return;
    requestScreenReload(ref);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
