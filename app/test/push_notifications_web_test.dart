import 'package:animal_supply_b2b/src/core/notifications/push_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('foreground web payload keeps Arabic copy and its deep link', () {
    final notification = PushForegroundNotification.fromMessage(
      const RemoteMessage(
        data: {
          'title': 'تحديث الطلب',
          'body': 'تم تجهيز طلبك.',
          'order_id': 'order-1',
        },
      ),
    );

    expect(notification.title, 'تحديث الطلب');
    expect(notification.body, 'تم تجهيز طلبك.');
    expect(notification.navigation.orderId, 'order-1');
    expect(notification.navigation.hasDestination, isTrue);
  });
}
