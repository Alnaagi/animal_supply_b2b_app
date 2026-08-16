bool isValidCustomerLoginDomain(String rawDomain) {
  final domain = rawDomain.trim().toLowerCase();
  if (domain.isEmpty ||
      domain.contains('/') ||
      domain.contains('@') ||
      domain.contains(':') ||
      !domain.contains('.') ||
      !RegExp(
        r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$',
      ).hasMatch(domain)) {
    return false;
  }
  const forbidden = {
    'example.com',
    'example.net',
    'example.org',
    'localhost',
  };
  return !forbidden.contains(domain) &&
      !domain.endsWith('.invalid') &&
      !domain.endsWith('.example') &&
      !domain.endsWith('.test') &&
      !domain.endsWith('.localhost');
}

String _asciiDigitsOnly(String raw) {
  const eastern = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final buffer = StringBuffer();
  for (final unit in raw.runes) {
    final character = String.fromCharCode(unit);
    final easternIndex = eastern.indexOf(character);
    if (easternIndex >= 0) {
      buffer.write(easternIndex);
      continue;
    }
    final persianIndex = persian.indexOf(character);
    if (persianIndex >= 0) {
      buffer.write(persianIndex);
      continue;
    }
    if (unit >= 48 && unit <= 57) {
      buffer.write(character);
    }
  }
  return buffer.toString();
}

/// Libyan mobile in E.164 (`+2189…`), or null if the value is not a phone.
String? normalizeLibyanLoginPhone(String raw) {
  var digits = _asciiDigitsOnly(raw);
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('0')) digits = '218${digits.substring(1)}';
  if (digits.startsWith('9')) digits = '218$digits';
  if (!digits.startsWith('2189')) return null;
  if (digits.length < 12 || digits.length > 13) return null;
  return '+$digits';
}

bool isValidCustomerUsername(String username) {
  final normalized = username.trim().toLowerCase();
  return RegExp(
        r'^[a-z0-9](?:[a-z0-9._-]{1,62}[a-z0-9])$',
      ).hasMatch(normalized) &&
      !normalized.contains('..');
}

/// Digits from a phone number that can be stored as `profiles.username`.
String? usernameFromPhoneDigits(String rawPhone) {
  final e164 = normalizeLibyanLoginPhone(rawPhone);
  final digits = e164 != null ? e164.substring(1) : _asciiDigitsOnly(rawPhone);
  if (!isValidCustomerUsername(digits)) return null;
  return digits;
}

/// On create, an empty username falls back to the phone digits.
String resolveCustomerCreateUsername({
  required String username,
  required String phone,
}) {
  final trimmed = username.trim();
  if (trimmed.isNotEmpty) return trimmed;
  return usernameFromPhoneDigits(phone) ?? '';
}

class LoginAuthTarget {
  const LoginAuthTarget.email(this.email) : phone = null;
  const LoginAuthTarget.phone(this.phone) : email = null;

  final String? email;
  final String? phone;
}

/// Documented seed/demo Auth emails for reserved staff usernames.
/// These are public identifiers, not secrets.
const reservedStaffLoginEmails = <String, String>{
  'admin': 'admin@demo.ly',
  'staff': 'staff@demo.ly',
};

bool isReservedStaffLoginIdentifier(String identifier) {
  final normalized = identifier.trim().toLowerCase();
  return reservedStaffLoginEmails.containsKey(normalized);
}

/// Maps a username or phone to the hidden Auth identifier.
/// Emails are still accepted internally for existing staff accounts, but the
/// login field does not ask for email.
LoginAuthTarget? loginAuthTargetForIdentifier({
  required String identifier,
  required String customerLoginDomain,
}) {
  final phone = normalizeLibyanLoginPhone(identifier);
  if (phone != null) {
    return LoginAuthTarget.phone(phone);
  }
  final email = loginEmailForIdentifier(
    identifier: identifier,
    customerLoginDomain: customerLoginDomain,
  );
  if (email == null) return null;
  return LoginAuthTarget.email(email);
}

String? loginEmailForIdentifier({
  required String identifier,
  required String customerLoginDomain,
}) {
  final normalized = identifier.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  if (normalizeLibyanLoginPhone(normalized) != null) return null;
  if (normalized.contains('@')) return normalized;
  if (isReservedStaffLoginIdentifier(normalized)) {
    return reservedStaffLoginEmails[normalized];
  }
  if (!isValidCustomerLoginDomain(customerLoginDomain)) return null;
  if (!isValidCustomerUsername(normalized)) {
    return null;
  }
  return '$normalized@${customerLoginDomain.trim().toLowerCase()}';
}
