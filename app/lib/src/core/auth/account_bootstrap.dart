import '../../data/models/app_user.dart';

class AccountBootstrapException implements Exception {
  const AccountBootstrapException(this.message);

  final String message;
}

AppUser appUserFromBootstrapPayload(
  Object? payload, {
  required String authUserId,
  String? fallbackIdentifier,
}) {
  if (payload is! Map) {
    throw const AccountBootstrapException(
      'تعذر التحقق من بيانات الحساب. تواصل مع إدارة المتجر.',
    );
  }
  final data = <String, dynamic>{
    for (final entry in payload.entries) entry.key.toString(): entry.value,
  };
  if (data['id']?.toString() != authUserId) {
    throw const AccountBootstrapException(
      'تعذر مطابقة الحساب مع جلسة الدخول الحالية.',
    );
  }

  final role = data['role']?.toString() ?? '';
  if (!const {'admin', 'staff', 'customer'}.contains(role)) {
    throw const AccountBootstrapException(
      'هذا الحساب لا يملك صلاحية معتمدة لاستخدام التطبيق.',
    );
  }
  if (data['active'] != true) {
    throw const AccountBootstrapException(
      'تم إيقاف هذا الحساب. تواصل مع إدارة المتجر.',
    );
  }
  final mustChangePassword = data['must_change_password'];
  if (mustChangePassword is! bool) {
    throw const AccountBootstrapException(
      'إعدادات أمان الحساب غير مكتملة. تواصل مع إدارة المتجر.',
    );
  }

  final customer = _stringMap(data['customer']);
  if (role == 'customer') {
    if (customer == null ||
        customer['id']?.toString().trim().isEmpty != false) {
      throw const AccountBootstrapException(
        'بيانات العميل غير مكتملة. تواصل مع إدارة المتجر.',
      );
    }
    final status = customer['account_status']?.toString() ?? '';
    if (status != 'active') {
      throw AccountBootstrapException(
        status == 'suspended'
            ? 'حساب العميل موقوف مؤقتاً. تواصل مع إدارة المتجر.'
            : 'حساب العميل مؤرشف وغير متاح للطلبات.',
      );
    }
  }

  final username = data['username']?.toString().trim() ?? '';
  final customerContact = customer?['contact_person']?.toString().trim() ?? '';
  final customerPhone = customer?['phone']?.toString().trim() ?? '';
  return AppUser(
    id: authUserId,
    username: username.isEmpty
        ? (fallbackIdentifier?.trim().isNotEmpty == true
            ? fallbackIdentifier!.trim()
            : 'مستخدم')
        : username,
    role: role,
    businessName: customer?['business_name']?.toString(),
    customerId: customer?['id']?.toString(),
    fullName: customerContact.isNotEmpty
        ? customerContact
        : data['full_name']?.toString(),
    phone: customerPhone.isNotEmpty ? customerPhone : data['phone']?.toString(),
    city: customer?['city']?.toString(),
    area: customer?['area']?.toString(),
    address: customer?['address']?.toString(),
    discountPercent: _asDiscountPercent(customer?['discount_percent']),
    creditLimit: _asDouble(customer?['credit_limit']),
    outstandingBalance: _asDouble(customer?['outstanding_balance']),
    profileActive: true,
    mustChangePassword: mustChangePassword,
    accountStatus: customer?['account_status']?.toString(),
  );
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) return null;
  return {
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDiscountPercent(Object? value) {
  if (value == null) return 0;
  final parsed =
      value is num ? value.toDouble() : double.tryParse(value.toString());
  if (parsed == null || !parsed.isFinite || parsed < 0 || parsed >= 100) {
    throw const AccountBootstrapException(
      'بيانات خصم العميل غير صالحة. تواصل مع إدارة المتجر.',
    );
  }
  final normalized = (parsed * 100).round() / 100;
  if ((normalized - parsed).abs() > 0.000000001) {
    throw const AccountBootstrapException(
      'بيانات خصم العميل غير صالحة. تواصل مع إدارة المتجر.',
    );
  }
  return normalized;
}
