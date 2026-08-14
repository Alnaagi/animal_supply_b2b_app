import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/models/app_user.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../features/auth/auth_controller.dart';
import '../config/app_config.dart';
import 'firebase_options.dart';

const androidOrdersAndUpdatesChannelId = 'animal_supply_orders';
const androidNotificationIconName = 'ic_stat_notification';

enum PushNotificationPermissionState {
  unavailable,
  notDetermined,
  denied,
  authorized,
  provisional,
}

const AndroidNotificationChannel _androidOrdersAndUpdatesChannel =
    AndroidNotificationChannel(
  androidOrdersAndUpdatesChannelId,
  'طلبات وإشعارات المتجر',
  description: 'حالات الطلبات والعروض المهمة',
  importance: Importance.max,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = firebaseOptionsForCurrentPlatform();
  if (options == null) return;
  await Firebase.initializeApp(options: options);
}

final pushNotificationsServiceProvider =
    Provider<PushNotificationsService>((ref) {
  final service = PushNotificationsService();
  ref.onDispose(service.dispose);
  return service;
});

final pushNotificationsCoordinatorProvider =
    Provider<PushNotificationsCoordinator>((ref) {
  final coordinator = PushNotificationsCoordinator(
    service: ref.read(pushNotificationsServiceProvider),
    repository: ref.read(notificationsRepositoryProvider),
  );
  ref
    ..onDispose(coordinator.dispose)
    ..listen<AuthState>(authControllerProvider, (_, next) {
      unawaited(coordinator.handleUser(next.user));
    });
  unawaited(
    coordinator
        .initialize(ref.read(authControllerProvider).user)
        .catchError((Object _, StackTrace __) {}),
  );
  return coordinator;
});

class PushNotificationNavigation {
  const PushNotificationNavigation({
    this.orderId,
    this.productId,
    this.type,
  });

  final String? orderId;
  final String? productId;
  final String? type;

  bool get hasDestination =>
      orderId?.isNotEmpty == true || productId?.isNotEmpty == true;

  factory PushNotificationNavigation.fromData(Map<String, dynamic> data) {
    return PushNotificationNavigation(
      orderId: data['order_id']?.toString(),
      productId: data['product_id']?.toString(),
      type: data['type']?.toString(),
    );
  }

  String? locationFor(AppUser user) {
    final order = orderId;
    if (order != null && order.isNotEmpty) {
      return Uri(
        path: user.isAdminLike ? '/admin/orders' : '/orders',
        queryParameters: {'order': order},
      ).toString();
    }
    final product = productId;
    if (product != null && product.isNotEmpty) {
      return user.isAdminLike ? '/admin/products' : '/product/$product';
    }
    return null;
  }
}

class PushForegroundNotification {
  const PushForegroundNotification({
    required this.title,
    required this.body,
    required this.navigation,
  });

  final String title;
  final String body;
  final PushNotificationNavigation navigation;

  factory PushForegroundNotification.fromMessage(RemoteMessage message) {
    return PushForegroundNotification(
      title: message.notification?.title ??
          message.data['title']?.toString() ??
          'إشعار جديد',
      body:
          message.notification?.body ?? message.data['body']?.toString() ?? '',
      navigation: PushNotificationNavigation.fromData(message.data),
    );
  }
}

class PendingPushNavigationStore {
  PushNotificationNavigation? _pending;

  bool get hasPending => _pending != null;

  void add(PushNotificationNavigation navigation) {
    _pending = navigation;
  }

  PushNotificationNavigation? takeIfReady({
    required bool authBootstrapping,
    required AppUser? user,
  }) {
    if (authBootstrapping || user == null) return null;
    final navigation = _pending;
    _pending = null;
    return navigation;
  }
}

class PushNotificationsService {
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<PushNotificationNavigation> _navigationController =
      StreamController<PushNotificationNavigation>.broadcast();
  final StreamController<PushForegroundNotification> _foregroundController =
      StreamController<PushForegroundNotification>.broadcast();

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;
  Future<void> Function(String token)? _onToken;
  bool _initialized = false;

  Stream<PushNotificationNavigation> get navigation =>
      _navigationController.stream;
  Stream<PushForegroundNotification> get foregroundNotifications =>
      _foregroundController.stream;

  Future<bool> initialize({
    required Future<void> Function(String token) onToken,
  }) async {
    if (_initialized) return true;
    if (AppConfig.isDemoMode || !AppConfig.remoteBackendEnabled) return false;

    final options = firebaseOptionsForCurrentPlatform();
    if (options == null) return false;

    await Firebase.initializeApp(options: options);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _onToken = onToken;

    // The web implementation of flutter_local_notifications registers its own
    // root-scoped worker. The app already owns that scope for offline caching
    // and FCM, so local notifications are deliberately mobile-only.
    final usesMobileLocalNotifications = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (usesMobileLocalNotifications) {
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(androidNotificationIconName),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _handleLocalNotificationResponse,
      );
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_androidOrdersAndUpdatesChannel);
      }
    }

    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      unawaited(_handleForegroundMessage(message));
    });
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _navigationController.add(
        PushNotificationNavigation.fromData(message.data),
      ),
    );
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) {
        final callback = _onToken;
        if (callback != null) {
          unawaited(
            callback(token).catchError((Object _, StackTrace __) {}),
          );
        }
      },
    );

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _navigationController.add(
        PushNotificationNavigation.fromData(initialMessage.data),
      );
    }
    _initialized = true;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (_isAuthorized(settings.authorizationStatus)) {
      await _configureAuthorizedNotifications();
    }
    return true;
  }

  Future<bool> requestPermissionAndRegister() async {
    if (!_initialized) return false;
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (!_isAuthorized(settings.authorizationStatus)) return false;
    await _configureAuthorizedNotifications();
    return true;
  }

  Future<PushNotificationPermissionState> permissionState() async {
    if (!_initialized) return PushNotificationPermissionState.unavailable;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.notDetermined =>
        PushNotificationPermissionState.notDetermined,
      AuthorizationStatus.denied => PushNotificationPermissionState.denied,
      AuthorizationStatus.authorized =>
        PushNotificationPermissionState.authorized,
      AuthorizationStatus.provisional =>
        PushNotificationPermissionState.provisional,
    };
  }

  Future<void> _configureAuthorizedNotifications() async {
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    final token = await currentToken();
    final callback = _onToken;
    if (token != null && token.isNotEmpty && callback != null) {
      await callback(token);
    }
  }

  Future<String?> currentToken() {
    return FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb && AppConfig.firebaseWebVapidKey.isNotEmpty
          ? AppConfig.firebaseWebVapidKey
          : null,
      serviceWorkerScriptPath: kIsWeb ? 'app_service_worker.js' : null,
    );
  }

  bool _isAuthorized(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  Future<void> deleteToken() async {
    if (!_initialized) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  void _handleLocalNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _navigationController.add(
          PushNotificationNavigation.fromData(
            Map<String, dynamic>.from(decoded),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (kIsWeb) {
      _foregroundController.add(
        PushForegroundNotification.fromMessage(message),
      );
      return;
    }
    try {
      await _showForegroundNotification(message);
    } catch (_) {
      // A foreground notification must not crash the app if a platform channel
      // is unavailable. The in-app notification history remains authoritative.
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'إشعار جديد';
    final body =
        message.notification?.body ?? message.data['body']?.toString() ?? '';
    await _localNotifications.show(
      id: message.messageId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          androidOrdersAndUpdatesChannelId,
          'طلبات وإشعارات المتجر',
          channelDescription: 'حالات الطلبات والعروض المهمة',
          importance: Importance.max,
          priority: Priority.high,
          icon: androidNotificationIconName,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _onToken = null;
    await _navigationController.close();
    await _foregroundController.close();
  }
}

class PushNotificationsCoordinator {
  PushNotificationsCoordinator({
    required this.service,
    required this.repository,
    bool? enabled,
    Future<String> Function()? appVersionLoader,
  })  : _enabled = enabled ??
            (!AppConfig.isDemoMode && AppConfig.remoteBackendEnabled),
        _appVersionLoader = appVersionLoader ?? _loadAppVersion;

  final PushNotificationsService service;
  final NotificationsRepository repository;
  final bool _enabled;
  final Future<String> Function() _appVersionLoader;

  AppUser? _currentUser;
  String _appVersion = '';
  bool _ready = false;
  String? _currentToken;
  Future<void>? _initializeFuture;
  Future<void> _authTransitionQueue = Future<void>.value();
  bool _disposed = false;

  Future<void> initialize(AppUser? initialUser) {
    _currentUser = initialUser;
    final current = _initializeFuture;
    if (current != null) return current;
    return _initializeFuture = _initialize().catchError(
      (Object error, StackTrace stackTrace) {
        _initializeFuture = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  Future<void> _initialize() async {
    if (!_enabled) return;
    _appVersion = await _appVersionLoader();
    _ready = await service.initialize(onToken: _registerToken);
    if (!_ready) return;
    if (_currentUser == null) {
      await service.deleteToken();
    }
  }

  Future<void> handleUser(AppUser? user) {
    if (_disposed) return Future<void>.value();
    final previousUser = _currentUser;
    _currentUser = user;
    final transition = _authTransitionQueue.then(
      (_) => _applyUserTransition(previousUser, user),
    );
    final guarded = transition.catchError((Object _, StackTrace __) {});
    _authTransitionQueue = guarded;
    return guarded;
  }

  Future<bool> requestPermissionAndRegister() async {
    if (!_enabled || _currentUser == null) return false;
    await initialize(_currentUser);
    if (!_ready) return false;
    return service.requestPermissionAndRegister();
  }

  Future<PushNotificationPermissionState> permissionState() async {
    if (!_enabled) return PushNotificationPermissionState.unavailable;
    await initialize(_currentUser);
    if (!_ready) return PushNotificationPermissionState.unavailable;
    return service.permissionState();
  }

  Future<void> signOut(AuthController authController) async {
    await _authTransitionQueue;
    final user = _currentUser;
    final token = _currentToken ?? await _readCurrentTokenSafely();
    await _unregisterTokenBestEffort(user: user, token: token);
    _currentUser = null;
    _currentToken = null;
    await service.deleteToken();
    await authController.logout();
  }

  Future<void> _refreshCurrentToken() async {
    final token = _currentToken ?? await service.currentToken();
    if (token != null && token.isNotEmpty) await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    final user = _currentUser;
    if (user == null || user.isDemo) return;
    await repository.registerDeviceToken(
      token: token,
      platform: _platformName(),
      appVersion: _appVersion,
    );
    if (_currentUser?.id == user.id) {
      _currentToken = token;
    }
  }

  Future<void> _applyUserTransition(
    AppUser? previousUser,
    AppUser? nextUser,
  ) async {
    if (!_ready || _disposed) return;
    if (nextUser == null) {
      if (previousUser == null) return;
      final token = _currentToken ?? await _readCurrentTokenSafely();
      await _unregisterTokenBestEffort(user: previousUser, token: token);
      _currentToken = null;
      await service.deleteToken();
      return;
    }

    // register_device_token_transaction transfers an existing token to the
    // authenticated profile, so direct account changes remain isolated.
    await _refreshCurrentToken();
  }

  Future<String?> _readCurrentTokenSafely() async {
    if (!_ready) return null;
    try {
      return await service.currentToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _unregisterTokenBestEffort({
    required AppUser? user,
    required String? token,
  }) async {
    if (token == null || token.isEmpty || user == null || user.isDemo) return;
    try {
      await repository.unregisterDeviceToken(token: token);
    } catch (_) {
      // Deleting the local FCM token prevents further delivery to this app
      // instance. The dispatcher will deactivate the stale server row when FCM
      // reports that the deleted registration token is no longer valid.
    }
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => defaultTargetPlatform.name,
    };
  }

  void dispose() {
    _disposed = true;
    _currentUser = null;
    _currentToken = null;
  }

  static Future<String> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }
}
