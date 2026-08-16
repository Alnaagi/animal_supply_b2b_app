import 'package:animal_supply_b2b/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows Arabic login screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AnimalSupplyApp()));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('دخول').evaluate().isNotEmpty) break;
    }
    expect(find.text('دخول'), findsOneWidget);
    expect(find.textContaining('تجربة سريعة'), findsOneWidget);
    expect(find.text('عميل'), findsOneWidget);
  });
}
