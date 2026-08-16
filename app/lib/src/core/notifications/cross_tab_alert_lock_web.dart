import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'cross_tab_alert_lock.dart';

CrossTabAlertLock createCrossTabAlertLockImpl() => WebCrossTabAlertLock();

class WebCrossTabAlertLock implements CrossTabAlertLock {
  WebCrossTabAlertLock({
    String storagePrefix = 'animal-supply.alert.',
    String channelName = 'animal-supply-local-alerts',
    String? tabId,
  })  : _storagePrefix = storagePrefix,
        _tabId = tabId ??
            '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(Object())}' {
    try {
      _channel = web.BroadcastChannel(channelName);
    } catch (_) {
      _channel = null;
    }
  }

  final String _storagePrefix;
  final String _tabId;
  web.BroadcastChannel? _channel;

  @override
  bool claim(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return false;
    final key = '$_storagePrefix$trimmed';
    try {
      final existing = web.window.localStorage.getItem(key);
      if (existing != null && existing.isNotEmpty) {
        return false;
      }
      final token = '$_tabId:${DateTime.now().millisecondsSinceEpoch}';
      web.window.localStorage.setItem(key, token);
      if (web.window.localStorage.getItem(key) != token) {
        return false;
      }
      _channel?.postMessage(trimmed.toJS);
      return true;
    } catch (_) {
      return true;
    }
  }

  @override
  void Function()? listen(void Function(String id) onClaimed) {
    final channel = _channel;
    if (channel == null) return null;
    void handle(web.MessageEvent event) {
      final data = event.data;
      final id = data == null ? '' : data.toString().trim();
      if (id.isNotEmpty) onClaimed(id);
    }

    final listener = handle.toJS;
    channel.addEventListener('message', listener);
    return () {
      channel.removeEventListener('message', listener);
      channel.close();
    };
  }
}
