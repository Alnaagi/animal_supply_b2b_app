import '../../core/constants/order_status.dart';

class BusinessCustomer {
  const BusinessCustomer({
    required this.id,
    this.profileId,
    required this.businessName,
    required this.username,
    this.contactPerson = '',
    this.phone = '',
    this.city = '',
    this.area = '',
    this.address = '',
    this.priceGroup = 'جملة',
    this.accountStatus = 'active',
    this.creditLimit = 0,
    this.outstandingBalance = 0,
  });

  final String id;
  final String? profileId;
  final String businessName;
  final String username;
  final String contactPerson;
  final String phone;
  final String city;
  final String area;
  final String address;
  final String priceGroup;
  final String accountStatus;
  final double creditLimit;
  final double outstandingBalance;

  bool get active => accountStatus == 'active';

  BusinessCustomer copyWith({
    String? id,
    String? profileId,
    String? businessName,
    String? username,
    String? contactPerson,
    String? phone,
    String? city,
    String? area,
    String? address,
    String? priceGroup,
    String? accountStatus,
    double? creditLimit,
    double? outstandingBalance,
  }) {
    return BusinessCustomer(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      businessName: businessName ?? this.businessName,
      username: username ?? this.username,
      contactPerson: contactPerson ?? this.contactPerson,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      area: area ?? this.area,
      address: address ?? this.address,
      priceGroup: priceGroup ?? this.priceGroup,
      accountStatus: accountStatus ?? this.accountStatus,
      creditLimit: creditLimit ?? this.creditLimit,
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
    );
  }

  factory BusinessCustomer.fromSupabase(Map<String, dynamic> row) {
    final profile = row['profiles'];
    final priceGroup = row['price_groups'];
    return BusinessCustomer(
      id: row['id'].toString(),
      profileId: row['profile_id']?.toString(),
      businessName: (row['business_name'] ?? '').toString(),
      username: profile is Map ? (profile['username'] ?? '').toString() : '',
      contactPerson: (row['contact_person'] ?? '').toString(),
      phone: (row['phone'] ?? '').toString(),
      city: (row['city'] ?? '').toString(),
      area: (row['area'] ?? '').toString(),
      address: (row['address'] ?? '').toString(),
      priceGroup: priceGroup is Map
          ? (priceGroup['name'] ?? 'جملة').toString()
          : 'جملة',
      accountStatus: (row['account_status'] ?? 'active').toString(),
      creditLimit: ((row['credit_limit'] ?? 0) as num).toDouble(),
      outstandingBalance: ((row['outstanding_balance'] ?? 0) as num).toDouble(),
    );
  }
}

class AdminDashboardStats {
  const AdminDashboardStats({
    required this.totalCustomers,
    required this.activeCustomers,
    required this.pendingOrders,
    required this.todayOrders,
    required this.lowStockCount,
    required this.monthSales,
  });

  final int totalCustomers;
  final int activeCustomers;
  final int pendingOrders;
  final int todayOrders;
  final int lowStockCount;
  final double monthSales;
}

class AppSettingsData {
  const AppSettingsData({
    this.shopName = 'متجر أعلاف ومستلزمات الحيوانات',
    this.supportWhatsapp = '+218910000000',
    this.downloadLink = 'https://example.com/animal-supply.apk',
    this.apkLink = 'https://example.com/downloads/animal-supply-b2b.apk',
    this.deliveryPolicy = 'يتم الاتفاق بعد تأكيد الطلب',
    this.minimumOrderAmount = 0,
    this.currency = 'LYD',
    this.maintenanceMode = false,
  });

  final String shopName;
  final String supportWhatsapp;
  final String downloadLink;
  final String apkLink;
  final String deliveryPolicy;
  final double minimumOrderAmount;
  final String currency;
  final bool maintenanceMode;

  Map<String, String> toKeyValues() => {
        'shop_name': shopName,
        'support_whatsapp': supportWhatsapp,
        'download_link': downloadLink,
        'apk_link': apkLink,
        'delivery_policy': deliveryPolicy,
        'minimum_order_amount': minimumOrderAmount.toStringAsFixed(2),
        'currency': currency,
        'maintenance_mode': maintenanceMode.toString(),
      };

  factory AppSettingsData.fromKeyValues(Map<String, String> values) {
    return AppSettingsData(
      shopName: values['shop_name'] ?? 'متجر أعلاف ومستلزمات الحيوانات',
      supportWhatsapp: values['support_whatsapp'] ?? '+218910000000',
      downloadLink:
          values['download_link'] ?? 'https://example.com/animal-supply.apk',
      apkLink: values['apk_link'] ??
          'https://example.com/downloads/animal-supply-b2b.apk',
      deliveryPolicy:
          values['delivery_policy'] ?? 'يتم الاتفاق بعد تأكيد الطلب',
      minimumOrderAmount:
          double.tryParse(values['minimum_order_amount'] ?? '') ?? 0,
      currency: values['currency'] ?? 'LYD',
      maintenanceMode: values['maintenance_mode'] == 'true',
    );
  }
}

class AppBanner {
  const AppBanner({
    required this.id,
    required this.title,
    this.body = '',
    this.ctaText = 'عرض',
    required this.imageUrl,
    this.targetType = 'catalog',
    this.targetValue = '',
    this.sortOrder = 0,
    this.active = true,
  });

  final String id;
  final String title;
  final String body;
  final String ctaText;
  final String imageUrl;
  final String targetType;
  final String targetValue;
  final int sortOrder;
  final bool active;

  factory AppBanner.fromSupabase(Map<String, dynamic> row) => AppBanner(
        id: row['id'].toString(),
        title: (row['title'] ?? '').toString(),
        body: (row['body'] ?? '').toString(),
        ctaText: (row['cta_text'] ?? 'عرض').toString(),
        imageUrl: (row['image_url'] ?? row['image_path'] ?? '').toString(),
        targetType: (row['target_type'] ?? 'catalog').toString(),
        targetValue: (row['target_value'] ?? '').toString(),
        sortOrder: (row['sort_order'] ?? 0) as int,
        active: row['active'] != false,
      );
}

class AppVersionInfo {
  const AppVersionInfo({
    this.platform = 'android',
    this.versionName = '1.0.0',
    this.versionCode = 1,
    this.apkUrl = '',
    this.required = false,
    this.releaseNotes = '',
  });

  final String platform;
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final bool required;
  final String releaseNotes;
}

class AdminNotification {
  const AdminNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.orderId,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final String? orderId;
  final bool read;
}

class OrderStatusUpdate {
  const OrderStatusUpdate({required this.status, this.adminNote = ''});
  final OrderStatus status;
  final String adminNote;
}
