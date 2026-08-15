import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/order_status.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../remote/supabase_clients.dart';
import 'demo_data.dart';

final ordersRepositoryProvider =
    Provider<OrdersRepository>((ref) => OrdersRepository());

class OrdersFunctionResponse {
  const OrdersFunctionResponse({required this.status, required this.data});

  final int status;
  final Object? data;
}

class OrdersTransportException implements Exception {
  const OrdersTransportException(this.cause);

  final Object cause;
}

typedef OrdersFunctionInvoker = Future<OrdersFunctionResponse> Function(
  String functionName,
  Map<String, dynamic> body,
);

class OrdersPage {
  const OrdersPage({
    required this.orders,
    required this.hasMore,
    required this.nextOffset,
    required this.snapshotAt,
  });

  final List<Order> orders;
  final bool hasMore;
  final int nextOffset;

  /// Upper timestamp boundary shared by every page in the same browsing
  /// session. This prevents newly inserted orders from shifting offset pages.
  final DateTime snapshotAt;
}

abstract interface class OrdersRemoteGateway {
  Future<List<Map<String, dynamic>>> ordersForCustomer(String customerId);

  Future<List<Map<String, dynamic>>> allOrders();

  Future<OrdersFunctionResponse> placeOrder(Map<String, dynamic> body);

  Future<OrdersFunctionResponse> transitionOrderStatus(
      Map<String, dynamic> body);
}

/// Optional bounded read capability for remote order gateways.
///
/// Kept separate from [OrdersRemoteGateway] so existing adapters and report
/// callers remain source-compatible while interactive history screens can use
/// production-safe paging.
abstract interface class OrdersPagedRemoteGateway {
  Future<List<Map<String, dynamic>>> queryOrdersPage({
    String? customerId,
    String? status,
    List<String>? statuses,
    DateTime? createdFrom,
    DateTime? createdUntil,
    required DateTime snapshotAt,
    required int offset,
    required int limit,
  });

  Future<Map<String, dynamic>?> queryOrderById(
    String orderId, {
    String? customerId,
  });
}

class SupabaseOrdersRemoteGateway
    implements OrdersRemoteGateway, OrdersPagedRemoteGateway {
  SupabaseOrdersRemoteGateway(
    this.client, {
    OrdersFunctionInvoker? functionInvoker,
    Duration requestTimeout = const Duration(seconds: 25),
  })  : _functionInvoker = functionInvoker ??
            ((functionName, body) async {
              final response = await client.functions.invoke(
                functionName,
                body: body,
              );
              return OrdersFunctionResponse(
                status: response.status,
                data: response.data,
              );
            }),
        _requestTimeout = requestTimeout;

  final SupabaseClient client;
  final OrdersFunctionInvoker _functionInvoker;
  final Duration _requestTimeout;

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
  Future<List<Map<String, dynamic>>> queryOrdersPage({
    String? customerId,
    String? status,
    List<String>? statuses,
    DateTime? createdFrom,
    DateTime? createdUntil,
    required DateTime snapshotAt,
    required int offset,
    required int limit,
  }) async {
    dynamic query = client.from('orders').select(_orderSelect);
    if (customerId != null && customerId.isNotEmpty) {
      query = query.eq('customer_id', customerId);
    }
    final statusIn = [
      for (final value in statuses ?? const <String>[])
        if (value.trim().isNotEmpty) value.trim(),
    ];
    if (statusIn.length > 1) {
      query = query.inFilter('status', statusIn);
    } else if (statusIn.length == 1) {
      query = query.eq('status', statusIn.single);
    } else if (status != null && status.isNotEmpty) {
      query = query.eq('status', status);
    }
    if (createdFrom != null) {
      query = query.gte(
        'created_at',
        createdFrom.toUtc().toIso8601String(),
      );
    }
    if (createdUntil != null) {
      query = query.lt(
        'created_at',
        createdUntil.toUtc().toIso8601String(),
      );
    }
    final rows = await query
        .lte('created_at', snapshotAt.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
    return _asRows(rows);
  }

  @override
  Future<Map<String, dynamic>?> queryOrderById(
    String orderId, {
    String? customerId,
  }) async {
    dynamic query =
        client.from('orders').select(_orderSelect).eq('id', orderId);
    if (customerId != null && customerId.isNotEmpty) {
      query = query.eq('customer_id', customerId);
    }
    final row = await query.maybeSingle();
    return _asMap(row);
  }

  @override
  Future<OrdersFunctionResponse> placeOrder(Map<String, dynamic> body) async {
    return _invokeFunction('place-order', body);
  }

  @override
  Future<OrdersFunctionResponse> transitionOrderStatus(
      Map<String, dynamic> body) async {
    return _invokeFunction('transition-order-status', body);
  }

  Future<OrdersFunctionResponse> _invokeFunction(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    try {
      return await _functionInvoker(functionName, body)
          .timeout(_requestTimeout);
    } on FunctionException catch (error) {
      return OrdersFunctionResponse(
        status: error.status,
        data: error.details,
      );
    } on Exception catch (error) {
      throw OrdersTransportException(error);
    }
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
    this.isRetryable = false,
  });

  final String code;
  final String message;
  final int? status;
  final Object? details;
  final bool isRetryable;

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

  static const defaultPageSize = 50;

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

  Future<OrdersPage> ordersPage({
    String? customerId,
    OrderStatus? status,
    Iterable<OrderStatus>? statuses,
    DateTime? createdFrom,
    DateTime? createdUntil,
    DateTime? snapshotAt,
    int offset = 0,
    int pageSize = defaultPageSize,
  }) async {
    final safeOffset = offset < 0 ? 0 : offset;
    final safePageSize = pageSize.clamp(1, 100).toInt();
    final safeSnapshot = (snapshotAt ?? DateTime.now()).toUtc();
    final normalizedCustomerId = _nonEmptyOrNull(customerId);
    final statusQuery = _statusQuery(status: status, statuses: statuses);
    final remote = _remote;

    if (remote case final OrdersPagedRemoteGateway pagedRemote) {
      final rows = await pagedRemote.queryOrdersPage(
        customerId: normalizedCustomerId,
        status: statusQuery.single,
        statuses: statusQuery.multiple,
        createdFrom: createdFrom?.toUtc(),
        createdUntil: createdUntil?.toUtc(),
        snapshotAt: safeSnapshot,
        offset: safeOffset,
        limit: safePageSize + 1,
      );
      final mapped = rows.map(Order.fromSupabase).toList(growable: false);
      if (normalizedCustomerId != null &&
          mapped.any((order) => order.customerId != normalizedCustomerId)) {
        throw const OrdersRepositoryException(
          code: 'INVALID_SERVER_RESPONSE',
          message:
              'وصلت بيانات طلبات غير مطابقة للحساب الحالي، لذلك لم يتم عرضها.',
        );
      }
      return _buildPage(
        mapped,
        offset: safeOffset,
        pageSize: safePageSize,
        snapshotAt: safeSnapshot,
      );
    }

    final source = remote == null
        ? _orders
        : normalizedCustomerId == null
            ? await remote
                .allOrders()
                .then((rows) => rows.map(Order.fromSupabase).toList())
            : await remote
                .ordersForCustomer(normalizedCustomerId)
                .then((rows) => rows.map(Order.fromSupabase).toList());
    final filtered = _filterAndSortOrders(
      source,
      customerId: normalizedCustomerId,
      status: status,
      statuses: statuses,
      createdFrom: createdFrom,
      createdUntil: createdUntil,
      snapshotAt: safeSnapshot,
    );
    final available = safeOffset >= filtered.length
        ? const <Order>[]
        : filtered.skip(safeOffset).take(safePageSize + 1).toList();
    return _buildPage(
      available,
      offset: safeOffset,
      pageSize: safePageSize,
      snapshotAt: safeSnapshot,
    );
  }

  Future<Order?> orderById(
    String orderId, {
    String? customerId,
  }) async {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return null;
    final normalizedCustomerId = _nonEmptyOrNull(customerId);
    final remote = _remote;

    if (remote case final OrdersPagedRemoteGateway pagedRemote) {
      final row = await pagedRemote.queryOrderById(
        normalizedOrderId,
        customerId: normalizedCustomerId,
      );
      if (row == null) return null;
      final order = Order.fromSupabase(row);
      if (normalizedCustomerId != null &&
          order.customerId != normalizedCustomerId) {
        return null;
      }
      return order;
    }

    final source = remote == null
        ? _orders
        : normalizedCustomerId == null
            ? await remote
                .allOrders()
                .then((rows) => rows.map(Order.fromSupabase).toList())
            : await remote
                .ordersForCustomer(normalizedCustomerId)
                .then((rows) => rows.map(Order.fromSupabase).toList());
    for (final order in source) {
      if (order.id == normalizedOrderId &&
          (normalizedCustomerId == null ||
              order.customerId == normalizedCustomerId)) {
        return order;
      }
    }
    return null;
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
      final response = await _sendPlaceOrder(remote, body);
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

  /// Retries a durable outbox place-order payload.
  ///
  /// Accepts only `client_request_id`, delivery/note text, and
  /// `product_id`/`quantity` lines. Never trusts client prices, totals,
  /// customer IDs, or status for the remote path.
  Future<Order> placeOrderFromOutbox({
    required String clientRequestId,
    required List<Map<String, Object?>> items,
    String deliveryAddress = '',
    String customerNote = '',
    String deliveryNote = '',
    String demoCustomerId = '',
    String demoBusinessName = '',
  }) async {
    final normalized = _normalizeOutboxItems(items);
    if (clientRequestId.trim().isEmpty) {
      throw const OrdersRepositoryException(
        code: 'INVALID_CLIENT_REQUEST_ID',
        message: 'تعذر تجهيز رقم آمن للطلب. حاول مرة أخرى.',
      );
    }
    if (normalized.isEmpty) {
      throw const OrdersRepositoryException(
        code: 'EMPTY_ORDER',
        message: 'لا يمكن إرسال طلب بدون منتجات.',
      );
    }

    final remote = _remote;
    if (remote != null) {
      final body = <String, dynamic>{
        'client_request_id': clientRequestId.trim(),
        if (deliveryAddress.trim().isNotEmpty)
          'delivery_address': deliveryAddress.trim(),
        if (customerNote.trim().isNotEmpty)
          'customer_note': customerNote.trim(),
        if (deliveryNote.trim().isNotEmpty)
          'delivery_note': deliveryNote.trim(),
        'items': [
          for (final item in normalized)
            {
              'product_id': item.productId,
              'quantity': item.quantity,
            },
        ],
      };
      final response = await _sendPlaceOrder(remote, body);
      return _orderFromFunction(response);
    }

    final cartItems = [
      for (final item in normalized)
        CartItem(
          product: Product(
            id: item.productId,
            nameAr: 'منتج مؤجل',
            sku: item.productId,
            category: 'مؤجل',
            animalType: '',
            brand: '',
            unitSize: '',
            basePrice: 0,
            stockQuantity: item.quantity,
            minOrderQty: 1,
          ),
          quantity: item.quantity,
        ),
    ];
    return placeOrder(
      clientRequestId: clientRequestId,
      customerId: demoCustomerId,
      businessName: demoBusinessName,
      items: cartItems,
      deliveryAddress: deliveryAddress,
      customerNote: customerNote,
      deliveryNote: deliveryNote,
    );
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

  static List<({String productId, int quantity})> _normalizeOutboxItems(
    List<Map<String, Object?>> items,
  ) {
    final normalized = <({String productId, int quantity})>[];
    for (final item in items) {
      final productId = item['product_id']?.toString().trim() ?? '';
      final quantityRaw = item['quantity'];
      final quantity = quantityRaw is int
          ? quantityRaw
          : quantityRaw is num
              ? quantityRaw.toInt()
              : int.tryParse(quantityRaw?.toString() ?? '') ?? 0;
      if (productId.isEmpty || quantity <= 0) {
        throw const OrdersRepositoryException(
          code: 'INVALID_QUANTITY',
          message: 'توجد كمية غير صالحة في السلة.',
        );
      }
      normalized.add((productId: productId, quantity: quantity));
    }
    return normalized;
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
      isRetryable: _isRetryableStatus(status),
    );
  }

  static Future<OrdersFunctionResponse> _sendPlaceOrder(
    OrdersRemoteGateway remote,
    Map<String, dynamic> body,
  ) async {
    try {
      return await remote.placeOrder(body);
    } on OrdersRepositoryException {
      rethrow;
    } on OrdersTransportException catch (error) {
      throw OrdersRepositoryException(
        code: 'NETWORK_ERROR',
        message:
            'تعذر الاتصال بالخادم. تم الاحتفاظ بالطلب لإعادة إرساله عند عودة الاتصال.',
        details: error.cause,
        isRetryable: true,
      );
    } on TimeoutException catch (error) {
      throw OrdersRepositoryException(
        code: 'REQUEST_TIMEOUT',
        message:
            'استغرق الاتصال بالخادم وقتاً طويلاً. تم الاحتفاظ بالطلب لإعادة إرساله.',
        details: error,
        isRetryable: true,
      );
    }
  }

  static bool _isRetryableStatus(int status) {
    return status == 408 || status == 425 || status == 429 || status >= 500;
  }

  static OrdersPage _buildPage(
    List<Order> available, {
    required int offset,
    required int pageSize,
    required DateTime snapshotAt,
  }) {
    final hasMore = available.length > pageSize;
    final orders = available.take(pageSize).toList(growable: false);
    return OrdersPage(
      orders: orders,
      hasMore: hasMore,
      nextOffset: offset + orders.length,
      snapshotAt: snapshotAt,
    );
  }

  static ({String? single, List<String>? multiple}) _statusQuery({
    OrderStatus? status,
    Iterable<OrderStatus>? statuses,
  }) {
    final selected = {
      if (statuses != null) ...statuses else if (status != null) status,
    };
    if (selected.isEmpty || selected.length == OrderStatus.values.length) {
      return (single: null, multiple: null);
    }
    final ordered = [
      for (final value in OrderStatus.values)
        if (selected.contains(value)) value.value,
    ];
    if (ordered.length == 1) {
      return (single: ordered.single, multiple: null);
    }
    return (single: null, multiple: ordered);
  }

  static List<Order> _filterAndSortOrders(
    Iterable<Order> source, {
    String? customerId,
    OrderStatus? status,
    Iterable<OrderStatus>? statuses,
    DateTime? createdFrom,
    DateTime? createdUntil,
    required DateTime snapshotAt,
  }) {
    final from = createdFrom?.toUtc();
    final until = createdUntil?.toUtc();
    final snapshot = snapshotAt.toUtc();
    final allowed = {
      if (statuses != null) ...statuses else if (status != null) status,
    };
    final filtered = source.where((order) {
      final created = order.createdAt.toUtc();
      if (customerId != null && order.customerId != customerId) return false;
      if (allowed.isNotEmpty &&
          allowed.length != OrderStatus.values.length &&
          !allowed.contains(order.status)) {
        return false;
      }
      if (created.isAfter(snapshot)) return false;
      if (from != null && created.isBefore(from)) return false;
      if (until != null && !created.isBefore(until)) return false;
      return true;
    }).toList();
    filtered.sort((first, second) {
      final byDate = second.createdAt.compareTo(first.createdAt);
      return byDate != 0 ? byDate : second.id.compareTo(first.id);
    });
    return filtered;
  }

  static String? _nonEmptyOrNull(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
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
      case 'MAINTENANCE_MODE':
        return 'الطلبات متوقفة مؤقتاً للصيانة. حاول لاحقاً أو تواصل مع الإدارة.';
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
