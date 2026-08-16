import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/concurrency/stale_write.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/order_status.dart';
import '../../core/localization/arabic_copy.dart';
import '../../core/support/customer_invite_copy.dart';
import '../../core/updates/download_page_links.dart';
import '../../core/updates/update_link.dart';
import '../../core/security/destructive_confirm_phrase.dart';
import '../models/admin_models.dart';
import '../models/application_data_reset.dart';
import '../models/database_usage.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../remote/supabase_clients.dart';

final adminRepositoryProvider =
    Provider<AdminRepository>((ref) => AdminRepository());

final appSettingsProvider = FutureProvider<AppSettingsData>(
  (ref) => ref.watch(adminRepositoryProvider).settings(),
);

typedef AdminEdgeFunctionInvoker = Future<Object?> Function(
  String functionName,
  Map<String, dynamic> body,
);

const adminCustomersDefaultPageSize = 50;
const adminCustomersMaximumPageSize = 100;
const _customerSelect = '*, profiles(username)';
const _supportedCustomerStatuses = <String>{
  'active',
  'suspended',
  'archived',
};

class AdminRemoteException implements Exception {
  const AdminRemoteException({
    required this.code,
    required this.message,
    this.status,
  });

  final String code;
  final String message;
  final int? status;

  @override
  String toString() {
    if (message.trim().isNotEmpty) return message.trim();
    if (code.trim().isNotEmpty) return code.trim();
    return 'AdminRemoteException';
  }
}

class AdminRemoteErrorInfo {
  const AdminRemoteErrorInfo({
    this.code = '',
    this.message = '',
    this.status,
  });

  final String code;
  final String message;
  final int? status;

  AdminRemoteException asException() {
    final resolvedCode =
        code.trim().isEmpty ? 'CUSTOMER_UPDATE_FAILED' : code.trim();
    final resolvedMessage =
        resolvedCode == 'STALE_WRITE' ||
                resolvedCode == 'CUSTOMER_UPDATE_CONFLICT' ||
                resolvedCode == 'RESET_IN_PROGRESS'
            ? mutationFailureMessageAr(
                AdminRemoteException(
                  code: resolvedCode,
                  message: '',
                  status: status,
                ),
                fallback: ArabicCopy.staleWrite,
              )
            : message.trim();
    return AdminRemoteException(
      code: resolvedCode,
      message: resolvedMessage,
      status: status,
    );
  }
}

class AdminCustomerPage {
  AdminCustomerPage({
    required List<BusinessCustomer> customers,
    required this.offset,
    required this.limit,
    required this.hasMore,
  }) : customers = List<BusinessCustomer>.unmodifiable(customers);

  final List<BusinessCustomer> customers;
  final int offset;
  final int limit;
  final bool hasMore;

  int get nextOffset => offset + customers.length;
}

class InviteResult {
  const InviteResult({
    required this.username,
    required this.temporaryPassword,
    required this.inviteLink,
    required this.whatsappMessage,
    required this.customerPhone,
    this.customerId = '',
    this.profileId,
    this.businessName = '',
    this.contactName = '',
  });

  final String username;
  final String temporaryPassword;
  final String inviteLink;
  final String whatsappMessage;
  final String customerPhone;
  final String customerId;
  final String? profileId;
  final String businessName;
  final String contactName;

  InviteResult copyWith({
    String? username,
    String? temporaryPassword,
    String? inviteLink,
    String? whatsappMessage,
    String? customerPhone,
    String? customerId,
    String? profileId,
    String? businessName,
    String? contactName,
  }) {
    return InviteResult(
      username: username ?? this.username,
      temporaryPassword: temporaryPassword ?? this.temporaryPassword,
      inviteLink: inviteLink ?? this.inviteLink,
      whatsappMessage: whatsappMessage ?? this.whatsappMessage,
      customerPhone: customerPhone ?? this.customerPhone,
      customerId: customerId ?? this.customerId,
      profileId: profileId ?? this.profileId,
      businessName: businessName ?? this.businessName,
      contactName: contactName ?? this.contactName,
    );
  }

  factory InviteResult.fromFunctionResponse(
    Object? responseData, {
    required String fallbackUsername,
    required String customerPhone,
  }) {
    final root = _stringKeyedMap(responseData);
    final nested = _stringKeyedMap(root['data']);
    final payload = <String, dynamic>{...root, ...nested};
    final username = _firstNonEmpty(payload, const [
      'username',
      'login_identifier',
    ]);
    final temporaryPassword = _requiredInviteValue(
      payload,
      const ['temporary_password', 'temporaryPassword'],
      'temporary password',
    );
    final inviteLink = _requiredSecureInviteLink(
      payload,
      const ['invite_link', 'inviteLink'],
    );
    final whatsappMessage = _requiredInviteValue(
      payload,
      const ['whatsapp_message', 'whatsappMessage'],
      'WhatsApp message',
    );

    final customerPayload = _stringKeyedMap(payload['customer']);
    final customerId = _firstNonEmpty(customerPayload, const ['id']);
    final profileId = _firstNonEmpty(customerPayload, const ['profile_id']);
    final businessName = _firstNonEmpty(customerPayload, const [
      'business_name',
      'businessName',
    ]);
    final contactName = _firstNonEmpty(customerPayload, const [
      'contact_person',
      'contactPerson',
    ]);

    return InviteResult(
      username: username.isEmpty ? fallbackUsername : username,
      temporaryPassword: temporaryPassword,
      inviteLink: inviteLink,
      whatsappMessage: whatsappMessage,
      customerPhone: customerPhone,
      customerId: customerId,
      profileId: profileId.isEmpty ? null : profileId,
      businessName: businessName,
      contactName: contactName,
    );
  }
}

Map<String, dynamic> _stringKeyedMap(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

String _firstNonEmpty(
  Map<String, dynamic> payload,
  List<String> keys,
) {
  for (final key in keys) {
    final value = payload[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && value != 'null') return value;
  }
  return '';
}

String _requiredInviteValue(
  Map<String, dynamic> payload,
  List<String> keys,
  String label,
) {
  final value = _firstNonEmpty(payload, keys);
  if (value.isEmpty) {
    throw StateError('Secure invite response is missing $label.');
  }
  return value;
}

String _requiredSecureInviteLink(
  Map<String, dynamic> payload,
  List<String> keys,
) {
  final value = _requiredInviteValue(payload, keys, 'one-time invite link');
  final uri = Uri.tryParse(value);
  final token = uri?.queryParameters['token']?.trim() ?? '';
  final forbiddenParameters = uri?.queryParameters.keys.any(
        (key) => const {
          'password',
          'temporary_password',
          'temporarypassword',
        }.contains(key.toLowerCase()),
      ) ??
      false;
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      token.isEmpty ||
      token == 'null' ||
      forbiddenParameters) {
    throw StateError('Secure invite response contains an invalid invite link.');
  }
  return value;
}

String _validatedCustomerQuery(String rawQuery) {
  final query = rawQuery.trim();
  if (query.length > 120 || RegExp(r'[\u0000-\u001f\u007f]').hasMatch(query)) {
    throw ArgumentError.value(
      rawQuery,
      'query',
      'Customer search must be at most 120 printable characters.',
    );
  }
  return query;
}

String? _validatedCustomerStatus(String? rawStatus) {
  final status = rawStatus?.trim();
  if (status == null || status.isEmpty) return null;
  if (!_supportedCustomerStatuses.contains(status)) {
    throw ArgumentError.value(
      rawStatus,
      'status',
      'Unsupported customer account status.',
    );
  }
  return status;
}

double _accountAmount(double value) => (value * 100).round() / 100;

AdminRemoteErrorInfo _errorInfoFromEnvelope(
  Object? raw, {
  required int? status,
}) {
  Object? current = raw;
  if (current is String && current.trim().isNotEmpty) {
    try {
      current = jsonDecode(current);
    } catch (_) {}
  }
  if (current is AdminRemoteException) {
    return AdminRemoteErrorInfo(
      code: current.code,
      message: current.message,
      status: current.status ?? status,
    );
  }
  final root = _stringKeyedMap(current);
  final nested = _stringKeyedMap(root['error']);
  final code = (nested['code'] ?? root['code'] ?? '').toString().trim();
  final message =
      (nested['message'] ?? root['message'] ?? '').toString().trim();
  if (code.isNotEmpty || message.isNotEmpty || root.isNotEmpty) {
    return AdminRemoteErrorInfo(
      code: code,
      message: message,
      status: status,
    );
  }
  final fallback = raw?.toString().trim() ?? '';
  return AdminRemoteErrorInfo(message: fallback, status: status);
}

void _validateCustomerPageArguments({
  required int offset,
  required int limit,
}) {
  if (offset < 0) {
    throw ArgumentError.value(offset, 'offset', 'Offset must not be negative.');
  }
  if (limit < 1 || limit > adminCustomersMaximumPageSize) {
    throw ArgumentError.value(
      limit,
      'limit',
      'Page size must be between 1 and $adminCustomersMaximumPageSize.',
    );
  }
}

bool _matchesCustomerQuery(BusinessCustomer customer, String query) {
  if (query.isEmpty) return true;
  final needle = query.toLowerCase();
  return [
    customer.businessName,
    customer.username,
    customer.contactPerson,
    customer.phone,
    customer.city,
    customer.area,
  ].any((value) => value.toLowerCase().contains(needle));
}

List<BusinessCustomer> _filterCustomers(
  Iterable<BusinessCustomer> customers, {
  required String query,
  String? status,
}) {
  return customers
      .where(
        (customer) =>
            (status == null || customer.accountStatus == status) &&
            _matchesCustomerQuery(customer, query),
      )
      .toList(growable: false);
}

AdminCustomerPage _customerPageFromWindow(
  List<BusinessCustomer> window, {
  required int offset,
  required int limit,
}) {
  if (window.length > limit + 1) {
    throw StateError('Customer page response exceeded the requested range.');
  }
  final hasMore = window.length > limit;
  return AdminCustomerPage(
    customers: window.take(limit).toList(growable: false),
    offset: offset,
    limit: limit,
    hasMore: hasMore,
  );
}

AdminCustomerPage _pageCustomers(
  List<BusinessCustomer> customers, {
  required int offset,
  required int limit,
}) {
  final window = customers.skip(offset).take(limit + 1).toList(growable: false);
  return _customerPageFromWindow(window, offset: offset, limit: limit);
}

AdminReportData buildAdminReportData({
  required List<Product> products,
  required List<Order> orders,
  required List<BusinessCustomer> customers,
  DateTime? from,
  DateTime? to,
}) {
  final periodOrders = orders.where((order) {
    if (from != null && order.createdAt.isBefore(from)) return false;
    if (to != null && order.createdAt.isAfter(to)) return false;
    return true;
  }).toList(growable: false);
  final deliveredOrders = periodOrders
      .where((order) => order.status == OrderStatus.delivered)
      .toList(growable: false);
  final customersById = {
    for (final customer in customers) customer.id: customer,
  };

  final customerRows = <String, AdminCustomerReportRow>{};
  final productRows = <String, AdminProductReportRow>{};
  for (final order in deliveredOrders) {
    final customerId =
        order.customerId.trim().isEmpty ? 'unknown' : order.customerId;
    final customerName = order.businessName.trim().isNotEmpty
        ? order.businessName.trim()
        : customersById[customerId]?.businessName.trim().isNotEmpty == true
            ? customersById[customerId]!.businessName.trim()
            : 'عميل غير معروف';
    final previousCustomer = customerRows[customerId];
    customerRows[customerId] = AdminCustomerReportRow(
      customerId: customerId,
      businessName: customerName,
      orderCount: (previousCustomer?.orderCount ?? 0) + 1,
      salesTotal: (previousCustomer?.salesTotal ?? 0) + order.total,
    );

    for (final item in order.items) {
      final productId = item.productId.trim().isEmpty
          ? 'sku:${item.productSku}'
          : item.productId;
      final previousProduct = productRows[productId];
      productRows[productId] = AdminProductReportRow(
        productId: productId,
        productName: item.productName,
        sku: item.productSku,
        quantity: (previousProduct?.quantity ?? 0) + item.quantity,
        salesTotal: (previousProduct?.salesTotal ?? 0) + item.lineTotal,
      );
    }
  }

  final topCustomers = customerRows.values.toList()
    ..sort((a, b) {
      final bySales = b.salesTotal.compareTo(a.salesTotal);
      return bySales != 0 ? bySales : a.businessName.compareTo(b.businessName);
    });
  final topProducts = productRows.values.toList()
    ..sort((a, b) {
      final byQuantity = b.quantity.compareTo(a.quantity);
      return byQuantity != 0
          ? byQuantity
          : b.salesTotal.compareTo(a.salesTotal);
    });
  final lowStockProducts = products
      .where(
        (product) =>
            product.stockTrackingEnabled &&
            (!product.isOrderable || product.lowStock),
      )
      .map(
        (product) => AdminInventoryReportRow(
          productId: product.id,
          productName: product.name,
          sku: product.sku,
          availableQuantity: product.orderableStockQuantity,
        ),
      )
      .toList()
    ..sort(
      (a, b) => a.availableQuantity.compareTo(b.availableQuantity),
    );
  final outstandingCustomers = customers
      .where((customer) => customer.outstandingBalance > 0)
      .map(
        (customer) => AdminBalanceReportRow(
          customerId: customer.id,
          businessName: customer.businessName,
          outstandingBalance: customer.outstandingBalance,
          creditLimit: customer.creditLimit,
        ),
      )
      .toList()
    ..sort(
      (a, b) => b.outstandingBalance.compareTo(a.outstandingBalance),
    );
  final salesTotal = deliveredOrders.fold<double>(
    0,
    (sum, order) => sum + order.total,
  );

  return AdminReportData(
    periodOrderCount: periodOrders.length,
    deliveredOrderCount: deliveredOrders.length,
    cancelledOrderCount: periodOrders
        .where((order) => order.status == OrderStatus.cancelled)
        .length,
    salesTotal: salesTotal,
    averageOrderValue:
        deliveredOrders.isEmpty ? 0 : salesTotal / deliveredOrders.length,
    outstandingBalance: outstandingCustomers.fold<double>(
      0,
      (sum, customer) => sum + customer.outstandingBalance,
    ),
    topCustomers: List.unmodifiable(topCustomers),
    topProducts: List.unmodifiable(topProducts),
    lowStockProducts: List.unmodifiable(lowStockProducts),
    outstandingCustomers: List.unmodifiable(outstandingCustomers),
  );
}

Uri? _safeBannerHttpsUri(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

AppBanner _validatedBanner(AppBanner banner) {
  final title = banner.title.trim();
  final body = banner.body.trim();
  final ctaText = banner.ctaText.trim();
  final imageUrl = banner.imageUrl.trim();
  final targetType = banner.targetType.trim().toLowerCase();
  var targetValue = banner.targetValue.trim();

  if (title.isEmpty || title.length > 120) {
    throw ArgumentError.value(
      banner.title,
      'title',
      'Banner title must contain 1 to 120 characters.',
    );
  }
  if (body.length > 500) {
    throw ArgumentError.value(
      banner.body,
      'body',
      'Banner body must not exceed 500 characters.',
    );
  }
  if (ctaText.isEmpty || ctaText.length > 40) {
    throw ArgumentError.value(
      banner.ctaText,
      'ctaText',
      'Banner CTA must contain 1 to 40 characters.',
    );
  }
  if (_safeBannerHttpsUri(imageUrl) == null) {
    throw ArgumentError.value(
      banner.imageUrl,
      'imageUrl',
      'Banner image must use a safe HTTPS URL.',
    );
  }
  if (!AppBanner.supportedTargetTypes.contains(targetType)) {
    throw ArgumentError.value(
      banner.targetType,
      'targetType',
      'Unsupported banner target type.',
    );
  }
  if (banner.sortOrder < 0 || banner.sortOrder > 100000) {
    throw ArgumentError.value(
      banner.sortOrder,
      'sortOrder',
      'Banner order must be between 0 and 100000.',
    );
  }

  switch (targetType) {
    case 'catalog':
      targetValue = '';
    case 'category':
      if (targetValue.isEmpty || targetValue.length > 120) {
        throw ArgumentError.value(
          banner.targetValue,
          'targetValue',
          'Category targets require 1 to 120 characters.',
        );
      }
    case 'product':
      if (!RegExp(r'^[A-Za-z0-9_-]{1,120}$').hasMatch(targetValue)) {
        throw ArgumentError.value(
          banner.targetValue,
          'targetValue',
          'Product targets require a safe product identifier.',
        );
      }
  }

  return banner.copyWith(
    title: title,
    body: body,
    ctaText: ctaText,
    imageUrl: imageUrl,
    targetType: targetType,
    targetValue: targetValue,
  );
}

class AdminRepository {
  AdminRepository({
    Iterable<BusinessCustomer>? demoCustomers,
    AdminEdgeFunctionInvoker? edgeFunctionInvoker,
  }) : _edgeFunctionInvoker = edgeFunctionInvoker {
    if (demoCustomers != null) {
      _customers
        ..clear()
        ..addAll(demoCustomers);
    }
  }

  final AdminEdgeFunctionInvoker? _edgeFunctionInvoker;

  final List<BusinessCustomer> _customers = [
    const BusinessCustomer(
      id: 'customer-1',
      profileId: 'customer-user-1',
      businessName: 'شركة طرابلس للحيوانات الأليفة',
      username: 'tripoli-pets',
      contactPerson: 'محمد السنوسي',
      phone: '+218910000001',
      city: 'طرابلس',
      area: 'حي الأندلس',
      address: 'شارع تجاري قريب من الطريق الرئيسي',
      discountPercent: 12.5,
      creditLimit: 2500,
      outstandingBalance: 420,
    ),
    const BusinessCustomer(
      id: 'customer-2',
      businessName: 'شركة بنغازي للتوريدات',
      username: 'benghazi-supplies',
      contactPerson: 'أحمد البرعصي',
      phone: '+218920000002',
      city: 'بنغازي',
      area: 'الهواري',
    ),
    const BusinessCustomer(
      id: 'customer-3',
      businessName: 'مزرعة الواحة',
      username: 'alwaha-farm',
      contactPerson: 'سالم علي',
      phone: '+218930000003',
      city: 'مصراتة',
      area: 'الدافنية',
      discountPercent: 5,
      accountStatus: 'suspended',
    ),
  ];

  AppSettingsData _settings = const AppSettingsData(
    shopName: AppConfig.shopName,
    supportWhatsapp: AppConfig.supportWhatsapp,
    downloadLink: AppConfig.downloadLink,
    apkLink: AppConfig.apkLink,
  );

  final List<AppBanner> _banners = [
    const AppBanner(
      id: 'banner-1',
      title: 'عروض خاصة لتجار مستلزمات الحيوانات',
      body: 'اطلب الأعلاف والمستلزمات بالجملة بسهولة',
      ctaText: 'تسوق الآن',
      imageUrl:
          'https://images.unsplash.com/photo-1714068691210-073dc52c6c1d?auto=format&fit=crop&w=1600&h=620&q=80',
      targetType: 'category',
      targetValue: 'كلاب',
      sortOrder: 1,
    ),
  ];

  final List<AdminNotification> _notifications = const [
    AdminNotification(
      id: 'notif-1',
      title: 'طلب جديد',
      body: 'شركة طرابلس للحيوانات الأليفة أرسل طلباً جديداً',
      type: 'new_order',
      orderId: 'o1001',
    ),
  ];

  bool get hasRemoteBackend => supabaseClient != null;

  Future<AdminDashboardStats> dashboardStats(
      List<Product> products, List<Order> orders) async {
    final customers = await listCustomers();
    final now = DateTime.now();
    return AdminDashboardStats(
      totalCustomers: customers.length,
      activeCustomers: customers.where((customer) => customer.active).length,
      pendingOrders:
          orders.where((order) => order.status == OrderStatus.pending).length,
      todayOrders: orders
          .where((order) =>
              order.createdAt.year == now.year &&
              order.createdAt.month == now.month &&
              order.createdAt.day == now.day)
          .length,
      lowStockCount: products.where((product) => product.lowStock).length,
      monthSales: orders
          .where((order) =>
              order.createdAt.year == now.year &&
              order.createdAt.month == now.month &&
              order.status == OrderStatus.delivered)
          .fold(0, (sum, order) => sum + order.total),
    );
  }

  Future<AdminDashboardData> dashboardData({
    List<Product> products = const <Product>[],
    List<Order> orders = const <Order>[],
  }) async {
    final client = supabaseClient;
    if (client != null) {
      final response = await client.rpc('admin_dashboard_snapshot');
      if (response is! Map) {
        throw StateError('Invalid admin_dashboard_snapshot response.');
      }
      return AdminDashboardData.fromRpc(
        Map<String, dynamic>.from(response),
      );
    }

    final stats = await dashboardStats(products, orders);
    final pending = orders
        .where((order) => order.status == OrderStatus.pending)
        .take(5)
        .map(
          (order) => AdminDashboardOrderRow(
            id: order.id,
            orderNumber: order.orderNumber,
            businessName: order.businessName,
            itemCount: order.items.length,
            total: order.total,
            createdAt: order.createdAt,
          ),
        )
        .toList(growable: false);
    final lowStock = products
        .where((product) => product.lowStock)
        .take(5)
        .map(
          (product) => AdminInventoryReportRow(
            productId: product.id,
            productName: product.name,
            sku: product.sku,
            availableQuantity: product.orderableStockQuantity,
          ),
        )
        .toList(growable: false);
    return AdminDashboardData(
      stats: stats,
      pendingOrders: pending,
      lowStockProducts: lowStock,
    );
  }

  Future<DatabaseUsageSnapshot> remoteDatabaseUsage() async {
    final responseData = await _invokeDatabaseUsage();
    return DatabaseUsageSnapshot.fromFunctionResponse(responseData);
  }

  Future<ApplicationDataResetResult> resetProductionApplicationData() async {
    final responseData = await _invokeApplicationDataReset();
    return ApplicationDataResetResult.fromFunctionResponse(responseData);
  }

  Future<Object?> _invokeDatabaseUsage() async {
    const body = <String, dynamic>{};
    if (_edgeFunctionInvoker != null) {
      return _edgeFunctionInvoker('admin-database-usage', body);
    }
    final client = supabaseClient;
    if (client == null) {
      throw StateError('A remote backend is required for database usage.');
    }
    return (await client.functions.invoke(
      'admin-database-usage',
      body: body,
    ))
        .data;
  }

  Future<Object?> _invokeApplicationDataReset() async {
    final body = <String, dynamic>{
      'confirm_phrase': DestructiveConfirmPhrase.requiredPhrase,
    };
    if (_edgeFunctionInvoker != null) {
      return _edgeFunctionInvoker('admin-reset-application-data', body);
    }
    final client = supabaseClient;
    if (client == null) {
      throw StateError(
        'A remote backend is required to reset production data.',
      );
    }
    return (await client.functions.invoke(
      'admin-reset-application-data',
      body: body,
    ))
        .data;
  }

  Future<AdminReportData> reports(
    List<Product> products,
    List<Order> orders, {
    DateTime? from,
    DateTime? to,
  }) async {
    final client = supabaseClient;
    if (client != null) {
      final response = await client.rpc(
        'admin_operational_report',
        params: {
          'p_from': from?.toUtc().toIso8601String(),
          'p_to': to?.toUtc().toIso8601String(),
        },
      );
      if (response is! Map) {
        throw StateError('Invalid admin_operational_report response.');
      }
      return AdminReportData.fromRpc(Map<String, dynamic>.from(response));
    }
    final customers = await listCustomers();
    return buildAdminReportData(
      products: products,
      orders: orders,
      customers: customers,
      from: from,
      to: to,
    );
  }

  static bool canUseServerSideCustomerSearch(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return true;
    if (query.length > 120) return false;
    return RegExp(
      r'^[A-Za-z0-9\u0600-\u06ff +\-]+$',
      unicode: true,
    ).hasMatch(query);
  }

  static String customerSearchFilterForServer(String rawQuery) {
    final query = _validatedCustomerQuery(rawQuery);
    if (query.isEmpty || !canUseServerSideCustomerSearch(query)) {
      throw ArgumentError.value(
        rawQuery,
        'query',
        'Customer search cannot be safely encoded for PostgREST.',
      );
    }
    final pattern = '*$query*';
    return [
      'business_name.ilike.$pattern',
      'contact_person.ilike.$pattern',
      'phone.ilike.$pattern',
      'city.ilike.$pattern',
      'area.ilike.$pattern',
    ].join(',');
  }

  static List<BusinessCustomer> _customersFromResponse(Object? responseData) {
    if (responseData is! List) {
      throw StateError('Invalid business_customers response.');
    }
    final customers = <BusinessCustomer>[];
    final customerIds = <String>{};
    for (final rawRow in responseData) {
      if (rawRow is! Map) {
        throw StateError('Invalid business_customers row.');
      }
      final row = _stringKeyedMap(rawRow);
      final id = row['id'];
      final businessName = row['business_name'];
      final accountStatus = row['account_status'];
      final creditLimit = row['credit_limit'];
      final outstandingBalance = row['outstanding_balance'];
      final discountPercent = row['discount_percent'];
      if (id is! String ||
          id.trim().isEmpty ||
          businessName is! String ||
          businessName.trim().isEmpty ||
          accountStatus is! String ||
          !_supportedCustomerStatuses.contains(accountStatus) ||
          (creditLimit != null && creditLimit is! num) ||
          (outstandingBalance != null && outstandingBalance is! num) ||
          (discountPercent != null && discountPercent is! num) ||
          (row['profiles'] != null && row['profiles'] is! Map)) {
        throw StateError('Malformed business_customers row.');
      }
      if (!customerIds.add(id)) {
        throw StateError('Duplicate customer in business_customers response.');
      }
      try {
        customers.add(BusinessCustomer.fromSupabase(row));
      } catch (_) {
        throw StateError('Malformed business_customers row.');
      }
    }
    return List<BusinessCustomer>.unmodifiable(customers);
  }

  static AdminCustomerPage customerPageFromResponse(
    Object? responseData, {
    required int offset,
    required int limit,
  }) {
    _validateCustomerPageArguments(offset: offset, limit: limit);
    final customers = _customersFromResponse(responseData);
    return _customerPageFromWindow(
      customers,
      offset: offset,
      limit: limit,
    );
  }

  Future<List<BusinessCustomer>> listCustomers({
    String query = '',
    String? status,
  }) async {
    final normalizedQuery = _validatedCustomerQuery(query);
    final normalizedStatus = _validatedCustomerStatus(status);
    final client = supabaseClient;
    if (client != null) {
      var request = client.from('business_customers').select(_customerSelect);
      if (normalizedStatus != null) {
        request = request.eq('account_status', normalizedStatus);
      }
      final rows = await request
          .order('created_at', ascending: false)
          .order('id', ascending: false);
      return _filterCustomers(
        _customersFromResponse(rows),
        query: normalizedQuery,
      );
    }
    return _filterCustomers(
      _customers,
      query: normalizedQuery,
      status: normalizedStatus,
    );
  }

  Future<AdminCustomerPage> listCustomersPage({
    String query = '',
    String? status,
    int offset = 0,
    int limit = adminCustomersDefaultPageSize,
  }) async {
    _validateCustomerPageArguments(offset: offset, limit: limit);
    final normalizedQuery = _validatedCustomerQuery(query);
    final normalizedStatus = _validatedCustomerStatus(status);
    final client = supabaseClient;
    if (client == null) {
      final filtered = _filterCustomers(
        _customers,
        query: normalizedQuery,
        status: normalizedStatus,
      );
      return _pageCustomers(filtered, offset: offset, limit: limit);
    }

    if (normalizedQuery.isNotEmpty &&
        !canUseServerSideCustomerSearch(normalizedQuery)) {
      final filtered = await listCustomers(
        query: normalizedQuery,
        status: normalizedStatus,
      );
      return _pageCustomers(filtered, offset: offset, limit: limit);
    }

    var request = client.from('business_customers').select(_customerSelect);
    if (normalizedStatus != null) {
      request = request.eq('account_status', normalizedStatus);
    }
    if (normalizedQuery.isNotEmpty) {
      request = request.or(
        customerSearchFilterForServer(normalizedQuery),
      );
    }
    final rows = await request
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit);
    return customerPageFromResponse(
      rows,
      offset: offset,
      limit: limit,
    );
  }

  Future<BusinessCustomer> saveCustomer(BusinessCustomer customer) async {
    final status = _validatedCustomerStatus(customer.accountStatus);
    if (status == null) {
      throw ArgumentError.value(
        customer.accountStatus,
        'accountStatus',
        'Unsupported customer account status.',
      );
    }
    final normalized = customer.copyWith(
      discountPercent:
          validatedCustomerDiscountPercent(customer.discountPercent),
      accountStatus: status,
      creditLimit: _accountAmount(customer.creditLimit),
      outstandingBalance: _accountAmount(customer.outstandingBalance),
    );
    final client = supabaseClient;
    if (client != null) {
      try {
        final response = await client.functions.invoke(
          'admin-update-customer',
          body: customerUpdatePayload(normalized),
        );
        return customerFromUpdateResponse(response.data);
      } on FunctionException catch (error) {
        throw describeRemoteError(error).asException();
      }
    }
    final index = _customers.indexWhere((item) => item.id == normalized.id);
    if (index == -1) {
      _customers.insert(0, normalized);
    } else {
      throwIfStaleWrite(
        current: _customers[index].updatedAt,
        expected: normalized.updatedAt,
      );
      _customers[index] = normalized.copyWith(updatedAt: DateTime.now());
    }
    return index == -1
        ? normalized
        : _customers[index];
  }

  static Map<String, dynamic> customerUpdatePayload(
    BusinessCustomer customer,
  ) {
    final expected = utcIsoOrNull(customer.updatedAt);
    return {
      'customer_id': customer.id,
      'business_name': customer.businessName,
      'contact_person': customer.contactPerson,
      'phone': customer.phone,
      'phone_is_whatsapp': customer.phoneIsWhatsapp,
      'city': customer.city,
      'area': customer.area,
      'address': customer.address,
      'discount_percent':
          validatedCustomerDiscountPercent(customer.discountPercent),
      'account_status':
          _validatedCustomerStatus(customer.accountStatus) ??
              customer.accountStatus,
      'credit_limit': _accountAmount(customer.creditLimit),
      'outstanding_balance': _accountAmount(customer.outstandingBalance),
      if (expected != null) 'expected_updated_at': expected,
    };
  }

  static Map<String, dynamic> customerCreatePayload(
    BusinessCustomer customer, {
    String? password,
  }) {
    final trimmedPassword = password?.trim() ?? '';
    return {
      'business_name': customer.businessName,
      'contact_person': customer.contactPerson,
      'phone': customer.phone,
      'phone_is_whatsapp': customer.phoneIsWhatsapp,
      'city': customer.city,
      'area': customer.area,
      'address': customer.address,
      'username': customer.username,
      'discount_percent':
          validatedCustomerDiscountPercent(customer.discountPercent),
      'credit_limit': customer.creditLimit,
      if (trimmedPassword.isNotEmpty) 'password': trimmedPassword,
    };
  }

  static AdminRemoteErrorInfo describeRemoteError(Object error) {
    if (error is StaleWriteException) {
      return AdminRemoteErrorInfo(
        code: StaleWriteException.code,
        message: error.message,
        status: 409,
      );
    }
    if (error is AdminRemoteException) {
      return AdminRemoteErrorInfo(
        code: error.code,
        message: error.message,
        status: error.status,
      );
    }
    if (error is FunctionException) {
      return _errorInfoFromEnvelope(error.details, status: error.status);
    }
    if (error is ArgumentError) {
      return AdminRemoteErrorInfo(
        code: 'VALIDATION_ERROR',
        message: error.message?.toString() ?? error.toString(),
      );
    }
    return _errorInfoFromEnvelope(error, status: null);
  }

  static BusinessCustomer customerFromUpdateResponse(Object? responseData) {
    final root = _stringKeyedMap(responseData);
    if (root['ok'] == false) {
      throw describeRemoteError(root).asException();
    }
    final nested = _stringKeyedMap(root['data']);
    final customer = _stringKeyedMap(
      nested['customer'] ?? root['customer'],
    );
    if (customer.isEmpty || _firstNonEmpty(customer, const ['id']).isEmpty) {
      throw StateError(
        'Customer update response is missing the saved customer.',
      );
    }
    return BusinessCustomer.fromSupabase(customer);
  }

  Future<InviteResult> createCustomerInvite(
    BusinessCustomer customer, {
    String? password,
    String? inviteTemplate,
  }) async {
    final client = supabaseClient;
    if (client != null) {
      final response = await client.functions.invoke(
        'admin-create-customer',
        body: customerCreatePayload(customer, password: password),
      );
      final parsed = InviteResult.fromFunctionResponse(
        response.data,
        fallbackUsername: customer.username,
        customerPhone: customer.phone,
      );
      return _withLocalInviteCopy(
        parsed,
        customer: customer,
        inviteTemplate: inviteTemplate,
      );
    }
    final id = customer.id == 'new' ? const Uuid().v4() : customer.id;
    final saved = customer.copyWith(id: id, accountStatus: 'active');
    await saveCustomer(saved);
    final temporaryPassword =
        (password?.trim().isNotEmpty ?? false) ? password!.trim() : 'Temp-92841!';
    final token = 'inv_${const Uuid().v4().substring(0, 8)}';
    final inviteLink =
        'animalsupplyb2b://invite?token=$token&client=${Uri.encodeComponent(saved.username)}';
    return _withLocalInviteCopy(
      InviteResult(
        username: saved.username,
        temporaryPassword: temporaryPassword,
        inviteLink: inviteLink,
        whatsappMessage: '',
        customerPhone: saved.phone,
        customerId: saved.id,
        profileId: saved.profileId,
        businessName: saved.businessName,
        contactName: saved.contactPerson,
      ),
      customer: saved,
      inviteTemplate: inviteTemplate,
    );
  }

  Map<String, dynamic> _customerPasswordResetBody(BusinessCustomer customer) {
    final profileId = customer.profileId?.trim() ?? '';
    final customerId = customer.id.trim();
    if (profileId.isEmpty && (customerId.isEmpty || customerId == 'new')) {
      throw StateError(
        'A saved customer ID is required for a secure password reset.',
      );
    }
    return <String, dynamic>{
      if (profileId.isNotEmpty)
        'user_id': profileId
      else
        'customer_id': customerId,
    };
  }

  Future<Object?> _invokeCustomerPasswordReset(Map<String, dynamic> body) async {
    final client = supabaseClient;
    if (_edgeFunctionInvoker != null) {
      return _edgeFunctionInvoker(
        'admin-reset-customer-password',
        body,
      );
    }
    if (client == null) return null;
    return (await client.functions.invoke(
      'admin-reset-customer-password',
      body: body,
    ))
        .data;
  }

  Future<void> setCustomerPassword(
    BusinessCustomer customer, {
    required String password,
  }) async {
    final trimmed = password.trim();
    if (trimmed.isEmpty) return;
    final body = {
      ..._customerPasswordResetBody(customer),
      'password': trimmed,
    };
    final responseData = await _invokeCustomerPasswordReset(body);
    if (responseData == null) {
      // Demo/offline: Auth is not available, so nothing is stored locally.
      return;
    }
    final root = _stringKeyedMap(responseData);
    final nested = _stringKeyedMap(root['data']);
    final updated = root['password_updated'] == true ||
        nested['password_updated'] == true;
    if (!updated) {
      throw StateError('The customer password was not updated on the server.');
    }
  }

  Future<InviteResult> resetCustomerPassword(BusinessCustomer customer) async {
    final client = supabaseClient;
    if (client != null || _edgeFunctionInvoker != null) {
      final responseData = await _invokeCustomerPasswordReset(
        _customerPasswordResetBody(customer),
      );
      return _withLocalInviteCopy(
        InviteResult.fromFunctionResponse(
          responseData,
          fallbackUsername: customer.username,
          customerPhone: customer.phone,
        ),
        customer: customer,
      );
    }
    const temp = 'Temp-48291!';
    final inviteLink =
        'animalsupplyb2b://invite?token=reset_demo&client=${Uri.encodeComponent(customer.username)}';
    return _withLocalInviteCopy(
      InviteResult(
        username: customer.username,
        temporaryPassword: temp,
        inviteLink: inviteLink,
        whatsappMessage: '',
        customerPhone: customer.phone,
        customerId: customer.id,
        profileId: customer.profileId,
        businessName: customer.businessName,
        contactName: customer.contactPerson,
      ),
      customer: customer,
    );
  }

  InviteResult composeLoginReminder(
    BusinessCustomer customer, {
    String? knownPassword,
    String? inviteTemplate,
  }) {
    return _withLocalInviteCopy(
      InviteResult(
        username: customer.username,
        temporaryPassword: knownPassword?.trim() ?? '',
        inviteLink: _publicLoginLink(),
        whatsappMessage: '',
        customerPhone: customer.phone,
        customerId: customer.id == 'new' ? '' : customer.id,
        profileId: customer.profileId,
        businessName: customer.businessName,
        contactName: customer.contactPerson,
      ),
      customer: customer,
      inviteTemplate: inviteTemplate,
    );
  }

  InviteResult _withLocalInviteCopy(
    InviteResult result, {
    required BusinessCustomer customer,
    String? inviteTemplate,
  }) {
    final businessName = result.businessName.isNotEmpty
        ? result.businessName
        : customer.businessName;
    final contactName = result.contactName.isNotEmpty
        ? result.contactName
        : customer.contactPerson;
    return result.copyWith(
      businessName: businessName,
      contactName: contactName,
      customerId: result.customerId.isNotEmpty
          ? result.customerId
          : (customer.id == 'new' ? '' : customer.id),
      profileId: result.profileId ?? customer.profileId,
      whatsappMessage: _inviteMessage(
        businessName,
        result.username.isEmpty ? customer.username : result.username,
        temporaryPassword: result.temporaryPassword,
        contactName: contactName,
        inviteTemplate: inviteTemplate,
      ),
    );
  }

  Future<AppSettingsData> settings() async {
    final client = supabaseClient;
    if (client != null) {
      final rows =
          await client.from('app_settings').select('key,value,updated_at');
      DateTime? latest;
      final values = <String, String>{};
      for (final row in rows) {
        values[row['key'].toString()] = row['value'].toString();
        final at = DateTime.tryParse(row['updated_at']?.toString() ?? '');
        if (at != null && (latest == null || at.isAfter(latest))) {
          latest = at;
        }
      }
      return AppSettingsData.fromKeyValues(values, updatedAt: latest);
    }
    return _settings;
  }

  Future<void> saveSettings(AppSettingsData settings) async {
    final client = supabaseClient;
    if (client != null) {
      try {
        await client.rpc(
          'admin_save_app_settings',
          params: {
            'p_settings': settings.toKeyValues(),
            'p_expected_updated_at': utcIsoOrNull(settings.updatedAt),
          },
        );
      } catch (error) {
        rethrowIfStaleWrite(error);
        if (!_isMissingRpc(error, 'admin_save_app_settings')) {
          rethrow;
        }
        await client.from('app_settings').upsert([
          for (final entry in settings.toKeyValues().entries)
            {
              'key': entry.key,
              'value': entry.value,
              'updated_at': DateTime.now().toIso8601String(),
            }
        ]);
      }
      _settings = settings;
      return;
    }
    throwIfStaleWrite(
      current: _settings.updatedAt,
      expected: settings.updatedAt,
    );
    _settings = settings.copyWith(updatedAt: DateTime.now());
  }

  Future<List<AppBanner>> banners() => _loadBanners(includeInactive: false);

  Future<List<AppBanner>> allBanners() => _loadBanners(includeInactive: true);

  Future<List<AppBanner>> _loadBanners({required bool includeInactive}) async {
    final client = supabaseClient;
    if (client != null) {
      final rows = includeInactive
          ? await client
              .from('banners')
              .select()
              .order('sort_order')
              .order('created_at')
          : await client
              .from('banners')
              .select()
              .eq('active', true)
              .order('sort_order')
              .order('created_at');
      return rows.map<AppBanner>((row) => AppBanner.fromSupabase(row)).toList();
    }
    final result = _banners
        .where((banner) => includeInactive || banner.active)
        .toList(growable: false)
      ..sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        return order != 0 ? order : a.title.compareTo(b.title);
      });
    return List<AppBanner>.unmodifiable(result);
  }

  Future<AppBanner> saveBanner(AppBanner banner) async {
    final normalized = _validatedBanner(banner);
    final client = supabaseClient;
    if (client != null) {
      final payload = {
        ...normalized.toSupabasePayload(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      final Map<String, dynamic>? saved;
      if (normalized.id == 'new') {
        saved = await client.from('banners').insert(payload).select().single();
      } else {
        try {
          final existing = await client
              .from('banners')
              .select('updated_at')
              .eq('id', normalized.id)
              .maybeSingle();
          if (existing == null) {
            throw const StaleWriteException();
          }
          throwIfStaleWrite(
            current: DateTime.tryParse(existing['updated_at']?.toString() ?? ''),
            expected: normalized.updatedAt,
          );
          saved = await client
              .from('banners')
              .update(payload)
              .eq('id', normalized.id)
              .select()
              .maybeSingle();
        } catch (error) {
          rethrowIfStaleWrite(error);
          rethrow;
        }
      }
      if (saved == null) {
        throw StateError('Banner write did not return a saved row.');
      }
      return AppBanner.fromSupabase(saved);
    }

    if (normalized.id == 'new') {
      final created = normalized.copyWith(id: const Uuid().v4());
      _banners.add(created);
      return created;
    }
    final index = _banners.indexWhere((item) => item.id == normalized.id);
    if (index == -1) {
      throw StateError('Banner not found.');
    }
    throwIfStaleWrite(
      current: _banners[index].updatedAt,
      expected: normalized.updatedAt,
    );
    _banners[index] = normalized.copyWith(updatedAt: DateTime.now());
    return _banners[index];
  }

  Future<AppBanner> setBannerActive(
    AppBanner banner, {
    required bool active,
  }) {
    return saveBanner(banner.copyWith(active: active));
  }

  Future<AppVersionInfo> latestVersion({String platform = 'android'}) async {
    final client = supabaseClient;
    if (client != null) {
      final row = await client
          .from('app_versions')
          .select()
          .eq('platform', platform)
          .eq('published', true)
          .order('version_code', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) {
        return AppVersionInfo(
          platform: (row['platform'] ?? 'android').toString(),
          versionName: (row['version_name'] ?? '1.0.0').toString(),
          versionCode: (row['version_code'] ?? 1) as int,
          apkUrl: (row['apk_url'] ?? '').toString(),
          required: row['required_update'] == true,
          releaseNotes: (row['release_notes'] ?? '').toString(),
          minimumSupportedCode: (row['minimum_supported_code'] ?? 1) as int,
          sha256: (row['sha256'] ?? '').toString(),
          fileSizeBytes: row['file_size_bytes'] as int?,
        );
      }
    }
    final isAndroid = platform == 'android';
    return AppVersionInfo(
      platform: platform,
      apkUrl: isAndroid ? _settings.apkLink : '',
      releaseNotes: isAndroid
          ? 'رابط APK تجريبي للاختبار المباشر.'
          : 'لم تُنشر بيانات توزيع iOS بعد.',
    );
  }

  Future<void> publishVersion(AppVersionInfo version) async {
    validateVersionForPublication(version);
    final client = supabaseClient;
    if (client == null) return;
    await client.from('app_versions').upsert(
      {
        'platform': version.platform,
        'version_name': version.versionName,
        'version_code': version.versionCode,
        'minimum_supported_code': version.minimumSupportedCode,
        'apk_url': version.apkUrl,
        'required_update': version.required,
        'release_notes': version.releaseNotes,
        'sha256': version.sha256.isEmpty ? null : version.sha256,
        'file_size_bytes': version.fileSizeBytes,
        'published': true,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'platform,version_code',
    );
  }

  static void validateVersionForPublication(AppVersionInfo version) {
    final platform = version.platform.trim().toLowerCase();
    final validPlatform = platform == 'android' || platform == 'ios';
    final validHash =
        RegExp(r'^[a-f0-9]{64}$').hasMatch(version.sha256.trim().toLowerCase());
    final requiresAndroidIntegrity = platform == 'android';
    if (!validPlatform ||
        version.versionName.trim().isEmpty ||
        version.versionCode < 1 ||
        version.minimumSupportedCode < 1 ||
        version.minimumSupportedCode > version.versionCode ||
        safeHttpsUpdateUri(version.apkUrl) == null ||
        (requiresAndroidIntegrity && !validHash) ||
        (requiresAndroidIntegrity &&
            (version.fileSizeBytes == null || version.fileSizeBytes! < 1)) ||
        (!requiresAndroidIntegrity &&
            version.sha256.trim().isNotEmpty &&
            !validHash) ||
        (version.fileSizeBytes != null && version.fileSizeBytes! < 1)) {
      throw const FormatException(
        'Version metadata is incomplete or unsafe for publication.',
      );
    }
  }

  Future<List<AdminNotification>> notifications() async {
    final client = supabaseClient;
    if (client != null) {
      final rows = await client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(30);
      return rows
          .map<AdminNotification>((row) => AdminNotification(
                id: row['id'].toString(),
                title: (row['title'] ?? '').toString(),
                body: (row['body'] ?? '').toString(),
                type: (row['type'] ?? '').toString(),
                orderId:
                    (row['payload'] is Map ? row['payload']['order_id'] : null)
                        ?.toString(),
                read: row['read_at'] != null,
              ))
          .toList();
    }
    return _notifications;
  }

  String _publicLoginLink() {
    return resolvePublicLoginUri(publicAppOrigin: AppConfig.publicAppOrigin)
            ?.toString() ??
        '';
  }

  String _inviteMessage(
    String businessName,
    String username, {
    String? temporaryPassword,
    String? contactName,
    String? inviteTemplate,
  }) {
    return customerWhatsappWelcomeMessage(
      businessName: businessName,
      shopName: _settings.shopName,
      username: username,
      loginUrl: _publicLoginLink(),
      temporaryPassword: temporaryPassword,
      contactName: contactName,
      template: inviteTemplate,
    );
  }

  static bool _isMissingRpc(Object error, String name) {
    final text = error.toString().toLowerCase();
    return text.contains(name.toLowerCase()) &&
        (text.contains('pgrst202') ||
            text.contains('could not find the function') ||
            text.contains('schema cache'));
  }
}
