import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/features/support/support_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('support screen renders faq and topic buttons', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: SupportScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('المساعدة والدعم'), findsOneWidget);
    expect(find.text('الأسئلة الشائعة'), findsOneWidget);
    expect(find.byKey(const Key('support-topic-order')), findsOneWidget);
    expect(find.byKey(const Key('support-topic-product')), findsOneWidget);
  });
}
