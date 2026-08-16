import 'package:animal_supply_b2b/src/data/repositories/notifications_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo unread count is not capped by the notification page size',
      () async {
    final repository = NotificationsRepository();
    for (var index = 0; index < 60; index++) {
      repository.addDemoOrderStatus(
        orderId: 'demo-order-$index',
        statusLabel: 'قيد التجهيز',
      );
    }

    expect(await repository.unreadCount(), 61);
  });

  test('unread count provider refreshes immediately after a read receipt',
      () async {
    final repository = NotificationsRepository();
    final container = ProviderContainer(
      overrides: [
        notificationsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      unreadNotificationsCountProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    expect(
      await container.read(unreadNotificationsCountProvider.future),
      1,
    );

    await repository.markRead('demo-notification-order');
    container.invalidate(unreadNotificationsCountProvider);

    expect(
      await container.read(unreadNotificationsCountProvider.future),
      0,
    );
  });

  test('mark all read clears every unread demo notification', () async {
    final repository = NotificationsRepository();
    repository.addDemoOrderStatus(
      orderId: 'demo-order-extra',
      statusLabel: 'جاهز',
    );
    expect(await repository.unreadCount(), 2);
    expect(await repository.markAllRead(), 2);
    expect(await repository.unreadCount(), 0);
  });
}
