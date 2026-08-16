import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/core/widgets/product_info_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'narrow RTL wrap keeps whole Arabic chips on one line instead of clipping',
    (tester) async {
      const leftover = ValueKey('leftover-stock-chip');
      const box = ValueKey('box-units-chip');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 168,
                  child: ProductChipWrap(
                    children: [
                      ProductInfoChip(
                        'يبقى ظاهراً عند النفاد',
                        color: Colors.blueGrey,
                      ),
                      ProductInfoChip(
                        key: leftover,
                        'متوفر 11',
                        color: Colors.blueGrey,
                      ),
                      ProductInfoChip(
                        key: box,
                        '10 في الصندوق',
                        color: Colors.blueGrey,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('يبقى ظاهراً عند النفاد'), findsOneWidget);
      expect(find.text('متوفر 11'), findsOneWidget);
      expect(find.text('10 في الصندوق'), findsOneWidget);

      final leftoverSize = tester.getSize(find.byKey(leftover));
      final boxSize = tester.getSize(find.byKey(box));
      expect(leftoverSize.height, lessThan(32));
      expect(boxSize.height, lessThan(32));
      expect(leftoverSize.width, greaterThan(72));
      expect(boxSize.width, greaterThan(72));

      final leftoverRect = tester.getRect(find.byKey(leftover));
      final boxRect = tester.getRect(find.byKey(box));
      expect(
        leftoverRect.top != boxRect.top || leftoverRect.left != boxRect.left,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
