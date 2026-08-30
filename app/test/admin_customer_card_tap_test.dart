import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_customers/admin_customers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'mobile RTL customer card opens edit while its menu remains isolated',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(646, 838));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = AdminRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: AdminCustomersScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(
        const ValueKey('admin-customer-card-customer-1'),
      );
      final menu = find.byKey(
        const ValueKey('admin-customer-menu-customer-1'),
      );

      expect(card, findsOneWidget);
      expect(menu, findsOneWidget);
      expect(Directionality.of(tester.element(card)), TextDirection.rtl);
      final cardRect = tester.getRect(card);
      final menuRect = tester.getRect(menu);
      expect(menuRect.width, greaterThanOrEqualTo(44));
      expect(menuRect.height, greaterThanOrEqualTo(44));
      expect(menuRect.left, greaterThanOrEqualTo(cardRect.left + 4));
      expect(menuRect.right, lessThanOrEqualTo(cardRect.right - 4));
      expect(tester.takeException(), isNull);

      await tester.tap(menu);
      await tester.pumpAndSettle();

      expect(find.text('تعديل'), findsOneWidget);
      expect(find.text('تعديل عميل'), findsNothing);

      await tester.tap(find.text('تعديل'));
      await tester.pumpAndSettle();

      expect(find.text('تعديل عميل'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'إلغاء'));
      await tester.pumpAndSettle();

      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(find.text('تعديل عميل'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
