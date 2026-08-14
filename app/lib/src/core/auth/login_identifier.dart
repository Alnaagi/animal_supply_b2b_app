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

String? loginEmailForIdentifier({
  required String identifier,
  required String customerLoginDomain,
}) {
  final normalized = identifier.trim().toLowerCase();
  if (normalized.contains('@')) return normalized;
  if (!isValidCustomerLoginDomain(customerLoginDomain)) return null;
  if (!RegExp(
        r'^[a-z0-9](?:[a-z0-9._-]{1,62}[a-z0-9])$',
      ).hasMatch(normalized) ||
      normalized.contains('..')) {
    return null;
  }
  return '$normalized@${customerLoginDomain.trim().toLowerCase()}';
}
