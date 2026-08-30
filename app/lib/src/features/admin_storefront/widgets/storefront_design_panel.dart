import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/storefront_config.dart';
import '../admin_storefront_controller.dart';
import '../apply_storefront_theme_to_admin.dart';
import 'storefront_color_picker_sheet.dart';

class StorefrontDesignPanel extends ConsumerWidget {
  const StorefrontDesignPanel({
    required this.state,
    required this.controller,
    this.onReset,
    super.key,
  });

  final StorefrontBuilderState state;
  final AdminStorefrontController controller;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final draftTheme = state.draft.theme;
    final applyToAdmin = ref.watch(applyStorefrontThemeToAdminProvider);
    final adminTheme = ref.watch(adminCustomThemeConfigProvider);
    return ListView(
      key: const Key('storefront-design-panel'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _GroupedCard(
          title: 'قوالب التصميم',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in StorefrontThemePreset.values)
                ChoiceChip(
                  label: Text(preset.labelAr),
                  selected: draftTheme.preset == preset,
                  onSelected: (_) => controller.applyThemePreset(preset),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _GroupedCard(
          title: 'الألوان',
          child: Column(
            children: [
              _ColorField(
                fieldKey: 'primary',
                label: 'اللون الأساسي',
                color: draftTheme.primaryColor,
                controller: controller,
                onChanged: (color) => controller.patchTheme(
                  (theme) => theme.copyWith(primaryColor: color),
                ),
              ),
              _ColorField(
                fieldKey: 'secondary',
                label: 'اللون الثانوي',
                color: draftTheme.secondaryColor,
                controller: controller,
                onChanged: (color) => controller.patchTheme(
                  (theme) => theme.copyWith(secondaryColor: color),
                ),
              ),
              _ColorField(
                fieldKey: 'text',
                label: 'لون النص',
                color: draftTheme.textColor,
                controller: controller,
                onChanged: (color) => controller.patchTheme(
                  (theme) => theme.copyWith(textColor: color),
                ),
              ),
              _ColorField(
                fieldKey: 'background',
                label: 'خلفية الصفحة',
                color: draftTheme.backgroundColor,
                controller: controller,
                onChanged: (color) => controller.patchTheme(
                  (theme) => theme.copyWith(backgroundColor: color),
                ),
              ),
              _ColorField(
                fieldKey: 'card',
                label: 'لون البطاقات',
                color: draftTheme.cardColor,
                controller: controller,
                onChanged: (color) => controller.patchTheme(
                  (theme) => theme.copyWith(cardColor: color),
                ),
              ),
              if (draftTheme.hasLowTextContrast)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '⚠️ تباين منخفض — قد يصعب قراءة النص على الخلفية.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const Divider(height: 24),
              SwitchListTile(
                key: const Key('storefront-separate-admin-colors'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'استخدام ألوان مستقلة للوحة الإدارة',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                subtitle: Text(
                  applyToAdmin
                      ? 'مفعّل لهذا الجهاز فقط — يمكنك تخصيص ألوان لوحة الإدارة بشكل مستقل عن ألوان المتجر.'
                      : 'عند الإيقاف تستخدم لوحة الإدارة ألوان المتجر المنشورة تلقائياً.',
                  style: theme.textTheme.bodySmall,
                ),
                value: applyToAdmin,
                onChanged: (value) {
                  ref
                      .read(applyStorefrontThemeToAdminProvider.notifier)
                      .setEnabled(value);
                },
              ),
              if (applyToAdmin) ...[
                const SizedBox(height: 8),
                Container(
                  key: const Key('admin-theme-customizer-section'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ألوان لوحة الإدارة',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          TextButton.icon(
                            key: const Key('storefront-admin-reset-colors'),
                            onPressed: () {
                              ref
                                  .read(adminCustomThemeConfigProvider.notifier)
                                  .resetToDefault();
                            },
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text(
                              'استعادة الافتراضي',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _ColorField(
                        controller: controller,
                        fieldKey: 'admin-primary',
                        label: 'اللون الأساسي للإدارة',
                        color: adminTheme.primaryColor,
                        onChanged: (color) {
                          ref
                              .read(adminCustomThemeConfigProvider.notifier)
                              .updateTheme(
                                adminTheme.copyWith(primaryColor: color),
                              );
                        },
                      ),
                      _ColorField(
                        controller: controller,
                        fieldKey: 'admin-background',
                        label: 'خلفية لوحة الإدارة',
                        color: adminTheme.backgroundColor,
                        onChanged: (color) {
                          ref
                              .read(adminCustomThemeConfigProvider.notifier)
                              .updateTheme(
                                adminTheme.copyWith(backgroundColor: color),
                              );
                        },
                      ),
                      _ColorField(
                        controller: controller,
                        fieldKey: 'admin-surface',
                        label: 'القوائم والبطاقات',
                        color: adminTheme.surfaceColor,
                        onChanged: (color) {
                          ref
                              .read(adminCustomThemeConfigProvider.notifier)
                              .updateTheme(
                                adminTheme.copyWith(surfaceColor: color),
                              );
                        },
                      ),
                      _ColorField(
                        controller: controller,
                        fieldKey: 'admin-text',
                        label: 'لون نصوص الإدارة',
                        color: adminTheme.textColor,
                        onChanged: (color) {
                          ref
                              .read(adminCustomThemeConfigProvider.notifier)
                              .updateTheme(
                                adminTheme.copyWith(textColor: color),
                              );
                        },
                      ),
                      if (adminTheme.hasLowTextContrast)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '⚠️ تباين منخفض — قد يصعب قراءة نصوص لوحة الإدارة على الخلفية.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _GroupedCard(
          title: 'الأسلوب',
          child: Column(
            children: [
              _SliderField(
                label: 'انحناء البطاقات',
                value: state.draft.style.cardRadius,
                min: 0,
                max: 48,
                onChanged: (value) => controller.updateStyle(
                  state.draft.style.copyWith(cardRadius: value),
                ),
              ),
              _SliderField(
                label: 'انحناء الأزرار',
                value: state.draft.style.buttonRadius,
                min: 0,
                max: 48,
                onChanged: (value) => controller.updateStyle(
                  state.draft.style.copyWith(buttonRadius: value),
                ),
              ),
              _SliderField(
                label: 'مسافة الأقسام',
                value: state.draft.style.sectionSpacing,
                min: 4,
                max: 48,
                onChanged: (value) => controller.updateStyle(
                  state.draft.style.copyWith(sectionSpacing: value),
                ),
              ),
              _SliderField(
                label: 'نسبة صورة المنتج',
                value: state.draft.style.productImageRatio,
                min: 0.5,
                max: 2,
                onChanged: (value) => controller.updateStyle(
                  state.draft.style.copyWith(productImageRatio: value),
                ),
              ),
              DropdownButtonFormField<StorefrontCardShadow>(
                initialValue: state.draft.style.cardShadow,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'ظل البطاقات'),
                items: const [
                  DropdownMenuItem(
                    value: StorefrontCardShadow.none,
                    child: Text('بدون'),
                  ),
                  DropdownMenuItem(
                    value: StorefrontCardShadow.light,
                    child: Text('خفيف'),
                  ),
                  DropdownMenuItem(
                    value: StorefrontCardShadow.medium,
                    child: Text('متوسط'),
                  ),
                  DropdownMenuItem(
                    value: StorefrontCardShadow.strong,
                    child: Text('قوي'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  controller.updateStyle(
                    state.draft.style.copyWith(cardShadow: value),
                  );
                },
              ),
              DropdownButtonFormField<StorefrontDensity>(
                initialValue: state.draft.style.density,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الكثافة'),
                items: const [
                  DropdownMenuItem(
                    value: StorefrontDensity.compact,
                    child: Text('مضغوط'),
                  ),
                  DropdownMenuItem(
                    value: StorefrontDensity.comfortable,
                    child: Text('مريح'),
                  ),
                  DropdownMenuItem(
                    value: StorefrontDensity.spacious,
                    child: Text('فسيح'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  controller.updateStyle(
                    state.draft.style.copyWith(density: value),
                  );
                },
              ),
            ],
          ),
        ),
        if (onReset != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('storefront-design-reset-button'),
            onPressed: state.saving || state.publishing ? null : onReset,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade400),
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.restart_alt),
            label: const Text('استعادة الافتراضي'),
          ),
        ],
      ],
    );
  }
}

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ColorField extends StatefulWidget {
  const _ColorField({
    required this.fieldKey,
    required this.label,
    required this.color,
    required this.onChanged,
    this.controller,
  });

  final String fieldKey;
  final String label;
  final Color color;
  final AdminStorefrontController? controller;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  late final TextEditingController _hexController;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _hexController =
        TextEditingController(text: storefrontColorToHex(widget.color));
  }

  @override
  void didUpdateWidget(covariant _ColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      final hex = storefrontColorToHex(widget.color);
      if (_hexController.text.toLowerCase() != hex) {
        _hexController.value = TextEditingValue(
          text: hex,
          selection: TextSelection.collapsed(offset: hex.length),
        );
      }
      _hexError = null;
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Future<void> _openPicker() async {
    await showStorefrontColorPickerSheet(
      context: context,
      label: widget.label,
      color: widget.color,
      fieldKey: widget.fieldKey,
      onChanged: widget.onChanged,
    );
    await widget.controller?.flushAutosave();
  }

  void _applyHex(String raw) {
    final parsed = storefrontColorFromHex(raw);
    if (parsed == null) {
      setState(() => _hexError = 'غير صالح');
      return;
    }
    setState(() => _hexError = null);
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final swatch = Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('storefront-color-swatch-${widget.fieldKey}'),
              onTap: _openPicker,
              borderRadius: BorderRadius.circular(10),
              child: Ink(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black26),
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.colorize,
                      size: 12,
                      color: widget.color.computeLuminance() > 0.55
                          ? Colors.black54
                          : Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
          );
          // Keep HEX compact so Arabic RTL labels are not starved/ellipsized.
          final hexWidth = constraints.maxWidth < 280 ? 72.0 : 84.0;
          final hexField = SizedBox(
            width: hexWidth,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                key: Key('storefront-color-hex-${widget.fieldKey}'),
                controller: _hexController,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  errorText: _hexError,
                  errorStyle: const TextStyle(fontSize: 10),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  border: const OutlineInputBorder(),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[#0-9A-Fa-f]')),
                  LengthLimitingTextInputFormatter(7),
                ],
                onChanged: (value) {
                  final parsed = storefrontColorFromHex(value);
                  if (parsed != null) {
                    setState(() => _hexError = null);
                    widget.onChanged(parsed);
                  } else if (value.trim().isNotEmpty) {
                    setState(() => _hexError = 'غير صالح');
                  }
                },
                onSubmitted: _applyHex,
              ),
            ),
          );
          final editButton = IconButton(
            key: Key('storefront-color-edit-${widget.fieldKey}'),
            tooltip: 'اختيار اللون',
            onPressed: _openPicker,
            icon: const Icon(Icons.palette_outlined, size: 20),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
            padding: EdgeInsets.zero,
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.clip,
                ),
              ),
              const SizedBox(width: 4),
              swatch,
              const SizedBox(width: 4),
              hexField,
              editButton,
            ],
          );
        },
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$label (${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)})',
          style: const TextStyle(fontSize: 13),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          activeColor: Theme.of(context).colorScheme.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
