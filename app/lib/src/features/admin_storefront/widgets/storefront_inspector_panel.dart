import 'package:flutter/material.dart';

import '../../../data/models/storefront_config.dart';
import '../admin_storefront_controller.dart';

class StorefrontInspectorPanel extends StatelessWidget {
  const StorefrontInspectorPanel({
    required this.state,
    required this.controller,
    super.key,
  });

  final StorefrontBuilderState state;
  final AdminStorefrontController controller;

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedSection;
    final section = selected == null ? null : state.draft.section(selected);

    return ColoredBox(
      color: Colors.white,
      child: ListView(
        key: const Key('storefront-inspector-panel'),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'إعدادات القسم',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              if (section != null)
                Chip(
                  label: Text(section.type.labelAr),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (section != null) ...[
            ..._commonFields(section, controller),
            const SizedBox(height: 8),
            ..._sectionFields(section, controller),
          ] else if (state.sidebarMode == StorefrontSidebarMode.design)
            _ThemeSummary(theme: state.draft.theme, style: state.draft.style)
          else
            _EmptyInspectorHint(mode: state.sidebarMode),
        ],
      ),
    );
  }

  List<Widget> _commonFields(
    StorefrontSectionConfig section,
    AdminStorefrontController controller,
  ) {
    void setSetting(String key, dynamic value) {
      controller.updateSectionSettings(section.type, {key: value});
    }

    final fields = <Widget>[
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('ظاهر في المتجر'),
        value: section.visible,
        onChanged: (value) {
          controller.setSectionVisible(section.type, value);
        },
      ),
    ];

    if (_hasTitle(section.type)) {
      fields.addAll([
        TextFormField(
          initialValue:
              section.settingString('title', _defaultTitle(section.type)),
          decoration: const InputDecoration(labelText: 'العنوان'),
          onChanged: (value) => setSetting('title', value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('إظهار العنوان'),
          value: section.settingBool('showTitle', fallback: true),
          onChanged: (value) => setSetting('showTitle', value),
        ),
      ]);
    }

    if (_supportsLayout(section.type)) {
      fields.add(
        DropdownButtonFormField<String>(
          initialValue: section.settingString('layout', 'default'),
          decoration: const InputDecoration(labelText: 'التخطيط'),
          items: const [
            DropdownMenuItem(value: 'default', child: Text('افتراضي')),
            DropdownMenuItem(value: 'compact', child: Text('مضغوط')),
            DropdownMenuItem(value: 'carousel', child: Text('عرض متحرك')),
          ],
          onChanged: (value) {
            if (value != null) setSetting('layout', value);
          },
        ),
      );
    }

    if (_supportsSizePreset(section.type)) {
      fields.add(
        DropdownButtonFormField<String>(
          initialValue: section.settingString('sizePreset', 'default'),
          decoration: const InputDecoration(labelText: 'حجم العرض'),
          items: const [
            DropdownMenuItem(value: 'compact', child: Text('صغير')),
            DropdownMenuItem(value: 'default', child: Text('متوسط')),
            DropdownMenuItem(value: 'large', child: Text('كبير')),
          ],
          onChanged: (value) {
            if (value != null) setSetting('sizePreset', value);
          },
        ),
      );
    }

    if (_supportsSpacing(section.type)) {
      fields.add(
        _SliderField(
          label: 'المسافة الداخلية',
          value: section.settingInt('spacing', fallback: 12).toDouble(),
          min: 0,
          max: 32,
          onChanged: (value) => setSetting('spacing', value.round()),
        ),
      );
    }

    return fields;
  }

  List<Widget> _sectionFields(
    StorefrontSectionConfig section,
    AdminStorefrontController controller,
  ) {
    void setSetting(String key, dynamic value) {
      controller.updateSectionSettings(section.type, {key: value});
    }

    switch (section.type) {
      case StorefrontSectionType.header:
        return [
          const Divider(height: 24),
          const Text(
            'خيارات الترحيب',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('إظهار البحث'),
            value: section.settingBool('showSearch', fallback: true),
            onChanged: (value) => setSetting('showSearch', value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('إظهار الإشعارات'),
            value: section.settingBool('showNotifications', fallback: true),
            onChanged: (value) => setSetting('showNotifications', value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('إظهار الموقع'),
            value: section.settingBool('showLocation', fallback: true),
            onChanged: (value) => setSetting('showLocation', value),
          ),
        ];
      case StorefrontSectionType.banner:
        return [
          const Divider(height: 24),
          const Text(
            'خيارات البانر',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          _SliderField(
            label: 'ارتفاع البانر',
            value: section.settingInt('height', fallback: 88).toDouble(),
            min: 72,
            max: 320,
            onChanged: (value) => setSetting('height', value.round()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('تشغيل تلقائي'),
            value: section.settingBool('autoPlay', fallback: true),
            onChanged: (value) => setSetting('autoPlay', value),
          ),
          _SliderField(
            label: 'مدة العرض (ث)',
            value:
                section.settingInt('intervalSeconds', fallback: 5).toDouble(),
            min: 2,
            max: 30,
            onChanged: (value) => setSetting('intervalSeconds', value.round()),
          ),
        ];
      case StorefrontSectionType.categories:
        return [
          const Divider(height: 24),
          const Text(
            'خيارات التصنيفات',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          _SliderField(
            label: 'الحد الأقصى',
            value: section.settingInt('maxVisible', fallback: 20).toDouble(),
            min: 4,
            max: 50,
            onChanged: (value) => setSetting('maxVisible', value.round()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('إظهار العدد'),
            value: section.settingBool('showCount', fallback: true),
            onChanged: (value) => setSetting('showCount', value),
          ),
        ];
      case StorefrontSectionType.featuredProducts:
      case StorefrontSectionType.offers:
      case StorefrontSectionType.latestProducts:
        return [
          const Divider(height: 24),
          Text(
            'خيارات ${section.type.labelAr}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          _SliderField(
            label: 'عدد المنتجات',
            value: section.settingInt('maxItems', fallback: 12).toDouble(),
            min: 4,
            max: 24,
            onChanged: (value) => setSetting('maxItems', value.round()),
          ),
          if (section.type != StorefrontSectionType.latestProducts)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إخفاء عند الفراغ'),
              value: section.settingBool('hideWhenEmpty', fallback: true),
              onChanged: (value) => setSetting('hideWhenEmpty', value),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('زر الإضافة للسلة'),
            value: section.settingBool('showAddToCart', fallback: true),
            onChanged: (value) => setSetting('showAddToCart', value),
          ),
        ];
      case StorefrontSectionType.bestSelling:
        return [
          const Divider(height: 24),
          const Text(
            'خيارات الأكثر طلباً',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          _SliderField(
            label: 'عدد المنتجات',
            value: section.settingInt('maxItems', fallback: 12).toDouble(),
            min: 4,
            max: 24,
            onChanged: (value) => setSetting('maxItems', value.round()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('الاحتياطي: أحدث المنتجات'),
            subtitle: const Text('يستخدم is_top_selling ثم أحدث المنتجات'),
            value: section.settingBool('fallbackToLatest', fallback: true),
            onChanged: (value) => setSetting('fallbackToLatest', value),
          ),
        ];
      case StorefrontSectionType.recentOrder:
        return [
          const Divider(height: 24),
          const Text(
            'خيارات إعادة الطلب',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('إظهار عدد المنتجات'),
            value: section.settingBool('showItemCount', fallback: true),
            onChanged: (value) => setSetting('showItemCount', value),
          ),
        ];
    }
  }

  bool _hasTitle(StorefrontSectionType type) {
    return type != StorefrontSectionType.header &&
        type != StorefrontSectionType.banner;
  }

  String _defaultTitle(StorefrontSectionType type) => type.labelAr;

  bool _supportsLayout(StorefrontSectionType type) {
    return type == StorefrontSectionType.featuredProducts ||
        type == StorefrontSectionType.offers ||
        type == StorefrontSectionType.latestProducts ||
        type == StorefrontSectionType.bestSelling;
  }

  bool _supportsSizePreset(StorefrontSectionType type) {
    return type == StorefrontSectionType.banner || _supportsLayout(type);
  }

  bool _supportsSpacing(StorefrontSectionType type) {
    return type != StorefrontSectionType.header;
  }
}

class _ThemeSummary extends StatelessWidget {
  const _ThemeSummary({required this.theme, required this.style});

  final StorefrontThemeConfig theme;
  final StorefrontStyleConfig style;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('storefront-theme-summary'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ملخص التصميم',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 12),
            Text('القالب: ${theme.preset.labelAr}'),
            const SizedBox(height: 8),
            Row(
              children: [
                _ColorSwatch(color: theme.primaryColor, label: 'أساسي'),
                const SizedBox(width: 8),
                _ColorSwatch(color: theme.textColor, label: 'نص'),
                const SizedBox(width: 8),
                _ColorSwatch(color: theme.backgroundColor, label: 'خلفية'),
              ],
            ),
            const SizedBox(height: 12),
            Text('كثافة: ${_densityLabel(style.density)}'),
            Text('مسافة الأقسام: ${style.sectionSpacing.round()}'),
            const SizedBox(height: 12),
            Text(
              'عدّل الألوان والأسلوب من تبويب التصميم في اللوحة اليسرى.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _densityLabel(StorefrontDensity density) {
    switch (density) {
      case StorefrontDensity.compact:
        return 'مضغوط';
      case StorefrontDensity.comfortable:
        return 'مريح';
      case StorefrontDensity.spacious:
        return 'فسيح';
    }
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _EmptyInspectorHint extends StatelessWidget {
  const _EmptyInspectorHint({required this.mode});

  final StorefrontSidebarMode mode;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.touch_app_outlined,
                size: 36, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            const Text(
              'اختر قسماً من القائمة لتعديل إعداداته',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (mode == StorefrontSidebarMode.page) ...[
              const SizedBox(height: 8),
              Text(
                'إعدادات الصفحة والمعاينة متوفرة في اللوحة اليسرى.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ],
        ),
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label (${value.round()})'),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          activeColor: scheme.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
