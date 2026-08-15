import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/data/local/admin_orders_filter_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('product default includes every status except delivered', () {
    expect(
      AdminOrdersFilterStore.productDefault,
      {
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
        OrderStatus.cancelled,
      },
    );
    expect(
      AdminOrdersFilterStore.labelFor(AdminOrdersFilterStore.productDefault),
      'كل الحالات ما عدا المُسلَّم',
    );
  });

  test('query args use an IN list for the product default', () {
    final query =
        AdminOrdersFilterStore.queryArgs(AdminOrdersFilterStore.productDefault);
    expect(query.status, isNull);
    expect(
      query.statuses,
      [
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
        OrderStatus.cancelled,
      ],
    );
  });

  test('saves included statuses and restores them on the next load', () async {
    final store = AdminOrdersFilterStore();
    expect(await store.load(), AdminOrdersFilterStore.productDefault);

    final custom = {OrderStatus.pending, OrderStatus.ready};
    expect(await store.save(custom), isTrue);
    expect(await store.load(), custom);

    expect(await store.reset(), isTrue);
    expect(await store.load(), AdminOrdersFilterStore.productDefault);
  });
}
