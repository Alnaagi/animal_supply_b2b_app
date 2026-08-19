import 'package:animal_supply_b2b/src/core/localization/arabic_copy.dart';
import 'package:animal_supply_b2b/src/core/support/customer_invite_copy.dart';
import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/core/widgets/network_status.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('welcome message keeps credentials and a login URL only', () {
    final withPassword = customerWhatsappWelcomeMessage(
      businessName: 'متجر الاختبار',
      shopName: 'متجر أعلاف',
      username: 'test',
      loginUrl: 'https://animal-supply-b2b.alnaagi-ai.workers.dev/login',
      temporaryPassword: 'test',
    );
    expect(withPassword, contains('اسم المستخدم: test'));
    expect(withPassword, contains('كلمة المرور: test'));
    expect(
      withPassword,
      contains('https://animal-supply-b2b.alnaagi-ai.workers.dev/login'),
    );
    expect(withPassword, isNot(contains('download')));
    expect(withPassword, isNot(contains('invite')));
    expect(withPassword, isNot(contains('تفعيل الحساب')));
    expect(withPassword, isNot(contains('تغيير كلمة المرور')));

    final reminder = customerWhatsappWelcomeMessage(
      businessName: 'متجر الاختبار',
      shopName: 'متجر أعلاف',
      username: 'test',
      loginUrl: 'https://animal-supply-b2b.alnaagi-ai.workers.dev/login',
    );
    expect(reminder, contains('اسم المستخدم: test'));
    expect(reminder, isNot(contains('كلمة المرور المؤقتة')));
    expect(reminder, contains('كلمة المرور الحالية'));
  });

  test('login reminder does not invent a password or reset credentials', () {
    final result = AdminRepository().composeLoginReminder(
      const BusinessCustomer(
        id: 'customer-1',
        businessName: 'متجر الاختبار',
        username: 'test',
        phone: '+218910000001',
      ),
    );
    expect(result.temporaryPassword, isEmpty);
    expect(result.whatsappMessage, contains('test'));
    expect(result.whatsappMessage, isNot(contains('كلمة المرور: test')));
    expect(result.whatsappMessage, contains('كلمة المرور الحالية'));
    expect(result.whatsappMessage, isNot(contains('invite')));
  });

  test(
      'login reminder includes a session-known password without putting it in the URL',
      () {
    final result = AdminRepository().composeLoginReminder(
      const BusinessCustomer(
        id: 'customer-1',
        businessName: 'متجر الاختبار',
        username: 'test',
        phone: '+218910000001',
      ),
      knownPassword: 'test',
    );
    expect(result.temporaryPassword, 'test');
    expect(result.whatsappMessage, contains('كلمة المرور: test'));
    expect(result.whatsappMessage, isNot(contains('password=test')));
  });

  testWidgets('login overlay appears while verifying credentials',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _LoadingAuth()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: LoginScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('branded-auth-loading')), findsOneWidget);
    expect(find.text(ArabicCopy.loginVerifying), findsOneWidget);
    expect(find.textContaining('لا تستخدم البريد'), findsNothing);
  });

  testWidgets('offline card explains cached data and deferred sync',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: OfflineStatusCard(onRetry: _noop),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('offline-status-card')), findsOneWidget);
    expect(find.text(ArabicCopy.offlineTitle), findsOneWidget);
    expect(find.textContaining('المزامنة مؤجلة'), findsOneWidget);
    expect(find.text(ArabicCopy.offlineRetry), findsOneWidget);
  });
}

void _noop() {}

class _LoadingAuth extends AuthController {
  _LoadingAuth() {
    state = const AuthState(loading: true);
  }
}
