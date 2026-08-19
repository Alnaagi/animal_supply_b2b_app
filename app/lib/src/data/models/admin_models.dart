import '../../core/config/app_config.dart';
import '../../core/constants/order_status.dart';

class BusinessCustomer {
  const BusinessCustomer({
    required this.id,
    this.profileId,
    required this.businessName,
    required this.username,
    this.contactPerson = '',
    this.phone = '',
    this.phoneIsWhatsapp = true,
    this.city = '',
    this.area = '',
    this.address = '',
    this.discountPercent = 0,
    this.accountStatus = 'active',
    this.creditLimit = 0,
    this.outstandingBalance = 0,
    this.updatedAt,
    this.lastActiveAt,
  });

  final String id;
  final String? profileId;
  final String businessName;
  final String username;
  final String contactPerson;
  final String phone;
  final bool phoneIsWhatsapp;
  final String city;
  final String area;
  final String address;
  final double discountPercent;
  final String accountStatus;
  final double creditLimit;
  final double outstandingBalance;
  final DateTime? updatedAt;
  final DateTime? lastActiveAt;

  bool get active => accountStatus == 'active';

  BusinessCustomer copyWith({
    String? id,
    String? profileId,
    String? businessName,
    String? username,
    String? contactPerson,
    String? phone,
    bool? phoneIsWhatsapp,
    String? city,
    String? area,
    String? address,
    double? discountPercent,
    String? accountStatus,
    double? creditLimit,
    double? outstandingBalance,
    DateTime? updatedAt,
    DateTime? lastActiveAt,
  }) {
    return BusinessCustomer(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      businessName: businessName ?? this.businessName,
      username: username ?? this.username,
      contactPerson: contactPerson ?? this.contactPerson,
      phone: phone ?? this.phone,
      phoneIsWhatsapp: phoneIsWhatsapp ?? this.phoneIsWhatsapp,
      city: city ?? this.city,
      area: area ?? this.area,
      address: address ?? this.address,
      discountPercent: discountPercent ?? this.discountPercent,
      accountStatus: accountStatus ?? this.accountStatus,
      creditLimit: creditLimit ?? this.creditLimit,
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
      updatedAt: updatedAt ?? this.updatedAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }

  factory BusinessCustomer.fromSupabase(Map<String, dynamic> row) {
    final profile = row['profiles'];
    return BusinessCustomer(
      id: row['id'].toString(),
      profileId: row['profile_id']?.toString(),
      businessName: (row['business_name'] ?? '').toString(),
      username: profile is Map ? (profile['username'] ?? '').toString() : '',
      contactPerson: (row['contact_person'] ?? '').toString(),
      phone: (row['phone'] ?? '').toString(),
      phoneIsWhatsapp: row['phone_is_whatsapp'] is bool
          ? row['phone_is_whatsapp'] as bool
          : true,
      city: (row['city'] ?? '').toString(),
      area: (row['area'] ?? '').toString(),
      address: (row['address'] ?? '').toString(),
      discountPercent:
          validatedCustomerDiscountPercent(row['discount_percent'] ?? 0),
      accountStatus: (row['account_status'] ?? 'active').toString(),
      creditLimit: ((row['credit_limit'] ?? 0) as num).toDouble(),
      outstandingBalance: ((row['outstanding_balance'] ?? 0) as num).toDouble(),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
      lastActiveAt: _customerLastActiveAt(row),
    );
  }
}

DateTime? _customerLastActiveAt(Map<String, dynamic> row) {
  final profile = row['profiles'];
  final candidates = <Object?>[
    if (profile is Map) ...[
      profile['last_active_at'],
      profile['customer_last_active_at'],
      profile['last_seen_at'],
      profile['last_login_at'],
    ],
    row['last_active_at'],
    row['last_seen_at'],
  ];
  for (final value in candidates) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return null;
}

double validatedCustomerDiscountPercent(Object? value) {
  if (value is! num) {
    throw ArgumentError.value(
      value,
      'discountPercent',
      'Customer discount must be numeric.',
    );
  }
  final discount = value.toDouble();
  if (!discount.isFinite || discount < 0 || discount >= 100) {
    throw ArgumentError.value(
      value,
      'discountPercent',
      'Customer discount must be between 0 and 99.99 with at most two decimals.',
    );
  }
  final normalized = (discount * 100).round() / 100;
  if ((normalized - discount).abs() > 0.000000001) {
    throw ArgumentError.value(
      value,
      'discountPercent',
      'Customer discount must be between 0 and 99.99 with at most two decimals.',
    );
  }
  return normalized;
}

double _adminMoney(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
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

class AdminDashboardData {
  const AdminDashboardData({
    required this.stats,
    required this.pendingOrders,
    required this.lowStockProducts,
  });

  final AdminDashboardStats stats;
  final List<AdminDashboardOrderRow> pendingOrders;
  final List<AdminInventoryReportRow> lowStockProducts;

  factory AdminDashboardData.fromRpc(Map<String, dynamic> value) {
    final stats = _adminMap(value['stats']);
    return AdminDashboardData(
      stats: AdminDashboardStats(
        totalCustomers: _adminInt(stats['total_customers']),
        activeCustomers: _adminInt(stats['active_customers']),
        pendingOrders: _adminInt(stats['pending_orders']),
        todayOrders: _adminInt(stats['today_orders']),
        lowStockCount: _adminInt(stats['low_stock_count']),
        monthSales: _adminMoney(stats['month_sales']),
      ),
      pendingOrders: [
        for (final row in _adminRows(value['pending_orders']))
          AdminDashboardOrderRow.fromRpc(row),
      ],
      lowStockProducts: [
        for (final row in _adminRows(value['low_stock_products']))
          AdminInventoryReportRow.fromRpc(row),
      ],
    );
  }
}

class AdminDashboardOrderRow {
  const AdminDashboardOrderRow({
    required this.id,
    required this.orderNumber,
    required this.businessName,
    required this.itemCount,
    required this.total,
    required this.createdAt,
  });

  final String id;
  final String orderNumber;
  final String businessName;
  final int itemCount;
  final double total;
  final DateTime createdAt;

  String get displayNumber {
    if (orderNumber.trim().isNotEmpty) return orderNumber;
    return id.substring(0, id.length < 8 ? id.length : 8);
  }

  factory AdminDashboardOrderRow.fromRpc(Map<String, dynamic> row) {
    return AdminDashboardOrderRow(
      id: (row['id'] ?? '').toString(),
      orderNumber: (row['order_number'] ?? '').toString(),
      businessName: (row['business_name'] ?? '').toString(),
      itemCount: _adminInt(row['item_count']),
      total: _adminMoney(row['total']),
      createdAt:
          DateTime.tryParse((row['created_at'] ?? '').toString())?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class AdminReportData {
  const AdminReportData({
    required this.periodOrderCount,
    required this.deliveredOrderCount,
    required this.cancelledOrderCount,
    required this.salesTotal,
    required this.averageOrderValue,
    required this.outstandingBalance,
    required this.topCustomers,
    required this.topProducts,
    required this.lowStockProducts,
    required this.outstandingCustomers,
  });

  final int periodOrderCount;
  final int deliveredOrderCount;
  final int cancelledOrderCount;
  final double salesTotal;
  final double averageOrderValue;

  /// A manually maintained reference value, not an accounting-ledger total.
  final double outstandingBalance;

  final List<AdminCustomerReportRow> topCustomers;
  final List<AdminProductReportRow> topProducts;
  final List<AdminInventoryReportRow> lowStockProducts;
  final List<AdminBalanceReportRow> outstandingCustomers;

  factory AdminReportData.fromRpc(Map<String, dynamic> value) {
    return AdminReportData(
      periodOrderCount: _adminInt(value['period_order_count']),
      deliveredOrderCount: _adminInt(value['delivered_order_count']),
      cancelledOrderCount: _adminInt(value['cancelled_order_count']),
      salesTotal: _adminMoney(value['sales_total']),
      averageOrderValue: _adminMoney(value['average_order_value']),
      outstandingBalance: _adminMoney(value['outstanding_balance']),
      topCustomers: [
        for (final row in _adminRows(value['top_customers']))
          AdminCustomerReportRow.fromRpc(row),
      ],
      topProducts: [
        for (final row in _adminRows(value['top_products']))
          AdminProductReportRow.fromRpc(row),
      ],
      lowStockProducts: [
        for (final row in _adminRows(value['low_stock_products']))
          AdminInventoryReportRow.fromRpc(row),
      ],
      outstandingCustomers: [
        for (final row in _adminRows(value['outstanding_customers']))
          AdminBalanceReportRow.fromRpc(row),
      ],
    );
  }
}

class AdminCustomerReportRow {
  const AdminCustomerReportRow({
    required this.customerId,
    required this.businessName,
    required this.orderCount,
    required this.salesTotal,
  });

  final String customerId;
  final String businessName;
  final int orderCount;
  final double salesTotal;

  factory AdminCustomerReportRow.fromRpc(Map<String, dynamic> row) =>
      AdminCustomerReportRow(
        customerId: (row['customer_id'] ?? '').toString(),
        businessName: (row['business_name'] ?? '').toString(),
        orderCount: _adminInt(row['order_count']),
        salesTotal: _adminMoney(row['sales_total']),
      );
}

class AdminProductReportRow {
  const AdminProductReportRow({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.salesTotal,
  });

  final String productId;
  final String productName;
  final String sku;
  final int quantity;
  final double salesTotal;

  factory AdminProductReportRow.fromRpc(Map<String, dynamic> row) =>
      AdminProductReportRow(
        productId: (row['product_id'] ?? '').toString(),
        productName: (row['product_name'] ?? '').toString(),
        sku: (row['sku'] ?? '').toString(),
        quantity: _adminInt(row['quantity']),
        salesTotal: _adminMoney(row['sales_total']),
      );
}

class AdminInventoryReportRow {
  const AdminInventoryReportRow({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.availableQuantity,
  });

  final String productId;
  final String productName;
  final String sku;
  final int availableQuantity;

  factory AdminInventoryReportRow.fromRpc(Map<String, dynamic> row) =>
      AdminInventoryReportRow(
        productId: (row['product_id'] ?? '').toString(),
        productName: (row['product_name'] ?? '').toString(),
        sku: (row['sku'] ?? '').toString(),
        availableQuantity: _adminInt(row['available_quantity']),
      );
}

class AdminBalanceReportRow {
  const AdminBalanceReportRow({
    required this.customerId,
    required this.businessName,
    required this.outstandingBalance,
    required this.creditLimit,
  });

  final String customerId;
  final String businessName;
  final double outstandingBalance;
  final double creditLimit;

  factory AdminBalanceReportRow.fromRpc(Map<String, dynamic> row) =>
      AdminBalanceReportRow(
        customerId: (row['customer_id'] ?? '').toString(),
        businessName: (row['business_name'] ?? '').toString(),
        outstandingBalance: _adminMoney(row['outstanding_balance']),
        creditLimit: _adminMoney(row['credit_limit']),
      );
}

int _adminInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Map<String, dynamic> _adminMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _adminRows(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return [
    for (final row in value)
      if (row is Map) Map<String, dynamic>.from(row),
  ];
}

class AppSettingsData {
  const AppSettingsData({
    this.shopName = AppConfig.shopName,
    this.shopLogoUrl = '',
    this.supportWhatsapp = '',
    this.downloadLink = '',
    this.apkLink = '',
    this.deliveryPolicy = 'يتم الاتفاق بعد تأكيد الطلب',
    this.minimumOrderAmount = 0,
    this.deliveryFee = 0,
    this.handlingFee = 0,
    this.currency = 'LYD',
    this.maintenanceMode = false,
    this.updatedAt,
  });

  final String shopName;
  final String shopLogoUrl;
  final String supportWhatsapp;
  final String downloadLink;
  final String apkLink;
  final String deliveryPolicy;
  final double minimumOrderAmount;
  final double deliveryFee;
  final double handlingFee;
  final String currency;
  final bool maintenanceMode;
  final DateTime? updatedAt;

  Map<String, String> toKeyValues() => {
        'shop_name': shopName,
        'shop_logo_url': shopLogoUrl,
        'support_whatsapp': supportWhatsapp,
        'download_link': downloadLink,
        'apk_link': apkLink,
        'delivery_policy': deliveryPolicy,
        'minimum_order_amount': minimumOrderAmount.toStringAsFixed(2),
        'delivery_fee': deliveryFee.toStringAsFixed(2),
        'handling_fee': handlingFee.toStringAsFixed(2),
        'currency': currency,
        'maintenance_mode': maintenanceMode.toString(),
      };

  AppSettingsData copyWith({
    String? shopName,
    String? shopLogoUrl,
    String? supportWhatsapp,
    String? downloadLink,
    String? apkLink,
    String? deliveryPolicy,
    double? minimumOrderAmount,
    double? deliveryFee,
    double? handlingFee,
    String? currency,
    bool? maintenanceMode,
    DateTime? updatedAt,
  }) {
    return AppSettingsData(
      shopName: shopName ?? this.shopName,
      shopLogoUrl: shopLogoUrl ?? this.shopLogoUrl,
      supportWhatsapp: supportWhatsapp ?? this.supportWhatsapp,
      downloadLink: downloadLink ?? this.downloadLink,
      apkLink: apkLink ?? this.apkLink,
      deliveryPolicy: deliveryPolicy ?? this.deliveryPolicy,
      minimumOrderAmount: minimumOrderAmount ?? this.minimumOrderAmount,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      handlingFee: handlingFee ?? this.handlingFee,
      currency: currency ?? this.currency,
      maintenanceMode: maintenanceMode ?? this.maintenanceMode,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory AppSettingsData.fromKeyValues(
    Map<String, String> values, {
    DateTime? updatedAt,
  }) {
    final parsedName = (values['shop_name'] ?? '').trim();
    return AppSettingsData(
      shopName: parsedName.isEmpty ? AppConfig.shopName : parsedName,
      shopLogoUrl: (values['shop_logo_url'] ?? '').trim(),
      supportWhatsapp: values['support_whatsapp'] ?? '',
      downloadLink: values['download_link'] ?? '',
      apkLink: values['apk_link'] ?? '',
      deliveryPolicy:
          values['delivery_policy'] ?? 'يتم الاتفاق بعد تأكيد الطلب',
      minimumOrderAmount:
          double.tryParse(values['minimum_order_amount'] ?? '') ?? 0,
      deliveryFee: double.tryParse(values['delivery_fee'] ?? '') ?? 0,
      handlingFee: double.tryParse(values['handling_fee'] ?? '') ?? 0,
      currency: values['currency'] ?? 'LYD',
      maintenanceMode: values['maintenance_mode'] == 'true',
      updatedAt: updatedAt,
    );
  }
}

class AppBanner {
  static const supportedTargetTypes = <String>{
    'catalog',
    'category',
    'product',
  };

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
    this.updatedAt,
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
  final DateTime? updatedAt;

  AppBanner copyWith({
    String? id,
    String? title,
    String? body,
    String? ctaText,
    String? imageUrl,
    String? targetType,
    String? targetValue,
    int? sortOrder,
    bool? active,
    DateTime? updatedAt,
  }) {
    return AppBanner(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      ctaText: ctaText ?? this.ctaText,
      imageUrl: imageUrl ?? this.imageUrl,
      targetType: targetType ?? this.targetType,
      targetValue: targetValue ?? this.targetValue,
      sortOrder: sortOrder ?? this.sortOrder,
      active: active ?? this.active,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toSupabasePayload() => {
        'title': title,
        'body': body.isEmpty ? null : body,
        'cta_text': ctaText,
        'image_url': imageUrl,
        'image_path': null,
        'target_type': targetType,
        'target_value': targetValue.isEmpty ? null : targetValue,
        'sort_order': sortOrder,
        'active': active,
      };

  factory AppBanner.fromSupabase(Map<String, dynamic> row) => AppBanner(
        id: row['id'].toString(),
        title: (row['title'] ?? '').toString(),
        body: (row['body'] ?? '').toString(),
        ctaText: (row['cta_text'] ?? 'عرض').toString(),
        imageUrl: (row['image_url'] ?? row['image_path'] ?? '').toString(),
        targetType: (row['target_type'] ?? 'catalog').toString(),
        targetValue: (row['target_value'] ?? '').toString(),
        sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
        active: row['active'] != false,
        updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
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
    this.minimumSupportedCode = 1,
    this.sha256 = '',
    this.fileSizeBytes,
  });

  final String platform;
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final bool required;
  final String releaseNotes;
  final int minimumSupportedCode;
  final String sha256;
  final int? fileSizeBytes;

  bool hasUpdateFor(int installedCode) => versionCode > installedCode;

  bool requiresUpdateFor(int installedCode) =>
      required || installedCode < minimumSupportedCode;
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
