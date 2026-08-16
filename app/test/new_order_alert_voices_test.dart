import 'package:animal_supply_b2b/src/core/notifications/new_order_alert_tone.dart';
import 'package:animal_supply_b2b/src/core/notifications/new_order_alert_voices.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String fingerprint(NewOrderAlertTone tone) {
    return newOrderAlertVoicesFor(tone)
        .map(
          (voice) =>
              '${voice.type}:${voice.startHz.toStringAsFixed(1)}>'
              '${voice.endHz.toStringAsFixed(1)}@${voice.delay.toStringAsFixed(3)}'
              'x${voice.duration.toStringAsFixed(3)}g${voice.peakGain}'
              'a${voice.attack}f${voice.filterHz}',
        )
        .join('|');
  }

  test('every synthesized preset has a unique patch', () {
    final fingerprints = {
      for (final tone in NewOrderAlertTone.values) fingerprint(tone),
    };
    expect(fingerprints.length, NewOrderAlertTone.values.length);
  });

  test('cha-ching pairs a high metallic ding with a low drawer note', () {
    final voices = newOrderAlertVoicesFor(NewOrderAlertTone.chaChing);
    expect(voices.any((voice) => voice.startHz > 1800), isTrue);
    expect(
      voices.any((voice) => voice.startHz < 200 && voice.filterHz != null),
      isTrue,
    );
    expect(voices.any((voice) => voice.type == 'square'), isTrue);
  });

  test('shop bell is a two-note ding-dong with long decay', () {
    final voices = newOrderAlertVoicesFor(NewOrderAlertTone.shopBell);
    final late = voices.where((voice) => voice.delay >= 0.25).toList();
    expect(voices.first.startHz, closeTo(783.99, 0.1));
    expect(late, isNotEmpty);
    expect(late.first.startHz, closeTo(659.25, 0.1));
    expect(voices.map((voice) => voice.duration).reduce(_max), greaterThan(1));
  });

  test('crystal uses clustered inharmonic highs', () {
    final voices = newOrderAlertVoicesFor(NewOrderAlertTone.crystal);
    expect(voices.every((voice) => voice.type == 'sine'), isTrue);
    expect(voices.every((voice) => voice.startHz > 2500), isTrue);
    final ratios = <double>[];
    for (var i = 1; i < voices.length; i++) {
      ratios.add(voices[i].startHz / voices.first.startHz);
    }
    expect(ratios.any((ratio) => (ratio - 2).abs() > 0.15), isTrue);
  });

  test('coin and sparkle stay short while soft chime rings', () {
    double span(NewOrderAlertTone tone) {
      return newOrderAlertVoicesFor(tone)
          .map((voice) => voice.delay + voice.duration)
          .reduce(_max);
    }

    expect(span(NewOrderAlertTone.goldCoin), lessThan(0.25));
    expect(span(NewOrderAlertTone.sparkle), lessThan(0.08));
    expect(span(NewOrderAlertTone.softChime), greaterThan(1.2));
    expect(
      newOrderAlertVoicesFor(NewOrderAlertTone.sparkle).first.startHz,
      greaterThan(4000),
    );
  });

  test('marimba sits in the wooden mid register', () {
    final voices = newOrderAlertVoicesFor(NewOrderAlertTone.marimba);
    expect(voices.every((voice) => voice.startHz < 600), isTrue);
    expect(voices.any((voice) => voice.startHz < 180), isTrue);
  });

  test('success rises through a major triad', () {
    final leads = newOrderAlertVoicesFor(NewOrderAlertTone.successRise)
        .where((voice) => voice.type == 'triangle')
        .toList();
    expect(leads.map((voice) => voice.startHz.round()), [523, 659, 784]);
    expect(leads[0].delay, lessThan(leads[1].delay));
    expect(leads[1].delay, lessThan(leads[2].delay));
  });
}

double _max(double a, double b) => a > b ? a : b;
