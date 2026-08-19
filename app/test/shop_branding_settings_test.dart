import 'package:animal_supply_b2b/src/core/config/app_config.dart';
import 'package:animal_supply_b2b/src/core/config/shop_branding.dart';
import 'package:animal_supply_b2b/src/core/config/shop_branding_cache.dart';
import 'package:animal_supply_b2b/src/core/support/customer_invite_copy.dart';
import 'package:animal_supply_b2b/src/data/models/admin_models.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/features/admin_dashboard/admin_shell.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/auth/login_screen.dart';
import 'package:animal_supply_b2b/src/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    ShopBrandingCache.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  test('settings shop name and logo round-trip through app_settings keys', () {
    const settings = AppSettingsData(
      shopName: 'مؤسسة النور للأعلاف',
      shopLogoUrl: 'https://cdn.example.ly/logos/store.png',
    );
    final restored = AppSettingsData.fromKeyValues(settings.toKeyValues());
    expect(restored.shopName, 'مؤسسة النور للأعلاف');
    expect(restored.shopLogoUrl, 'https://cdn.example.ly/logos/store.png');
  });

  test('empty shop name falls back and unsafe logo URLs are dropped', () {
    final branding = ShopBranding.fromSettings(
      const AppSettingsData(
        shopName: '   ',
        shopLogoUrl: 'http://insecure.example/logo.png',
      ),
    );
    expect(branding.shopName, AppConfig.shopName);
    expect(branding.logoUrl, isNull);
  });

  test('cached shop name is used before app_settings load', () async {
    SharedPreferences.setMockInitialValues({
      ShopBrandingCache.namePrefsKey: 'مؤسسة النور للأعلاف',
    });
    await ShopBrandingCache.load();
    expect(ShopBrandingCache.current.shopName, 'مؤسسة النور للأعلاف');
    expect(ShopBrandingCache.resolve(null).shopName, 'مؤسسة النور للأعلاف');
  });

  test('saved shop name wins over a stale settings snapshot', () {
    ShopBrandingCache.syncFromRemote(
      const ShopBranding(shopName: 'الاسم القديم'),
    );
    ShopBrandingCache.rememberSaved(
      const ShopBranding(shopName: 'مؤسسة النور للأعلاف'),
    );
    expect(
      ShopBrandingCache.resolve(
        const AppSettingsData(shopName: 'الاسم القديم'),
      ).shopName,
      'مؤسسة النور للأعلاف',
    );
    expect(
      ShopBrandingCache.resolve(
        const AppSettingsData(shopName: 'مؤسسة النور للأعلاف'),
      ).shopName,
      'مؤسسة النور للأعلاف',
    );
  });

  test('invite copy substitutes the live shop name', () {
    final message = customerWhatsappWelcomeMessage(
      businessName: 'شركة الاختبار',
      shopName: 'مؤسسة النور للأعلاف',
      username: 'noor',
      loginUrl: 'https://example.ly/login',
      temporaryPassword: 'secret',
    );
    expect(message, contains('أهلاً بكم في مؤسسة النور للأعلاف'));
    expect(message, isNot(contains('متجر أعلاف ومستلزمات الحيوانات')));
    expect(defaultCustomerInviteTemplate, contains('{shop_name}'));
  });

  testWidgets('login title follows app_settings shop name', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _IdleAuth()),
          appSettingsProvider.overrideWith(
            (ref) async => const AppSettingsData(
              shopName: 'مؤسسة النور للأعلاف',
            ),
          ),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: LoginScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('مؤسسة النور للأعلاف'), findsWidgets);
    expect(
      find.textContaining(
          'مرحباً بك في منصة طلبات الجملة لدى مؤسسة النور للأعلاف'),
      findsOneWidget,
    );
  });

  testWidgets('admin sidebar header uses the live store name', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/admin',
      routes: [
        GoRoute(
          path: '/admin',
          builder: (context, state) => const AdminShell(
            title: 'لوحة الإدارة',
            child: SizedBox.shrink(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _AdminAuth()),
          appSettingsProvider.overrideWith(
            (ref) async => const AppSettingsData(
              shopName: 'مؤسسة النور للأعلاف',
            ),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (find.byTooltip('فتح قائمة الإدارة').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('فتح قائمة الإدارة'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('مؤسسة النور للأعلاف'), findsWidgets);
    expect(find.textContaining('لوحة العمليات'), findsWidgets);
  });

  testWidgets('store settings card previews the logo and upload action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/admin/settings',
      routes: [
        GoRoute(
          path: '/admin/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _AdminAuth()),
          adminRepositoryProvider.overrideWithValue(AdminRepository()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('إعدادات المتجر'), findsOneWidget);
    expect(find.text('تنبيهات المتصفح مفعلة'), findsNothing);
    expect(
        find.text('تنبيهات المتصفح متاحة — Firebase غير مهيأ'), findsNothing);
    expect(find.text('فعّل تنبيهات الطلب'), findsNothing);
    expect(find.text('إدارة إصدارات التطبيق'), findsNothing);
    expect(find.text('نشر إصدار Android'), findsNothing);
    expect(
        find.byKey(const Key('store-settings-logo-preview')), findsOneWidget);
    expect(find.text('الشعار الافتراضي'), findsOneWidget);

    await tester.tap(find.text('تعديل الإعدادات'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('store-settings-logo-edit-preview')),
        findsOneWidget);
    expect(find.byKey(const Key('store-settings-logo-upload')), findsOneWidget);
    expect(find.text('رفع شعار المتجر'), findsOneWidget);
    expect(find.text('واتساب الدعم'), findsWidgets);
    expect(find.text('وضع الصيانة'), findsWidgets);
    expect(find.text('صفحة التنزيل والانضمام'), findsNothing);
    expect(find.text('رابط APK المباشر'), findsNothing);
    expect(find.text('سياسة التوصيل'), findsNothing);
    expect(find.text('الحد الأدنى للطلب'), findsNothing);
    expect(find.text('رسوم التوصيل'), findsNothing);
    expect(find.text('رسوم المناولة'), findsNothing);
  });

  testWidgets(
    'saving store settings keeps hidden delivery and download values',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const seeded = AppSettingsData(
        shopName: 'مؤسسة النور للأعلاف',
        supportWhatsapp: '218910000999',
        downloadLink: 'https://example.ly/download',
        apkLink: 'https://example.ly/app.apk',
        deliveryPolicy: 'سياسة محفوظة لا تُمسح',
        minimumOrderAmount: 150,
        deliveryFee: 12.5,
        handlingFee: 3.25,
        currency: 'LYD',
        maintenanceMode: false,
      );
      final repository = AdminRepository();
      await repository.saveSettings(seeded);

      final router = GoRouter(
        initialLocation: '/admin/settings',
        routes: [
          GoRoute(
            path: '/admin/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith((ref) => _AdminAuth()),
            adminRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('صفحة التنزيل والانضمام'), findsNothing);
      expect(find.text('سياسة التوصيل'), findsNothing);
      expect(find.text('رسوم التوصيل'), findsNothing);

      await tester.tap(find.text('تعديل الإعدادات'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
      await tester.pumpAndSettle();

      final saved = await repository.settings();
      expect(saved.downloadLink, seeded.downloadLink);
      expect(saved.apkLink, seeded.apkLink);
      expect(saved.deliveryPolicy, seeded.deliveryPolicy);
      expect(saved.minimumOrderAmount, seeded.minimumOrderAmount);
      expect(saved.deliveryFee, seeded.deliveryFee);
      expect(saved.handlingFee, seeded.handlingFee);
    },
  );
}

class _IdleAuth extends AuthController {
  _IdleAuth() {
    state = const AuthState();
  }
}

class _AdminAuth extends AuthController {
  _AdminAuth() {
    state = const AuthState(
      user: AppUser(
        id: 'admin-branding-test',
        username: 'admin',
        role: 'admin',
      ),
    );
  }
}
