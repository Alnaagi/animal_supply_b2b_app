import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Storefront config schema version supported by this app build.
const storefrontConfigSchemaVersion = 1;

/// Core section types — exactly one instance each in v1.
enum StorefrontSectionType {
  header('header', 'الترحيب'),
  banner('banner', 'البانر'),
  categories('categories', 'التصنيفات'),
  featuredProducts('featured_products', 'منتجات مميزة'),
  offers('offers', 'العروض'),
  bestSelling('best_selling', 'الأكثر طلباً'),
  latestProducts('latest_products', 'أحدث المنتجات'),
  recentOrder('recent_order', 'إعادة آخر طلب');

  const StorefrontSectionType(this.key, this.labelAr);

  final String key;
  final String labelAr;

  static StorefrontSectionType? fromKey(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final type in values) {
      if (type.key == raw) return type;
    }
    return null;
  }
}

enum StorefrontThemePreset {
  defaultPreset('default', 'الافتراضي'),
  clean('clean', 'نظيف'),
  warm('warm', 'دافئ'),
  modern('modern', 'حديث');

  const StorefrontThemePreset(this.key, this.labelAr);

  final String key;
  final String labelAr;

  static StorefrontThemePreset fromKey(String? raw) {
    return values.firstWhere(
      (preset) => preset.key == raw,
      orElse: () => defaultPreset,
    );
  }
}

enum StorefrontCardShadow {
  none('none'),
  light('light'),
  medium('medium'),
  strong('strong');

  const StorefrontCardShadow(this.key);

  final String key;

  static StorefrontCardShadow fromKey(String? raw) {
    return values.firstWhere(
      (value) => value.key == raw,
      orElse: () => medium,
    );
  }
}

enum StorefrontDensity {
  compact('compact'),
  comfortable('comfortable'),
  spacious('spacious');

  const StorefrontDensity(this.key);

  final String key;

  static StorefrontDensity fromKey(String? raw) {
    return values.firstWhere(
      (value) => value.key == raw,
      orElse: () => comfortable,
    );
  }
}

class StorefrontThemeConfig {
  const StorefrontThemeConfig({
    this.preset = StorefrontThemePreset.defaultPreset,
    this.primaryColor = const Color(0xff146c4e),
    this.secondaryColor = const Color(0xff8a623f),
    this.backgroundColor = const Color(0xfff7f2ea),
    this.cardColor = Colors.white,
    this.textColor = const Color(0xff173f32),
  });

  final StorefrontThemePreset preset;
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color textColor;

  StorefrontThemeConfig copyWith({
    StorefrontThemePreset? preset,
    Color? primaryColor,
    Color? secondaryColor,
    Color? backgroundColor,
    Color? cardColor,
    Color? textColor,
  }) {
    return StorefrontThemeConfig(
      preset: preset ?? this.preset,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      cardColor: cardColor ?? this.cardColor,
      textColor: textColor ?? this.textColor,
    );
  }

  Map<String, dynamic> toJson() => {
        'preset': preset.key,
        'primaryColor': _colorToHex(primaryColor),
        'secondaryColor': _colorToHex(secondaryColor),
        'backgroundColor': _colorToHex(backgroundColor),
        'cardColor': _colorToHex(cardColor),
        'textColor': _colorToHex(textColor),
      };

  factory StorefrontThemeConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const StorefrontThemeConfig();
    return StorefrontThemeConfig(
      preset: StorefrontThemePreset.fromKey(json['preset'] as String?),
      primaryColor: _colorFromHex(json['primaryColor'] as String?, 0xff146c4e),
      secondaryColor:
          _colorFromHex(json['secondaryColor'] as String?, 0xff8a623f),
      backgroundColor:
          _colorFromHex(json['backgroundColor'] as String?, 0xfff7f2ea),
      cardColor: _colorFromHex(json['cardColor'] as String?, 0xffffffff),
      textColor: _colorFromHex(json['textColor'] as String?, 0xff173f32),
    );
  }

  /// Relative luminance contrast ratio (WCAG).
  double contrastRatio(Color foreground, Color background) {
    final l1 = _relativeLuminance(foreground);
    final l2 = _relativeLuminance(background);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  bool get hasLowTextContrast =>
      contrastRatio(textColor, backgroundColor) < 4.5 ||
      contrastRatio(textColor, cardColor) < 4.5;

  static double _relativeLuminance(Color color) {
    double channel(double value) {
      final c = value / 255;
      return c <= 0.03928
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel((color.r * 255.0).round().toDouble()) +
        0.7152 * channel((color.g * 255.0).round().toDouble()) +
        0.0722 * channel((color.b * 255.0).round().toDouble());
  }
}

class StorefrontStyleConfig {
  const StorefrontStyleConfig({
    this.cardRadius = 22,
    this.buttonRadius = 18,
    this.cardShadow = StorefrontCardShadow.medium,
    this.density = StorefrontDensity.comfortable,
    this.sectionSpacing = 14,
    this.productImageRatio = 1.0,
  });

  final double cardRadius;
  final double buttonRadius;
  final StorefrontCardShadow cardShadow;
  final StorefrontDensity density;
  final double sectionSpacing;
  final double productImageRatio;

  StorefrontStyleConfig copyWith({
    double? cardRadius,
    double? buttonRadius,
    StorefrontCardShadow? cardShadow,
    StorefrontDensity? density,
    double? sectionSpacing,
    double? productImageRatio,
  }) {
    return StorefrontStyleConfig(
      cardRadius: cardRadius ?? this.cardRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      cardShadow: cardShadow ?? this.cardShadow,
      density: density ?? this.density,
      sectionSpacing: sectionSpacing ?? this.sectionSpacing,
      productImageRatio: productImageRatio ?? this.productImageRatio,
    );
  }

  List<BoxShadow> get cardBoxShadow {
    switch (cardShadow) {
      case StorefrontCardShadow.none:
        return const [];
      case StorefrontCardShadow.light:
        return [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ];
      case StorefrontCardShadow.medium:
        return [
          BoxShadow(
            color: Colors.black.withValues(alpha: .08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ];
      case StorefrontCardShadow.strong:
        return [
          BoxShadow(
            color: Colors.black.withValues(alpha: .14),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ];
    }
  }

  double get densityScale {
    switch (density) {
      case StorefrontDensity.compact:
        return 0.85;
      case StorefrontDensity.comfortable:
        return 1.0;
      case StorefrontDensity.spacious:
        return 1.15;
    }
  }

  Map<String, dynamic> toJson() => {
        'cardRadius': cardRadius,
        'buttonRadius': buttonRadius,
        'cardShadow': cardShadow.key,
        'density': density.key,
        'sectionSpacing': sectionSpacing,
        'productImageRatio': productImageRatio,
      };

  factory StorefrontStyleConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const StorefrontStyleConfig();
    return StorefrontStyleConfig(
      cardRadius: _num(json['cardRadius'], 22, 0, 48),
      buttonRadius: _num(json['buttonRadius'], 18, 0, 48),
      cardShadow: StorefrontCardShadow.fromKey(json['cardShadow'] as String?),
      density: StorefrontDensity.fromKey(json['density'] as String?),
      sectionSpacing: _num(json['sectionSpacing'], 14, 4, 48),
      productImageRatio: _num(json['productImageRatio'], 1.0, 0.5, 2.0),
    );
  }
}

class StorefrontSectionConfig {
  const StorefrontSectionConfig({
    required this.type,
    this.visible = true,
    this.settings = const {},
  });

  final StorefrontSectionType type;
  final bool visible;
  final Map<String, dynamic> settings;

  String settingString(String key, String fallback) {
    final value = settings[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  bool settingBool(String key, {required bool fallback}) {
    final value = settings[key];
    if (value is bool) return value;
    return fallback;
  }

  int settingInt(String key,
      {required int fallback, int min = 1, int max = 100}) {
    final value = settings[key];
    if (value is num) {
      return value.round().clamp(min, max);
    }
    return fallback.clamp(min, max);
  }

  StorefrontSectionConfig copyWith({
    bool? visible,
    Map<String, dynamic>? settings,
  }) {
    return StorefrontSectionConfig(
      type: type,
      visible: visible ?? this.visible,
      settings: settings ?? this.settings,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.key,
        'visible': visible,
        'settings': settings,
      };

  factory StorefrontSectionConfig.fromJson(Map<String, dynamic> json) {
    final type = StorefrontSectionType.fromKey(json['type'] as String?) ??
        StorefrontSectionType.header;
    final settingsRaw = json['settings'];
    return StorefrontSectionConfig(
      type: type,
      visible: json['visible'] as bool? ?? true,
      settings: settingsRaw is Map
          ? Map<String, dynamic>.from(settingsRaw)
          : const {},
    );
  }
}

class StorefrontConfig {
  const StorefrontConfig({
    this.schemaVersion = storefrontConfigSchemaVersion,
    this.theme = const StorefrontThemeConfig(),
    this.style = const StorefrontStyleConfig(),
    this.sections = const [],
  });

  final int schemaVersion;
  final StorefrontThemeConfig theme;
  final StorefrontStyleConfig style;
  final List<StorefrontSectionConfig> sections;

  StorefrontSectionConfig? section(StorefrontSectionType type) {
    for (final section in sections) {
      if (section.type == type) return section;
    }
    return null;
  }

  bool isVisible(StorefrontSectionType type) => section(type)?.visible ?? false;

  List<StorefrontSectionConfig> get visibleSections =>
      sections.where((section) => section.visible).toList(growable: false);

  StorefrontConfig copyWith({
    StorefrontThemeConfig? theme,
    StorefrontStyleConfig? style,
    List<StorefrontSectionConfig>? sections,
  }) {
    return StorefrontConfig(
      schemaVersion: schemaVersion,
      theme: theme ?? this.theme,
      style: style ?? this.style,
      sections: sections ?? this.sections,
    );
  }

  StorefrontConfig withSection(StorefrontSectionConfig updated) {
    final next = [
      for (final section in sections)
        if (section.type == updated.type) updated else section,
    ];
    return copyWith(sections: next);
  }

  StorefrontConfig reorderSections(List<StorefrontSectionType> order) {
    final byType = {for (final s in sections) s.type: s};
    return copyWith(
      sections: [
        for (final type in order)
          if (byType.containsKey(type)) byType[type]!,
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'theme': theme.toJson(),
        'style': style.toJson(),
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  factory StorefrontConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return StorefrontDefaults.bundled;
    final sectionsRaw = json['sections'];
    final sections = sectionsRaw is List
        ? sectionsRaw
            .whereType<Map>()
            .map((item) => StorefrontSectionConfig.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(growable: false)
        : <StorefrontSectionConfig>[];
    return StorefrontConfig(
      schemaVersion:
          json['schemaVersion'] as int? ?? storefrontConfigSchemaVersion,
      theme: StorefrontThemeConfig.fromJson(
        json['theme'] is Map
            ? Map<String, dynamic>.from(json['theme'] as Map)
            : null,
      ),
      style: StorefrontStyleConfig.fromJson(
        json['style'] is Map
            ? Map<String, dynamic>.from(json['style'] as Map)
            : null,
      ),
      sections:
          sections.isEmpty ? StorefrontDefaults.bundled.sections : sections,
    );
  }

  factory StorefrontConfig.decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return StorefrontConfig.fromJson(decoded);
      }
    } catch (_) {}
    return StorefrontDefaults.bundled;
  }

  /// Validates config structure; throws [FormatException] on failure.
  void validate() {
    if (schemaVersion != storefrontConfigSchemaVersion) {
      throw FormatException('Unsupported schema version: $schemaVersion');
    }
    _validateHex(theme.primaryColor);
    _validateHex(theme.secondaryColor);
    _validateHex(theme.backgroundColor);
    _validateHex(theme.cardColor);
    _validateHex(theme.textColor);

    if (style.cardRadius < 0 || style.cardRadius > 48) {
      throw const FormatException('cardRadius out of range');
    }
    if (style.buttonRadius < 0 || style.buttonRadius > 48) {
      throw const FormatException('buttonRadius out of range');
    }
    if (style.sectionSpacing < 4 || style.sectionSpacing > 48) {
      throw const FormatException('sectionSpacing out of range');
    }
    if (style.productImageRatio < 0.5 || style.productImageRatio > 2.0) {
      throw const FormatException('productImageRatio out of range');
    }

    final seen = <StorefrontSectionType>{};
    for (final section in sections) {
      if (!seen.add(section.type)) {
        throw FormatException('Duplicate section: ${section.type.key}');
      }
    }
    for (final type in StorefrontSectionType.values) {
      if (!seen.contains(type)) {
        throw FormatException('Missing section: ${type.key}');
      }
    }
    if (seen.length != StorefrontSectionType.values.length) {
      throw const FormatException('Incomplete sections list');
    }
  }
}

class StorefrontAdminState {
  const StorefrontAdminState({
    required this.draftConfig,
    required this.publishedConfig,
    this.version = 1,
    this.updatedAt,
    this.publishedAt,
    this.hasDraftChanges = false,
  });

  final StorefrontConfig draftConfig;
  final StorefrontConfig publishedConfig;
  final int version;
  final DateTime? updatedAt;
  final DateTime? publishedAt;
  final bool hasDraftChanges;

  factory StorefrontAdminState.fromRemote(Map<String, dynamic> json) {
    return StorefrontAdminState(
      draftConfig: StorefrontConfig.fromJson(
        json['draftConfig'] is Map
            ? Map<String, dynamic>.from(json['draftConfig'] as Map)
            : null,
      ),
      publishedConfig: StorefrontConfig.fromJson(
        json['publishedConfig'] is Map
            ? Map<String, dynamic>.from(json['publishedConfig'] as Map)
            : null,
      ),
      version: json['version'] as int? ?? 1,
      updatedAt: _parseDate(json['updatedAt']),
      publishedAt: _parseDate(json['publishedAt']),
      hasDraftChanges: json['hasDraftChanges'] as bool? ?? false,
    );
  }
}

/// Bundled default matching current production home layout (backward compatible).
class StorefrontDefaults {
  StorefrontDefaults._();

  static StorefrontConfig get bundled => const StorefrontConfig(
        sections: [
          StorefrontSectionConfig(
            type: StorefrontSectionType.header,
            settings: {
              'showSearch': true,
              'showNotifications': true,
              'showLocation': true,
            },
          ),
          StorefrontSectionConfig(
            type: StorefrontSectionType.banner,
            settings: {
              'height': 88,
              'autoPlay': true,
              'intervalSeconds': 5,
              'borderRadius': 18,
              'showIndicators': true,
            },
          ),
          StorefrontSectionConfig(
            type: StorefrontSectionType.categories,
            settings: {
              'title': 'التصنيفات',
              'maxVisible': 20,
              'showCount': true,
              'layout': 'horizontal',
            },
          ),
          StorefrontSectionConfig(
            type: StorefrontSectionType.featuredProducts,
            settings: {
              'title': 'منتجات مميزة',
              'maxItems': 12,
              'showAddToCart': true,
              'hideWhenEmpty': true,
            },
          ),
          StorefrontSectionConfig(
            type: StorefrontSectionType.bestSelling,
            settings: {
              'title': 'الأكثر طلباً',
              'maxItems': 12,
              // Uses products.is_top_selling flag (manual admin flag, not sales aggregate).
              'fallbackToLatest': true,
              'showAddToCart': true,
            },
          ),
          StorefrontSectionConfig(
            type: StorefrontSectionType.offers,
            settings: {
              'title': 'العروض',
              'maxItems': 12,
              'showDiscountBadge': true,
              'hideWhenEmpty': true,
            },
          ),
          StorefrontSectionConfig(
            type: StorefrontSectionType.latestProducts,
            visible: false,
            settings: {
              'title': 'أحدث المنتجات',
              'maxItems': 12,
              'showAddToCart': true,
            },
          ),
          StorefrontSectionConfig(
            type: StorefrontSectionType.recentOrder,
            settings: {
              'title': 'إعادة آخر طلب',
              'showItemCount': true,
            },
          ),
        ],
      );

  static StorefrontThemeConfig presetTheme(StorefrontThemePreset preset) {
    switch (preset) {
      case StorefrontThemePreset.defaultPreset:
        return const StorefrontThemeConfig();
      case StorefrontThemePreset.clean:
        return const StorefrontThemeConfig(
          preset: StorefrontThemePreset.clean,
          primaryColor: Color(0xff2563eb),
          secondaryColor: Color(0xff64748b),
          backgroundColor: Color(0xfff8fafc),
          cardColor: Colors.white,
          textColor: Color(0xff0f172a),
        );
      case StorefrontThemePreset.warm:
        return const StorefrontThemeConfig(
          preset: StorefrontThemePreset.warm,
          primaryColor: Color(0xffb45309),
          secondaryColor: Color(0xff92400e),
          backgroundColor: Color(0xfffdf6ec),
          cardColor: Color(0xfffffbf5),
          textColor: Color(0xff3f2a14),
        );
      case StorefrontThemePreset.modern:
        return const StorefrontThemeConfig(
          preset: StorefrontThemePreset.modern,
          primaryColor: Color(0xff0d9488),
          secondaryColor: Color(0xff475569),
          backgroundColor: Color(0xfff1f5f9),
          cardColor: Colors.white,
          textColor: Color(0xff134e4a),
        );
    }
  }
}

String _colorToHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

Color _colorFromHex(String? raw, int fallbackArgb) {
  if (raw == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(raw)) {
    return Color(fallbackArgb);
  }
  return Color(int.parse(raw.substring(1), radix: 16) + 0xFF000000);
}

void _validateHex(Color color) {
  final hex = _colorToHex(color);
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) {
    throw FormatException('Invalid color: $hex');
  }
}

double _num(dynamic raw, double fallback, double min, double max) {
  if (raw is num) return raw.toDouble().clamp(min, max);
  return fallback.clamp(min, max);
}

DateTime? _parseDate(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw);
  }
  return null;
}

/// Best-selling section source: manual `products.is_top_selling` admin flag.
/// Operational sales rankings live in admin reports RPC, not storefront home.
const storefrontBestSellingSourceDoc =
    'الأكثر طلباً uses Product.isTopSelling (is_top_selling column), not sales aggregates.';
