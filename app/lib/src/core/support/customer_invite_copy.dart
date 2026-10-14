const defaultCustomerInviteTemplate = '''مرحباً {business_name} 👋

أهلاً بكم في {shop_name}. يسعدنا انضمام نشاطكم إلى منصة طلبات الجملة.

بيانات الدخول:
اسم المستخدم: {username}
كلمة المرور: {password}

رابط تسجيل الدخول:
{login_url}

يمكنكم تسجيل الدخول باستخدام اسم المستخدم وكلمة المرور الظاهرة هنا.''';

const defaultCustomerInviteTemplateWithoutPassword =
    '''مرحباً {business_name} 👋

أهلاً بكم في {shop_name}. يسعدنا انضمام نشاطكم إلى منصة طلبات الجملة.

اسم المستخدم: {username}

رابط تسجيل الدخول:
{login_url}

يمكنكم تسجيل الدخول باستخدام اسم المستخدم الظاهر هنا وكلمة المرور الحالية لديكم. إذا نسيتم كلمة المرور، تواصلوا مع المتجر لإعادة تعيينها.''';

const customerInviteTemplatePlaceholders = <String>[
  '{business_name}',
  '{contact_name}',
  '{shop_name}',
  '{username}',
  '{password}',
  '{login_url}',
];

const _passwordUrlKeys = {
  'password',
  'temporary_password',
  'temporarypassword',
  'pwd',
  'pass',
};

String customerWhatsappWelcomeMessage({
  required String businessName,
  required String shopName,
  required String username,
  required String loginUrl,
  String? temporaryPassword,
  String? contactName,
  String? template,
}) {
  return renderCustomerInviteTemplate(
    template: template ?? defaultCustomerInviteTemplate,
    businessName: businessName,
    shopName: shopName,
    username: username,
    loginUrl: loginUrl,
    password: temporaryPassword,
    contactName: contactName,
  );
}

String renderCustomerInviteTemplate({
  required String template,
  required String businessName,
  required String shopName,
  required String username,
  required String loginUrl,
  String? password,
  String? contactName,
}) {
  final knownPassword = password?.trim() ?? '';
  final safeLoginUrl = sanitizeInviteLoginUrl(loginUrl);
  var source =
      template.trim().isEmpty ? defaultCustomerInviteTemplate : template;
  if (knownPassword.isEmpty && _isDefaultPasswordTemplate(source)) {
    source = defaultCustomerInviteTemplateWithoutPassword;
  }

  var rendered = source
      .replaceAll('{business_name}', businessName.trim())
      .replaceAll('{contact_name}', (contactName ?? '').trim())
      .replaceAll('{shop_name}', shopName.trim())
      .replaceAll('{username}', username.trim())
      .replaceAll('{password}', knownPassword)
      .replaceAll('{login_url}', safeLoginUrl);

  if (knownPassword.isEmpty) {
    rendered = rendered.replaceAll(
      RegExp(r'^[^\n]*كلمة المرور[^\n]*:\s*$', multiLine: true),
      '',
    );
  }

  rendered = stripSecretsFromInviteUrls(rendered, knownPassword);
  return _collapseBlankLines(rendered).trim();
}

bool _isDefaultPasswordTemplate(String template) {
  return _collapseBlankLines(template).trim() ==
      _collapseBlankLines(defaultCustomerInviteTemplate).trim();
}

String sanitizeInviteLoginUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final parsed = Uri.tryParse(
    trimmed.contains('://') ? trimmed : 'https://$trimmed',
  );
  if (parsed == null || parsed.host.isEmpty) return '';
  final scheme = parsed.scheme.toLowerCase() == 'http' ? 'http' : 'https';
  final includePort = parsed.hasPort &&
      !((scheme == 'https' && parsed.port == 443) ||
          (scheme == 'http' && parsed.port == 80));
  final host = includePort ? '${parsed.host}:${parsed.port}' : parsed.host;
  return '$scheme://$host/login';
}

String stripSecretsFromInviteUrls(String message, String password) {
  return message.replaceAllMapped(
    RegExp(r'https?://[^\s]+', caseSensitive: false),
    (match) {
      final raw = match.group(0) ?? '';
      final uri = Uri.tryParse(raw);
      if (uri == null) return raw;
      final keys =
          uri.queryParameters.keys.map((key) => key.toLowerCase()).toSet();
      final hasSecretQuery = keys.any(_passwordUrlKeys.contains);
      final embedsPassword = password.isNotEmpty && raw.contains(password);
      if (!hasSecretQuery && !embedsPassword && uri.userInfo.isEmpty) {
        return raw;
      }
      final scheme = uri.scheme;
      final includePort = uri.hasPort &&
          !((scheme == 'https' && uri.port == 443) ||
              (scheme == 'http' && uri.port == 80));
      final host = includePort ? '${uri.host}:${uri.port}' : uri.host;
      final path = uri.path.isEmpty ? '/login' : uri.path;
      return '$scheme://$host$path';
    },
  );
}

String _collapseBlankLines(String value) {
  return value.replaceAll(RegExp(r'\n{3,}'), '\n\n');
}
