import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/storefront_config.dart';
import 'package:animal_supply_b2b/src/data/repositories/notifications_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/storefront_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_dashboard/admin_shell.dart';
import 'package:animal_supply_b2b/src/features/admin_storefront/admin_storefront_controller.dart';
import 'package:animal_supply_b2b/src/features/admin_storefront/apply_storefront_theme_to_admin.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/storefront/storefront_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('storefront theme scope does not mutate global AppTheme.light',
      (tester) async {
    const warm = StorefrontThemeConfig(
      preset: StorefrontThemePreset.warm,
      primaryColor: Color(0xffb45309),
      backgroundColor: Color(0xfffdf6ec),
      textColor: Color(0xff3f2a14),
    );
    final config = StorefrontDefaults.bundled.copyWith(theme: warm);
    late ThemeData scopedTheme;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StorefrontThemeScope(
          config: config,
          child: Builder(
            builder: (context) {
              scopedTheme = Theme.of(context);
              return Text(
                'primary:${scopedTheme.colorScheme.primary.toARGB32()}',
                key: const Key('scoped-theme'),
              );
            },
          ),
        ),
      ),
    );

    expect(AppTheme.light.colorScheme.primary, AppTheme.green);
    expect(scopedTheme.colorScheme.primary, warm.primaryColor);
    expect(scopedTheme.scaffoldBackgroundColor, warm.backgroundColor);
    expect(scopedTheme.cardTheme.color, warm.cardColor);
  });

  test('storefront buttons keep readable foregrounds for light brand colors',
      () {
    final lightTheme = storefrontThemeData(
      StorefrontDefaults.bundled.copyWith(
        theme: const StorefrontThemeConfig(
          primaryColor: Color(0xffffef76),
          secondaryColor: Color(0xfff7d6a3),
        ),
      ),
    );
    final darkTheme = storefrontThemeData(
      StorefrontDefaults.bundled.copyWith(
        theme: const StorefrontThemeConfig(
          primaryColor: Color(0xff163b2f),
          secondaryColor: Color(0xff5b351b),
        ),
      ),
    );

    expect(lightTheme.colorScheme.onPrimary, AppTheme.darkGreen);
    expect(lightTheme.colorScheme.onSecondary, AppTheme.darkGreen);
    expect(darkTheme.colorScheme.onPrimary, Colors.white);
    expect(darkTheme.colorScheme.onSecondary, Colors.white);
  });

  test('mid-tone brand colors receive WCAG-readable action foregrounds', () {
    const mediumBlue = Color(0xff0088ff);
    final config = StorefrontDefaults.bundled.copyWith(
      theme: const StorefrontThemeConfig(primaryColor: mediumBlue),
    );
    final theme = storefrontThemeData(config);
    final outlinedForeground =
        theme.outlinedButtonTheme.style?.foregroundColor?.resolve({});

    expect(theme.colorScheme.onPrimary, Colors.black);
    expect(
      config.theme.contrastRatio(
        theme.colorScheme.onPrimary,
        mediumBlue,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(outlinedForeground, isNotNull);
    expect(
      config.theme.contrastRatio(
        outlinedForeground!,
        config.theme.cardColor,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('admin shell inherits storefront primary when toggle is off',
      (tester) async {
    const draftPrimary = Color(0xffb45309);
    final harness = _AdminThemeHarness(draftPrimary: draftPrimary);
    addTearDown(harness.container.dispose);

    await tester.pumpWidget(harness.build());
    await tester.pump();

    expect(
        harness.container.read(applyStorefrontThemeToAdminProvider), isFalse);
    expect(harness.container.read(adminShellStorefrontThemeProvider), isNull);

    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    expect(
        Theme.of(scaffoldContext).colorScheme.primary,
        StorefrontDefaults.bundled.theme.primaryColor,
    );
  });

  testWidgets('admin shell keeps standard admin colors when toggle is on',
      (tester) async {
    const draftPrimary = Color(0xffb45309);
    SharedPreferences.setMockInitialValues({
      ApplyStorefrontThemeToAdminPrefs.storageKey: true,
    });
    final harness = _AdminThemeHarness(draftPrimary: draftPrimary);
    addTearDown(harness.container.dispose);

    await harness.container
        .read(applyStorefrontThemeToAdminProvider.notifier)
        .reload();
    expect(harness.container.read(applyStorefrontThemeToAdminProvider), isTrue);

    await tester.pumpWidget(harness.build());
    await tester.pump();

    expect(
      harness.container
          .read(adminShellStorefrontThemeProvider)
          ?.colorScheme
          .primary,
      AppTheme.light.colorScheme.primary,
    );

    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    expect(
      Theme.of(scaffoldContext).colorScheme.primary,
      AppTheme.light.colorScheme.primary,
    );

    await harness.container
        .read(applyStorefrontThemeToAdminProvider.notifier)
        .setEnabled(false);
    await tester.pump();

    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary,
      StorefrontDefaults.bundled.theme.primaryColor,
    );
  });

  testWidgets('custom admin colors apply to admin shell when toggle is on',
      (tester) async {
    const customAdminPrimary = Color(0xff2563eb);
    const customAdminBg = Color(0xfff1f5f9);
    const customAdminSurface = Color(0xffffffff);
    const customAdminText = Color(0xff0f172a);

    SharedPreferences.setMockInitialValues({
      ApplyStorefrontThemeToAdminPrefs.storageKey: true,
      ApplyStorefrontThemeToAdminPrefs.adminThemeStorageKey:
          '{"primary":"#2563eb","background":"#f1f5f9","surface":"#ffffff","text":"#0f172a"}',
    });
    final harness = _AdminThemeHarness(draftPrimary: const Color(0xffb45309));
    addTearDown(harness.container.dispose);

    await harness.container
        .read(applyStorefrontThemeToAdminProvider.notifier)
        .reload();
    await harness.container
        .read(adminCustomThemeConfigProvider.notifier)
        .reload();

    await tester.pumpWidget(harness.build());
    await tester.pump();

    final scaffoldContext = tester.element(find.byType(Scaffold).first);
    expect(
      Theme.of(scaffoldContext).colorScheme.primary,
      customAdminPrimary,
    );
    expect(
      Theme.of(scaffoldContext).scaffoldBackgroundColor,
      customAdminBg,
    );
    expect(
      Theme.of(scaffoldContext).colorScheme.surface,
      customAdminSurface,
    );
    expect(
      Theme.of(scaffoldContext).colorScheme.onSurface,
      customAdminText,
    );
  });

  test('apply-to-admin preference and custom theme persist in SharedPreferences',
      () async {
    final store = ApplyStorefrontThemeToAdminPrefs();
    expect(await store.load(), isFalse);
    expect(await store.save(true), isTrue);
    expect(await store.load(), isTrue);
    expect(await store.save(false), isTrue);
    expect(await store.load(), isFalse);

    // Custom theme persistence
    expect(await store.loadAdminTheme(), AdminThemeConfig.standard);
    const customTheme = AdminThemeConfig(
      primaryColor: Color(0xff2563eb),
      backgroundColor: Color(0xfff8fafc),
      surfaceColor: Color(0xffffffff),
      textColor: Color(0xff0f172a),
    );
    expect(await store.saveAdminTheme(customTheme), isTrue);
    final loaded = await store.loadAdminTheme();
    expect(loaded.primaryColor, customTheme.primaryColor);
    expect(loaded.backgroundColor, customTheme.backgroundColor);
    expect(loaded.surfaceColor, customTheme.surfaceColor);
    expect(loaded.textColor, customTheme.textColor);

    // Reset to standard removes key
    expect(await store.saveAdminTheme(AdminThemeConfig.standard), isTrue);
    expect(await store.loadAdminTheme(), AdminThemeConfig.standard);
  });
}

class _AdminThemeHarness {
  _AdminThemeHarness({required this.draftPrimary}) {
    final draft = StorefrontDefaults.bundled.copyWith(
      theme: StorefrontThemeConfig(
        preset: StorefrontThemePreset.warm,
        primaryColor: draftPrimary,
        backgroundColor: const Color(0xfffdf6ec),
        textColor: const Color(0xff3f2a14),
      ),
    );
    final prefs = ApplyStorefrontThemeToAdminPrefs();
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((ref) => _AdminAuth()),
        unreadNotificationsCountProvider.overrideWith((ref) async => 0),
        storefrontRepositoryProvider.overrideWithValue(
          StorefrontRepository(demoDraft: draft),
        ),
        applyStorefrontThemeToAdminPrefsProvider.overrideWithValue(prefs),
        applyStorefrontThemeToAdminProvider.overrideWith(
          (ref) => ApplyStorefrontThemeToAdminController(prefs),
        ),
        adminCustomThemeConfigProvider.overrideWith(
          (ref) => AdminCustomThemeController(prefs),
        ),
        adminStorefrontControllerProvider.overrideWith(
          (ref) => AdminStorefrontController(
            ref.watch(storefrontRepositoryProvider),
            autoLoad: false,
          )..state = StorefrontBuilderState(loading: false, draft: draft),
        ),
      ],
    );
  }

  final Color draftPrimary;
  late final ProviderContainer container;

  Widget build() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: storefrontThemeData(StorefrontDefaults.bundled),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: AdminShell(
            title: 'اختبار',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _AdminAuth extends AuthController {
  _AdminAuth() {
    state = const AuthState(
      user: AppUser(
        id: 'admin-theme-isolation',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}
