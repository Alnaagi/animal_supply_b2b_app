import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/data/models/storefront_config.dart';
import 'package:animal_supply_b2b/src/data/repositories/storefront_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_storefront/admin_storefront_controller.dart';
import 'package:animal_supply_b2b/src/features/admin_storefront/apply_storefront_theme_to_admin.dart';
import 'package:animal_supply_b2b/src/features/admin_storefront/widgets/storefront_color_picker_sheet.dart';
import 'package:animal_supply_b2b/src/features/admin_storefront/widgets/storefront_design_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('storefront hex helpers', () {
    test('formats color as #rrggbb lowercase', () {
      expect(
        storefrontColorToHex(const Color(0xff146c4e)),
        '#146c4e',
      );
      expect(
        storefrontColorToHex(const Color(0xfff5f0e8)),
        '#f5f0e8',
      );
    });

    test('parses standard and RTL-mangled hex', () {
      expect(
        storefrontColorFromHex('#146c4e')?.toARGB32(),
        const Color(0xff146c4e).toARGB32(),
      );
      expect(
        storefrontColorFromHex('f5f0e8#')?.toARGB32(),
        const Color(0xfff5f0e8).toARGB32(),
      );
      expect(
        storefrontColorFromHex('146C4E')?.toARGB32(),
        const Color(0xff146c4e).toARGB32(),
      );
      expect(storefrontColorFromHex('bad'), isNull);
      expect(storefrontColorFromHex('#12'), isNull);
    });
  });

  testWidgets('tapping color swatch opens picker sheet', (tester) async {
    late AdminStorefrontController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storefrontRepositoryProvider
              .overrideWithValue(StorefrontRepository()),
          adminStorefrontControllerProvider.overrideWith((ref) {
            controller = AdminStorefrontController(
              ref.watch(storefrontRepositoryProvider),
              autoLoad: false,
            )..state = StorefrontBuilderState(loading: false);
            return controller;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(adminStorefrontControllerProvider);
                  return StorefrontDesignPanel(
                    state: state,
                    controller:
                        ref.read(adminStorefrontControllerProvider.notifier),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('#146c4e'), findsOneWidget);
    expect(find.text('#f7f2ea'), findsOneWidget);
    // Must not reverse as f7f2ea# in the editable value.
    final bgHex = tester.widget<TextField>(
        find.byKey(const Key('storefront-color-hex-background')));
    expect(bgHex.controller?.text, '#f7f2ea');

    await tester.tap(find.byKey(const Key('storefront-color-swatch-primary')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('storefront-color-picker-sheet-primary')),
      findsOneWidget,
    );
    expect(
        find.byKey(const Key('storefront-color-picker-hex')), findsOneWidget);
    expect(find.text('ألوان سريعة'), findsOneWidget);
  });

  testWidgets('picker preset applies color to draft theme', (tester) async {
    late AdminStorefrontController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storefrontRepositoryProvider
              .overrideWithValue(StorefrontRepository()),
          adminStorefrontControllerProvider.overrideWith((ref) {
            controller = AdminStorefrontController(
              ref.watch(storefrontRepositoryProvider),
              autoLoad: false,
            )..state = StorefrontBuilderState(loading: false);
            return controller;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(adminStorefrontControllerProvider);
                  return StorefrontDesignPanel(
                    state: state,
                    controller:
                        ref.read(adminStorefrontControllerProvider.notifier),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('storefront-color-swatch-primary')));
    await tester.pumpAndSettle();

    // Tap the blue preset (#2563eb) — 7th in kStorefrontColorPresets.
    final presetBlue = find.byWidgetPredicate(
      (widget) =>
          widget is Material &&
          widget.color == const Color(0xff2563eb) &&
          widget.shape is RoundedRectangleBorder,
    );
    expect(presetBlue, findsOneWidget);
    await tester.tap(presetBlue);
    await tester.pump();

    expect(
      controller.state.draft.theme.primaryColor.toARGB32(),
      const Color(0xff2563eb).toARGB32(),
    );
    expect(controller.state.hasUnsavedChanges, isTrue);

    await tester.tap(find.byKey(const Key('storefront-color-picker-done')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('storefront-color-picker-sheet-primary')),
      findsNothing,
    );
  });

  testWidgets('Arabic color labels stay fully readable in narrow sidebar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storefrontRepositoryProvider
              .overrideWithValue(StorefrontRepository()),
          adminStorefrontControllerProvider.overrideWith((ref) {
            return AdminStorefrontController(
              ref.watch(storefrontRepositoryProvider),
              autoLoad: false,
            )..state = StorefrontBuilderState(loading: false);
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: 300,
                child: Consumer(
                  builder: (context, ref, _) {
                    final state = ref.watch(adminStorefrontControllerProvider);
                    return StorefrontDesignPanel(
                      state: state,
                      controller:
                          ref.read(adminStorefrontControllerProvider.notifier),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    const labels = [
      'اللون الأساسي',
      'اللون الثانوي',
      'لون النص',
      'خلفية الصفحة',
      'لون البطاقات',
    ];
    for (final label in labels) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.maxLines, 2);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.softWrap, isTrue);
    }

    // Sidebar content width leaves HEX compact so labels keep flex space.
    final hexBox = tester.getSize(
      find.byKey(const Key('storefront-color-hex-primary')),
    );
    expect(hexBox.width, lessThanOrEqualTo(84));
  });

  testWidgets('inline hex entry updates draft in LTR field', (tester) async {
    late AdminStorefrontController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storefrontRepositoryProvider
              .overrideWithValue(StorefrontRepository()),
          adminStorefrontControllerProvider.overrideWith((ref) {
            controller = AdminStorefrontController(
              ref.watch(storefrontRepositoryProvider),
              autoLoad: false,
            )..state = StorefrontBuilderState(loading: false);
            return controller;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(adminStorefrontControllerProvider);
                  return StorefrontDesignPanel(
                    state: state,
                    controller:
                        ref.read(adminStorefrontControllerProvider.notifier),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final hexField = find.byKey(const Key('storefront-color-hex-text'));
    await tester.enterText(hexField, '#0f172a');
    await tester.pump();

    expect(
      controller.state.draft.theme.textColor.toARGB32(),
      const Color(0xff0f172a).toARGB32(),
    );
  });

  testWidgets('admin panel color fields reveal when separate colors toggle is on',
      (tester) async {
    final repo = StorefrontRepository(demoDraft: StorefrontDefaults.bundled);
    final controller = AdminStorefrontController(repo, autoLoad: false)
      ..state = StorefrontBuilderState(
        loading: false,
        draft: StorefrontDefaults.bundled,
      );
    final prefs = ApplyStorefrontThemeToAdminPrefs();
    final container = ProviderContainer(
      overrides: [
        storefrontRepositoryProvider.overrideWithValue(repo),
        adminStorefrontControllerProvider.overrideWith((ref) => controller),
        applyStorefrontThemeToAdminPrefsProvider.overrideWithValue(prefs),
        applyStorefrontThemeToAdminProvider.overrideWith(
          (ref) => ApplyStorefrontThemeToAdminController(prefs),
        ),
        adminCustomThemeConfigProvider.overrideWith(
          (ref) => AdminCustomThemeController(prefs),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(adminStorefrontControllerProvider);
                  return StorefrontDesignPanel(
                    state: state,
                    controller:
                        ref.read(adminStorefrontControllerProvider.notifier),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Toggle is OFF by default -> admin color customizer section not visible
    expect(
      find.byKey(const Key('admin-theme-customizer-section')),
      findsNothing,
    );

    // Turn toggle ON
    await tester.tap(find.byKey(const Key('storefront-separate-admin-colors')));
    await tester.pumpAndSettle();

    // Now admin color customizer section is visible
    expect(
      find.byKey(const Key('admin-theme-customizer-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('storefront-color-hex-admin-primary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('storefront-color-hex-admin-background')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('storefront-color-hex-admin-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('storefront-color-hex-admin-text')),
      findsOneWidget,
    );

    // Change admin primary color via hex input
    final adminPrimaryHex =
        find.byKey(const Key('storefront-color-hex-admin-primary'));
    await tester.enterText(adminPrimaryHex, '#2563eb');
    await tester.pump();

    final adminTheme = container.read(adminCustomThemeConfigProvider);
    expect(adminTheme.primaryColor.toARGB32(), const Color(0xff2563eb).toARGB32());

    // Tap reset admin colors button
    await tester.ensureVisible(find.byKey(const Key('storefront-admin-reset-colors')));
    await tester.tap(find.byKey(const Key('storefront-admin-reset-colors')));
    await tester.pumpAndSettle();

    final resetTheme = container.read(adminCustomThemeConfigProvider);
    expect(resetTheme.primaryColor.toARGB32(), AdminThemeConfig.standard.primaryColor.toARGB32());
  });
}
