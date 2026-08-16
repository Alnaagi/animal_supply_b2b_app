import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DashboardWidgetId {
  customers('customers', 'العملاء'),
  activeCustomers('active_customers', 'نشطين'),
  pendingOrdersStat('pending_orders_stat', 'طلبات معلقة'),
  todayOrders('today_orders', 'طلبات اليوم'),
  lowStockStat('low_stock_stat', 'مخزون منخفض'),
  monthSales('month_sales', 'مبيعات الشهر'),
  pendingOrdersPanel('pending_orders_panel', 'طلبات تحتاج مراجعة'),
  lowStockPanel('low_stock_panel', 'قائمة المخزون المنخفض'),
  dataFullness('data_fullness', 'امتلاء قاعدة البيانات');

  const DashboardWidgetId(this.storageKey, this.labelAr);

  final String storageKey;
  final String labelAr;
}

class DashboardWidgetVisibility {
  const DashboardWidgetVisibility(this._hidden);

  static const allVisible = DashboardWidgetVisibility({});

  final Set<DashboardWidgetId> _hidden;

  bool isVisible(DashboardWidgetId id) => !_hidden.contains(id);

  DashboardWidgetVisibility withVisible(DashboardWidgetId id, bool visible) {
    final next = {..._hidden};
    if (visible) {
      next.remove(id);
    } else {
      next.add(id);
    }
    return DashboardWidgetVisibility(next);
  }

  String encode() {
    return jsonEncode({
      for (final id in DashboardWidgetId.values)
        id.storageKey: isVisible(id),
    });
  }

  static DashboardWidgetVisibility decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return allVisible;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return allVisible;
      final hidden = <DashboardWidgetId>{};
      for (final id in DashboardWidgetId.values) {
        final value = decoded[id.storageKey];
        if (value == false) hidden.add(id);
      }
      return DashboardWidgetVisibility(hidden);
    } catch (_) {
      return allVisible;
    }
  }
}

class DashboardWidgetPrefs {
  DashboardWidgetPrefs({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const storageKey = 'admin_dashboard.widget_visibility.v1';

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

  Future<DashboardWidgetVisibility> load() async {
    try {
      final prefs = await _store();
      return DashboardWidgetVisibility.decode(prefs?.getString(storageKey));
    } catch (_) {
      return DashboardWidgetVisibility.allVisible;
    }
  }

  Future<bool> save(DashboardWidgetVisibility visibility) async {
    try {
      final prefs = await _store();
      if (prefs == null) return false;
      return await prefs.setString(storageKey, visibility.encode());
    } catch (_) {
      return false;
    }
  }
}

final dashboardWidgetPrefsProvider = Provider<DashboardWidgetPrefs>(
  (ref) => DashboardWidgetPrefs(),
);

final dashboardWidgetVisibilityProvider = StateNotifierProvider<
    DashboardWidgetVisibilityController, DashboardWidgetVisibility>(
  (ref) => DashboardWidgetVisibilityController(
    ref.watch(dashboardWidgetPrefsProvider),
  ),
);

class DashboardWidgetVisibilityController
    extends StateNotifier<DashboardWidgetVisibility> {
  DashboardWidgetVisibilityController(this._prefs)
      : super(DashboardWidgetVisibility.allVisible) {
    unawaited(reload());
  }

  final DashboardWidgetPrefs _prefs;

  Future<void> reload() async {
    state = await _prefs.load();
  }

  Future<void> setVisible(DashboardWidgetId id, bool visible) async {
    state = state.withVisible(id, visible);
    await _prefs.save(state);
  }
}
