import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const double adminTextScaleDefault = 1.0;
const double adminTextScaleMin = 0.8;
const double adminTextScaleMax = 1.4;
const double adminTextScaleStep = 0.1;

double clampAdminTextScale(double value) {
  return value.clamp(adminTextScaleMin, adminTextScaleMax).toDouble();
}

class AdminTextScalePrefs {
  AdminTextScalePrefs({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const storageKey = 'admin.text_scale.v1';

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

  Future<double> load() async {
    try {
      final prefs = await _store();
      final raw = prefs?.getDouble(storageKey);
      return raw == null ? adminTextScaleDefault : clampAdminTextScale(raw);
    } catch (_) {
      return adminTextScaleDefault;
    }
  }

  Future<bool> save(double value) async {
    try {
      final prefs = await _store();
      if (prefs == null) return false;
      return prefs.setDouble(storageKey, clampAdminTextScale(value));
    } catch (_) {
      return false;
    }
  }
}

final adminTextScalePrefsProvider = Provider<AdminTextScalePrefs>(
  (ref) => AdminTextScalePrefs(),
);

final adminTextScaleProvider =
    StateNotifierProvider<AdminTextScaleController, double>(
  (ref) => AdminTextScaleController(
    ref.watch(adminTextScalePrefsProvider),
  ),
);

class AdminTextScaleController extends StateNotifier<double> {
  AdminTextScaleController(this._prefs) : super(adminTextScaleDefault) {
    unawaited(reload());
  }

  final AdminTextScalePrefs _prefs;
  bool _hasLocalUpdate = false;

  Future<void> reload() async {
    final loaded = await _prefs.load();
    if (!_hasLocalUpdate) state = loaded;
  }

  Future<void> setScale(double value) async {
    final next = clampAdminTextScale(value);
    _hasLocalUpdate = true;
    state = next;
    await _prefs.save(next);
  }

  Future<void> increase() => setScale(state + adminTextScaleStep);

  Future<void> decrease() => setScale(state - adminTextScaleStep);

  Future<void> reset() => setScale(adminTextScaleDefault);
}

class AdminTextScaleControls extends ConsumerWidget {
  const AdminTextScaleControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(adminTextScaleProvider);
    final percent = (scale * 100).round();
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Semantics(
      container: true,
      label: 'حجم نص لوحة الإدارة',
      child: Container(
        key: const Key('admin-text-scale-controls'),
        margin: const EdgeInsetsDirectional.only(start: 2, end: 2),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AdminTextScaleButton(
              key: const Key('admin-text-scale-decrease'),
              tooltip: 'تصغير النص',
              icon: Icons.remove,
              enabled: scale > adminTextScaleMin,
              onPressed: () =>
                  ref.read(adminTextScaleProvider.notifier).decrease(),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: compact ? 34 : 42,
              ),
              child: Text(
                '$percent%',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _AdminTextScaleButton(
              key: const Key('admin-text-scale-increase'),
              tooltip: 'تكبير النص',
              icon: Icons.add,
              enabled: scale < adminTextScaleMax,
              onPressed: () =>
                  ref.read(adminTextScaleProvider.notifier).increase(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminTextScaleButton extends StatelessWidget {
  const _AdminTextScaleButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 17),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 38),
    );
  }
}
