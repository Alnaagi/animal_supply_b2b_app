import 'dart:convert';

enum FirebaseClientPlatform { web, android, ios }

String? validatePublicAppOriginAr(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      _isLocalOrPlaceholderHost(uri.host)) {
    return 'APP_PUBLIC_ORIGIN يجب أن يكون أصل HTTPS حقيقياً للتطبيق بلا مسار أو بيانات دخول.';
  }
  return null;
}

class SupabasePublicConfigValidation {
  const SupabasePublicConfigValidation._({
    required this.isValid,
    this.messageAr,
  });

  const SupabasePublicConfigValidation.valid() : this._(isValid: true);

  const SupabasePublicConfigValidation.invalid(String messageAr)
      : this._(isValid: false, messageAr: messageAr);

  final bool isValid;
  final String? messageAr;
}

SupabasePublicConfigValidation validateSupabasePublicConfig({
  required String url,
  required String publicKey,
  required bool allowLocalUrl,
}) {
  final normalizedUrl = url.trim();
  final normalizedKey = publicKey.trim();
  if (normalizedUrl.isEmpty || normalizedKey.isEmpty) {
    return const SupabasePublicConfigValidation.invalid(
      'أضف SUPABASE_URL وSUPABASE_ANON_KEY العام عند بناء النسخة.',
    );
  }

  final uri = Uri.tryParse(normalizedUrl);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    return const SupabasePublicConfigValidation.invalid(
      'SUPABASE_URL يجب أن يكون رابط HTTPS أساسياً صالحاً بلا بيانات دخول أو استعلامات.',
    );
  }
  if (!allowLocalUrl && _isLocalOrPlaceholderHost(uri.host)) {
    return const SupabasePublicConfigValidation.invalid(
      'نسخة الإنتاج تحتاج مشروع Supabase حقيقياً، وليس رابطاً محلياً أو تجريبياً.',
    );
  }

  if (normalizedKey.startsWith('sb_secret_')) {
    return const SupabasePublicConfigValidation.invalid(
      'تم رفض مفتاح Supabase سري. استخدم مفتاح anon أو publishable العام فقط.',
    );
  }
  if (normalizedKey.startsWith('sb_publishable_')) {
    if (normalizedKey.length < 24 || _looksLikePlaceholder(normalizedKey)) {
      return const SupabasePublicConfigValidation.invalid(
        'مفتاح Supabase العام غير صالح أو ما زال قيمة تجريبية.',
      );
    }
    return const SupabasePublicConfigValidation.valid();
  }

  final jwtRole = _legacySupabaseJwtRole(normalizedKey);
  if (jwtRole == 'service_role') {
    return const SupabasePublicConfigValidation.invalid(
      'تم رفض مفتاح service_role. هذا المفتاح يبقى داخل Edge Functions فقط.',
    );
  }
  if (jwtRole != 'anon') {
    return const SupabasePublicConfigValidation.invalid(
      'SUPABASE_ANON_KEY ليس مفتاح anon أو publishable عاماً صالحاً.',
    );
  }

  return const SupabasePublicConfigValidation.valid();
}

String? firebaseClientConfigurationIssueAr({
  required FirebaseClientPlatform platform,
  required String apiKey,
  required String projectId,
  required String messagingSenderId,
  required String webAppId,
  required String androidAppId,
  required String iosAppId,
  required String webVapidKey,
}) {
  final requiredBase = [apiKey, projectId, messagingSenderId];
  if (requiredBase.any(
    (value) => value.trim().isEmpty || _looksLikePlaceholder(value),
  )) {
    return 'نسخة الإنتاج تحتاج إعداد Firebase العام الكامل للإشعارات.';
  }

  switch (platform) {
    case FirebaseClientPlatform.web:
      if (webAppId.trim().isEmpty ||
          webVapidKey.trim().isEmpty ||
          _looksLikePlaceholder(webAppId) ||
          _looksLikePlaceholder(webVapidKey)) {
        return 'نسخة الويب تحتاج FIREBASE_WEB_APP_ID وFIREBASE_WEB_VAPID_KEY صالحين.';
      }
    case FirebaseClientPlatform.android:
      if (androidAppId.trim().isEmpty || _looksLikePlaceholder(androidAppId)) {
        return 'نسخة Android تحتاج FIREBASE_ANDROID_APP_ID صالحاً.';
      }
    case FirebaseClientPlatform.ios:
      if (iosAppId.trim().isEmpty || _looksLikePlaceholder(iosAppId)) {
        return 'نسخة iOS تحتاج FIREBASE_IOS_APP_ID صالحاً.';
      }
  }
  return null;
}

String firebaseClosedAppRequirementAr({required bool configured}) {
  const tray =
      'بعد السماح، يظهر التنبيه في شريط إشعارات الهاتف أو الحاسوب طالما التطبيق أو تبويب المتصفح يعمل، حتى في الخلفية.';
  const closed =
      'لا نستخدم Firebase حالياً. إذا أُغلقت العملية بالكامل فلن يصل إشعار جديد.';
  return '$tray $closed';
}

String? _legacySupabaseJwtRole(String key) {
  final parts = key.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map) return null;
    return payload['role']?.toString();
  } catch (_) {
    return null;
  }
}

bool _isLocalOrPlaceholderHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1' ||
      normalized.endsWith('.localhost') ||
      normalized.endsWith('.invalid') ||
      normalized.endsWith('.example') ||
      normalized == 'example.com' ||
      normalized == 'example.net' ||
      normalized == 'example.org' ||
      normalized.contains('your_project');
}

bool _looksLikePlaceholder(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized.contains('your_') ||
      normalized.contains('replace_me') ||
      normalized.contains('xxxxxxxx') ||
      normalized.contains('<') ||
      normalized.contains('>');
}
