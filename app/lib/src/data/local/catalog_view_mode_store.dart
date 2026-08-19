import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CatalogViewMode {
  comfortable('comfortable'),
  compact('compact'),
  grid('grid');

  const CatalogViewMode(this.storageValue);
  final String storageValue;

  static CatalogViewMode fromStorage(String? raw) {
    for (final mode in CatalogViewMode.values) {
      if (mode.storageValue == raw) return mode;
    }
    return CatalogViewMode.comfortable;
  }
}

class CatalogViewModeStore {
  CatalogViewModeStore({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const storageKey = 'catalog.customer.view_mode.v1';

  final SharedPreferences? _prefsOverride;
  final Future<SharedPreferences?> Function()? _storeLoader;
  SharedPreferences? _prefs;

  static CatalogViewMode defaultForWidth(double width) {
    if (width >= 1000) return CatalogViewMode.grid;
    return CatalogViewMode.comfortable;
  }

  Future<SharedPreferences?> _store() async {
    if (_prefsOverride != null) return _prefsOverride;
    try {
      return _prefs ??=
          await (_storeLoader?.call() ?? SharedPreferences.getInstance());
    } catch (_) {
      return null;
    }
  }

  Future<CatalogViewMode> load({
    required CatalogViewMode fallbackMode,
  }) async {
    final prefs = await _store();
    final raw = prefs?.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) return fallbackMode;
    return CatalogViewMode.fromStorage(raw.trim());
  }

  Future<bool> save(CatalogViewMode mode) async {
    final prefs = await _store();
    if (prefs == null) return false;
    try {
      return await prefs.setString(storageKey, mode.storageValue);
    } catch (_) {
      return false;
    }
  }
}

final catalogViewModeStoreProvider = Provider<CatalogViewModeStore>(
  (ref) => CatalogViewModeStore(),
);
