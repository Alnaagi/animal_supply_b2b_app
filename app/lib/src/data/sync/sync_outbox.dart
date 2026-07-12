import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final syncOutboxProvider = Provider<SyncOutbox>((ref) => SyncOutbox());

class SyncOutboxEntry {
  const SyncOutboxEntry({
    required this.id,
    required this.entityType,
    required this.payload,
    this.status = 'pending',
  });

  final String id;
  final String entityType;
  final Map<String, Object?> payload;
  final String status;

  SyncOutboxEntry copyWith({String? status}) => SyncOutboxEntry(
        id: id,
        entityType: entityType,
        payload: payload,
        status: status ?? this.status,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'entityType': entityType,
        'payload': payload,
        'status': status,
      };

  factory SyncOutboxEntry.fromJson(Map<String, dynamic> json) {
    final payloadRaw = json['payload'];
    return SyncOutboxEntry(
      id: (json['id'] ?? '').toString(),
      entityType: (json['entityType'] ?? '').toString(),
      payload: payloadRaw is Map
          ? Map<String, Object?>.from(payloadRaw)
          : <String, Object?>{},
      status: (json['status'] ?? 'pending').toString(),
    );
  }
}

/// Durable outbox for deferred remote writes.
///
/// Pending place-order payloads store product IDs and quantities only. Prices,
/// stock, customer identity, and status remain server-authoritative on retry.
class SyncOutbox {
  SyncOutbox({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const _entriesKey = 'sync_outbox.entries.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;
  List<SyncOutboxEntry> _entries = [];
  bool _loaded = false;

  Future<SharedPreferences?> _store() async {
    if (_prefsOverride != null) return _prefsOverride;
    try {
      return _prefs ??= await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await _store();
    final raw = prefs?.getString(_entriesKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return;
    _entries = [
      for (final row in decoded)
        if (row is Map)
          SyncOutboxEntry.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  Future<void> _persist() async {
    final prefs = await _store();
    if (prefs == null) return;
    await prefs.setString(
      _entriesKey,
      jsonEncode([for (final entry in _entries) entry.toJson()]),
    );
  }

  Future<void> enqueue(SyncOutboxEntry entry) async {
    await _ensureLoaded();
    final index = _entries.indexWhere((item) => item.id == entry.id);
    if (index == -1) {
      _entries = [..._entries, entry];
    } else {
      _entries = [
        for (var i = 0; i < _entries.length; i++)
          if (i == index) entry else _entries[i],
      ];
    }
    await _persist();
  }

  Future<List<SyncOutboxEntry>> pending() async {
    await _ensureLoaded();
    return _entries.where((entry) => entry.status == 'pending').toList();
  }

  Future<void> markSynced(String id) async {
    await _ensureLoaded();
    _entries = [
      for (final entry in _entries)
        if (entry.id == id) entry.copyWith(status: 'synced') else entry,
    ];
    await _persist();
  }

  Future<void> remove(String id) async {
    await _ensureLoaded();
    _entries = _entries.where((entry) => entry.id != id).toList();
    await _persist();
  }
}
