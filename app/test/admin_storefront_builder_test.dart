import 'package:animal_supply_b2b/src/core/routing/app_router.dart';
import 'package:animal_supply_b2b/src/core/theme/app_theme.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/models/storefront_config.dart';
import 'package:animal_supply_b2b/src/data/repositories/storefront_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_dashboard/admin_shell.dart';
import 'package:animal_supply_b2b/src/features/admin_storefront/admin_storefront_controller.dart';
import 'package:animal_supply_b2b/src/features/admin_storefront/admin_storefront_screen.dart';
import 'package:animal_supply_b2b/src/features/admin_storefront/widgets/storefront_inspector_panel.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('undo/redo restores draft config changes', () async {
    final repo = StorefrontRepository();
    final container = ProviderContainer(
      overrides: [
        storefrontRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final controller =
        container.read(adminStorefrontControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    final originalRadius = container
        .read(adminStorefrontControllerProvider)
        .draft
        .style
        .cardRadius;
    controller.updateStyle(
      container.read(adminStorefrontControllerProvider).draft.style.copyWith(
            cardRadius: 30,
          ),
    );
    expect(
      container.read(adminStorefrontControllerProvider).draft.style.cardRadius,
      30,
    );
    controller.undo();
    expect(
      container.read(adminStorefrontControllerProvider).draft.style.cardRadius,
      originalRadius,
    );
    controller.redo();
    expect(
      container.read(adminStorefrontControllerProvider).draft.style.cardRadius,
      30,
    );
  });

  test('draft status label reflects unsaved changes', () async {
    final container = ProviderContainer(
      overrides: [
        storefrontRepositoryProvider.overrideWithValue(StorefrontRepository()),
      ],
    );
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);
    final controller =
        container.read(adminStorefrontControllerProvider.notifier);
    expect(
      container.read(adminStorefrontControllerProvider).draftStatusLabelAr,
      'منشور ومحدّث',
    );
    controller.updateStyle(
      container.read(adminStorefrontControllerProvider).draft.style.copyWith(
            cardRadius: 12,
          ),
    );
    expect(
      container.read(adminStorefrontControllerProvider).draftStatusLabelAr,
      'مسودة غير محفوظة',
    );
  });

  test('autosave persists theme patch after debounce', () async {
    final repo = StorefrontRepository();
    final container = ProviderContainer(
      overrides: [
        storefrontRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final controller =
        container.read(adminStorefrontControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    controller.patchTheme(
      (theme) => theme.copyWith(primaryColor: const Color(0xff2563eb)),
    );
    expect(
      container.read(adminStorefrontControllerProvider).hasUnsavedChanges,
      isTrue,
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final state = container.read(adminStorefrontControllerProvider);
    expect(state.hasUnsavedChanges, isFalse);
    expect(state.draft.theme.primaryColor.toARGB32() & 0xFFFFFF, 0x2563eb);
    expect(
      state.draftStatusLabelAr,
      anyOf('مسودة محفوظة — غير منشورة', 'تم الحفظ'),
    );
  });

  test('publish after color change succeeds without manual save', () async {
    final repo = StorefrontRepository();
    final container = ProviderContainer(
      overrides: [
        storefrontRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final controller =
        container.read(adminStorefrontControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    controller.patchTheme(
      (theme) => theme.copyWith(primaryColor: const Color(0xffdc2626)),
    );
    // Publish immediately without waiting for autosave debounce.
    final ok = await controller.publish();
    expect(ok, isTrue);
    final state = container.read(adminStorefrontControllerProvider);
    expect(state.hasUnsavedChanges, isFalse);
    expect(state.hasUnpublishedChanges, isFalse);
    expect(state.published.theme.primaryColor.toARGB32() & 0xFFFFFF, 0xdc2626);
  });

  test('resetDraft restores bundled defaults', () async {
    final repo = StorefrontRepository();
    final container = ProviderContainer(
      overrides: [
        storefrontRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final controller =
        container.read(adminStorefrontControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    controller.patchTheme(
      (theme) => theme.copyWith(primaryColor: const Color(0xff2563eb)),
    );
    await controller.flushAutosave();
    final ok = await controller.resetDraft();
    expect(ok, isTrue);
    final state = container.read(adminStorefrontControllerProvider);
    expect(
      state.draft.theme.primaryColor.toARGB32(),
      StorefrontDefaults.bundled.theme.primaryColor.toARGB32(),
    );
  });

  testWidgets('staff cannot access storefront designer route', (tester) async {
    final harness = await _pumpRouter(
      tester,
      AuthState(user: _user(role: 'staff')),
    );
    addTearDown(harness.dispose);
    harness.router.go('/admin/storefront');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(harness.router.routeInformationProvider.value.uri.path, '/admin');
  });

  testWidgets('admin storefront builder shows redesigned toolbar actions',
      (tester) async {
    await _pumpBuilder(tester, width: 1400, height: 900);
    expect(find.byKey(const Key('storefront-toolbar')), findsOneWidget);
    expect(find.text('حفظ المسودة'), findsNothing);
    expect(find.text('إعادة ضبط'), findsOneWidget);
    expect(find.byKey(const Key('storefront-reset-button')), findsOneWidget);
    expect(find.text('نشر التغييرات'), findsOneWidget);
    expect(find.text('معاينة المنشور'), findsOneWidget);
    expect(
        find.byKey(const Key('storefront-draft-status-chip')), findsOneWidget);
    expect(find.text('منشور ومحدّث'), findsOneWidget);
    expect(find.byKey(const Key('storefront-undo-button')), findsOneWidget);
    expect(find.byKey(const Key('storefront-redo-button')), findsOneWidget);
    await _flushAsync(tester);
  });

  testWidgets('reset button shows confirmation dialog', (tester) async {
    await _pumpBuilder(tester, width: 1400, height: 900);
    await tester.tap(find.byKey(const Key('storefront-reset-button')));
    await tester.pumpAndSettle();
    expect(find.text('إعادة ضبط التصميم'), findsOneWidget);
    expect(find.textContaining('التصميم الافتراضي'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'إلغاء'));
    await tester.pumpAndSettle();
    await _flushAsync(tester);
  });

  testWidgets('desktop layout renders sidebar modes and preview badge',
      (tester) async {
    await _pumpBuilder(tester, width: 1400, height: 900);
    expect(find.byKey(const Key('storefront-sidebar')), findsOneWidget);
    expect(
        find.byKey(const Key('storefront-sidebar-mode-tabs')), findsOneWidget);
    expect(find.byKey(const Key('storefront-sections-list')), findsOneWidget);
    expect(find.byKey(const Key('storefront-inspector-panel')), findsOneWidget);
    expect(
        find.byKey(const Key('storefront-preview-mode-badge')), findsOneWidget);
    expect(
      find.text('وضع المعاينة — لا تُنفَّذ إجراءات السلة أو الطلبات'),
      findsOneWidget,
    );
    await _flushAsync(tester);
  });

  testWidgets('sidebar mode switching shows design and page panels',
      (tester) async {
    await _pumpBuilder(tester, width: 1400, height: 900);
    final element = tester.element(find.byType(AdminStorefrontScreen));
    final container = ProviderScope.containerOf(element);
    final controller =
        container.read(adminStorefrontControllerProvider.notifier);

    controller.setSidebarMode(StorefrontSidebarMode.design);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('storefront-design-panel')), findsOneWidget);
    expect(find.text('قوالب التصميم'), findsOneWidget);
    expect(find.text('ترتيب الأقسام'), findsNothing);

    controller.setSidebarMode(StorefrontSidebarMode.page);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('storefront-page-panel')), findsOneWidget);
    expect(find.text('جهاز المعاينة'), findsOneWidget);
    await _flushAsync(tester);
  });

  testWidgets(
      'section selection updates inspector without duplicating theme controls',
      (tester) async {
    await _pumpBuilder(tester, width: 1400, height: 900);
    final list = find.byKey(const Key('storefront-sections-list'));
    await tester.tap(find.descendant(of: list, matching: find.text('البانر')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('خيارات البانر'), findsOneWidget);
    expect(find.text('قوالب التصميم'), findsNothing);

    final tabs = find.byKey(const Key('storefront-sidebar-mode-tabs'));
    await tester.tap(find.descendant(of: tabs, matching: find.text('التصميم')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.descendant(of: tabs, matching: find.text('الأقسام')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.descendant(of: list, matching: find.text('الترحيب')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('خيارات الترحيب'), findsOneWidget);
    await _flushAsync(tester);
  });

  testWidgets('design mode with no section shows theme summary in inspector',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storefrontRepositoryProvider
              .overrideWithValue(StorefrontRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: StorefrontInspectorPanel(
              state: StorefrontBuilderState(
                loading: false,
                sidebarMode: StorefrontSidebarMode.design,
              ),
              controller: _NoopStorefrontController(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('storefront-theme-summary')), findsOneWidget);
    expect(find.text('ملخص التصميم'), findsOneWidget);
    await _flushAsync(tester);
  });

  testWidgets('compact admin nav renders on storefront builder route',
      (tester) async {
    await _pumpBuilder(tester, width: 1400, height: 900);
    expect(find.byKey(const Key('admin-compact-nav-rail')), findsOneWidget);
    await _flushAsync(tester);
  });

  testWidgets(
      'storefront builder has no empty AppBar above the demo notice',
      (tester) async {
    await _pumpBuilder(
      tester,
      width: 1400,
      height: 900,
      user: _user(role: 'admin', isDemo: true),
    );
    final adminScaffold = tester.widget<Scaffold>(
      find
          .descendant(
            of: find.byType(AdminShell),
            matching: find.byType(Scaffold),
          )
          .first,
    );
    expect(adminScaffold.appBar, isNull);
    expect(find.byKey(const Key('admin-demo-mode-notice')), findsOneWidget);
    expect(find.byKey(const Key('storefront-toolbar')), findsOneWidget);
    expect(
      find.byKey(const Key('storefront-notifications-button')),
      findsOneWidget,
    );

    final demoTop =
        tester.getTopLeft(find.byKey(const Key('admin-demo-mode-notice'))).dy;
    final toolbarTop =
        tester.getTopLeft(find.byKey(const Key('storefront-toolbar'))).dy;
    expect(demoTop, lessThan(toolbarTop));
    // Demo notice sits at the top of the content column — no sand AppBar gap.
    expect(demoTop, lessThan(8));
    await _flushAsync(tester);
  });

  testWidgets('mobile layout uses tabs instead of desktop columns',
      (tester) async {
    await _pumpBuilder(tester, width: 390, height: 844);
    expect(find.byKey(const Key('storefront-mobile-tabs')), findsOneWidget);
    expect(find.byKey(const Key('storefront-mobile-header')), findsOneWidget);
    expect(find.byKey(const Key('storefront-sidebar')), findsNothing);
    expect(find.byKey(const Key('storefront-toolbar')), findsNothing);
    expect(find.text('معاينة'), findsWidgets);
    expect(find.text('الأقسام'), findsWidgets);
    expect(find.text('التصميم'), findsWidgets);
    await _flushAsync(tester);
  });

  testWidgets('sections list has no drag-handle lines next to visibility',
      (tester) async {
    await _pumpBuilder(tester, width: 1400, height: 900);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
    expect(find.byIcon(Icons.visibility_outlined), findsWidgets);
    expect(
      find.byType(ReorderableDelayedDragStartListener),
      findsWidgets,
    );
    await _flushAsync(tester);
  });

  group('responsive storefront builder widths', () {
    for (final width in [320, 360, 390, 430, 768, 1024, 1440]) {
      testWidgets('width $width layout and overflow safety', (tester) async {
        await _pumpBuilder(tester, width: width.toDouble(), height: 844);
        await _flushAsync(tester);

        final isMobile = width < 650;
        final isTablet = width >= 650 && width < 1000;
        final isDesktop = width >= 1000;

        if (isMobile) {
          expect(
              find.byKey(const Key('storefront-mobile-tabs')), findsOneWidget);
          expect(find.byKey(const Key('storefront-mobile-header')),
              findsOneWidget);
          expect(find.byKey(const Key('storefront-sidebar')), findsNothing);
          expect(find.byKey(const Key('storefront-toolbar')), findsNothing);
          expect(
              find.byKey(
                  const Key('storefront-preview-compact-phone-portrait')),
              findsOneWidget);
          expect(
            find.byKey(const Key('storefront-preview-phone-portrait')),
            findsNothing,
          );
        }

        if (isTablet) {
          expect(find.byKey(const Key('storefront-toolbar')), findsOneWidget);
          expect(find.byKey(const Key('storefront-sidebar')), findsNothing);
        }

        if (isDesktop) {
          expect(find.byKey(const Key('storefront-sidebar')), findsOneWidget);
          expect(find.byKey(const Key('storefront-toolbar')), findsOneWidget);
        }

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('mobile shows one workspace at a time', (tester) async {
      await _pumpBuilder(tester, width: 390, height: 844);
      final element = tester.element(find.byType(AdminStorefrontScreen));
      final container = ProviderScope.containerOf(element);
      final controller =
          container.read(adminStorefrontControllerProvider.notifier);

      expect(find.byKey(const Key('storefront-design-panel')), findsNothing);
      expect(find.byKey(const Key('storefront-sections-list')), findsNothing);

      controller.setMobileTab(StorefrontBuilderTab.sections);
      await tester.pump();
      expect(find.byKey(const Key('storefront-sections-list')), findsOneWidget);
      expect(find.byKey(const Key('storefront-design-panel')), findsNothing);

      controller.setMobileTab(StorefrontBuilderTab.design);
      await tester.pump();
      expect(find.byKey(const Key('storefront-design-panel')), findsOneWidget);
      expect(find.byKey(const Key('storefront-sections-list')), findsNothing);

      await _flushAsync(tester);
    });

    testWidgets('mobile preview settings bottom sheet opens', (tester) async {
      await _pumpBuilder(tester, width: 390, height: 844);
      await tester
          .tap(find.byKey(const Key('storefront-preview-settings-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('storefront-preview-settings-sheet')),
          findsOneWidget);
      expect(find.text('إعدادات المعاينة'), findsOneWidget);
      expect(find.text('المنشور'), findsWidgets);
      expect(find.text('هاتف'), findsOneWidget);
      expect(find.text('سطح المكتب'), findsOneWidget);
      expect(find.text('تابلت'), findsNothing);
      expect(find.text('رأسي'), findsNothing);
      expect(find.text('أفقي'), findsNothing);
      await _flushAsync(tester);
    });

    testWidgets('phone preview shows customer shell chrome', (tester) async {
      await _pumpBuilder(tester, width: 1400, height: 900);
      expect(
        find.byKey(const Key('customer-preview-shell-scaffold')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('customer-mobile-app-bar')), findsOneWidget);
      expect(
        find.byKey(const Key('customer-bottom-navigation')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('customer-navigation-rail')), findsNothing);
      await _flushAsync(tester);
    });

    testWidgets('desktop preview uses wide constraints and desktop chrome',
        (tester) async {
      await _pumpBuilder(tester, width: 1400, height: 900);
      final element = tester.element(find.byType(AdminStorefrontScreen));
      final container = ProviderScope.containerOf(element);
      container
          .read(adminStorefrontControllerProvider.notifier)
          .setPreviewDevice(StorefrontPreviewDevice.desktop);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(const Key('storefront-preview-desktop')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('customer-preview-shell-scaffold')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('customer-desktop-app-bar')), findsOneWidget);
      expect(find.byKey(const Key('customer-navigation-rail')), findsOneWidget);
      expect(find.byKey(const Key('customer-bottom-navigation')), findsNothing);

      final previewContext = tester.element(
        find.byKey(const Key('customer-preview-shell-scaffold')),
      );
      expect(MediaQuery.sizeOf(previewContext).width, 1200);
      expect(
        MediaQuery.sizeOf(previewContext).width,
        greaterThanOrEqualTo(AppBreakpoints.expanded),
      );

      final frame = tester.getRect(
        find.byKey(const Key('storefront-preview-desktop')),
      );
      // Preview must fill most of the canvas — no large beige dead zone below.
      expect(frame.height, greaterThan(500));
      expect(frame.height / 900, greaterThan(0.55));
      await _flushAsync(tester);
    });

    testWidgets('device switcher offers only phone and desktop', (tester) async {
      await _pumpBuilder(tester, width: 1400, height: 900);
      expect(StorefrontPreviewDevice.values, hasLength(2));
      expect(
        StorefrontPreviewDevice.values.map((d) => d.name).toList(),
        ['phone', 'desktop'],
      );
      expect(
        find.byKey(const Key('storefront-preview-device-phone')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('storefront-preview-device-desktop')),
        findsOneWidget,
      );
      expect(find.text('تابلت'), findsNothing);
      expect(find.text('أفقي'), findsNothing);
      await _flushAsync(tester);
    });

    testWidgets(
        'mobile has no sticky save bar; shows reset and autosave status',
        (tester) async {
      await _pumpBuilder(tester, width: 390, height: 844);
      expect(find.byKey(const Key('storefront-mobile-save-bar')), findsNothing);
      expect(find.text('حفظ المسودة'), findsNothing);
      expect(find.byKey(const Key('storefront-mobile-reset')), findsOneWidget);

      final element = tester.element(find.byType(AdminStorefrontScreen));
      final container = ProviderScope.containerOf(element);
      container.read(adminStorefrontControllerProvider.notifier).updateStyle(
            container
                .read(adminStorefrontControllerProvider)
                .draft
                .style
                .copyWith(cardRadius: 18),
          );
      await tester.pump();
      expect(find.text('مسودة غير محفوظة'), findsWidgets);
      expect(find.byKey(const Key('storefront-mobile-save-bar')), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      await _flushAsync(tester);
    });

    testWidgets('mobile publish and undo accessible from header',
        (tester) async {
      await _pumpBuilder(tester, width: 360, height: 844);
      expect(
          find.byKey(const Key('storefront-mobile-publish')), findsOneWidget);
      expect(find.byKey(const Key('storefront-undo-button')), findsOneWidget);
      expect(find.byKey(const Key('storefront-redo-button')), findsOneWidget);
      await _flushAsync(tester);
    });

    testWidgets('mobile design tab preview FAB switches tab', (tester) async {
      await _pumpBuilder(tester, width: 430, height: 844);
      final element = tester.element(find.byType(AdminStorefrontScreen));
      final container = ProviderScope.containerOf(element);
      container
          .read(adminStorefrontControllerProvider.notifier)
          .setMobileTab(StorefrontBuilderTab.design);
      await tester.pump();
      await tester.tap(find.byKey(const Key('storefront-mobile-preview-fab')));
      await tester.pump();
      expect(
        container.read(adminStorefrontControllerProvider).mobileTab,
        StorefrontBuilderTab.preview,
      );
      await _flushAsync(tester);
    });
  });
}

class _FixedAuthController extends AuthController {
  _FixedAuthController(AuthState initial) {
    state = initial;
  }
}

class _NoopStorefrontController extends AdminStorefrontController {
  _NoopStorefrontController() : super(StorefrontRepository(), autoLoad: false);
}

Future<void> _pumpBuilder(
  WidgetTester tester, {
  required double width,
  required double height,
  AppUser? user,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => _FixedAuthController(
              AuthState(user: user ?? _user(role: 'admin')),
            )),
        storefrontRepositoryProvider.overrideWithValue(StorefrontRepository()),
        adminStorefrontControllerProvider.overrideWith(
          (ref) => AdminStorefrontController(
            ref.watch(storefrontRepositoryProvider),
            autoLoad: false,
          )..state = StorefrontBuilderState(loading: false),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, height)),
          child: const Directionality(
            textDirection: TextDirection.rtl,
            child: AdminStorefrontScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _flushAsync(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(tester.takeException(), isNull);
}

AppUser _user({required String role, bool isDemo = false}) => AppUser(
      id: '$role-profile',
      username: role,
      role: role,
      accountStatus: 'active',
      isDemo: isDemo,
    );

Future<_RouterHarness> _pumpRouter(
  WidgetTester tester,
  AuthState authState,
) async {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        (ref) => _FixedAuthController(authState),
      ),
    ],
  );
  final router = container.read(appRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return _RouterHarness(container: container, router: router);
}

class _RouterHarness {
  _RouterHarness({required this.container, required this.router});

  final ProviderContainer container;
  final GoRouter router;

  void dispose() {
    router.dispose();
    container.dispose();
  }
}
