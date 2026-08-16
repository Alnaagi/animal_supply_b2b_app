import 'new_order_alert_tone.dart';

/// Compatibility wrapper around [NewOrderAlertTone] for older call sites.
class NewOrderAlertPreset {
  const NewOrderAlertPreset._(this.tone);

  final NewOrderAlertTone tone;

  String get id => tone.id;
  String get nameAr => tone.labelAr;
  String get hintAr => tone.captionAr;

  static NewOrderAlertPreset fromTone(NewOrderAlertTone tone) =>
      NewOrderAlertPreset._(tone);

  static const NewOrderAlertPreset defaultPreset =
      NewOrderAlertPreset._(NewOrderAlertTone.chaChing);

  static NewOrderAlertPreset fromId(String? raw) =>
      NewOrderAlertPreset._(NewOrderAlertTone.fromId(raw));
}
