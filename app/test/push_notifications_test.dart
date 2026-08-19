import 'dart:io';

import 'package:animal_supply_b2b/src/core/notifications/push_notifications.dart';
import 'package:animal_supply_b2b/src/core/notifications/push_permission_card.dart';
import 'package:animal_supply_b2b/src/data/models/app_user.dart';
import 'package:animal_supply_b2b/src/data/repositories/notifications_repository.dart';
import 'package:animal_supply_b2b/src/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('push navigation', () {
    test('waits for auth bootstrap and consumes the destination once', () {
      final store = PendingPushNavigationStore()
        ..add(const PushNotificationNavigation(orderId: 'order-1'));

      expect(
        store.takeIfReady(
          authBootstrapping: true,
          user: _customer('customer-a'),
        ),
        isNull,
      );
      expect(store.hasPending, isTrue);
      expect(
        store.takeIfReady(authBootstrapping: false, user: null),
        isNull,
      );
      expect(store.hasPending, isTrue);

      final navigation = store.takeIfReady(
        authBootstrapping: false,
        user: _customer('customer-a'),
      );
      expect(navigation?.orderId, 'order-1');
      expect(store.hasPending, isFalse);
      expect(
        store.takeIfReady(
          authBootstrapping: false,
          user: _customer('customer-a'),
        ),
        isNull,
      );
    });

    test('maps order and product taps to role-safe routes', () {
      const order = PushNotificationNavigation(orderId: 'order-1');
      const product = PushNotificationNavigation(productId: 'product-1');

      expect(
          order.locationFor(_customer('customer-a')), '/orders?order=order-1');
      expect(
        order.locationFor(_admin('admin-a')),
        '/admin/orders?order=order-1',
      );
      expect(
        product.locationFor(_customer('customer-a')),
        '/product/product-1',
      );
      expect(product.locationFor(_admin('admin-a')), '/admin/products');
    });
  });

  group('device token lifecycle', () {
    test('explicit sign-out unregisters before deleting the local token',
        () async {
      final service = _FakePushNotificationsService('token-a');
      final repository = _FakeNotificationsRepository();
      final user = _customer('customer-a');
      final coordinator = _coordinator(service, repository);
      final auth = _FakeAuthController(user);

      await coordinator.initialize(user);
      await coordinator.signOut(auth);

      expect(repository.registeredTokens, ['token-a']);
      expect(repository.unregisteredTokens, ['token-a']);
      expect(service.deleteCalls, 1);
      expect(auth.logoutCalls, 1);
      expect(auth.state.user, isNull);
    });

    test('direct auth loss still deletes the token when unregister fails',
        () async {
      final service = _FakePushNotificationsService('token-a');
      final repository = _FakeNotificationsRepository(
        failUnregister: true,
      );
      final user = _customer('customer-a');
      final coordinator = _coordinator(service, repository);

      await coordinator.initialize(user);
      await coordinator.handleUser(null);

      expect(repository.unregisteredTokens, ['token-a']);
      expect(service.deleteCalls, 1);
    });

    test('direct account switch re-registers without deleting the token',
        () async {
      final service = _FakePushNotificationsService('token-a');
      final repository = _FakeNotificationsRepository();
      final coordinator = _coordinator(service, repository);

      await coordinator.initialize(_customer('customer-a'));
      await coordinator.handleUser(_customer('customer-b'));

      expect(repository.registeredTokens, ['token-a', 'token-a']);
      expect(repository.unregisteredTokens, isEmpty);
      expect(service.deleteCalls, 0);
    });

    test('notification initialization can retry after a transient failure',
        () async {
      final service = _RetryingPushNotificationsService('token-a');
      final repository = _FakeNotificationsRepository();
      final coordinator = _coordinator(service, repository);
      final user = _customer('customer-a');

      await expectLater(coordinator.initialize(user), throwsStateError);
      expect(
        await coordinator.permissionState(),
        PushNotificationPermissionState.authorized,
      );
      expect(service.initializeCalls, 2);
    });
  });

  test('Android default channel stays aligned with the app channel', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(androidOrdersAndUpdatesChannelId, 'animal_supply_orders');
    expect(
      manifest,
      contains(
        'com.google.firebase.messaging.default_notification_channel_id',
      ),
    );
    expect(
      manifest,
      contains('android:value="$androidOrdersAndUpdatesChannelId"'),
    );
  });

  test('Android notifications use a dedicated white-alpha status icon', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final icon = File(
      'android/app/src/main/res/drawable/$androidNotificationIconName.xml',
    );

    expect(androidNotificationIconName, 'ic_stat_notification');
    expect(
      manifest,
      contains('com.google.firebase.messaging.default_notification_icon'),
    );
    expect(
      manifest,
      contains('android:resource="@drawable/$androidNotificationIconName"'),
    );
    expect(icon.existsSync(), isTrue);
    final iconXml = icon.readAsStringSync();
    expect(iconXml, contains('android:fillColor="#FFFFFFFF"'));
    expect(iconXml, isNot(contains('<bitmap')));
  });

  test('Android launcher exposes adaptive and monochrome icon resources', () {
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    );
    final themed = File(
      'android/app/src/main/res/mipmap-anydpi-v33/ic_launcher.xml',
    );

    expect(adaptive.existsSync(), isTrue);
    expect(adaptive.readAsStringSync(), contains('<adaptive-icon'));
    expect(themed.existsSync(), isTrue);
    expect(
      themed.readAsStringSync(),
      contains('android:drawable="@drawable/ic_stat_notification"'),
    );
  });

  testWidgets('visible permission card enables push for the current device',
      (tester) async {
    final service = _FakePushNotificationsService(
      'token-a',
      permission: PushNotificationPermissionState.notDetermined,
    );
    final repository = _FakeNotificationsRepository();
    final coordinator = _coordinator(service, repository);
    await coordinator.initialize(_customer('customer-a'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushNotificationsCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PushPermissionCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('فعّل تنبيهات الطلب'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('enable-push-notifications-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('الإشعارات الفورية مفعلة'), findsOneWidget);
    expect(service.permissionRequests, 1);
  });
}

PushNotificationsCoordinator _coordinator(
  _FakePushNotificationsService service,
  _FakeNotificationsRepository repository,
) {
  return PushNotificationsCoordinator(
    service: service,
    repository: repository,
    enabled: true,
    appVersionLoader: () async => '1.0.2+3',
    installationIdLoader: () async => 'test-installation-id-0001',
  );
}

AppUser _customer(String id) {
  return AppUser(
    id: id,
    username: id,
    role: 'customer',
    customerId: 'business-$id',
    accountStatus: 'active',
  );
}

AppUser _admin(String id) {
  return AppUser(id: id, username: id, role: 'admin');
}

class _FakePushNotificationsService extends PushNotificationsService {
  _FakePushNotificationsService(
    this.token, {
    this.permission = PushNotificationPermissionState.authorized,
  });

  String? token;
  int deleteCalls = 0;
  int permissionRequests = 0;
  PushNotificationPermissionState permission;

  @override
  Future<bool> initialize({
    required Future<void> Function(String token) onToken,
  }) async {
    final current = token;
    if (current != null) await onToken(current);
    return true;
  }

  @override
  Future<String?> currentToken() async => token;

  @override
  Future<PushNotificationPermissionState> permissionState() async => permission;

  @override
  Future<bool> requestPermissionAndRegister() async {
    permissionRequests++;
    permission = PushNotificationPermissionState.authorized;
    return true;
  }

  @override
  Future<bool> requestOsNotificationPermission() async => false;

  @override
  Future<bool> showInboxNotification({
    required String id,
    required String title,
    required String body,
  }) async =>
      false;

  @override
  Future<void> deleteToken() async {
    deleteCalls++;
    token = null;
  }
}

class _FakeNotificationsRepository extends NotificationsRepository {
  _FakeNotificationsRepository({this.failUnregister = false});

  final bool failUnregister;
  final List<String> registeredTokens = [];
  final List<String> unregisteredTokens = [];

  @override
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    required String appVersion,
    String? installationId,
    String? deviceId,
    String? deviceLabel,
  }) async {
    registeredTokens.add(token);
  }

  @override
  Future<void> unregisterDeviceToken({
    required String token,
    String? deviceId,
  }) async {
    unregisteredTokens.add(token);
    if (failUnregister) throw StateError('offline');
  }
}

class _RetryingPushNotificationsService extends _FakePushNotificationsService {
  _RetryingPushNotificationsService(super.token);

  int initializeCalls = 0;

  @override
  Future<bool> initialize({
    required Future<void> Function(String token) onToken,
  }) async {
    initializeCalls++;
    if (initializeCalls == 1) throw StateError('temporary initialization');
    return super.initialize(onToken: onToken);
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(AppUser user) {
    state = AuthState(user: user);
  }

  int logoutCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const AuthState();
  }
}
