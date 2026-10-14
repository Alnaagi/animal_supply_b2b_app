import 'package:animal_supply_b2b/src/core/concurrency/stale_write.dart';
import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/core/localization/arabic_copy.dart';
import 'package:animal_supply_b2b/src/core/notifications/cross_tab_alert_lock.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/orders_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sameUpdatedAt treats a missing expected timestamp as compatible', () {
    expect(sameUpdatedAt(DateTime.utc(2026, 8, 16), null), isTrue);
    expect(
      sameUpdatedAt(
        DateTime.utc(2026, 8, 16, 12),
        DateTime.utc(2026, 8, 16, 13),
      ),
      isFalse,
    );
  });

  test('throwIfStaleWrite uses the Arabic reload copy', () {
    expect(
      () => throwIfStaleWrite(
        current: DateTime.utc(2026, 8, 16, 12),
        expected: DateTime.utc(2026, 8, 16, 11),
      ),
      throwsA(
        isA<StaleWriteException>().having(
          (error) => error.message,
          'message',
          ArabicCopy.staleWrite,
        ),
      ),
    );
  });

  test('customer update payload includes expected_updated_at when known', () {
    final updatedAt = DateTime.utc(2026, 8, 16, 10, 30);
    final payload = AdminRepository.customerUpdatePayload(
      BusinessCustomer(
        id: '11111111-1111-4111-8111-111111111111',
        businessName: 'متجر النور',
        username: 'noor-shop',
        contactPerson: 'أحمد',
        phone: '+218910000001',
        city: 'طرابلس',
        updatedAt: updatedAt,
      ),
    );
    expect(payload['expected_updated_at'], utcIsoOrNull(updatedAt));
  });

  test('memory cross-tab lock claims an id only once', () {
    final lock = MemoryCrossTabAlertLock();
    expect(lock.claim('order-1'), isTrue);
    expect(lock.claim('order-1'), isFalse);
  });

  test('demo order status rejects a stale updated_at', () async {
    final repository = OrdersRepository.demo(seed: const []);
    const product = Product(
      id: 'product-1',
      nameAr: 'علف',
      sku: 'FEED-1',
      category: 'أعلاف',
      animalType: 'دواجن',
      brand: 'Brand',
      unitSize: '25 كجم',
      basePrice: 20,
      stockQuantity: 40,
      minOrderQty: 1,
    );
    final placed = await repository.placeOrder(
      clientRequestId: 'stale-1',
      customerId: 'customer-1',
      items: const [CartItem(product: product, quantity: 1)],
    );
    expect(
      () => repository.transitionOrderStatus(
        placed.id,
        OrderStatus.confirmed,
        expectedUpdatedAt: DateTime.utc(2020),
      ),
      throwsA(
        isA<OrdersRepositoryException>().having(
          (error) => error.code,
          'code',
          StaleWriteException.code,
        ),
      ),
    );
  });
}
