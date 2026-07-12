import 'package:animal_supply_b2b/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows Arabic login screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AnimalSupplyApp()));
    expect(find.text('دخول'), findsOneWidget);
    expect(find.textContaining('تجربة سريعة'), findsOneWidget);
    expect(find.text('عميل'), findsOneWidget);
  });
}
