import 'package:animal_supply_b2b/src/core/support/customer_invite_copy.dart';
import 'package:animal_supply_b2b/src/data/local/customer_invite_template_store.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_customers/admin_customers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('invite template keeps password out of the login URL', () {
    final rendered = renderCustomerInviteTemplate(
      template:
          'مرحباً {business_name}\n{username}\n{password}\n{login_url}?password={password}',
      businessName: 'متجر الاختبار',
      shopName: 'المتجر',
      username: 'test',
      loginUrl:
          'https://animal-supply-b2b.alnaagi-ai.workers.dev/login?password=secret',
      password: 'secret',
      contactName: 'أحمد',
    );
    expect(rendered, contains('مرحباً متجر الاختبار'));
    expect(rendered, contains('test'));
    expect(rendered, contains('secret'));
    expect(
      rendered,
      contains('https://animal-supply-b2b.alnaagi-ai.workers.dev/login'),
    );
    expect(rendered, isNot(contains('password=secret')));
    expect(rendered, isNot(contains('/login?password')));
  });

  test('custom placeholders include contact name', () {
    final rendered = renderCustomerInviteTemplate(
      template: 'أهلاً {contact_name} من {business_name}. المستخدم {username}',
      businessName: 'شركة النور',
      shopName: 'المتجر',
      username: 'noor',
      loginUrl: 'https://example.ly/other',
      contactName: 'سالم',
    );
    expect(rendered, contains('أهلاً سالم من شركة النور'));
    expect(rendered, contains('المستخدم noor'));
  });

  test('invite template store round-trips locally', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = CustomerInviteTemplateStore(prefs: prefs);
    expect(await store.load(), defaultCustomerInviteTemplate);
    expect(
      await store.save('مرحباً {business_name}\n{username}\n{password}'),
      isTrue,
    );
    expect(await store.load(), contains('{username}'));
    expect(await store.reset(), isTrue);
    expect(await store.load(), defaultCustomerInviteTemplate);
  });

  testWidgets('gear edits the default invite template for later messages',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(
            AdminRepository(
              demoCustomers: const [
                BusinessCustomer(
                  id: 'customer-invite',
                  businessName: 'متجر الاختبار',
                  username: 'test',
                  phone: '+218910000001',
                ),
              ],
            ),
          ),
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

    await tester.tap(find.byKey(const Key('admin-customers-invite-template-gear')));
    await tester.pumpAndSettle();
    expect(find.text('نص دعوة واتساب الافتراضي'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('admin-invite-template-field')),
      'قالب خاص {username} {password} {login_url}',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ للدعوات الجديدة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('تم حفظ نص الدعوة'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('admin-customer-menu-customer-invite')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('رسالة ترحيب ورابط الدخول عبر واتساب'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'تجهيز الرسالة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('admin-invite-preview')), findsOneWidget);
    expect(find.textContaining('قالب خاص test'), findsWidgets);
  });

  testWidgets('pen edits greeting username and password in the preview',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(
            AdminRepository(
              demoCustomers: const [
                BusinessCustomer(
                  id: 'customer-invite',
                  businessName: 'متجر الاختبار',
                  username: 'test',
                  phone: '+218910000001',
                ),
              ],
            ),
          ),
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

    await tester.tap(find.byKey(const ValueKey('admin-customer-menu-customer-invite')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('رسالة ترحيب ورابط الدخول عبر واتساب'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'تجهيز الرسالة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('اسم المستخدم: test'), findsWidgets);
    expect(find.textContaining('كلمة المرور الحالية'), findsWidgets);

    await tester.tap(find.byKey(const Key('admin-invite-edit-pen')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('admin-invite-field-greeting')),
      'عميل التحرير',
    );
    await tester.enterText(
      find.byKey(const Key('admin-invite-field-password')),
      'Secret42',
    );
    await tester.pump();

    expect(find.textContaining('مرحباً عميل التحرير'), findsWidgets);
    expect(find.textContaining('كلمة المرور: Secret42'), findsWidgets);
    expect(find.textContaining('password=Secret42'), findsNothing);
    expect(find.text('نسخ وفتح واتساب'), findsNothing);
    expect(find.byKey(const Key('admin-invite-preview')), findsOneWidget);
  });
}
