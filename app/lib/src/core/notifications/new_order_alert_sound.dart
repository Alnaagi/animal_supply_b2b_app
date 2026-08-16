import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'new_order_alert_sound_native.dart'
    if (dart.library.js_interop) 'new_order_alert_sound_web.dart' as platform;
import 'new_order_alert_sound_prefs.dart';
import 'new_order_alert_tone.dart';

final newOrderAlertSoundProvider = Provider<NewOrderAlertSound>((ref) {
  final settings = ref.watch(newOrderAlertSoundSettingsProvider);
  return NewOrderAlertSound(
    tone: settings.tone,
    volume: settings.clampedVolume,
  );
});

class NewOrderAlertSound {
  const NewOrderAlertSound({
    this.tone = NewOrderAlertTone.chaChing,
    this.volume = NewOrderAlertSoundSettings.defaultVolume,
  });

  final NewOrderAlertTone tone;
  final double volume;

  bool get isAvailable => platform.isNewOrderAlertSoundAvailable;

  Future<bool> prime() => platform.primeNewOrderAlertSound();

  Future<bool> play({
    NewOrderAlertTone? tone,
    double? volume,
  }) {
    return platform.playNewOrderAlertSound(
      tone: tone ?? this.tone,
      volume: volume ?? this.volume,
    );
  }
}
