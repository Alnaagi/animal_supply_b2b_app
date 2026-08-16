import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/order_status.dart';
import '../models/order.dart';

final adminOrderWorkflowStoreProvider =
    Provider<AdminOrderWorkflowStore>((ref) => AdminOrderWorkflowStore());

/// Local staff preference for which legal next-status buttons appear.
///
/// This never invents statuses. Buttons are still intersected with
/// [allowedOrderTransitions] before any Edge Function call.
class AdminOrderWorkflowStore {
  AdminOrderWorkflowStore({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const storageKey = 'admin_orders.workflow.enabled_steps.v1';

  static Set<OrderStatus> get allSteps => {
        for (final status in OrderStatus.values)
          for (final next in allowedOrderTransitions(status))
            next,
      };

  final SharedPreferences? _prefsOverride;
  final Future<SharedPreferences?> Function()? _storeLoader;
  SharedPreferences? _prefs;

  static bool sameSet(Set<OrderStatus> left, Set<OrderStatus> right) =>
      left.length == right.length && left.containsAll(right);

  static List<OrderStatus> ordered(Set<OrderStatus> enabled) => [
        for (final status in OrderStatus.values)
          if (enabled.contains(status) && allSteps.contains(status)) status,
      ];

  static List<OrderStatus> visibleNextStatuses({
    required OrderStatus current,
    required Set<OrderStatus> enabledSteps,
  }) {
    return [
      for (final status in allowedOrderTransitions(current))
        if (enabledSteps.contains(status)) status,
    ];
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
    if (raw == null || raw.trim().isEmpty) return {...allSteps};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {...allSteps};
      final parsed = <OrderStatus>{};
      for (final value in decoded) {
        final name = value.toString().trim();
        for (final status in allSteps) {
          if (status.value == name) parsed.add(status);
        }
      }
      if (parsed.isEmpty) return {...allSteps};
      return parsed;
    } catch (_) {
      return {...allSteps};
    }
  }

  Future<bool> save(Set<OrderStatus> enabled) async {
    final next = {
      for (final status in enabled)
        if (allSteps.contains(status)) status,
    };
    if (next.isEmpty) return false;
    final prefs = await _store();
    if (prefs == null) return false;
    try {
      return await prefs.setString(
        storageKey,
        jsonEncode([for (final status in ordered(next)) status.value]),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> reset() => save(allSteps);
}
