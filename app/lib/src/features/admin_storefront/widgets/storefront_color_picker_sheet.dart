import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// Shared HEX helpers — keep `#` on the leading side even under RTL.
String storefrontColorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

Color? storefrontColorFromHex(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'\s'), '');
  // Repair RTL-mangled values like `f5f0e8#`.
  if (s.endsWith('#')) {
    s = '#${s.substring(0, s.length - 1)}';
  }
  if (!s.startsWith('#')) {
    s = '#$s';
  }
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(s)) return null;
  return Color(int.parse(s.substring(1), radix: 16) + 0xFF000000);
}

const List<Color> kStorefrontColorPresets = [
  Color(0xff146c4e),
  Color(0xff1a3d2e),
  Color(0xff8a623f),
  Color(0xfff5f0e8),
  Color(0xffffffff),
  Color(0xff0f172a),
  Color(0xff2563eb),
  Color(0xffb45309),
  Color(0xff0d9488),
  Color(0xffdc2626),
  Color(0xff64748b),
  Color(0xfff8fafc),
];

Future<void> showStorefrontColorPickerSheet({
  required BuildContext context,
  required String label,
  required Color color,
  required ValueChanged<Color> onChanged,
  String? fieldKey,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _StorefrontColorPickerBody(
          label: label,
          initialColor: color,
          fieldKey: fieldKey,
          onChanged: onChanged,
        ),
      );
    },
  );
}

class _StorefrontColorPickerBody extends StatefulWidget {
  const _StorefrontColorPickerBody({
    required this.label,
    required this.initialColor,
    required this.onChanged,
    this.fieldKey,
  });

  final String label;
  final Color initialColor;
  final ValueChanged<Color> onChanged;
  final String? fieldKey;

  @override
  State<_StorefrontColorPickerBody> createState() =>
      _StorefrontColorPickerBodyState();
}

class _StorefrontColorPickerBodyState
    extends State<_StorefrontColorPickerBody> {
  late Color _color;
  late final TextEditingController _hexController;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _color = widget.initialColor.withValues(alpha: 1);
    _hexController = TextEditingController(text: storefrontColorToHex(_color));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _applyColor(Color next, {bool syncHex = true}) {
    final opaque = next.withValues(alpha: 1);
    setState(() {
      _color = opaque;
      _hexError = null;
      if (syncHex) {
        final hex = storefrontColorToHex(opaque);
        if (_hexController.text.toLowerCase() != hex) {
          _hexController.value = TextEditingValue(
            text: hex,
            selection: TextSelection.collapsed(offset: hex.length),
          );
        }
      }
    });
    widget.onChanged(opaque);
  }

  void _tryApplyHex(String raw) {
    final parsed = storefrontColorFromHex(raw);
    if (parsed == null) {
      setState(() => _hexError = 'صيغة غير صحيحة — استخدم #RRGGBB');
      return;
    }
    _applyColor(parsed, syncHex: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: Key(
        'storefront-color-picker-sheet${widget.fieldKey != null ? '-${widget.fieldKey}' : ''}',
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'اختر لوناً أو أدخل رمز HEX',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                key: const Key('storefront-color-picker-preview'),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextField(
                    key: const Key('storefront-color-picker-hex'),
                    controller: _hexController,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    keyboardType: TextInputType.text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                    decoration: InputDecoration(
                      labelText: 'HEX',
                      isDense: true,
                      errorText: _hexError,
                      border: const OutlineInputBorder(),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[#0-9A-Fa-f]'),
                      ),
                      LengthLimitingTextInputFormatter(7),
                    ],
                    onChanged: (value) {
                      final parsed = storefrontColorFromHex(value);
                      if (parsed != null) {
                        _applyColor(parsed, syncHex: false);
                      } else if (value.trim().isNotEmpty) {
                        setState(
                          () => _hexError = 'صيغة غير صحيحة — استخدم #RRGGBB',
                        );
                      }
                    },
                    onSubmitted: _tryApplyHex,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'ألوان سريعة',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in kStorefrontColorPresets)
                _PresetSwatch(
                  color: preset,
                  selected: _colorsEqual(preset, _color),
                  onTap: () => _applyColor(preset),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ColorPicker(
            pickerColor: _color,
            onColorChanged: _applyColor,
            enableAlpha: false,
            hexInputBar: false,
            labelTypes: const [],
            portraitOnly: true,
            pickerAreaHeightPercent: 0.55,
            displayThumbColor: true,
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('storefront-color-picker-done'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () {
              final parsed = storefrontColorFromHex(_hexController.text);
              if (parsed != null) {
                widget.onChanged(parsed);
              }
              Navigator.of(context).pop();
            },
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }

  bool _colorsEqual(Color a, Color b) =>
      (a.toARGB32() & 0xFFFFFF) == (b.toARGB32() & 0xFFFFFF);
}

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = color.computeLuminance() > 0.85;
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.black26,
          width: selected ? 2.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 40,
          child: selected
              ? Icon(
                  Icons.check,
                  size: 20,
                  color: isLight ? Colors.black87 : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}
