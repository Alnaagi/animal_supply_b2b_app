import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/order_status.dart';

final adminOrdersFilterStoreProvider =
    Provider<AdminOrdersFilterStore>((ref) => AdminOrdersFilterStore());

/// Local staff preference for which order statuses appear by default.
///
/// Product default is every status except delivered so active work stays
/// visible without hiding cancelled orders. Persistence is device-local and
/// does not change RLS or server query authorization.
class AdminOrdersFilterStore {
  AdminOrdersFilterStore({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const storageKey = 'admin_orders.filter.included_statuses.v1';

  static Set<OrderStatus> get productDefault => {
        for (final status in OrderStatus.values)
          if (status != OrderStatus.delivered) status,
      };

  static Set<OrderStatus> get allStatuses => {...OrderStatus.values};

  final SharedPreferences? _prefsOverride;
  final Future<SharedPreferences?> Function()? _storeLoader;
  SharedPreferences? _prefs;

  static bool sameSet(Set<OrderStatus> left, Set<OrderStatus> right) =>
      left.length == right.length && left.containsAll(right);

  static List<OrderStatus> ordered(Set<OrderStatus> included) => [
        for (final status in OrderStatus.values)
          if (included.contains(status)) status,
      ];

  static String labelFor(Set<OrderStatus> included) {
    if (sameSet(included, allStatuses)) return 'كل الحالات';
    if (sameSet(included, productDefault)) {
      return 'كل الحالات ما عدا المُسلَّم';
    }
    if (included.length == 1) return included.single.label;
    return 'حسب إعداداتك';
  }

  /// Maps a staff status set onto the existing single-status query plus an
  /// optional `IN` list for mixed filters.
  static ({OrderStatus? status, List<OrderStatus>? statuses}) queryArgs(
    Set<OrderStatus> included,
  ) {
    final selected = {...included};
    if (selected.isEmpty || sameSet(selected, allStatuses)) {
      return (status: null, statuses: null);
    }
    final orderedStatuses = ordered(selected);
    if (orderedStatuses.length == 1) {
      return (status: orderedStatuses.single, statuses: null);
    }
    return (status: null, statuses: orderedStatuses);
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

  Future<Set<OrderStatus>> load() async {
    final prefs = await _store();
    final raw = prefs?.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) return productDefault;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return productDefault;
      final parsed = <OrderStatus>{};
      for (final value in decoded) {
        final name = value.toString().trim();
        for (final status in OrderStatus.values) {
          if (status.value == name) parsed.add(status);
        }
      }
      if (parsed.isEmpty) return productDefault;
      return parsed;
    } catch (_) {
      return productDefault;
    }
  }

  Future<bool> save(Set<OrderStatus> included) async {
    if (included.isEmpty) return false;
    final prefs = await _store();
    if (prefs == null) return false;
    try {
      return await prefs.setString(
        storageKey,
        jsonEncode([for (final status in ordered(included)) status.value]),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> reset() => save(productDefault);
}
