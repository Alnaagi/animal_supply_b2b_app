import 'dart:js_interop';

import 'package:web/web.dart' as web;

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

Future<bool> playNewOrderAlertSound() async {
  if (!await primeNewOrderAlertSound()) return false;

  try {
    final context = _audioContext!;
    final startedAt = context.currentTime;
    final oscillator = context.createOscillator();
    final gain = context.createGain();

    oscillator
      ..type = 'sine'
      ..frequency.setValueAtTime(880, startedAt)
      ..frequency.setValueAtTime(1174.66, startedAt + 0.16);
    gain.gain
      ..setValueAtTime(0.0001, startedAt)
      ..exponentialRampToValueAtTime(0.22, startedAt + 0.015)
      ..exponentialRampToValueAtTime(0.0001, startedAt + 0.38);

    oscillator.connect(gain);
    gain.connect(context.destination);
    oscillator.start(startedAt);
    oscillator.stop(startedAt + 0.4);
    return true;
  } catch (_) {
    return false;
  }
}
