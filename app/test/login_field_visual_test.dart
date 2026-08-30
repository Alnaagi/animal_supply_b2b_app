import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login fields use clear RTL-friendly visual styling',
      (tester) async {
    tester.view.physicalSize = const Size(392, 838);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FixedAuthController(),
          ),
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

    final loginTheme = tester.widget<Theme>(
      find.byKey(const Key('login-input-theme')),
    );
    final decoration = loginTheme.data.inputDecorationTheme;
    final enabledBorder = decoration.enabledBorder! as OutlineInputBorder;
    final focusedBorder = decoration.focusedBorder! as OutlineInputBorder;
    final errorBorder = decoration.errorBorder! as OutlineInputBorder;

    final expectedFill = Color.alphaBlend(
      AppTheme.green.withValues(alpha: 0.04),
      AppTheme.light.colorScheme.surface,
    );
    final expectedBorder = Color.alphaBlend(
      AppTheme.green.withValues(alpha: 0.18),
      AppTheme.light.colorScheme.outlineVariant,
    );

    expect(decoration.filled, isTrue);
    expect(decoration.fillColor, expectedFill);
    expect(decoration.helperMaxLines, 2);
    expect(decoration.prefixIconColor, AppTheme.green);
    expect(enabledBorder.borderSide.color, expectedBorder);
    expect(enabledBorder.borderSide.width, 1.25);
    expect(enabledBorder.borderRadius.topLeft.x, 16);
    expect(focusedBorder.borderSide.color, AppTheme.green);
    expect(focusedBorder.borderSide.width, 2);
    expect(errorBorder.borderSide.color, AppTheme.red);

    final usernameField = tester.widget<TextField>(
      find.byKey(const Key('login-username-field')),
    );
    expect(
      usernameField.decoration?.labelText,
      'اسم المستخدم أو رقم الهاتف',
    );
    expect(usernameField.decoration?.helperText, isNull);
    expect(find.textContaining('واتساب'), findsNothing);
    expect(find.byKey(const Key('login-invite-field')), findsNothing);
    expect(find.text('رمز الدعوة'), findsNothing);
    expect(find.text('اسم المستخدم أو البريد'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('login-username-field'))).dy,
      lessThan(
          tester.getTopLeft(find.byKey(const Key('login-password-field'))).dy),
    );
    expect(
      Directionality.of(
        tester.element(find.byKey(const Key('login-username-field'))),
      ),
      TextDirection.rtl,
    );
  });
}

class _FixedAuthController extends AuthController {
  _FixedAuthController() {
    state = const AuthState();
  }
}
