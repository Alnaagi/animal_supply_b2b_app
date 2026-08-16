import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/new_order_alert_sound.dart';
import '../../core/notifications/new_order_alert_sound_prefs.dart';
import '../../core/notifications/new_order_alert_tone.dart';

class AdminOrderSoundSettingsPanel extends ConsumerWidget {
  const AdminOrderSoundSettingsPanel({
    required this.soundEnabled,
    required this.soundReady,
    super.key,
  });

  final bool soundEnabled;
  final bool soundReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(newOrderAlertSoundSettingsProvider);
    final volumePercent = (settings.clampedVolume * 100).round();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        key: const ValueKey('admin-orders-sound-settings'),
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(11, 11, 11, 8),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'صوت التنبيه',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              soundEnabled
                  ? 'نغمات أصلية مولَّدة داخل المتصفح — ليست ملفات متاجر أخرى. تُحفظ على هذا الجهاز.'
                  : 'شغّل صوت الطلبات أولاً ثم اختر النغمة ومستوى الصوت.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            for (final tone in NewOrderAlertTone.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _ToneRow(
                  tone: tone,
                  selected: settings.tone == tone,
                  enabled: soundEnabled,
                  onSelect: () => _selectAndPreview(ref, tone),
                  onPreview: () => _preview(ref, tone, settings.clampedVolume),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.volume_down_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider(
                    key: const ValueKey('admin-orders-sound-volume-slider'),
                    value: settings.clampedVolume,
                    min: NewOrderAlertSoundSettings.minVolume,
                    max: NewOrderAlertSoundSettings.maxVolume,
                    label: '$volumePercent٪',
                    onChanged: soundEnabled
                        ? (value) => ref
                            .read(newOrderAlertSoundSettingsProvider.notifier)
                            .setVolume(value)
                        : null,
                    onChangeEnd: soundEnabled
                        ? (value) => _preview(ref, settings.tone, value)
                        : null,
                  ),
                ),
                Icon(
                  Icons.volume_up_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  '$volumePercent٪',
                  key: const ValueKey('admin-orders-sound-volume-label'),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (!soundReady && soundEnabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'اضغط رمز الصوت أعلاه مرة واحدة إذا لم يُسمع التنبيه بعد.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectAndPreview(WidgetRef ref, NewOrderAlertTone tone) async {
    await ref.read(newOrderAlertSoundSettingsProvider.notifier).setTone(tone);
    final volume = ref.read(newOrderAlertSoundSettingsProvider).clampedVolume;
    await _preview(ref, tone, volume);
  }

  Future<void> _preview(
    WidgetRef ref,
    NewOrderAlertTone tone,
    double volume,
  ) async {
    final sound = ref.read(newOrderAlertSoundProvider);
    if (!sound.isAvailable) return;
    final ready = await sound.prime();
    if (!ready) return;
    await sound.play(tone: tone, volume: volume);
  }
}

class _ToneRow extends StatelessWidget {
  const _ToneRow({
    required this.tone,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onPreview,
  });

  final NewOrderAlertTone tone;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = selected
        ? scheme.primary
        : scheme.outlineVariant.withValues(alpha: .8);
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: .10)
          : scheme.surface.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('admin-orders-sound-tone-${tone.id}'),
        onTap: enabled ? onSelect : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : tone.icon,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tone.labelAr,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    Text(
                      tone.captionAr,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 10.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('admin-orders-sound-preview-${tone.id}'),
                tooltip: 'معاينة ${tone.labelAr}',
                onPressed: enabled ? onPreview : null,
                icon: const Icon(Icons.play_circle_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
