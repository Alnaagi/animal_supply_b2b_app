import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'new_order_alert_preset.dart';
import 'new_order_alert_tone.dart';

class NewOrderAlertSoundPrefs {
  NewOrderAlertSoundPrefs({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const storageKey = 'admin_orders.new_order_alert_sound.v1';

  final SharedPreferences? _prefsOverride;
  final Future<SharedPreferences?> Function()? _storeLoader;
  SharedPreferences? _prefs;

  Future<SharedPreferences?> _store() async {
    if (_prefsOverride != null) return _prefsOverride;
    try {
      return _prefs ??=
          await (_storeLoader?.call() ?? SharedPreferences.getInstance());
    } catch (_) {
      return null;
    }
  }

  Future<NewOrderAlertSoundSettings> load() async {
    try {
      final prefs = await _store();
      return NewOrderAlertSoundSettings.decode(prefs?.getString(storageKey));
    } catch (_) {
      return NewOrderAlertSoundSettings.defaults;
    }
  }

  Future<bool> save(NewOrderAlertSoundSettings settings) async {
    try {
      final prefs = await _store();
      if (prefs == null) return false;
      return await prefs.setString(storageKey, settings.encode());
    } catch (_) {
      return false;
    }
  }
}

final newOrderAlertSoundPrefsProvider = Provider<NewOrderAlertSoundPrefs>(
  (ref) => NewOrderAlertSoundPrefs(),
);

final newOrderAlertSoundSettingsProvider = StateNotifierProvider<
    NewOrderAlertSoundSettingsController, NewOrderAlertSoundSettings>(
  (ref) => NewOrderAlertSoundSettingsController(
    ref.watch(newOrderAlertSoundPrefsProvider),
  ),
);

class NewOrderAlertSoundSettingsController
    extends StateNotifier<NewOrderAlertSoundSettings> {
  NewOrderAlertSoundSettingsController(this._prefs)
      : super(NewOrderAlertSoundSettings.defaults) {
    unawaited(reload());
  }

  final NewOrderAlertSoundPrefs _prefs;

  Future<void> reload() async {
    state = await _prefs.load();
  }

  Future<void> setTone(NewOrderAlertTone tone) async {
    state = state.copyWith(tone: tone);
    await _prefs.save(state);
  }

  Future<void> setPreset(NewOrderAlertPreset preset) => setTone(preset.tone);

  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
    await _prefs.save(state);
  }
}
