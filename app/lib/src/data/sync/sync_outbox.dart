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
}

class SyncOutbox {
  final List<SyncOutboxEntry> _entries = [];

  Future<void> enqueue(SyncOutboxEntry entry) async => _entries.add(entry);
  Future<List<SyncOutboxEntry>> pending() async =>
      _entries.where((e) => e.status == 'pending').toList();
}
