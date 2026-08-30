import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import 'widgets/storefront_color_picker_sheet.dart';

/// Configuration for independent Admin Panel chrome theme.
class AdminThemeConfig {
  const AdminThemeConfig({
    this.primaryColor = const Color(0xff146c4e),
    this.backgroundColor = const Color(0xfff7f2ea),
    this.surfaceColor = const Color(0xffffffff),
    this.textColor = const Color(0xff173f32),
  });

  final Color primaryColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color textColor;

  static const standard = AdminThemeConfig();

  bool get hasLowTextContrast {
    final onBg = contrastRatio(textColor, backgroundColor);
    final onSurface = contrastRatio(textColor, surfaceColor);
    return onBg < 4.0 || onSurface < 4.0;
  }

  static double contrastRatio(Color fg, Color bg) {
    final lum1 = fg.computeLuminance();
    final lum2 = bg.computeLuminance();
    final lighter = lum1 > lum2 ? lum1 : lum2;
    final darker = lum1 > lum2 ? lum2 : lum1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  AdminThemeConfig copyWith({
    Color? primaryColor,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? textColor,
  }) {
    return AdminThemeConfig(
      primaryColor: primaryColor ?? this.primaryColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      textColor: textColor ?? this.textColor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'primary': storefrontColorToHex(primaryColor),
      'background': storefrontColorToHex(backgroundColor),
      'surface': storefrontColorToHex(surfaceColor),
      'text': storefrontColorToHex(textColor),
    };
  }

  factory AdminThemeConfig.fromJson(Map<String, dynamic> json) {
    return AdminThemeConfig(
      primaryColor: storefrontColorFromHex(json['primary'] as String? ?? '') ??
          const Color(0xff146c4e),
      backgroundColor:
          storefrontColorFromHex(json['background'] as String? ?? '') ??
              const Color(0xfff7f2ea),
      surfaceColor:
          storefrontColorFromHex(json['surface'] as String? ?? '') ??
              const Color(0xffffffff),
      textColor: storefrontColorFromHex(json['text'] as String? ?? '') ??
          const Color(0xff173f32),
    );
  }

  String encode() => jsonEncode(toJson());

  static AdminThemeConfig decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return standard;
    try {
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        return AdminThemeConfig.fromJson(map);
      }
      if (map is Map) {
        return AdminThemeConfig.fromJson(Map<String, dynamic>.from(map));
      }
    } catch (_) {}
    return standard;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminThemeConfig &&
          other.primaryColor == primaryColor &&
          other.backgroundColor == backgroundColor &&
          other.surfaceColor == surfaceColor &&
          other.textColor == textColor;

  @override
  int get hashCode => Object.hash(
        primaryColor,
        backgroundColor,
        surfaceColor,
        textColor,
      );
}

/// Local admin preference: keep the admin chrome on its own custom or standard palette.
class ApplyStorefrontThemeToAdminPrefs {
  ApplyStorefrontThemeToAdminPrefs({
    SharedPreferences? prefs,
    Future<SharedPreferences?> Function()? storeLoader,
  })  : _prefsOverride = prefs,
        _storeLoader = storeLoader;

  static const storageKey = 'admin.storefront.separate_colors.v1';
  static const legacyStorageKey = 'admin.storefront.apply_theme_to_admin.v1';
  static const adminThemeStorageKey = 'admin.theme.custom_colors.v1';

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

  Future<bool> load() async {
    try {
      final prefs = await _store();
      if (prefs == null) return false;
      return prefs.getBool(storageKey) == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> save(bool enabled) async {
    try {
      final prefs = await _store();
      if (prefs == null) return false;
      if (enabled) {
        await prefs.remove(legacyStorageKey);
        return await prefs.setBool(storageKey, true);
      }
      await prefs.remove(legacyStorageKey);
      return await prefs.remove(storageKey);
    } catch (_) {
      return false;
    }
  }

  Future<AdminThemeConfig> loadAdminTheme() async {
    try {
      final prefs = await _store();
      if (prefs == null) return AdminThemeConfig.standard;
      final raw = prefs.getString(adminThemeStorageKey);
      return AdminThemeConfig.decode(raw);
    } catch (_) {
      return AdminThemeConfig.standard;
    }
  }

  Future<bool> saveAdminTheme(AdminThemeConfig config) async {
    try {
      final prefs = await _store();
      if (prefs == null) return false;
      if (config == AdminThemeConfig.standard) {
        return await prefs.remove(adminThemeStorageKey);
      }
      return await prefs.setString(adminThemeStorageKey, config.encode());
    } catch (_) {
      return false;
    }
  }
}

final applyStorefrontThemeToAdminPrefsProvider =
    Provider<ApplyStorefrontThemeToAdminPrefs>(
  (ref) => ApplyStorefrontThemeToAdminPrefs(),
);

final applyStorefrontThemeToAdminProvider =
    StateNotifierProvider<ApplyStorefrontThemeToAdminController, bool>(
  (ref) => ApplyStorefrontThemeToAdminController(
    ref.watch(applyStorefrontThemeToAdminPrefsProvider),
  ),
);

class ApplyStorefrontThemeToAdminController extends StateNotifier<bool> {
  ApplyStorefrontThemeToAdminController(this._prefs) : super(false) {
    unawaited(reload());
  }

  final ApplyStorefrontThemeToAdminPrefs _prefs;

  Future<void> reload() async {
    state = await _prefs.load();
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _prefs.save(enabled);
  }
}

final adminCustomThemeConfigProvider =
    StateNotifierProvider<AdminCustomThemeController, AdminThemeConfig>(
  (ref) => AdminCustomThemeController(
    ref.watch(applyStorefrontThemeToAdminPrefsProvider),
  ),
);

class AdminCustomThemeController extends StateNotifier<AdminThemeConfig> {
  AdminCustomThemeController(this._prefs) : super(AdminThemeConfig.standard) {
    unawaited(reload());
  }

  final ApplyStorefrontThemeToAdminPrefs _prefs;

  Future<void> reload() async {
    state = await _prefs.loadAdminTheme();
  }

  Future<void> updateTheme(AdminThemeConfig config) async {
    state = config;
    await _prefs.saveAdminTheme(config);
  }

  Future<void> resetToDefault() async {
    state = AdminThemeConfig.standard;
    await _prefs.saveAdminTheme(AdminThemeConfig.standard);
  }
}

/// When the preference is on, returns the customized admin theme so the shell is
/// visually independent from the published storefront. When off, returns
/// null so [AdminShell] inherits the app-wide published storefront theme.
final adminShellStorefrontThemeProvider = Provider<ThemeData?>((ref) {
  final separate = ref.watch(applyStorefrontThemeToAdminProvider);
  if (!separate) return null;
  final config = ref.watch(adminCustomThemeConfigProvider);
  return adminThemeData(config);
});

ThemeData adminThemeData(AdminThemeConfig config) {
  final base = AppTheme.light;
  final onPrimary = _bestOnColor(
    config.primaryColor,
    preferredDark: config.textColor,
  );
  final primaryContainer = _tone(
    config.primaryColor,
    config.surfaceColor,
    .14,
  );
  final outline = _tone(config.textColor, config.surfaceColor, .24);
  final muted = _tone(config.textColor, config.surfaceColor, .66);
  final interactivePrimary = _brandForegroundOn(
    preferred: config.primaryColor,
    surface: config.surfaceColor,
    fallback: config.textColor,
  );

  final scheme = base.colorScheme.copyWith(
    primary: config.primaryColor,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: config.textColor,
    surface: config.surfaceColor,
    onSurface: config.textColor,
    onSurfaceVariant: muted,
    outline: _tone(config.textColor, config.surfaceColor, .42),
    outlineVariant: outline,
    surfaceTint: config.primaryColor,
  );

  final textTheme = base.textTheme.apply(
    bodyColor: config.textColor,
    displayColor: config.textColor,
  );

  return base.copyWith(
    scaffoldBackgroundColor: config.backgroundColor,
    colorScheme: scheme,
    textTheme: textTheme,
    cardColor: config.surfaceColor,
    cardTheme: base.cardTheme.copyWith(
      color: config.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.large),
        side: BorderSide(color: outline),
      ),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: config.backgroundColor,
      foregroundColor: config.textColor,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: config.textColor,
        fontWeight: FontWeight.w800,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        backgroundColor: WidgetStatePropertyAll(config.primaryColor),
        foregroundColor: WidgetStatePropertyAll(onPrimary),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        foregroundColor: WidgetStatePropertyAll(interactivePrimary),
        side: WidgetStatePropertyAll(BorderSide(color: outline)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        foregroundColor: WidgetStatePropertyAll(interactivePrimary),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: base.iconButtonTheme.style?.copyWith(
        foregroundColor: WidgetStatePropertyAll(interactivePrimary),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: config.surfaceColor,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        borderSide: BorderSide(color: interactivePrimary, width: 1.6),
      ),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: config.surfaceColor,
      indicatorColor: primaryContainer,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? interactivePrimary
              : muted,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return textTheme.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? interactivePrimary
              : muted,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w700,
        );
      }),
    ),
    navigationRailTheme: base.navigationRailTheme.copyWith(
      backgroundColor: config.surfaceColor,
      indicatorColor: primaryContainer,
      selectedIconTheme: IconThemeData(color: interactivePrimary),
      unselectedIconTheme: IconThemeData(color: muted),
      selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
        color: interactivePrimary,
        fontWeight: FontWeight.w800,
      ),
      unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
        color: muted,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: base.dividerTheme.copyWith(color: outline),
    listTileTheme: base.listTileTheme.copyWith(
      iconColor: interactivePrimary,
      textColor: config.textColor,
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: config.primaryColor,
      linearTrackColor: primaryContainer,
      circularTrackColor: primaryContainer,
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: config.surfaceColor,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: config.surfaceColor,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: config.surfaceColor,
    ),
  );
}

Color _bestOnColor(Color background, {Color? preferredDark}) {
  if (_contrastRatio(Colors.white, background) >= 4.5) {
    return Colors.white;
  }
  final dark = preferredDark ?? Colors.black;
  if (_contrastRatio(dark, background) >= 4.5) {
    return dark;
  }
  if (_contrastRatio(Colors.black, background) >= 4.5) {
    return Colors.black;
  }
  return Colors.black;
}

Color _brandForegroundOn({
  required Color preferred,
  required Color surface,
  required Color fallback,
}) {
  if (_contrastRatio(preferred, surface) >= 4.5) return preferred;
  if (_contrastRatio(fallback, surface) >= 4.5) return fallback;
  return _bestOnColor(surface);
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground.computeLuminance()
      : background.computeLuminance();
  final darker = foreground.computeLuminance() > background.computeLuminance()
      ? background.computeLuminance()
      : foreground.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}

Color _tone(Color foreground, Color background, double opacity) {
  return Color.alphaBlend(
    foreground.withValues(alpha: opacity),
    background,
  );
}
