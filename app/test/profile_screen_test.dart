import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('customer profile hides discount, credit, and balance cards',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _CustomerAuth()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: ProfileScreen()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('متجر الاختبار'), findsWidgets);
    expect(find.text('خصم جميع المنتجات'), findsNothing);
    expect(find.text('حد الائتمان'), findsNothing);
    expect(find.text('الرصيد المستحق'), findsNothing);
  });
}

class _CustomerAuth extends AuthController {
  _CustomerAuth() {
    state = const AuthState(
      user: AppUser(
        id: 'profile-1',
        username: 'customer',
        role: 'customer',
        businessName: 'متجر الاختبار',
        customerId: 'customer-1',
        city: 'طرابلس',
      ),
    );
  }
}
