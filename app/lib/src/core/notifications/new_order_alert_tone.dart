import 'dart:convert';

import 'package:flutter/material.dart';

enum NewOrderAlertTone {
  chaChing(
    'cha_ching',
    'صوت الصندوق',
    'تشا تشينغ: رنين معدني ثم نغمة درج نابضة',
    Icons.point_of_sale_outlined,
  ),
  shopBell(
    'shop_bell',
    'جرس المتجر',
    'دينغ دونغ بنغمتين ورنين طويل',
    Icons.notifications_active_outlined,
  ),
  crystal(
    'crystal',
    'بلوري',
    'وميض زجاجي حاد في الطبقة العالية',
    Icons.diamond_outlined,
  ),
  goldCoin(
    'gold_coin',
    'عملة ذهبية',
    'بينغ قصير ساطع مثل سقوط عملة',
    Icons.monetization_on_outlined,
  ),
  marimba(
    'marimba',
    'ماريمبا',
    'مطرقة خشبية دافئة في الطبقة الوسطى',
    Icons.piano,
  ),
  sparkle(
    'sparkle',
    'وميض',
    'فرقعة عالية قصيرة جداً',
    Icons.auto_awesome_outlined,
  ),
  softChime(
    'soft_chime',
    'رنين هادئ',
    'نغمات ناعمة بخفوت وصدى طويل',
    Icons.spa_outlined,
  ),
  successRise(
    'success_rise',
    'إشعار نجاح',
    'تآلف كبير صاعد من ثلاث نغمات',
    Icons.trending_up,
  );

  const NewOrderAlertTone(
    this.id,
    this.labelAr,
    this.captionAr,
    this.icon,
  );

  final String id;
  final String labelAr;
  final String captionAr;
  final IconData icon;

  static NewOrderAlertTone fromId(String? raw) {
    for (final tone in values) {
      if (tone.id == raw) return tone;
    }
    return NewOrderAlertTone.chaChing;
  }
}

class NewOrderAlertSoundSettings {
  const NewOrderAlertSoundSettings({
    required this.tone,
    required this.volume,
  });

  static const defaultVolume = 0.82;
  static const minVolume = 0.12;
  static const maxVolume = 1.0;

  static const defaults = NewOrderAlertSoundSettings(
    tone: NewOrderAlertTone.chaChing,
    volume: defaultVolume,
  );

  final NewOrderAlertTone tone;
  final double volume;

  double get clampedVolume => volume.clamp(minVolume, maxVolume).toDouble();

  NewOrderAlertSoundSettings copyWith({
    NewOrderAlertTone? tone,
    double? volume,
  }) {
    return NewOrderAlertSoundSettings(
      tone: tone ?? this.tone,
      volume: (volume ?? this.volume).clamp(minVolume, maxVolume).toDouble(),
    );
  }

  String encode() => jsonEncode({
        'tone': tone.id,
        'volume': clampedVolume,
      });

  static NewOrderAlertSoundSettings decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return defaults;
      final volumeRaw = decoded['volume'];
      final volume = volumeRaw is num ? volumeRaw.toDouble() : defaultVolume;
      return NewOrderAlertSoundSettings(
        tone: NewOrderAlertTone.fromId(decoded['tone'] as String?),
        volume: volume.clamp(minVolume, maxVolume).toDouble(),
      );
    } catch (_) {
      return defaults;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NewOrderAlertSoundSettings &&
      other.tone == tone &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(tone, volume);
}

