import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final syncOutboxProvider = Provider<SyncOutbox>((ref) {
  final outbox = SyncOutbox();
  ref.onDispose(outbox.dispose);
  return outbox;
});

final customerOrderOutboxProvider = StreamProvider.autoDispose
    .family<CustomerOrderOutboxSnapshot, String>((ref, ownerProfileId) {
  return ref
      .watch(syncOutboxProvider)
      .watchCustomerOrders(ownerProfileId: ownerProfileId);
});

enum CustomerQueuedOrderState { pending, failed }

class CustomerOrderOutboxSnapshot {
  const CustomerOrderOutboxSnapshot({
    this.pending = const [],
    this.failed = const [],
  });

  final List<SyncOutboxEntry> pending;
  final List<SyncOutboxEntry> failed;

  bool get isEmpty => pending.isEmpty && failed.isEmpty;
  int get totalCount => pending.length + failed.length;
}

class SyncOutboxEntry {
  const SyncOutboxEntry({
    required this.id,
    required this.ownerProfileId,
    required this.entityType,
    required this.payload,
    this.status = 'pending',
    this.errorCode,
  });

  final String id;
  final String ownerProfileId;
  final String entityType;
  final Map<String, Object?> payload;
  final String status;
  final String? errorCode;

  SyncOutboxEntry copyWith({
    String? status,
    String? errorCode,
  }) =>
      SyncOutboxEntry(
        id: id,
        ownerProfileId: ownerProfileId,
        entityType: entityType,
        payload: payload,
        status: status ?? this.status,
        errorCode: errorCode ?? this.errorCode,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'ownerProfileId': ownerProfileId,
        'entityType': entityType,
        'payload': payload,
        'status': status,
        if (errorCode != null) 'errorCode': errorCode,
      };

  factory SyncOutboxEntry.fromJson(Map<String, dynamic> json) {
    final payloadRaw = json['payload'];
    return SyncOutboxEntry(
      id: (json['id'] ?? '').toString(),
      ownerProfileId: (json['ownerProfileId'] ?? '').toString(),
      entityType: (json['entityType'] ?? '').toString(),
      payload: payloadRaw is Map
          ? Map<String, Object?>.from(payloadRaw)
          : <String, Object?>{},
      status: (json['status'] ?? 'pending').toString(),
      errorCode: json['errorCode']?.toString(),
    );
  }
}

/// Durable outbox for deferred remote writes.
///
/// Pending place-order payloads store product IDs and quantities only. Prices,
/// stock, customer identity, and status remain server-authoritative on retry.
class SyncOutbox {
  SyncOutbox({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const _legacyEntriesKey = 'sync_outbox.entries.v1';
  static const _entriesKeyPrefix = 'sync_outbox.entries.v2.';
  static const _quarantineKey = 'sync_outbox.quarantine.v1';

  final SharedPreferences? _prefsOverride;
  final Future<SharedPreferences?> Function()? _storeLoader;
  SharedPreferences? _prefs;
  final Map<String, List<SyncOutboxEntry>> _entriesByOwner = {};
  final Set<String> _loadedOwners = {};
  final Map<String, Future<void>> _loadFuturesByOwner = {};
  final Map<String, Set<String>> _removedIdsByOwner = {};
  final StreamController<String> _ownerChanges =
      StreamController<String>.broadcast(sync: true);
  Future<void>? _legacyQuarantineFuture;

  Stream<String> get ownerChanges => _ownerChanges.stream;

  void dispose() {
    unawaited(_ownerChanges.close());
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

  Future<void> _ensureLoaded(String ownerProfileId) {
    if (_loadedOwners.contains(ownerProfileId)) return Future.value();
    final existing = _loadFuturesByOwner[ownerProfileId];
    if (existing != null) return existing;
    final loading = _loadOwner(ownerProfileId);
    _loadFuturesByOwner[ownerProfileId] = loading;
    return loading.whenComplete(() {
      if (identical(_loadFuturesByOwner[ownerProfileId], loading)) {
        _loadFuturesByOwner.remove(ownerProfileId);
      }
    });
  }

  Future<void> _loadOwner(String ownerProfileId) async {
    await _quarantineLegacyEntries();
    final prefs = await _store();
    final key = _entriesKey(ownerProfileId);
    final raw = prefs?.getString(key);
    if (raw == null || raw.isEmpty) {
      _entriesByOwner[ownerProfileId] = const [];
      _loadedOwners.add(ownerProfileId);
      return;
    }

    final accepted = <SyncOutboxEntry>[];
    final rejected = <Object?>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final row in decoded) {
          if (row is! Map) {
            rejected.add(row);
            continue;
          }
          final mapped = Map<String, dynamic>.from(row);
          final entry = SyncOutboxEntry.fromJson(mapped);
          if (entry.id.trim().isEmpty ||
              entry.entityType.trim().isEmpty ||
              entry.ownerProfileId != ownerProfileId) {
            rejected.add(mapped);
            continue;
          }
          accepted.add(entry);
        }
      } else {
        rejected.add(decoded);
      }
    } catch (_) {
      rejected.add(raw);
    }

    final removedIds = _removedIdsByOwner[ownerProfileId] ?? const {};
    final acceptedBeforeDiscard = accepted.length;
    accepted.removeWhere((entry) => removedIds.contains(entry.id));
    _entriesByOwner[ownerProfileId] = accepted;
    _loadedOwners.add(ownerProfileId);
    if (rejected.isNotEmpty || accepted.length != acceptedBeforeDiscard) {
      await _appendQuarantine(
        sourceKey: key,
        reason: 'invalid_or_owner_mismatch',
        values: rejected,
      );
      await _persist(ownerProfileId);
    }
  }

  Future<bool> _persist(String ownerProfileId) async {
    final prefs = await _store();
    if (prefs == null) return false;
    try {
      return await prefs.setString(
        _entriesKey(ownerProfileId),
        jsonEncode([
          for (final entry in _entriesByOwner[ownerProfileId] ?? const [])
            entry.toJson(),
        ]),
      );
    } catch (_) {
      return false;
    }
  }

  /// Returns true only when the entry was durably written to device storage.
  ///
  /// A false result means the entry remains available for this process only
  /// and must not be described to the customer as safely stored offline.
  Future<bool> enqueue(SyncOutboxEntry entry) async {
    final owner = _normalizeOwner(entry.ownerProfileId);
    if (owner == null || owner != entry.ownerProfileId) {
      throw ArgumentError.value(
        entry.ownerProfileId,
        'entry.ownerProfileId',
        'A normalized authenticated profile ID is required.',
      );
    }
    await _ensureLoaded(owner);
    _removedIdsByOwner[owner]?.remove(entry.id);
    final entries = _entriesByOwner[owner] ?? const [];
    final index = entries.indexWhere((item) => item.id == entry.id);
    if (index == -1) {
      _entriesByOwner[owner] = [...entries, entry];
    } else {
      _entriesByOwner[owner] = [
        for (var i = 0; i < entries.length; i++)
          if (i == index) entry else entries[i],
      ];
    }
    final durable = await _persist(owner);
    _notifyOwner(owner);
    return durable;
  }

  Future<List<SyncOutboxEntry>> pending({
    required String ownerProfileId,
  }) async {
    final owner = _normalizeOwner(ownerProfileId);
    if (owner == null) return const [];
    await _ensureLoaded(owner);
    final removedIds = _removedIdsByOwner[owner] ?? const {};
    return (_entriesByOwner[owner] ?? const [])
        .where(
          (entry) =>
              entry.status == 'pending' && !removedIds.contains(entry.id),
        )
        .toList(growable: false);
  }

  Future<List<SyncOutboxEntry>> failed({
    required String ownerProfileId,
  }) async {
    final owner = _normalizeOwner(ownerProfileId);
    if (owner == null) return const [];
    await _ensureLoaded(owner);
    return (_entriesByOwner[owner] ?? const [])
        .where((entry) => entry.status == 'failed')
        .toList(growable: false);
  }

  Future<CustomerOrderOutboxSnapshot> customerOrderSnapshot({
    required String ownerProfileId,
  }) async {
    final owner = _normalizeOwner(ownerProfileId);
    if (owner == null) return const CustomerOrderOutboxSnapshot();
    await _ensureLoaded(owner);
    final removedIds = _removedIdsByOwner[owner] ?? const {};
    final placeOrders = (_entriesByOwner[owner] ?? const [])
        .where(
          (entry) =>
              entry.ownerProfileId == owner &&
              entry.entityType == 'place_order' &&
              !removedIds.contains(entry.id),
        )
        .toList(growable: false);
    return CustomerOrderOutboxSnapshot(
      pending: placeOrders
          .where((entry) => entry.status == 'pending')
          .toList(growable: false),
      failed: placeOrders
          .where((entry) => entry.status == 'failed')
          .toList(growable: false),
    );
  }

  Stream<CustomerOrderOutboxSnapshot> watchCustomerOrders({
    required String ownerProfileId,
  }) {
    final owner = _normalizeOwner(ownerProfileId);
    if (owner == null) {
      return Stream.value(const CustomerOrderOutboxSnapshot());
    }

    late final StreamController<CustomerOrderOutboxSnapshot> controller;
    StreamSubscription<String>? changeSubscription;
    var cancelled = false;
    var refreshChain = Future<void>.value();

    Future<void> emitSnapshot() async {
      try {
        final snapshot = await customerOrderSnapshot(ownerProfileId: owner);
        if (!cancelled && !controller.isClosed) {
          controller.add(snapshot);
        }
      } catch (error, stackTrace) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    void scheduleRefresh() {
      refreshChain = refreshChain.then((_) => emitSnapshot());
    }

    controller = StreamController<CustomerOrderOutboxSnapshot>(
      sync: true,
      onListen: () {
        changeSubscription = _ownerChanges.stream.listen(
          (changedOwner) {
            if (changedOwner == owner) scheduleRefresh();
          },
          onError: controller.addError,
          onDone: controller.close,
        );
        scheduleRefresh();
      },
      onCancel: () async {
        cancelled = true;
        await changeSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> markSynced(
    String id, {
    required String ownerProfileId,
  }) async {
    final owner = _normalizeOwner(ownerProfileId);
    if (owner == null) return;
    await _ensureLoaded(owner);
    final entries = _entriesByOwner[owner] ?? const [];
    _entriesByOwner[owner] = [
      for (final entry in entries)
        if (entry.id == id) entry.copyWith(status: 'synced') else entry,
    ];
    await _persist(owner);
    _notifyOwner(owner);
  }

  Future<void> markFailed(
    String id, {
    required String ownerProfileId,
    required String errorCode,
  }) async {
    final owner = _normalizeOwner(ownerProfileId);
    if (owner == null) return;
    await _ensureLoaded(owner);
    final entries = _entriesByOwner[owner] ?? const [];
    _entriesByOwner[owner] = [
      for (final entry in entries)
        if (entry.id == id)
          entry.copyWith(status: 'failed', errorCode: errorCode)
        else
          entry,
    ];
    await _persist(owner);
    _notifyOwner(owner);
  }

  /// Discards a queued order only when its owner and visible state still match.
  ///
  /// This is intentionally a discard-for-edit operation, not a manual replay
  /// of a potentially stale payload.
  Future<bool> discardPlaceOrderForEditing(
    String id, {
    required String ownerProfileId,
    required CustomerQueuedOrderState expectedState,
  }) async {
    final owner = _normalizeOwner(ownerProfileId);
    if (owner == null) return false;
    await _ensureLoaded(owner);
    final entries = _entriesByOwner[owner] ?? const [];
    final index = entries.indexWhere(
      (entry) =>
          entry.id == id &&
          entry.ownerProfileId == owner &&
          entry.entityType == 'place_order' &&
          entry.status == expectedState.name,
    );
    if (index == -1) return false;

    final previousEntries = List<SyncOutboxEntry>.from(entries);
    final removedIds = _removedIdsByOwner[owner] ??= <String>{};
    final wasAlreadyRemoved = removedIds.contains(id);
    removedIds.add(id);
    _entriesByOwner[owner] = [
      for (var i = 0; i < entries.length; i++)
        if (i != index) entries[i],
    ];
    final durable = await _persist(owner);
    if (!durable) {
      _entriesByOwner[owner] = previousEntries;
      if (!wasAlreadyRemoved) removedIds.remove(id);
      if (removedIds.isEmpty) _removedIdsByOwner.remove(owner);
      return false;
    }
    _notifyOwner(owner);
    return true;
  }

  /// Removes an entry only when the updated owner queue is durably persisted.
  ///
  /// A false result leaves the in-memory and stored entry intact so an
  /// idempotent remote write can be reconciled again after storage recovers.
  Future<bool> remove(
    String id, {
    required String ownerProfileId,
  }) async {
    final owner = _normalizeOwner(ownerProfileId);
    if (owner == null) return false;
    await _ensureLoaded(owner);
    final entries = _entriesByOwner[owner] ?? const [];
    if (!entries.any((entry) => entry.id == id)) return false;

    final previousEntries = List<SyncOutboxEntry>.from(entries);
    final removedIds = _removedIdsByOwner[owner] ??= <String>{};
    final wasAlreadyRemoved = removedIds.contains(id);
    removedIds.add(id);
    _entriesByOwner[owner] = [
      for (final entry in entries)
        if (entry.id != id) entry,
    ];
    final durable = await _persist(owner);
    if (!durable) {
      _entriesByOwner[owner] = previousEntries;
      if (!wasAlreadyRemoved) removedIds.remove(id);
      if (removedIds.isEmpty) _removedIdsByOwner.remove(owner);
      return false;
    }
    _notifyOwner(owner);
    return true;
  }

  Future<void> _quarantineLegacyEntries() {
    return _legacyQuarantineFuture ??= _quarantineLegacyEntriesBody();
  }

  Future<void> _quarantineLegacyEntriesBody() async {
    final prefs = await _store();
    final raw = prefs?.getString(_legacyEntriesKey);
    if (prefs == null || raw == null || raw.isEmpty) return;
    final values = <Object?>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        values.addAll(decoded);
      } else {
        values.add(decoded);
      }
    } catch (_) {
      values.add(raw);
    }
    await _appendQuarantine(
      sourceKey: _legacyEntriesKey,
      reason: 'legacy_unowned',
      values: values,
    );
    await prefs.remove(_legacyEntriesKey);
  }

  Future<void> _appendQuarantine({
    required String sourceKey,
    required String reason,
    required List<Object?> values,
  }) async {
    final prefs = await _store();
    if (prefs == null || values.isEmpty) return;
    final quarantined = <Object?>[];
    final existing = prefs.getString(_quarantineKey);
    if (existing != null && existing.isNotEmpty) {
      try {
        final decoded = jsonDecode(existing);
        if (decoded is List) quarantined.addAll(decoded);
      } catch (_) {}
    }
    quarantined.addAll([
      for (final value in values)
        {
          'sourceKey': sourceKey,
          'reason': reason,
          'value': value,
        },
    ]);
    await prefs.setString(_quarantineKey, jsonEncode(quarantined));
  }

  static String? _normalizeOwner(String ownerProfileId) {
    final owner = ownerProfileId.trim();
    return owner.isEmpty ? null : owner;
  }

  static String _entriesKey(String ownerProfileId) {
    final encoded =
        base64Url.encode(utf8.encode(ownerProfileId)).replaceAll('=', '');
    return '$_entriesKeyPrefix$encoded';
  }

  void _notifyOwner(String ownerProfileId) {
    if (!_ownerChanges.isClosed) {
      _ownerChanges.add(ownerProfileId);
    }
  }
}
