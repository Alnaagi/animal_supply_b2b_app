import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'src/core/config/app_config.dart';
import 'src/core/config/app_runtime_mode.dart';
import 'src/core/notifications/push_notifications.dart';
import 'src/core/routing/app_router.dart';
import 'src/core/routing/deep_link_service.dart';
import 'src/core/theme/app_theme.dart';
import 'src/core/updates/app_update_gate.dart';
import 'src/data/repositories/notifications_repository.dart';
import 'src/features/auth/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await AppRuntimeMode.load();
  await AppConfig.tryInitializeSupabase();
  runApp(const ProviderScope(child: AnimalSupplyApp()));
}

class AnimalSupplyApp extends ConsumerStatefulWidget {
  const AnimalSupplyApp({super.key});

  @override
  ConsumerState<AnimalSupplyApp> createState() => _AnimalSupplyAppState();
}

class _AnimalSupplyAppState extends ConsumerState<AnimalSupplyApp> {
  StreamSubscription<PushNotificationNavigation>? _notificationSubscription;
  StreamSubscription<PushForegroundNotification>? _foregroundSubscription;
  StreamSubscription<Uri>? _deepLinkSubscription;
  DeepLinkService? _deepLinkService;
  final PendingPushNavigationStore _pendingPushNavigation =
      PendingPushNavigationStore();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  bool _notificationNavigationScheduled = false;

  @override
  void initState() {
    super.initState();
    final pushService = ref.read(pushNotificationsServiceProvider);
    _notificationSubscription =
        pushService.navigation.listen(_handleNotificationNavigation);
    _foregroundSubscription = pushService.foregroundNotifications.listen(
      _handleForegroundNotification,
    );
    ref.listenManual<AuthState>(authControllerProvider, (_, next) {
      if (!next.bootstrapping && next.user != null) {
        _schedulePendingNotificationNavigation();
      }
    });
    ref.read(pushNotificationsCoordinatorProvider);
    if (AppConfig.remoteBackendEnabled) {
      _deepLinkService = DeepLinkService();
      _deepLinkSubscription = _deepLinkService!.links.listen((uri) {
        if (ref.read(authControllerProvider).user != null) return;
        ref.read(appRouterProvider).go(uri.toString());
      });
    }
  }

  void _handleNotificationNavigation(PushNotificationNavigation navigation) {
    ref.invalidate(unreadNotificationsCountProvider);
    _pendingPushNavigation.add(navigation);
    _schedulePendingNotificationNavigation();
  }

  void _schedulePendingNotificationNavigation() {
    if (_notificationNavigationScheduled ||
        !_pendingPushNavigation.hasPending) {
      return;
    }
    final auth = ref.read(authControllerProvider);
    if (auth.bootstrapping || auth.user == null) return;
    _notificationNavigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationNavigationScheduled = false;
      if (!mounted) return;
      final latestAuth = ref.read(authControllerProvider);
      final navigation = _pendingPushNavigation.takeIfReady(
        authBootstrapping: latestAuth.bootstrapping,
        user: latestAuth.user,
      );
      final user = latestAuth.user;
      if (navigation == null || user == null) return;
      final location = navigation.locationFor(user);
      if (location != null) ref.read(appRouterProvider).go(location);
    });
  }

  void _handleForegroundNotification(PushForegroundNotification notification) {
    ref.invalidate(unreadNotificationsCountProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = _scaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              notification.body.isEmpty
                  ? notification.title
                  : '${notification.title}\n${notification.body}',
            ),
            duration: const Duration(seconds: 7),
            action: notification.navigation.hasDestination
                ? SnackBarAction(
                    label: 'فتح',
                    onPressed: () => _handleNotificationNavigation(
                      notification.navigation,
                    ),
                  )
                : null,
          ),
        );
    });
  }

  @override
  void dispose() {
    unawaited(_notificationSubscription?.cancel());
    unawaited(_foregroundSubscription?.cancel());
    unawaited(_deepLinkSubscription?.cancel());
    unawaited(_deepLinkService?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: AppConfig.shopName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      scaffoldMessengerKey: _scaffoldMessengerKey,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: AppUpdateGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
