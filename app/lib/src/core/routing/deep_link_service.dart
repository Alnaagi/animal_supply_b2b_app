import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

class DeepLinkService {
  DeepLinkService() {
    unawaited(_emitInitialLink());
    _subscription = AppLinks().uriLinkStream.listen(
      (uri) {
        final normalized = normalizeInviteUri(uri);
        if (normalized != null) _controller.add(normalized);
      },
      onError: (_) {},
    );
  }

  late final StreamSubscription<Uri> _subscription;
  final StreamController<Uri> _controller = StreamController<Uri>.broadcast();

  Stream<Uri> get links => _controller.stream;

  Future<void> _emitInitialLink() async {
    try {
      final initial = await AppLinks().getInitialLink();
      if (initial == null) return;
      final normalized = normalizeInviteUri(initial);
      if (normalized != null && !_controller.isClosed) {
        _controller.add(normalized);
      }
    } catch (_) {}
  }

  static Uri? normalizeInviteUri(
    Uri uri, {
    String? trustedHttpsHost,
  }) {
    final token = uri.queryParameters['token']?.trim() ?? '';
    if (token.length < 20 ||
        token.length > 512 ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(token)) {
      return null;
    }

    final customInvite =
        uri.scheme == 'animalsupplyb2b' && uri.host == 'invite';
    final configuredHost =
        (trustedHttpsHost ?? AppConfig.publicAppHost).trim().toLowerCase();
    final currentWebHost = kIsWeb ? Uri.base.host.toLowerCase() : '';
    final expectedHttpsHost =
        configuredHost.isNotEmpty ? configuredHost : currentWebHost;
    final httpsInvite = uri.scheme == 'https' &&
        expectedHttpsHost.isNotEmpty &&
        uri.host.toLowerCase() == expectedHttpsHost &&
        uri.path == '/invite' &&
        uri.userInfo.isEmpty;
    if (!customInvite && !httpsInvite) return null;

    final client = uri.queryParameters['client']?.trim();
    return Uri(
      path: '/invite',
      queryParameters: {
        'token': token,
        if (client != null && client.isNotEmpty) 'client': client,
      },
    );
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _controller.close();
  }
}
