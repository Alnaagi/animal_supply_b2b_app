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

enum CatalogViewModeScope {
  compact,
  expanded,
}

class CatalogViewModeStore {
  CatalogViewModeStore({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const storageKey = 'catalog.customer.view_mode.v1';
  static const compactStorageKey = 'catalog.customer.view_mode.compact.v2';
  static const expandedStorageKey = 'catalog.customer.view_mode.expanded.v2';

  final SharedPreferences? _prefsOverride;
  final Future<SharedPreferences?> Function()? _storeLoader;
  SharedPreferences? _prefs;

  static CatalogViewMode defaultForWidth(double width) {
    if (width >= 1000) return CatalogViewMode.grid;
    return CatalogViewMode.comfortable;
  }

  static CatalogViewModeScope scopeForWidth(double width) {
    return width >= 1000
        ? CatalogViewModeScope.expanded
        : CatalogViewModeScope.compact;
  }

  static String storageKeyForScope(CatalogViewModeScope scope) {
    return switch (scope) {
      CatalogViewModeScope.compact => compactStorageKey,
      CatalogViewModeScope.expanded => expandedStorageKey,
    };
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
    CatalogViewModeScope? scope,
  }) async {
    final prefs = await _store();
    final scopedRaw = scope == null
        ? prefs?.getString(storageKey)
        : prefs?.getString(storageKeyForScope(scope));
    if (scopedRaw?.trim().isNotEmpty == true) {
      return CatalogViewMode.fromStorage(scopedRaw!.trim());
    }

    // Migrate the old shared preference only when it naturally belongs to
    // this viewport family. This prevents a phone list choice from turning
    // into a stretched desktop list, while preserving sensible old choices.
    if (scope != null) {
      final legacyRaw = prefs?.getString(storageKey);
      if (legacyRaw?.trim().isNotEmpty == true) {
        final legacyMode = CatalogViewMode.fromStorage(legacyRaw!.trim());
        final belongsToScope = switch (scope) {
          CatalogViewModeScope.compact => legacyMode != CatalogViewMode.grid,
          CatalogViewModeScope.expanded => legacyMode == CatalogViewMode.grid,
        };
        if (belongsToScope) return legacyMode;
      }
    }
    return fallbackMode;
  }

  Future<bool> save(
    CatalogViewMode mode, {
    CatalogViewModeScope? scope,
  }) async {
    final prefs = await _store();
    if (prefs == null) return false;
    try {
      return await prefs.setString(
        scope == null ? storageKey : storageKeyForScope(scope),
        mode.storageValue,
      );
    } catch (_) {
      return false;
    }
  }
}

final catalogViewModeStoreProvider = Provider<CatalogViewModeStore>(
  (ref) => CatalogViewModeStore(),
);
