import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'new_order_alert_tone.dart';
import 'new_order_alert_voices.dart';

web.AudioContext? _audioContext;

const bool isNewOrderAlertSoundAvailable = true;

web.AudioContext _usableContext() {
  final current = _audioContext;
  if (current == null || current.state == 'closed') {
    return _audioContext = web.AudioContext();
  }
  return current;
}

Future<bool> primeNewOrderAlertSound() async {
  try {
    final context = _usableContext();
    if (context.state != 'running') {
      await context.resume().toDart;
    }
    return context.state == 'running';
  } catch (_) {
    return false;
  }
}

Future<bool> playNewOrderAlertSound({
  NewOrderAlertTone tone = NewOrderAlertTone.chaChing,
  double volume = NewOrderAlertSoundSettings.defaultVolume,
}) async {
  if (!await primeNewOrderAlertSound()) return false;

  try {
    final context = _audioContext!;
    final startedAt = context.currentTime;
    final masterGain = volume
        .clamp(
          NewOrderAlertSoundSettings.minVolume,
          NewOrderAlertSoundSettings.maxVolume,
        )
        .toDouble();
    final destination = _masterDestination(
      context,
      startedAt: startedAt,
      volume: masterGain,
    );

    for (final voice in newOrderAlertVoicesFor(tone)) {
      _startVoice(
        context,
        destination: destination,
        startedAt: startedAt + voice.delay,
        voice: voice,
      );
    }
    return true;
  } catch (_) {
    return false;
  }
}

web.AudioNode _masterDestination(
  web.AudioContext context, {
  required double startedAt,
  required double volume,
}) {
  final gain = context.createGain();
  gain.gain.setValueAtTime(volume, startedAt);
  gain.connect(_compressedDestination(context, startedAt));
  return gain;
}

web.AudioNode _compressedDestination(
  web.AudioContext context,
  double startedAt,
) {
  try {
    final compressor = context.createDynamicsCompressor();
    compressor.threshold.setValueAtTime(-18, startedAt);
    compressor.knee.setValueAtTime(8, startedAt);
    compressor.ratio.setValueAtTime(2.2, startedAt);
    compressor.attack.setValueAtTime(0.004, startedAt);
    compressor.release.setValueAtTime(0.18, startedAt);
    compressor.connect(context.destination);
    return compressor;
  } catch (_) {
    return context.destination;
  }
}

void _startVoice(
  web.AudioContext context, {
  required web.AudioNode destination,
  required double startedAt,
  required NewOrderAlertVoice voice,
}) {
  final oscillator = context.createOscillator();
  final gain = context.createGain();
  final attack = voice.attack.clamp(0.0004, voice.duration * 0.45);
  final peakAt = startedAt + attack;
  final endAt = startedAt + voice.duration;
  final safeEnd = voice.endHz < 20 ? 20.0 : voice.endHz;

  oscillator
    ..type = voice.type
    ..frequency.setValueAtTime(voice.startHz, startedAt);
  if (!voice.holdsPitch) {
    oscillator.frequency.exponentialRampToValueAtTime(safeEnd, endAt);
  }

  gain.gain
    ..setValueAtTime(0.0001, startedAt)
    ..exponentialRampToValueAtTime(voice.peakGain, peakAt)
    ..exponentialRampToValueAtTime(0.0001, endAt);

  web.AudioNode voiceOut = oscillator;
  final filterHz = voice.filterHz;
  if (filterHz != null && filterHz > 20) {
    try {
      final filter = context.createBiquadFilter();
      filter.type = 'lowpass';
      filter.frequency.setValueAtTime(filterHz, startedAt);
      filter.Q.setValueAtTime(0.65, startedAt);
      oscillator.connect(filter);
      voiceOut = filter;
    } catch (_) {
      voiceOut = oscillator;
    }
  }

  voiceOut.connect(gain);
  gain.connect(destination);
  oscillator.start(startedAt);
  oscillator.stop(endAt);
}
