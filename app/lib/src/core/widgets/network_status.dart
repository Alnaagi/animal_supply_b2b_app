import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../connectivity/connectivity_provider.dart';
import '../localization/arabic_copy.dart';
import '../theme/app_theme.dart';
import 'shop_loading.dart';

class NetworkStatusHeader extends ConsumerStatefulWidget {
  const NetworkStatusHeader({super.key});

  @override
  ConsumerState<NetworkStatusHeader> createState() =>
      _NetworkStatusHeaderState();
}

class _NetworkStatusHeaderState extends ConsumerState<NetworkStatusHeader> {
  static const _slowDelay = Duration(milliseconds: 450);
  Timer? _slowTimer;
  bool _showSlow = false;

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  void _syncSlowIndicator(int activity, bool online) {
    if (!online || activity <= 0) {
      _slowTimer?.cancel();
      if (_showSlow) setState(() => _showSlow = false);
      return;
    }
    if (_showSlow || _slowTimer?.isActive == true) return;
    _slowTimer = Timer(_slowDelay, () {
      if (!mounted) return;
      final stillBusy = ref.read(remoteActivityProvider) > 0;
      final stillOnline = isOnlineFromConnectivity(ref.read(connectivityProvider));
      setState(() => _showSlow = stillBusy && stillOnline);
    });
  }

  Future<void> _retry() async {
    ref.invalidate(connectivityProvider);
    await ref.read(connectivityProvider.future);
    if (!mounted) return;
    ref.read(networkRetryTickProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final online = isOnlineFromConnectivity(ref.watch(connectivityProvider));
    final activity = ref.watch(remoteActivityProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSlowIndicator(activity, online);
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!online)
          OfflineStatusCard(
            onRetry: _retry,
            demoMode: AppConfig.isDemoMode || AppConfig.allowsDemoCredentials,
          ),
        if (_showSlow) const SlowConnectionBar(),
      ],
    );
  }
}

class OfflineStatusCard extends StatelessWidget {
  const OfflineStatusCard({
    required this.onRetry,
    this.demoMode = false,
    super.key,
  });

  final VoidCallback onRetry;
  final bool demoMode;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('offline-status-card'),
      color: const Color(0xfffff4d6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.wifi_off, color: Color(0xff8a5a00)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    ArabicCopy.offlineTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xff8a5a00),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    demoMode
                        ? ArabicCopy.offlineBodyDemo
                        : ArabicCopy.offlineBody,
                    style: const TextStyle(
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              child: const Text(ArabicCopy.offlineRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class SlowConnectionBar extends StatelessWidget {
  const SlowConnectionBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('slow-connection-bar'),
      color: AppTheme.green.withValues(alpha: 0.10),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            ShopLoading.compact(size: 16),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                ArabicCopy.slowConnection,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
