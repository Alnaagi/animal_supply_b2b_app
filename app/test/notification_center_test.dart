import 'package:animal_supply_b2b/src/data/repositories/notifications_repository.dart';
import 'package:animal_supply_b2b/src/features/notifications/notification_center_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('notification center groups by day and marks all as read',
      (tester) async {
    final repository = NotificationsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotificationCenterSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('قراءة الكل'), findsOneWidget);
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.text('أمس'), findsOneWidget);
    expect(find.text('تم تأكيد الطلب'), findsOneWidget);
    expect(find.text('منتجات جديدة'), findsOneWidget);

    expect(await repository.unreadCount(), 1);
    await tester
        .tap(find.byKey(const Key('mark-all-notifications-read-button')));
    await tester.pumpAndSettle();
    expect(await repository.unreadCount(), 0);
  });
}
