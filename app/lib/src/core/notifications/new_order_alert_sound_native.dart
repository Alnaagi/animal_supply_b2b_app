import 'new_order_alert_tone.dart';

const bool isNewOrderAlertSoundAvailable = false;

Future<bool> primeNewOrderAlertSound() async => false;

Future<bool> playNewOrderAlertSound({
  NewOrderAlertTone tone = NewOrderAlertTone.chaChing,
  double volume = NewOrderAlertSoundSettings.defaultVolume,
}) async =>
    false;
