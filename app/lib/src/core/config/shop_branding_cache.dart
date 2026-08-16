import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/admin_models.dart';
import '../updates/update_link.dart';
import 'app_config.dart';
import 'shop_branding.dart';
import 'shop_document_title.dart';

/// Last-known shop branding so the browser tab and splash do not flash the
/// compile-time placeholder while `app_settings` loads.
class ShopBrandingCache {
  static const namePrefsKey = 'shop_branding.shop_name.v1';
  static const logoPrefsKey = 'shop_branding.logo_url.v1';

  static ShopBranding _current = ShopBranding(shopName: AppConfig.shopName);
  static bool _optimistic = false;

  static ShopBranding get current => _current;

  static void resetForTest() {
    _current = ShopBranding(shopName: AppConfig.shopName);
    _optimistic = false;
  }

  static Future<void> load() async {
    final fromDocument = readCachedShopDocumentTitle()?.trim() ?? '';
    String? name;
    String? logo;
    try {
      final prefs = await SharedPreferences.getInstance();
      name = prefs.getString(namePrefsKey)?.trim();
      logo = prefs.getString(logoPrefsKey)?.trim();
    } catch (_) {}

    final resolvedName = (name != null && name.isNotEmpty)
        ? name
        : (fromDocument.isNotEmpty ? fromDocument : AppConfig.shopName);
    final resolvedLogo = (logo == null || logo.isEmpty)
        ? null
        : safeHttpsUpdateUri(logo)?.toString();
    _current = ShopBranding(shopName: resolvedName, logoUrl: resolvedLogo);
    _optimistic = false;
    applyShopDocumentTitle(_current.shopName);
  }

  static void rememberSaved(ShopBranding branding) {
    _optimistic = true;
    _assign(branding);
  }

  static void syncFromRemote(ShopBranding branding) {
    if (_optimistic && branding.shopName != _current.shopName) {
      return;
    }
    _optimistic = false;
    _assign(branding);
  }

  static ShopBranding resolve(AppSettingsData? settings) {
    if (settings != null) {
      syncFromRemote(ShopBranding.fromSettings(settings));
    }
    return _current;
  }

  static void _assign(ShopBranding branding) {
    final nextName = branding.shopName.trim().isEmpty
        ? AppConfig.shopName
        : branding.shopName.trim();
    final next = ShopBranding(shopName: nextName, logoUrl: branding.logoUrl);
    final changed = next.shopName != _current.shopName ||
        next.logoUrl != _current.logoUrl;
    _current = next;
    applyShopDocumentTitle(_current.shopName);
    if (changed) unawaited(_persist());
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(namePrefsKey, _current.shopName);
      final logo = _current.logoUrl?.trim() ?? '';
      if (logo.isEmpty) {
        await prefs.remove(logoPrefsKey);
      } else {
        await prefs.setString(logoPrefsKey, logo);
      }
    } catch (_) {}
  }
}
