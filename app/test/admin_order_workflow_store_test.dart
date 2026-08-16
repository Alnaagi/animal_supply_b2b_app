import 'package:animal_supply_b2b/src/core/constants/order_status.dart';
import 'package:animal_supply_b2b/src/data/local/admin_order_workflow_store.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('workflow steps are only statuses the server already accepts', () {
    expect(
      AdminOrderWorkflowStore.allSteps,
      {
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
        OrderStatus.delivered,
        OrderStatus.cancelled,
      },
    );
    expect(AdminOrderWorkflowStore.allSteps.contains(OrderStatus.pending), isFalse);
    for (final status in OrderStatus.values) {
      for (final next in allowedOrderTransitions(status)) {
        expect(AdminOrderWorkflowStore.allSteps.contains(next), isTrue);
      }
    }
  });

  test('hides disabled next steps without inventing a skip', () {
    expect(
      AdminOrderWorkflowStore.visibleNextStatuses(
        current: OrderStatus.pending,
        enabledSteps: {
          OrderStatus.confirmed,
          OrderStatus.delivered,
        },
      ),
      [OrderStatus.confirmed],
    );
    expect(
      AdminOrderWorkflowStore.visibleNextStatuses(
        current: OrderStatus.confirmed,
        enabledSteps: {OrderStatus.cancelled},
      ),
      [OrderStatus.cancelled],
    );
  });

  test('persists enabled workflow steps', () async {
    final store = AdminOrderWorkflowStore();
    expect(await store.load(), AdminOrderWorkflowStore.allSteps);

    final custom = {OrderStatus.confirmed, OrderStatus.cancelled};
    expect(await store.save(custom), isTrue);
    expect(await store.load(), custom);
    expect(await store.reset(), isTrue);
    expect(await store.load(), AdminOrderWorkflowStore.allSteps);
  });

  test('rejects invented status names from storage', () async {
    SharedPreferences.setMockInitialValues({
      AdminOrderWorkflowStore.storageKey: '["confirmed","shipped"]',
    });
    final store = AdminOrderWorkflowStore();
    expect(await store.load(), {OrderStatus.confirmed});
  });
}
