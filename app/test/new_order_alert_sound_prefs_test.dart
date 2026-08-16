import 'package:animal_supply_b2b/src/core/notifications/new_order_alert_sound_prefs.dart';
import 'package:animal_supply_b2b/src/core/notifications/new_order_alert_tone.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to the two-tone shop ding', () {
    expect(
      NewOrderAlertSoundSettings.defaults.tone,
      NewOrderAlertTone.chaChing,
    );
    expect(NewOrderAlertTone.chaChing.labelAr, 'صوت الصندوق');
    expect(NewOrderAlertTone.marimba.labelAr, 'ماريمبا');
    expect(NewOrderAlertTone.crystal.labelAr, 'بلوري');
    expect(NewOrderAlertTone.softChime.labelAr, 'رنين هادئ');
    expect(NewOrderAlertTone.goldCoin.labelAr, 'عملة ذهبية');
  });

  test('persists a selected synthesized tone', () async {
    final store = NewOrderAlertSoundPrefs();
    expect(await store.load(), NewOrderAlertSoundSettings.defaults);

    const selected = NewOrderAlertSoundSettings(
      tone: NewOrderAlertTone.marimba,
      volume: 0.9,
    );
    expect(await store.save(selected), isTrue);
    final loaded = await store.load();
    expect(loaded.tone, NewOrderAlertTone.marimba);
    expect(loaded.clampedVolume, closeTo(0.9, 0.001));
  });

  test('unknown stored tone ids fall back to the default ding', () {
    final decoded = NewOrderAlertSoundSettings.decode(
      '{"tone":"shopify_wav","volume":0.5}',
    );
    expect(decoded.tone, NewOrderAlertTone.chaChing);
    expect(decoded.clampedVolume, closeTo(0.5, 0.001));
  });
}
