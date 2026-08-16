import 'package:flutter/material.dart';

class CategoryIconPreset {
  const CategoryIconPreset({
    required this.key,
    required this.labelAr,
    required this.icon,
  });

  final String key;
  final String labelAr;
  final IconData icon;
}

class CategoryIconCatalog {
  const CategoryIconCatalog._();

  static const defaultKey = 'category';

  static const presets = <CategoryIconPreset>[
    CategoryIconPreset(
      key: defaultKey,
      labelAr: 'تصنيف عام',
      icon: Icons.category_outlined,
    ),
    CategoryIconPreset(
      key: 'feed',
      labelAr: 'أعلاف',
      icon: Icons.grass,
    ),
    CategoryIconPreset(
      key: 'grain',
      labelAr: 'حبوب',
      icon: Icons.rice_bowl_outlined,
    ),
    CategoryIconPreset(
      key: 'hay',
      labelAr: 'تبن وعلف أخضر',
      icon: Icons.park_outlined,
    ),
    CategoryIconPreset(
      key: 'chicken',
      labelAr: 'دواجن',
      icon: Icons.egg_alt_outlined,
    ),
    CategoryIconPreset(
      key: 'livestock',
      labelAr: 'مواشي',
      icon: Icons.agriculture_outlined,
    ),
    CategoryIconPreset(
      key: 'cow',
      labelAr: 'أبقار',
      icon: Icons.agriculture,
    ),
    CategoryIconPreset(
      key: 'cat',
      labelAr: 'قطط',
      icon: Icons.pets,
    ),
    CategoryIconPreset(
      key: 'dog',
      labelAr: 'كلاب',
      icon: Icons.pets_outlined,
    ),
    CategoryIconPreset(
      key: 'bird',
      labelAr: 'طيور',
      icon: Icons.flutter_dash,
    ),
    CategoryIconPreset(
      key: 'fish',
      labelAr: 'أسماك',
      icon: Icons.water,
    ),
    CategoryIconPreset(
      key: 'rabbit',
      labelAr: 'أرانب',
      icon: Icons.cruelty_free_outlined,
    ),
    CategoryIconPreset(
      key: 'pet',
      labelAr: 'حيوانات أليفة',
      icon: Icons.emoji_nature_outlined,
    ),
    CategoryIconPreset(
      key: 'medicine',
      labelAr: 'أدوية بيطرية',
      icon: Icons.medical_services_outlined,
    ),
    CategoryIconPreset(
      key: 'supplements',
      labelAr: 'مكملات',
      icon: Icons.medication_liquid_outlined,
    ),
    CategoryIconPreset(
      key: 'cleaning',
      labelAr: 'تنظيف',
      icon: Icons.cleaning_services_outlined,
    ),
    CategoryIconPreset(
      key: 'grooming',
      labelAr: 'عناية',
      icon: Icons.shower_outlined,
    ),
    CategoryIconPreset(
      key: 'tools',
      labelAr: 'أدوات',
      icon: Icons.handyman_outlined,
    ),
    CategoryIconPreset(
      key: 'supplies',
      labelAr: 'مستلزمات',
      icon: Icons.inventory_2_outlined,
    ),
    CategoryIconPreset(
      key: 'toys',
      labelAr: 'ألعاب',
      icon: Icons.toys_outlined,
    ),
    CategoryIconPreset(
      key: 'treats',
      labelAr: 'وجبات خفيفة',
      icon: Icons.cookie_outlined,
    ),
    CategoryIconPreset(
      key: 'wholesale',
      labelAr: 'جملة',
      icon: Icons.warehouse_outlined,
    ),
  ];

  static CategoryIconPreset? byKey(String? key) {
    final normalized = key?.trim() ?? '';
    if (normalized.isEmpty) return null;
    for (final preset in presets) {
      if (preset.key == normalized) return preset;
    }
    return null;
  }

  static bool isKnownKey(String? key) => byKey(key) != null;

  static String inferredKey(String name) {
    final n = name.trim();
    return switch (n) {
      'قطط' => 'cat',
      'كلاب' => 'dog',
      'طيور' => 'bird',
      'أسماك' => 'fish',
      'مواشي' => 'livestock',
      'مستلزمات' => 'supplies',
      'تنظيف' => 'cleaning',
      'مكملات' => 'supplements',
      'أعلاف' || 'علف' => 'feed',
      'حبوب' => 'grain',
      'دواجن' => 'chicken',
      'أبقار' => 'cow',
      _ => _inferredFromKeywords(n),
    };
  }

  static String _inferredFromKeywords(String name) {
    if (name.contains('قط')) return 'cat';
    if (name.contains('كلب')) return 'dog';
    if (name.contains('طير') || name.contains('طيور')) return 'bird';
    if (name.contains('سمك') || name.contains('أسماك')) return 'fish';
    if (name.contains('أرانب') || name.contains('أرنب')) return 'rabbit';
    if (name.contains('دواجن') || name.contains('دجاج')) return 'chicken';
    if (name.contains('بقر') || name.contains('أبقار')) return 'cow';
    if (name.contains('ماش') || name.contains('غنم') || name.contains('إبل')) {
      return 'livestock';
    }
    if (name.contains('علف') || name.contains('أعلاف')) return 'feed';
    if (name.contains('حبوب') || name.contains('شعير') || name.contains('ذرة')) {
      return 'grain';
    }
    if (name.contains('تبن') || name.contains('برسيم')) return 'hay';
    if (name.contains('دواء') || name.contains('أدوية') || name.contains('بيطر')) {
      return 'medicine';
    }
    if (name.contains('مكمل')) return 'supplements';
    if (name.contains('تنظيف') || name.contains('مطهر')) return 'cleaning';
    if (name.contains('عناية') || name.contains('شامبو')) return 'grooming';
    if (name.contains('أداة') || name.contains('أدوات')) return 'tools';
    if (name.contains('لعب')) return 'toys';
    if (name.contains('مستلزم')) return 'supplies';
    if (name.contains('جملة')) return 'wholesale';
    if (name.contains('أليف')) return 'pet';
    return defaultKey;
  }

  static IconData iconData({
    String? iconKey,
    String? fallbackName,
  }) {
    final preset = byKey(iconKey);
    if (preset != null) return preset.icon;
    if (fallbackName != null && fallbackName.trim().isNotEmpty) {
      return byKey(inferredKey(fallbackName))?.icon ?? Icons.category_outlined;
    }
    return Icons.category_outlined;
  }
}

class CategoryIconSelection {
  const CategoryIconSelection({
    this.iconKey,
    this.iconUrl,
  });

  final String? iconKey;
  final String? iconUrl;

  bool get hasIcon {
    final key = iconKey?.trim() ?? '';
    final url = iconUrl?.trim() ?? '';
    return key.isNotEmpty || url.isNotEmpty;
  }
}
