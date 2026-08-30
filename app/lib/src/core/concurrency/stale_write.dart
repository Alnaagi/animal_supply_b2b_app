import '../localization/arabic_copy.dart';

class StaleWriteException implements Exception {
  const StaleWriteException([this.message = ArabicCopy.staleWrite]);

  static const code = 'STALE_WRITE';

  final String message;

  @override
  String toString() => message;
}

String? utcIsoOrNull(DateTime? value) {
  if (value == null) return null;
  // Truncate to milliseconds to match Postgres assert_fresh_updated_at.
  final utc = value.toUtc();
  final truncated = DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  );
  return truncated.toIso8601String();
}

bool sameUpdatedAt(DateTime? current, DateTime? expected) {
  if (expected == null) return true;
  if (current == null) return false;
  return current.toUtc().millisecondsSinceEpoch ==
      expected.toUtc().millisecondsSinceEpoch;
}

void throwIfStaleWrite({
  required DateTime? current,
  required DateTime? expected,
}) {
  if (!sameUpdatedAt(current, expected)) {
    throw const StaleWriteException();
  }
}

void rethrowIfStaleWrite(Object error) {
  if (error is StaleWriteException) throw error;
  final code = _errorCode(error);
  final message = (_errorMessage(error) ?? error.toString()).toUpperCase();
  if (code == StaleWriteException.code ||
      code == 'CUSTOMER_UPDATE_CONFLICT' ||
      code == 'RESET_IN_PROGRESS' ||
      message.contains('STALE_WRITE') ||
      message.contains('RESET_IN_PROGRESS')) {
    throw StaleWriteException(
      mutationFailureMessageAr(error, fallback: ArabicCopy.staleWrite),
    );
  }
}

String mutationFailureMessageAr(
  Object error, {
  required String fallback,
}) {
  if (error is StaleWriteException) return error.message;
  final code = _errorCode(error);
  if (code == StaleWriteException.code ||
      code == 'CUSTOMER_UPDATE_CONFLICT' ||
      code == 'RESET_IN_PROGRESS') {
    final message = _errorMessage(error);
    if (message != null && message.trim().isNotEmpty) return message.trim();
    if (code == 'RESET_IN_PROGRESS') {
      return 'عملية مسح البيانات قيد التنفيذ من جهاز آخر. انتظر ثم حدّث الصفحة.';
    }
    return ArabicCopy.staleWrite;
  }
  final message = _errorMessage(error);
  if (message != null && _containsArabic(message)) return message;
  // Surface PostgREST/DB detail so storefront and similar builders aren't opaque.
  final details = <String>[
    if (code != null && code.isNotEmpty) code,
    if (message != null && message.trim().isNotEmpty) message.trim(),
  ];
  if (details.isEmpty) return fallback;
  return '$fallback (${details.join(': ')})';
}

String? _errorCode(Object error) {
  try {
    final value = (error as dynamic).code;
    if (value is String) return value.toUpperCase();
  } catch (_) {}
  return null;
}

String? _errorMessage(Object error) {
  try {
    final value = (error as dynamic).message;
    if (value is String) return value;
  } catch (_) {}
  return null;
}

bool _containsArabic(String value) =>
    RegExp(r'[\u0600-\u06ff]').hasMatch(value);
