import 'new_order_alert_tone.dart';

/// One oscillator event in an original (non-sampled) alert patch.
class NewOrderAlertVoice {
  const NewOrderAlertVoice({
    required this.type,
    required this.startHz,
    required this.endHz,
    required this.delay,
    required this.duration,
    required this.peakGain,
    this.attack = 0.008,
    this.filterHz,
  });

  /// Web Audio oscillator type: `sine`, `triangle`, or `square`.
  final String type;
  final double startHz;
  final double endHz;
  final double delay;
  final double duration;
  final double peakGain;
  final double attack;

  /// Optional low-pass cutoff so square/triangle partials stay musical.
  final double? filterHz;

  bool get holdsPitch => (startHz - endHz).abs() < 0.5;
}

/// Distinct original patches. Each preset must differ in register, rhythm,
/// envelope, and oscillator mix so they cannot collapse into one beep.
List<NewOrderAlertVoice> newOrderAlertVoicesFor(NewOrderAlertTone tone) {
  switch (tone) {
    case NewOrderAlertTone.chaChing:
      return const [
        // Metallic "ching" — high ding with a bright inharmonic partial.
        NewOrderAlertVoice(
          type: 'triangle',
          startHz: 2489.02,
          endHz: 2489.02,
          delay: 0,
          duration: 0.42,
          peakGain: 0.48,
          attack: 0.0014,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 3728.5,
          endHz: 3520,
          delay: 0.004,
          duration: 0.2,
          peakGain: 0.15,
          attack: 0.001,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 1864.66,
          endHz: 1864.66,
          delay: 0.018,
          duration: 0.34,
          peakGain: 0.32,
          attack: 0.002,
        ),
        // Springy cash-drawer thunk in the low mids.
        NewOrderAlertVoice(
          type: 'square',
          startHz: 174.61,
          endHz: 98,
          delay: 0.072,
          duration: 0.22,
          peakGain: 0.17,
          attack: 0.004,
          filterHz: 780,
        ),
        NewOrderAlertVoice(
          type: 'triangle',
          startHz: 116.54,
          endHz: 73.42,
          delay: 0.088,
          duration: 0.28,
          peakGain: 0.26,
          attack: 0.006,
          filterHz: 520,
        ),
      ];
    case NewOrderAlertTone.shopBell:
      return const [
        // Classic ding–dong (G5 then E5) with long ringing decay.
        NewOrderAlertVoice(
          type: 'triangle',
          startHz: 783.99,
          endHz: 783.99,
          delay: 0,
          duration: 1.05,
          peakGain: 0.4,
          attack: 0.005,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 1567.98,
          endHz: 1567.98,
          delay: 0.01,
          duration: 0.62,
          peakGain: 0.11,
          attack: 0.006,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 787.2,
          endHz: 787.2,
          delay: 0.02,
          duration: 0.9,
          peakGain: 0.09,
          attack: 0.008,
        ),
        NewOrderAlertVoice(
          type: 'triangle',
          startHz: 659.25,
          endHz: 659.25,
          delay: 0.28,
          duration: 1.15,
          peakGain: 0.38,
          attack: 0.006,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 1318.51,
          endHz: 1318.51,
          delay: 0.29,
          duration: 0.7,
          peakGain: 0.1,
          attack: 0.007,
        ),
      ];
    case NewOrderAlertTone.crystal:
      return const [
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 3127,
          endHz: 3127,
          delay: 0,
          duration: 0.92,
          peakGain: 0.22,
          attack: 0.004,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 3194,
          endHz: 3194,
          delay: 0.03,
          duration: 0.84,
          peakGain: 0.09,
          attack: 0.006,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 2683,
          endHz: 2683,
          delay: 0.06,
          duration: 0.98,
          peakGain: 0.16,
          attack: 0.005,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 4211,
          endHz: 4100,
          delay: 0.1,
          duration: 0.72,
          peakGain: 0.14,
          attack: 0.003,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 5477,
          endHz: 5200,
          delay: 0.16,
          duration: 0.4,
          peakGain: 0.08,
          attack: 0.002,
        ),
      ];
    case NewOrderAlertTone.goldCoin:
      return const [
        NewOrderAlertVoice(
          type: 'triangle',
          startHz: 2793.83,
          endHz: 2637.02,
          delay: 0,
          duration: 0.13,
          peakGain: 0.5,
          attack: 0.0008,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 5587.65,
          endHz: 5274.04,
          delay: 0,
          duration: 0.07,
          peakGain: 0.14,
          attack: 0.0006,
        ),
        NewOrderAlertVoice(
          type: 'triangle',
          startHz: 2093,
          endHz: 1975.53,
          delay: 0.09,
          duration: 0.08,
          peakGain: 0.2,
          attack: 0.001,
        ),
      ];
    case NewOrderAlertTone.marimba:
      return const [
        NewOrderAlertVoice(
          type: 'triangle',
          startHz: 261.63,
          endHz: 246.94,
          delay: 0,
          duration: 0.44,
          peakGain: 0.5,
          attack: 0.003,
          filterHz: 1800,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 523.25,
          endHz: 493.88,
          delay: 0,
          duration: 0.16,
          peakGain: 0.12,
          attack: 0.002,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 130.81,
          endHz: 123.47,
          delay: 0.004,
          duration: 0.36,
          peakGain: 0.16,
          attack: 0.006,
          filterHz: 900,
        ),
        NewOrderAlertVoice(
          type: 'triangle',
          startHz: 329.63,
          endHz: 311.13,
          delay: 0.15,
          duration: 0.5,
          peakGain: 0.46,
          attack: 0.003,
          filterHz: 1900,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 164.81,
          endHz: 155.56,
          delay: 0.154,
          duration: 0.4,
          peakGain: 0.14,
          attack: 0.007,
          filterHz: 900,
        ),
      ];
    case NewOrderAlertTone.sparkle:
      return const [
        NewOrderAlertVoice(
          type: 'triangle',
          startHz: 4698.63,
          endHz: 4978,
          delay: 0,
          duration: 0.055,
          peakGain: 0.34,
          attack: 0.0005,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 7040,
          endHz: 7450,
          delay: 0.004,
          duration: 0.04,
          peakGain: 0.12,
          attack: 0.0004,
        ),
      ];
    case NewOrderAlertTone.softChime:
      return const [
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 523.25,
          endHz: 523.25,
          delay: 0,
          duration: 1.4,
          peakGain: 0.16,
          attack: 0.028,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 659.25,
          endHz: 659.25,
          delay: 0.14,
          duration: 1.28,
          peakGain: 0.13,
          attack: 0.03,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 987.77,
          endHz: 987.77,
          delay: 0.08,
          duration: 1.05,
          peakGain: 0.06,
          attack: 0.04,
        ),
      ];
    case NewOrderAlertTone.successRise:
      return const [
        NewOrderAlertVoice(
          type: 'triangle',
          startHz: 523.25,
          endHz: 523.25,
          delay: 0,
          duration: 0.2,
          peakGain: 0.36,
          attack: 0.007,
          filterHz: 2400,
        ),
        NewOrderAlertVoice(
          type: 'triangle',
          startHz: 659.25,
          endHz: 659.25,
          delay: 0.12,
          duration: 0.22,
          peakGain: 0.38,
          attack: 0.007,
          filterHz: 2600,
        ),
        NewOrderAlertVoice(
          type: 'triangle',
          startHz: 783.99,
          endHz: 783.99,
          delay: 0.24,
          duration: 0.46,
          peakGain: 0.42,
          attack: 0.008,
          filterHz: 2800,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 523.25,
          endHz: 523.25,
          delay: 0.24,
          duration: 0.46,
          peakGain: 0.16,
          attack: 0.012,
        ),
        NewOrderAlertVoice(
          type: 'sine',
          startHz: 1174.66,
          endHz: 1174.66,
          delay: 0.26,
          duration: 0.38,
          peakGain: 0.1,
          attack: 0.01,
        ),
      ];
  }
}
