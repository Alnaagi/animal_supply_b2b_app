import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/storefront_config.dart';

/// Last-known published storefront palette, so cold starts (and the startup
/// paw intro) use the client's colors before the remote config loads, and
/// offline launches do not fall back to the bundled palette.
class StorefrontThemeCache {
  static const prefsKey = 'storefront_theme.published.v1';

  static StorefrontThemeConfig? _current;

  static StorefrontThemeConfig? get current => _current;

  static void resetForTest() {
    _current = null;
  }

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _current =
            StorefrontThemeConfig.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
  }

  static void remember(StorefrontThemeConfig theme) {
    final encoded = jsonEncode(theme.toJson());
    final previous = _current;
    _current = theme;
    if (previous != null && jsonEncode(previous.toJson()) == encoded) return;
    unawaited(_persist(encoded));
  }

  /// Bundled storefront with the cached published palette, if any.
  static StorefrontConfig fallbackConfig() {
    return StorefrontDefaults.bundled.copyWith(theme: _current);
  }

  static Future<void> _persist(String encoded) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, encoded);
    } catch (_) {}
  }
}
