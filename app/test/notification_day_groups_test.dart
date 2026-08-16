import 'package:animal_supply_b2b/src/core/notifications/notification_day_groups.dart';
import 'package:animal_supply_b2b/src/data/models/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groups inbox rows under Arabic day headers', () {
    final now = DateTime(2026, 8, 16, 12);
    final notifications = [
      AppNotification(
        id: 'today',
        type: 'new_order',
        title: 'طلب جديد',
        body: 'وصل طلب.',
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
      AppNotification(
        id: 'yesterday',
        type: 'order_status_changed',
        title: 'تحديث الطلب',
        body: 'تم التأكيد.',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      AppNotification(
        id: 'older',
        type: 'product_campaign',
        title: 'عرض',
        body: 'منتج جديد.',
        createdAt: DateTime(2026, 8, 10, 9),
      ),
    ];

    final groups = groupNotificationsByDay(notifications, now: now);

    expect(groups.map((group) => group.label).toList(), [
      'اليوم',
      'أمس',
      'الاثنين 10 أغسطس 2026',
    ]);
    expect(groups.first.items.single.id, 'today');
    expect(groups[1].items.single.id, 'yesterday');
  });
}
