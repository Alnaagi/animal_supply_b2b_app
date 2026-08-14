import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'new_order_alert_sound_native.dart'
    if (dart.library.js_interop) 'new_order_alert_sound_web.dart' as platform;

final newOrderAlertSoundProvider = Provider<NewOrderAlertSound>(
  (ref) => const NewOrderAlertSound(),
);

class NewOrderAlertSound {
  const NewOrderAlertSound();

  bool get isAvailable => platform.isNewOrderAlertSoundAvailable;

  Future<bool> prime() => platform.primeNewOrderAlertSound();

  Future<bool> play() => platform.playNewOrderAlertSound();
}
