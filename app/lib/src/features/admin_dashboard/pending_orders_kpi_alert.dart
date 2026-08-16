import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingOrdersKpiAlertState {
  const PendingOrdersKpiAlertState({
    this.hasObserved = false,
    this.lastObservedCount = 0,
    this.acknowledgedCount = 0,
    this.ackOnNextObserve = false,
  });

  final bool hasObserved;
  final int lastObservedCount;
  final int acknowledgedCount;
  final bool ackOnNextObserve;

  bool get shouldHighlight {
    if (ackOnNextObserve) return false;
    if (!hasObserved) return false;
    return lastObservedCount > 0 && lastObservedCount > acknowledgedCount;
  }

  PendingOrdersKpiAlertState copyWith({
    bool? hasObserved,
    int? lastObservedCount,
    int? acknowledgedCount,
    bool? ackOnNextObserve,
  }) {
    return PendingOrdersKpiAlertState(
      hasObserved: hasObserved ?? this.hasObserved,
      lastObservedCount: lastObservedCount ?? this.lastObservedCount,
      acknowledgedCount: acknowledgedCount ?? this.acknowledgedCount,
      ackOnNextObserve: ackOnNextObserve ?? this.ackOnNextObserve,
    );
  }
}

class PendingOrdersKpiAlertLogic {
  const PendingOrdersKpiAlertLogic();

  PendingOrdersKpiAlertState observe({
    required PendingOrdersKpiAlertState state,
    required int pendingCount,
  }) {
    final pending = pendingCount < 0 ? 0 : pendingCount;
    var acknowledged = state.acknowledgedCount;
    if (pending < acknowledged) acknowledged = pending;

    if (state.ackOnNextObserve) {
      return PendingOrdersKpiAlertState(
        hasObserved: true,
        lastObservedCount: pending,
        acknowledgedCount: pending,
        ackOnNextObserve: false,
      );
    }

    return PendingOrdersKpiAlertState(
      hasObserved: true,
      lastObservedCount: pending,
      acknowledgedCount: acknowledged,
      ackOnNextObserve: false,
    );
  }

  PendingOrdersKpiAlertState acknowledge(PendingOrdersKpiAlertState state) {
    if (!state.hasObserved) {
      return state.copyWith(ackOnNextObserve: true);
    }
    return state.copyWith(
      acknowledgedCount: state.lastObservedCount,
      ackOnNextObserve: false,
    );
  }
}

class PendingOrdersKpiAlertStore {
  PendingOrdersKpiAlertStore({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const storageKey = 'admin_dashboard.pending_orders_kpi_alert.v1';

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

  Future<PendingOrdersKpiAlertState> load() async {
    try {
      final prefs = await _store();
      return decode(prefs?.getString(storageKey));
    } catch (_) {
      return const PendingOrdersKpiAlertState();
    }
  }

  Future<bool> save(PendingOrdersKpiAlertState state) async {
    try {
      final prefs = await _store();
      if (prefs == null) return false;
      return await prefs.setString(storageKey, encode(state));
    } catch (_) {
      return false;
    }
  }

  static String encode(PendingOrdersKpiAlertState state) {
    return jsonEncode({
      'acknowledgedCount': state.acknowledgedCount,
      'ackOnNextObserve': state.ackOnNextObserve,
    });
  }

  static PendingOrdersKpiAlertState decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const PendingOrdersKpiAlertState();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const PendingOrdersKpiAlertState();
      return PendingOrdersKpiAlertState(
        acknowledgedCount: _asInt(decoded['acknowledgedCount']),
        ackOnNextObserve: decoded['ackOnNextObserve'] == true,
      );
    } catch (_) {
      return const PendingOrdersKpiAlertState();
    }
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

final pendingOrdersKpiAlertStoreProvider = Provider<PendingOrdersKpiAlertStore>(
  (ref) => PendingOrdersKpiAlertStore(),
);

final pendingOrdersKpiAlertProvider = StateNotifierProvider<
    PendingOrdersKpiAlertController, PendingOrdersKpiAlertState>(
  (ref) => PendingOrdersKpiAlertController(
    ref.watch(pendingOrdersKpiAlertStoreProvider),
  ),
);

class PendingOrdersKpiAlertController
    extends StateNotifier<PendingOrdersKpiAlertState> {
  PendingOrdersKpiAlertController(this._store)
      : super(const PendingOrdersKpiAlertState()) {
    _ready = reload();
  }

  final PendingOrdersKpiAlertStore _store;
  final PendingOrdersKpiAlertLogic _logic = const PendingOrdersKpiAlertLogic();
  late final Future<void> _ready;

  Future<void> reload() async {
    state = await _store.load();
  }

  Future<void> observe(int pendingCount) async {
    await _ready;
    state = _logic.observe(state: state, pendingCount: pendingCount);
    await _store.save(state);
  }

  Future<void> acknowledge() async {
    await _ready;
    state = _logic.acknowledge(state);
    await _store.save(state);
  }
}

Future<void> openAdminOrders(
  WidgetRef ref,
  void Function(String location) go, {
  String location = '/admin/orders',
}) async {
  await ref.read(pendingOrdersKpiAlertProvider.notifier).acknowledge();
  go(location);
}
