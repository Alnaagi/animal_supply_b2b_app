import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final browserNotificationPromptStoreProvider =
    Provider<BrowserNotificationPromptStore>(
  (ref) => BrowserNotificationPromptStore(),
);

/// Device-local dismissal so a denied or postponed browser prompt is not
/// shown again on every shell rebuild.
class BrowserNotificationPromptStore {
  BrowserNotificationPromptStore({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const dismissedKey = 'browser_notifications.prompt.dismissed.v1';

  final SharedPreferences? _prefsOverride;
  final Future<SharedPreferences?> Function()? _storeLoader;
  SharedPreferences? _prefs;

  Future<SharedPreferences?> _store() async {
    if (_prefsOverride != null) return _prefsOverride;
    try {
      return _prefs ??=
          await (_storeLoader?.call() ?? SharedPreferences.getInstance());
    } catch (_) {
      return null;
    }
  }

  Future<bool> isDismissed() async {
    final prefs = await _store();
    return prefs?.getBool(dismissedKey) ?? false;
  }

  Future<void> dismiss() async {
    final prefs = await _store();
    await prefs?.setBool(dismissedKey, true);
  }
}
