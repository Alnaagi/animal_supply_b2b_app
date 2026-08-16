import 'package:animal_supply_b2b/src/core/config/admin_data_reset_visibility.dart';
import 'package:animal_supply_b2b/src/core/config/app_runtime_mode.dart';
import 'package:animal_supply_b2b/src/core/security/destructive_confirm_phrase.dart';
import 'package:animal_supply_b2b/src/data/local/local_cache.dart';
import 'package:animal_supply_b2b/src/data/local/local_device_data_reset.dart';
import 'package:animal_supply_b2b/src/data/models/order.dart';
import 'package:animal_supply_b2b/src/data/models/product.dart';
import 'package:animal_supply_b2b/src/data/repositories/admin_repository.dart';
import 'package:animal_supply_b2b/src/data/repositories/demo_data.dart';
import 'package:animal_supply_b2b/src/data/sync/sync_outbox.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:animal_supply_b2b/src/features/settings/admin_data_mode_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppRuntimeMode.debugReset();
  });

  tearDown(AppRuntimeMode.debugReset);

  group('DestructiveConfirmPhrase', () {
    test('accepts only exact Latin uppercase RESET', () {
      expect(DestructiveConfirmPhrase.matches('RESET'), isTrue);
      expect(DestructiveConfirmPhrase.matches('reset'), isFalse);
      expect(DestructiveConfirmPhrase.matches('Reset'), isFalse);
      expect(DestructiveConfirmPhrase.matches('RESET '), isFalse);
      expect(DestructiveConfirmPhrase.matches('مسح'), isFalse);
      expect(
        DestructiveConfirmPhrase.validationMessage('reset'),
        DestructiveConfirmPhrase.mismatchAr,
      );
      expect(DestructiveConfirmPhrase.validationMessage('RESET'), isNull);
    });
  });

  group('AppRuntimeMode', () {
    test('persists a local demo overlay and refuses production without backend',
        () async {
      final prefs = await SharedPreferences.getInstance();

      final enabled = await AppRuntimeMode.setPreferLocalDemo(
        true,
        productionBackendAvailable: true,
        prefs: prefs,
      );
      expect(enabled.applied, isTrue);
      expect(enabled.preferLocalDemo, isTrue);
      expect(prefs.getBool(AppRuntimeMode.preferLocalDemoPrefsKey), isTrue);

      AppRuntimeMode.debugReset();
      await AppRuntimeMode.load(prefs: prefs);
      expect(AppRuntimeMode.preferLocalDemo, isTrue);

      final blocked = await AppRuntimeMode.setPreferLocalDemo(
        false,
        productionBackendAvailable: false,
        prefs: prefs,
      );
      expect(blocked.applied, isFalse);
      expect(blocked.preferLocalDemo, isTrue);
      expect(blocked.messageAr, contains('APP_ENV=production'));
      expect(AppRuntimeMode.preferLocalDemo, isTrue);

      final restored = await AppRuntimeMode.setPreferLocalDemo(
        false,
        productionBackendAvailable: true,
        prefs: prefs,
      );
      expect(restored.applied, isTrue);
      expect(restored.preferLocalDemo, isFalse);
      expect(prefs.getBool(AppRuntimeMode.preferLocalDemoPrefsKey), isNull);
    });

    test('ignores leftover v1 demo overlay so production stays the default',
        () async {
      SharedPreferences.setMockInitialValues({
        'app_runtime.prefer_local_demo.v1': true,
      });
      final prefs = await SharedPreferences.getInstance();
      await AppRuntimeMode.load(prefs: prefs);
      expect(AppRuntimeMode.preferLocalDemo, isFalse);
      expect(prefs.getBool(AppRuntimeMode.preferLocalDemoPrefsKey), isNull);
    });
  });

  group('LocalDeviceDataReset', () {
    test('clears cache snapshots and outbox keys only', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppRuntimeMode.preferLocalDemoPrefsKey, true);
      final cache = LocalCache(prefs: prefs);
      final outbox = SyncOutbox(prefs: prefs);
      await cache.saveProducts(const [_resetProduct]);
      await cache.saveCart(
        ownerProfileId: 'profile-1',
        items: const [CartItem(product: _resetProduct, quantity: 2)],
      );
      await outbox.enqueue(
        const SyncOutboxEntry(
          id: 'outbox-1',
          ownerProfileId: 'profile-1',
          entityType: 'place_order',
          payload: {'productId': 'reset-1'},
        ),
      );

      await LocalDeviceDataReset(cache: cache, outbox: outbox)
          .wipeLocalDemoCacheAndOutbox();

      expect(await cache.cachedProducts(), isEmpty);
      expect(
        await cache.cachedCart(ownerProfileId: 'profile-1'),
        isEmpty,
      );
      expect(
        await outbox.pending(ownerProfileId: 'profile-1'),
        isEmpty,
      );
      expect(
        prefs.getKeys().where((key) => key.startsWith('local_cache.')),
        isEmpty,
      );
      expect(
        prefs.getKeys().where((key) => key.startsWith('sync_outbox.')),
        isEmpty,
      );
      expect(prefs.getBool(AppRuntimeMode.preferLocalDemoPrefsKey), isTrue);
    });
  });

  testWidgets('settings danger card requires CAPS RESET and admin password',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final cache = LocalCache(prefs: prefs);
    await cache.saveProducts(const [_resetProduct]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _DemoAdminAuthController(),
          ),
          localCacheProvider.overrideWithValue(cache),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: AdminDataModeCard(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin-data-mode-card')), findsOneWidget);
    expect(find.text('الوضع التجريبي وبيانات الجهاز'), findsOneWidget);
    expect(find.byKey(const Key('admin-local-reset-button')), findsOneWidget);
    expect(find.text('مسح البيانات التجريبية'), findsWidgets);
    expect(find.textContaining('خادم الإنتاج غير'), findsWidgets);

    final demoSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('admin-demo-mode-switch')),
    );
    expect(demoSwitch.value, isTrue);
    expect(demoSwitch.onChanged, isNull);

    await tester.tap(find.byKey(const Key('admin-local-reset-button')));
    await tester.pumpAndSettle();

    expect(find.text('تأكيد عملية مسح خطرة'), findsOneWidget);
    expect(find.textContaining('بأحرف إنجليزية كبيرة'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('admin-reset-password')),
      'admin',
    );
    await tester.enterText(
      find.byKey(const Key('admin-reset-confirm-phrase')),
      'reset',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'نعم، امسح'));
    await tester.pumpAndSettle();

    expect(find.text(DestructiveConfirmPhrase.mismatchAr), findsOneWidget);
    expect(await cache.cachedProducts(), isNotEmpty);

    await tester.enterText(
      find.byKey(const Key('admin-reset-confirm-phrase')),
      'RESET',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'نعم، امسح'));
    await tester.pumpAndSettle();

    expect(find.text('تأكيد عملية مسح خطرة'), findsNothing);
    expect(await cache.cachedProducts(), isEmpty);
    expect(
      find.text('تم مسح البيانات التجريبية المحلية والكاش والطابور.'),
      findsOneWidget,
    );
  });

  test('danger-card actions follow demo overlay vs live production', () {
    const demoOverlay = AdminDataResetVisibility(
      demoMode: true,
      productionBackendLive: false,
    );
    expect(demoOverlay.showDemoLocalReset, isTrue);
    expect(demoOverlay.showProductionRemoteReset, isFalse);
    expect(demoOverlay.showLocalCacheOnlyReset, isFalse);

    const production = AdminDataResetVisibility(
      demoMode: false,
      productionBackendLive: true,
    );
    expect(production.showDemoLocalReset, isFalse);
    expect(production.showProductionRemoteReset, isTrue);
    expect(production.showLocalCacheOnlyReset, isTrue);
  });

  testWidgets('production mode shows server wipe and local-cache-only',
      (tester) async {
    var invoked = '';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _DemoAdminAuthController(),
          ),
          adminRepositoryProvider.overrideWithValue(
            AdminRepository(
              demoCustomers: const [],
              edgeFunctionInvoker: (functionName, body) async {
                invoked = functionName;
                expect(body['confirm_phrase'], 'RESET');
                return {
                  'ok': true,
                  'data': {
                    'reset': true,
                    'preserved_admin_id': 'admin-1',
                    'truncated_tables': const ['products', 'orders'],
                    'customer_profiles_deleted': 0,
                    'customer_auth_users_deleted': 0,
                  },
                };
              },
            ),
          ),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: AdminDataModeCard(
                  visibilityOverride: AdminDataResetVisibility(
                    demoMode: false,
                    productionBackendLive: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مسح البيانات التجريبية'), findsNothing);
    expect(find.text('مسح قاعدة البيانات الحقيقية'), findsWidgets);
    expect(find.byKey(const Key('admin-production-reset-button')), findsOneWidget);
    expect(find.byKey(const Key('admin-local-cache-reset-button')), findsOneWidget);
    expect(find.textContaining('لا رجعة فيه على الخادم'), findsWidgets);

    await tester.tap(find.byKey(const Key('admin-production-reset-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('حسابك الإداري الحالي لن يُحذف'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('admin-reset-password')),
      'admin',
    );
    await tester.enterText(
      find.byKey(const Key('admin-reset-confirm-phrase')),
      'RESET',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'نعم، امسح'));
    await tester.pumpAndSettle();

    expect(invoked, 'admin-reset-application-data');
    expect(
      find.textContaining('تم مسح بيانات التشغيل على الخادم'),
      findsOneWidget,
    );
  });
}

class _DemoAdminAuthController extends AuthController {
  _DemoAdminAuthController() {
    state = AuthState(
      user: demoAdmin.copyWith(isDemo: true),
      notice: 'حساب تجريبي: أي تغييرات هنا ليست بيانات تشغيل حقيقية.',
    );
  }
}

const _resetProduct = Product(
  id: 'reset-1',
  nameAr: 'منتج للمسح',
  sku: 'RESET-1',
  category: 'كلاب',
  animalType: 'كلاب',
  brand: 'تجريبي',
  unitSize: 'كيس',
  basePrice: 10,
  stockQuantity: 4,
  minOrderQty: 1,
);
