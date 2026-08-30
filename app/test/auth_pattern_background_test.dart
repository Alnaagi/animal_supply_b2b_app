import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/auth/login_screen.dart';
import 'package:animal_supply_b2b/src/features/auth/widgets/auth_pattern_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AuthPatternBackground renders ambient glow and pattern painter',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const AuthPatternBackground(
          child: Text('Login Content'),
        ),
      ),
    );

    expect(find.text('Login Content'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  testWidgets(
      'AuthPatternBackground harmonizes with custom theme primary color',
      (tester) async {
    const customPrimary = Color(0xffe05638);
    const customSecondary = Color(0xff8c4a2f);
    final customTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: customPrimary,
        primary: customPrimary,
        secondary: customSecondary,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: customTheme,
        home: const AuthPatternBackground(
          child: Text('Custom Theme Login'),
        ),
      ),
    );

    expect(find.text('Custom Theme Login'), findsOneWidget);
    final customPaintWidgets = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(customPaintWidgets, isNotEmpty);
    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  testWidgets('LoginScreen embeds AuthPatternBackground with frosted card',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
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

    expect(find.byType(AuthPatternBackground), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
    expect(find.byKey(const Key('login-input-theme')), findsOneWidget);
    expect(find.byKey(const Key('login-username-field')), findsOneWidget);
    expect(find.byKey(const Key('login-password-field')), findsOneWidget);
  });
}

class _FixedAuthController extends AuthController {
  _FixedAuthController() {
    state = const AuthState();
  }
}
