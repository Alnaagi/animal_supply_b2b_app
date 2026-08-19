/// Typed confirmation for irreversible admin actions.
///
/// Arabic has no capital letters, so the required phrase is Latin uppercase.
class DestructiveConfirmPhrase {
  static const requiredPhrase = 'RESET';

  static const instructionsAr = 'اكتب RESET بأحرف إنجليزية كبيرة (CAPS). '
      'كلمة reset الصغيرة غير مقبولة، والعربية لا تملك أحرفاً كبيرة.';

  static const mismatchAr =
      'يجب إدخال RESET بأحرف إنجليزية كبيرة تماماً. الأحرف الصغيرة مرفوضة.';

  static bool matches(String input) => input == requiredPhrase;

  static String? validationMessage(String input) {
    if (matches(input)) return null;
    return mismatchAr;
  }
}
