import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/order_status.dart';
import '../models/order.dart';
import '../remote/supabase_clients.dart';
import 'demo_data.dart';

final ordersRepositoryProvider =
    Provider<OrdersRepository>((ref) => OrdersRepository());

class OrdersFunctionResponse {
  const OrdersFunctionResponse({required this.status, required this.data});

  final int status;
  final Object? data;
}

abstract interface class OrdersRemoteGateway {
  Future<List<Map<String, dynamic>>> ordersForCustomer(String customerId);

  Future<List<Map<String, dynamic>>> allOrders();

  Future<OrdersFunctionResponse> placeOrder(Map<String, dynamic> body);

  Future<OrdersFunctionResponse> transitionOrderStatus(
      Map<String, dynamic> body);
}

class SupabaseOrdersRemoteGateway implements OrdersRemoteGateway {
  SupabaseOrdersRemoteGateway(this.client);

  final SupabaseClient client;

  static const _orderSelect = '''
    *,
    order_items(*, products(*, categories(name))),
    status_history:order_status_history(*),
    business_customers(
      id,
      profile_id,
      business_name,
      contact_person,
      phone,
      city,
      area,
      address
    )
  ''';

  @override
  Future<List<Map<String, dynamic>>> ordersForCustomer(
      String customerId) async {
    final rows = await client
        .from('orders')
        .select(_orderSelect)
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);
    return _asRows(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> allOrders() async {
    final rows = await client
        .from('orders')
        .select(_orderSelect)
        .order('created_at', ascending: false);
    return _asRows(rows);
  }

  @override
  Future<OrdersFunctionResponse> placeOrder(Map<String, dynamic> body) async {
    final response = await client.functions.invoke('place-order', body: body);
    return OrdersFunctionResponse(
      status: response.status,
      data: response.data,
    );
  }

  @override
  Future<OrdersFunctionResponse> transitionOrderStatus(
      Map<String, dynamic> body) async {
    final response =
        await client.functions.invoke('transition-order-status', body: body);
    return OrdersFunctionResponse(
      status: response.status,
      data: response.data,
    );
  }

  static List<Map<String, dynamic>> _asRows(Object? rows) {
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (_asMap(row) case final mapped?) mapped,
    ];
  }
}

class OrdersRepositoryException implements Exception {
  const OrdersRepositoryException({
    required this.code,
    required this.message,
    this.status,
    this.details,
  });

  final String code;
  final String message;
  final int? status;
  final Object? details;

  @override
  String toString() => message;
}

class OrdersRepository {
  OrdersRepository({
    OrdersRemoteGateway? remote,
    List<Order>? demoSeed,
  })  : _remote = remote ?? _configuredRemote(),
        _orders = [...(demoSeed ?? demoOrders)];

  OrdersRepository.demo({List<Order>? seed})
      : _remote = null,
        _orders = [...(seed ?? demoOrders)];

  final OrdersRemoteGateway? _remote;
  final List<Order> _orders;

  static OrdersRemoteGateway? _configuredRemote() {
    final client = supabaseClient;
    return client == null ? null : SupabaseOrdersRemoteGateway(client);
  }

  bool get isDemoMode => _remote == null;

  Future<List<Order>> ordersForCustomer(String customerId) async {
    final remote = _remote;
    if (remote != null) {
      final rows = await remote.ordersForCustomer(customerId);
      return rows.map(Order.fromSupabase).toList(growable: false);
    }
    return _orders.where((order) => order.customerId == customerId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<Order>> allOrders() async {
    final remote = _remote;
    if (remote != null) {
      final rows = await remote.allOrders();
      return rows.map(Order.fromSupabase).toList(growable: false);
    }
    return [..._orders]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Places an order through the trusted server boundary.
  ///
  /// Customer identity, prices, fees, totals, stock, MOQ, and initial status
  /// are intentionally not accepted from Flutter in production.
  Future<Order> placeOrder({
    required String clientRequestId,
    required String customerId,
    required List<CartItem> items,
    String businessName = '',
    String deliveryAddress = '',
    String customerNote = '',
    String deliveryNote = '',
  }) async {
    _validateOrderRequest(clientRequestId: clientRequestId, items: items);

    final remote = _remote;
    if (remote != null) {
      final body = <String, dynamic>{
        'client_request_id': clientRequestId,
        if (deliveryAddress.trim().isNotEmpty)
          'delivery_address': deliveryAddress.trim(),
        if (customerNote.trim().isNotEmpty)
          'customer_note': customerNote.trim(),
        if (deliveryNote.trim().isNotEmpty)
          'delivery_note': deliveryNote.trim(),
        'items': [
          for (final item in items)
            {
              'product_id': item.product.id,
              'quantity': item.quantity,
            },
        ],
      };
      final response = await remote.placeOrder(body);
      return _orderFromFunction(response);
    }

    final pricing = CartPricingSummary.estimate(items);
    final now = DateTime.now();
    final sequence = _orders.length + 1001;
    final order = Order(
      id: clientRequestId,
      orderNumber: 'DEMO-$sequence',
      clientRequestId: clientRequestId,
      customerId: customerId,
      businessName: businessName,
      status: OrderStatus.pending,
      items: [
        for (final item in items)
          OrderItem(
            productId: item.product.id,
            productName: item.product.name,
            productSku: item.product.sku,
            unitSize: item.product.unitSize,
            packageLabel: item.product.effectivePackageSize,
            quantity: item.quantity,
            unitPrice: item.product.price,
            lineTotal: item.lineTotal,
            product: item.product,
          ),
      ],
      createdAt: now,
      updatedAt: now,
      deliveryAddress: deliveryAddress.trim(),
      deliveryNote: deliveryNote.trim(),
      customerNote: customerNote.trim(),
      subtotal: pricing.subtotal,
      handlingFee: pricing.handlingFee,
      deliveryFee: pricing.deliveryFee,
      total: pricing.total,
      statusHistory: [
        OrderStatusHistoryEntry(
          toStatus: OrderStatus.pending,
          note: 'تم إنشاء الطلب في الوضع التجريبي',
          changedAt: now,
        ),
      ],
    );
    _orders.insert(0, order);
    return order;
  }

  Future<Order> transitionOrderStatus(
    String orderId,
    OrderStatus status, {
    String adminNote = '',
  }) async {
    final remote = _remote;
    if (remote != null) {
      final response = await remote.transitionOrderStatus({
        'order_id': orderId,
        'status': status.value,
        if (adminNote.trim().isNotEmpty) ...{
          'note': adminNote.trim(),
          'admin_note': adminNote.trim(),
        },
      });
      return _orderFromFunction(response);
    }

    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index == -1) {
      throw const OrdersRepositoryException(
        code: 'ORDER_NOT_FOUND',
        message: 'تعذر العثور على الطلب.',
        status: 404,
      );
    }
    final current = _orders[index];
    if (current.status == status) return current;
    if (!current.allowedNextStatuses.contains(status)) {
      throw const OrdersRepositoryException(
        code: 'INVALID_STATUS_TRANSITION',
        message: 'لا يمكن نقل الطلب مباشرةً إلى هذه الحالة.',
        status: 409,
      );
    }

    final now = DateTime.now();
    final updated = current.copyWith(
      status: status,
      adminNote: adminNote.trim(),
      updatedAt: now,
      statusHistory: [
        ...current.statusHistory,
        OrderStatusHistoryEntry(
          fromStatus: current.status,
          toStatus: status,
          note: adminNote.trim(),
          changedAt: now,
        ),
      ],
    );
    _orders[index] = updated;
    return updated;
  }

  String whatsappSummary(Order order, String fallbackBusinessName) {
    final businessName = order.businessName.trim().isNotEmpty
        ? order.businessName.trim()
        : fallbackBusinessName.trim();
    final lines = <String>[
      'طلب من: ${businessName.isEmpty ? 'عميل B2B' : businessName}',
      'رقم الطلب: ${order.displayNumber}',
      'الحالة: ${order.status.label}',
      '',
      'المنتجات:',
      for (var i = 0; i < order.items.length; i++)
        '${i + 1}. ${order.items[i].productName} × ${order.items[i].quantity} — ${order.items[i].lineTotal.toStringAsFixed(2)} د.ل',
      '',
      'الإجمالي الفرعي: ${order.subtotal.toStringAsFixed(2)} د.ل',
      if (order.deliveryFee > 0)
        'التوصيل: ${order.deliveryFee.toStringAsFixed(2)} د.ل',
      if (order.handlingFee > 0)
        'المناولة: ${order.handlingFee.toStringAsFixed(2)} د.ل',
      'الإجمالي: ${order.total.toStringAsFixed(2)} د.ل',
      if (order.deliveryAddress.isNotEmpty)
        'عنوان التسليم: ${order.deliveryAddress}',
      'ملاحظة العميل: ${order.customerNote.isEmpty ? 'لا توجد' : order.customerNote}',
    ];
    return lines.join('\n');
  }

  static void _validateOrderRequest({
    required String clientRequestId,
    required List<CartItem> items,
  }) {
    if (clientRequestId.trim().isEmpty) {
      throw const OrdersRepositoryException(
        code: 'INVALID_CLIENT_REQUEST_ID',
        message: 'تعذر تجهيز رقم آمن للطلب. حاول مرة أخرى.',
      );
    }
    if (items.isEmpty) {
      throw const OrdersRepositoryException(
        code: 'EMPTY_ORDER',
        message: 'لا يمكن إرسال طلب بدون منتجات.',
      );
    }
    if (items.any((item) => item.quantity <= 0)) {
      throw const OrdersRepositoryException(
        code: 'INVALID_QUANTITY',
        message: 'توجد كمية غير صالحة في السلة.',
      );
    }
  }

  static Order _orderFromFunction(OrdersFunctionResponse response) {
    final envelope = _asMap(response.data);
    if (response.status < 200 ||
        response.status >= 300 ||
        envelope?['ok'] == false) {
      throw _functionError(response.status, envelope, response.data);
    }
    if (envelope == null) {
      throw const OrdersRepositoryException(
        code: 'INVALID_SERVER_RESPONSE',
        message: 'وصل رد غير صالح من الخادم. لم يتم مسح السلة.',
      );
    }

    final data = _asMap(envelope['data']);
    final orderMap = _asMap(data?['order']) ??
        _asMap(envelope['order']) ??
        (data != null && data.containsKey('id') ? data : null);
    if (orderMap == null || (orderMap['id'] ?? '').toString().isEmpty) {
      throw const OrdersRepositoryException(
        code: 'INVALID_SERVER_RESPONSE',
        message: 'لم يرجع الخادم الطلب المؤكد. لم يتم مسح السلة.',
      );
    }
    return Order.fromMap(orderMap);
  }

  static OrdersRepositoryException _functionError(
    int status,
    Map<String, dynamic>? envelope,
    Object? raw,
  ) {
    final error = _asMap(envelope?['error']);
    final code = (error?['code'] ?? envelope?['code'] ?? 'ORDER_REQUEST_FAILED')
        .toString()
        .toUpperCase();
    final serverMessage =
        (error?['message'] ?? envelope?['message'] ?? '').toString().trim();
    final message = _localizedErrorMessage(
      code: code,
      status: status,
      serverMessage: serverMessage,
    );
    return OrdersRepositoryException(
      code: code,
      message: message,
      status: status,
      details: error?['details'] ?? raw,
    );
  }

  static String _localizedErrorMessage({
    required String code,
    required int status,
    required String serverMessage,
  }) {
    switch (code) {
      case 'UNAUTHORIZED':
      case 'AUTH_REQUIRED':
      case 'INVALID_TOKEN':
        return 'انتهت جلسة الدخول. سجل الدخول من جديد ثم أعد المحاولة.';
      case 'FORBIDDEN':
      case 'ACCOUNT_INACTIVE':
      case 'CUSTOMER_ACCOUNT_INACTIVE':
      case 'PROFILE_INACTIVE':
      case 'CUSTOMER_SUSPENDED':
        return 'الحساب غير مخول لإرسال هذا الطلب. تواصل مع الإدارة.';
      case 'OUT_OF_STOCK':
      case 'INSUFFICIENT_STOCK':
        return 'تغير المخزون لبعض المنتجات. راجع السلة وحاول من جديد.';
      case 'MINIMUM_QUANTITY':
      case 'MINIMUM_QUANTITY_NOT_MET':
      case 'MOQ_NOT_MET':
        return 'إحدى الكميات أقل من الحد الأدنى المسموح.';
      case 'MINIMUM_ORDER_NOT_MET':
      case 'MINIMUM_ORDER_AMOUNT_NOT_MET':
        return 'قيمة الطلب أقل من الحد الأدنى المسموح.';
      case 'PRICE_CHANGED':
      case 'PRODUCT_PRICE_UNAVAILABLE':
        return 'تغير سعر أحد المنتجات. راجع السعر الجديد قبل التأكيد.';
      case 'ORDER_NOT_FOUND':
      case 'NOT_FOUND':
        return 'تعذر العثور على الطلب.';
      case 'INVALID_STATUS_TRANSITION':
        return 'لا يمكن نقل الطلب مباشرةً إلى هذه الحالة.';
      case 'DUPLICATE_REQUEST':
      case 'IDEMPOTENCY_CONFLICT':
        return 'تم إرسال هذا الطلب سابقاً أو تغيرت بياناته. حدّث الطلبات أولاً.';
      case 'VALIDATION_ERROR':
      case 'INVALID_ITEMS':
      case 'INVALID_ORDER_ITEM':
      case 'ORDER_ITEMS_REQUIRED':
      case 'TOO_MANY_ORDER_ITEMS':
      case 'INVALID_ORDER_STATUS':
      case 'INVALID_REQUEST':
        return 'بيانات الطلب غير مكتملة أو غير صالحة.';
    }
    if (status == 401) {
      return 'انتهت جلسة الدخول. سجل الدخول من جديد ثم أعد المحاولة.';
    }
    if (status == 403) {
      return 'ليس لديك صلاحية لتنفيذ هذه العملية.';
    }
    if (status == 409) {
      return 'تعارضت العملية مع حالة الطلب الحالية. حدّث الصفحة وحاول مجدداً.';
    }
    if (status == 422) {
      return 'تعذر اعتماد بيانات الطلب. راجع الكميات والعنوان.';
    }
    if (_containsArabic(serverMessage)) return serverMessage;
    return 'تعذر إكمال عملية الطلب حالياً. لم يتم مسح السلة، ويمكنك المحاولة مجدداً.';
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

bool _containsArabic(String value) =>
    RegExp(r'[\u0600-\u06ff]').hasMatch(value);
