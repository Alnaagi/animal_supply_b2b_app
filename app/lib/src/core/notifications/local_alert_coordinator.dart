import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser_local_notifications.dart';
import 'cross_tab_alert_lock.dart';
import 'new_order_alert_sound.dart';
import 'push_notifications.dart';

final localAlertCoordinatorProvider = Provider<LocalAlertCoordinator>((ref) {
  return LocalAlertCoordinator(
    notifications: ref.watch(browserLocalNotificationsProvider),
    sound: ref.watch(newOrderAlertSoundProvider),
    mobileAlerts: ref.watch(pushNotificationsServiceProvider),
    crossTabLock: createCrossTabAlertLock(),
  );
});

class LocalAlertResult {
  const LocalAlertResult({
    required this.shown,
    required this.playedSound,
  });

  final bool shown;
  final bool playedSound;
}

/// Deduplicates browser banners and alert sounds for the same notification id.
class LocalAlertCoordinator {
  LocalAlertCoordinator({
    required BrowserLocalNotifications notifications,
    required NewOrderAlertSound sound,
    PushNotificationsService? mobileAlerts,
    CrossTabAlertLock? crossTabLock,
  })  : _notifications = notifications,
        _sound = sound,
        _mobileAlerts = mobileAlerts,
        _crossTabLock = crossTabLock ?? MemoryCrossTabAlertLock() {
    _crossTabUnsubscribe = _crossTabLock.listen((claimedId) {
      _announcedIds.add(claimedId);
    });
  }

  final BrowserLocalNotifications _notifications;
  final NewOrderAlertSound _sound;
  final PushNotificationsService? _mobileAlerts;
  final CrossTabAlertLock _crossTabLock;
  final Set<String> _announcedIds = {};
  void Function()? _crossTabUnsubscribe;

  bool wasAnnounced(String id) => _announcedIds.contains(id);

  void dispose() {
    _crossTabUnsubscribe?.call();
  }

  Future<LocalAlertResult> announce({
    required String id,
    required String title,
    required String body,
    bool playSound = true,
    String? target,
  }) async {
    if (id.isEmpty || !_announcedIds.add(id) || !_crossTabLock.claim(id)) {
      _announcedIds.add(id);
      return const LocalAlertResult(shown: false, playedSound: false);
    }
    final browserShown = await _notifications.show(
      title: title,
      body: body,
      tag: id,
      target: target,
    );
    final mobileShown =
        await _mobileAlerts?.showInboxNotification(
          id: id,
          title: title,
          body: body,
        ) ??
        false;
    final shown = browserShown || mobileShown;
    var playedSound = false;
    if (playSound && _sound.isAvailable) {
      playedSound = await _sound.play();
    }
    return LocalAlertResult(shown: shown, playedSound: playedSound);
  }
}
