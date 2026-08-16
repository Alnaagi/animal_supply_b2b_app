class DatabaseUsageSnapshot {
  const DatabaseUsageSnapshot({
    required this.usedBytes,
    required this.quotaBytes,
    required this.percent,
  });

  final int usedBytes;
  final int quotaBytes;
  final int percent;

  factory DatabaseUsageSnapshot.fromFunctionResponse(Object? responseData) {
    final root = _stringKeyedMap(responseData);
    final nested = _stringKeyedMap(root['data']);
    final payload = nested.isNotEmpty ? nested : root;
    if (root['ok'] == false) {
      throw const FormatException('Database usage response was not accepted.');
    }
    final usedBytes = _asNonNegativeInt(payload['used_bytes']);
    final quotaBytes = _asPositiveInt(payload['quota_bytes']);
    final percent = payload.containsKey('percent')
        ? _asPercent(payload['percent'])
        : ((usedBytes / quotaBytes) * 100).round().clamp(0, 100);
    return DatabaseUsageSnapshot(
      usedBytes: usedBytes,
      quotaBytes: quotaBytes,
      percent: percent,
    );
  }
}

Map<String, dynamic> _stringKeyedMap(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

int _asNonNegativeInt(Object? value) {
  final parsed = _asInt(value);
  if (parsed < 0) {
    throw const FormatException('used_bytes must be non-negative.');
  }
  return parsed;
}

int _asPositiveInt(Object? value) {
  final parsed = _asInt(value);
  if (parsed < 1) {
    throw const FormatException('quota_bytes must be positive.');
  }
  return parsed;
}

int _asPercent(Object? value) {
  return _asInt(value).clamp(0, 100);
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  throw const FormatException('A numeric usage field was missing.');
}
