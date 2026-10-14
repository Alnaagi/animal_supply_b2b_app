class ApplicationDataResetResult {
  const ApplicationDataResetResult({
    required this.reset,
    required this.preservedAdminId,
    required this.truncatedTables,
    required this.customerProfilesDeleted,
    required this.customerAuthUsersDeleted,
  });

  final bool reset;
  final String preservedAdminId;
  final List<String> truncatedTables;
  final int customerProfilesDeleted;
  final int customerAuthUsersDeleted;

  factory ApplicationDataResetResult.fromFunctionResponse(
      Object? responseData) {
    final root = _stringKeyedMap(responseData);
    final nested = _stringKeyedMap(root['data']);
    final payload = nested.isNotEmpty ? nested : root;
    if (root['ok'] == false || payload['reset'] != true) {
      throw const FormatException(
          'Application reset response was not accepted.');
    }
    return ApplicationDataResetResult(
      reset: true,
      preservedAdminId: payload['preserved_admin_id']?.toString() ?? '',
      truncatedTables: _asStringList(payload['truncated_tables']),
      customerProfilesDeleted: _asNonNegativeInt(
        payload['customer_profiles_deleted'],
      ),
      customerAuthUsersDeleted: _asNonNegativeInt(
        payload['customer_auth_users_deleted'],
      ),
    );
  }
}

Map<String, dynamic> _stringKeyedMap(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}

int _asNonNegativeInt(Object? value) {
  if (value == null) return 0;
  if (value is int) {
    if (value < 0) {
      throw const FormatException('A reset count was negative.');
    }
    return value;
  }
  if (value is num) return value.round().clamp(0, 1 << 30);
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed >= 0) return parsed;
  }
  throw const FormatException('A reset count was missing.');
}
