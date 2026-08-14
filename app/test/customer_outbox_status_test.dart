import 'dart:async';

import 'package:animal_supply_b2b/src/data/local/local_cache.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:animal_supply_b2b/src/data/sync/sync_outbox.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/cart/cart_controller.dart';
import 'package:animal_supply_b2b/src/features/orders/orders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('customer order snapshot is owner scoped and reactive', () async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = SyncOutbox(prefs: prefs);
    addTearDown(outbox.dispose);
    final iterator = StreamIterator(
      outbox.watchCustomerOrders(ownerProfileId: 'profile-a'),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.isEmpty, isTrue);

    await outbox.enqueue(
      _entry(
        id: 'request-b',
        ownerProfileId: 'profile-b',
        address: 'بيانات حساب آخر',
      ),
    );
    await outbox.enqueue(
      _entry(
        id: 'request-a',
        ownerProfileId: 'profile-a',
        address: 'طرابلس',
      ),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.pending.map((entry) => entry.id), ['request-a']);
    expect(iterator.current.failed, isEmpty);

    await outbox.markFailed(
      'request-a',
      ownerProfileId: 'profile-a',
      errorCode: 'INSUFFICIENT_STOCK',
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.pending, isEmpty);
    expect(iterator.current.failed.single.id, 'request-a');
    await iterator.cancel();
  });

  test('discard-for-edit requires the same owner and visible state', () async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = SyncOutbox(prefs: prefs);
    addTearDown(outbox.dispose);
    await outbox.enqueue(
      _entry(
        id: 'failed-a',
        ownerProfileId: 'profile-a',
        status: 'failed',
        errorCode: 'INSUFFICIENT_STOCK',
      ),
    );
    await outbox.enqueue(
      _entry(
        id: 'pending-a',
        ownerProfileId: 'profile-a',
      ),
    );

    expect(
      await outbox.discardPlaceOrderForEditing(
        'failed-a',
        ownerProfileId: 'profile-b',
        expectedState: CustomerQueuedOrderState.failed,
      ),
      isFalse,
    );
    expect(
      await outbox.discardPlaceOrderForEditing(
        'failed-a',
        ownerProfileId: 'profile-a',
        expectedState: CustomerQueuedOrderState.pending,
      ),
      isFalse,
    );
    expect(
      await outbox.discardPlaceOrderForEditing(
        'failed-a',
        ownerProfileId: 'profile-a',
        expectedState: CustomerQueuedOrderState.failed,
      ),
      isTrue,
    );

    final snapshot =
        await outbox.customerOrderSnapshot(ownerProfileId: 'profile-a');
    expect(snapshot.failed, isEmpty);
    expect(snapshot.pending.single.id, 'pending-a');
  });

  test('discard and removal fail closed when queue persistence is unavailable',
      () async {
    final outbox = SyncOutbox(storeLoader: () async => null);
    addTearDown(outbox.dispose);
    expect(
      await outbox.enqueue(
        _entry(
          id: 'durability-required',
          ownerProfileId: 'profile-a',
          status: 'failed',
          errorCode: 'INSUFFICIENT_STOCK',
        ),
      ),
      isFalse,
    );

    expect(
      await outbox.discardPlaceOrderForEditing(
        'durability-required',
        ownerProfileId: 'profile-a',
        expectedState: CustomerQueuedOrderState.failed,
      ),
      isFalse,
    );
    expect(
      (await outbox.customerOrderSnapshot(ownerProfileId: 'profile-a'))
          .failed
          .single
          .id,
      'durability-required',
    );

    expect(
      await outbox.remove(
        'durability-required',
        ownerProfileId: 'profile-a',
      ),
      isFalse,
    );
    expect(
      (await outbox.customerOrderSnapshot(ownerProfileId: 'profile-a'))
          .failed
          .single
          .id,
      'durability-required',
    );
  });

  test('discarding a failed request preserves the current cart', () async {
    final prefs = await SharedPreferences.getInstance();
    final cache = LocalCache(prefs: prefs);
    final outbox = SyncOutbox(prefs: prefs);
    addTearDown(outbox.dispose);
    const cart = [
      CartItem(product: _product, quantity: 3),
    ];
    await cache.saveCart(ownerProfileId: 'profile-a', items: cart);
    await cache.savePendingRequest(
      ownerProfileId: 'profile-a',
      requestId: 'failed-a',
      fingerprint: 'cart-fingerprint',
    );
    await outbox.enqueue(
      _entry(
        id: 'failed-a',
        ownerProfileId: 'profile-a',
        status: 'failed',
        errorCode: 'INSUFFICIENT_STOCK',
      ),
    );
    await outbox.enqueue(
      _entry(
        id: 'other-account',
        ownerProfileId: 'profile-b',
        status: 'failed',
        errorCode: 'INSUFFICIENT_STOCK',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        localCacheProvider.overrideWithValue(cache),
        syncOutboxProvider.overrideWithValue(outbox),
        authControllerProvider.overrideWith(
          (ref) => _CustomerAuthController('profile-a'),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(cartControllerProvider.notifier);
    await controller.hydrate();
    expect(container.read(cartControllerProvider), cart);

    expect(
      await controller.discardQueuedOrderForEditing(
        requestId: 'other-account',
        expectedState: CustomerQueuedOrderState.failed,
      ),
      isFalse,
    );
    expect(
      await controller.discardQueuedOrderForEditing(
        requestId: 'failed-a',
        expectedState: CustomerQueuedOrderState.failed,
      ),
      isTrue,
    );

    expect(container.read(cartControllerProvider), cart);
    expect(
      await cache.pendingRequest(ownerProfileId: 'profile-a'),
      isNull,
    );
    expect(
      (await outbox.customerOrderSnapshot(ownerProfileId: 'profile-a')).isEmpty,
      isTrue,
    );
    expect(
      (await outbox.customerOrderSnapshot(ownerProfileId: 'profile-b'))
          .failed
          .single
          .id,
      'other-account',
    );
  });

  testWidgets('orders screen shows only the signed-in customer local queue',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final outbox = SyncOutbox(prefs: prefs);
    addTearDown(outbox.dispose);
    await outbox.enqueue(
      _entry(
        id: 'pending-a',
        ownerProfileId: 'profile-a',
        address: 'طرابلس - الظهرة',
      ),
    );
    await outbox.enqueue(
      _entry(
        id: 'failed-a',
        ownerProfileId: 'profile-a',
        status: 'failed',
        errorCode: 'INSUFFICIENT_STOCK',
      ),
    );
    await outbox.enqueue(
      _entry(
        id: 'failed-b',
        ownerProfileId: 'profile-b',
        status: 'failed',
        errorCode: 'INSUFFICIENT_STOCK',
        address: 'بيانات حساب آخر',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncOutboxProvider.overrideWithValue(outbox),
          authControllerProvider.overrideWith(
            (ref) => _CustomerAuthController('profile-a'),
          ),
          ordersRepositoryProvider.overrideWithValue(
            OrdersRepository.demo(seed: const []),
          ),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: OrdersScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('طلبات محفوظة على هذا الجهاز'), findsOneWidget);
    expect(find.text('بانتظار الإرسال التلقائي'), findsOneWidget);
    expect(find.text('تعذر اعتماد طلب محفوظ'), findsOneWidget);
    expect(find.textContaining('تغير المخزون'), findsOneWidget);
    expect(find.textContaining('طرابلس - الظهرة'), findsOneWidget);
    expect(find.textContaining('بيانات حساب آخر'), findsNothing);
    expect(find.text('إعادة الإرسال الآن'), findsNothing);
  });

  test('failed error copy is Arabic and explains that retry stops', () {
    expect(
      queuedOrderFailureMessage('INSUFFICIENT_STOCK'),
      allOf(contains('المخزون'), contains('لن يعاد إرسال')),
    );
    expect(
      queuedOrderFailureMessage('UNKNOWN'),
      contains('لن يعاد إرسالها تلقائياً'),
    );
  });
}

class _CustomerAuthController extends AuthController {
  _CustomerAuthController(String profileId) {
    state = AuthState(
      user: AppUser(
        id: profileId,
        username: 'customer',
        role: 'customer',
        businessName: 'متجر الاختبار',
        customerId: 'customer-a',
      ),
    );
  }
}

SyncOutboxEntry _entry({
  required String id,
  required String ownerProfileId,
  String status = 'pending',
  String? errorCode,
  String address = '',
}) {
  return SyncOutboxEntry(
    id: id,
    ownerProfileId: ownerProfileId,
    entityType: 'place_order',
    status: status,
    errorCode: errorCode,
    payload: {
      'client_request_id': id,
      if (address.isNotEmpty) 'delivery_address': address,
      'items': const [
        {'product_id': 'product-1', 'quantity': 3},
      ],
    },
  );
}

const _product = Product(
  id: 'product-1',
  nameAr: 'علف اختبار',
  sku: 'TEST-1',
  category: 'أعلاف',
  animalType: 'أغنام',
  brand: 'اختبار',
  unitSize: '25 كجم',
  basePrice: 40,
  stockQuantity: 100,
  minOrderQty: 1,
);
