import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/storefront_config.dart';
import '../../data/repositories/storefront_repository.dart';

/// Applies both the published storefront configuration and its derived
/// Material theme to customer shopping surfaces and admin previews.
class StorefrontThemeScope extends StatelessWidget {
  const StorefrontThemeScope({
    required this.config,
    required this.child,
    super.key,
  });

  final StorefrontConfig config;
  final Widget child;

  static StorefrontConfig of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_StorefrontThemeInherited>();
    return scope?.config ?? StorefrontDefaults.bundled;
  }

  static StorefrontConfig? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_StorefrontThemeInherited>()
        ?.config;
  }

  @override
  Widget build(BuildContext context) {
    return _StorefrontThemeInherited(
      config: config,
      child: Theme(
        data: storefrontThemeData(config),
        child: child,
      ),
    );
  }
}

class _StorefrontThemeInherited extends InheritedWidget {
  const _StorefrontThemeInherited({
    required this.config,
    required super.child,
  });

  final StorefrontConfig config;

  @override
  bool updateShouldNotify(_StorefrontThemeInherited oldWidget) =>
      oldWidget.config.encode() != config.encode();
}

/// Convenience wrapper for routes outside [CustomerShell], such as product
/// details and checkout, so the shopping journey keeps one visual identity.
class PublishedStorefrontTheme extends ConsumerWidget {
  const PublishedStorefrontTheme({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(publishedStorefrontConfigProvider).valueOrNull ??
        StorefrontDefaults.bundled;
    return StorefrontThemeScope(config: config, child: child);
  }
}

ThemeData storefrontThemeData(StorefrontConfig config) {
  final theme = config.theme;
  final style = config.style;
  final base = AppTheme.light;
  final onPrimary = _bestOnColor(
    theme.primaryColor,
    preferredDark: theme.textColor,
  );
  final onSecondary = _bestOnColor(
    theme.secondaryColor,
    preferredDark: theme.textColor,
  );
  final primaryContainer = _tone(
    theme.primaryColor,
    theme.cardColor,
    .14,
  );
  final secondaryContainer = _tone(
    theme.secondaryColor,
    theme.cardColor,
    .14,
  );
  final outline = _tone(theme.textColor, theme.cardColor, .16);
  final muted = _tone(theme.textColor, theme.cardColor, .66);
  final interactivePrimary = _brandForegroundOn(
    preferred: theme.primaryColor,
    surface: theme.cardColor,
    fallback: theme.textColor,
  );
  final scheme = base.colorScheme.copyWith(
    primary: theme.primaryColor,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: theme.textColor,
    secondary: theme.secondaryColor,
    onSecondary: onSecondary,
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: theme.textColor,
    surface: theme.cardColor,
    onSurface: theme.textColor,
    onSurfaceVariant: muted,
    outline: _tone(theme.textColor, theme.cardColor, .42),
    outlineVariant: outline,
    surfaceTint: theme.primaryColor,
  );
  final textTheme = base.textTheme.apply(
    bodyColor: theme.textColor,
    displayColor: theme.textColor,
  );

  return base.copyWith(
    scaffoldBackgroundColor: theme.backgroundColor,
    colorScheme: scheme,
    textTheme: textTheme,
    cardTheme: base.cardTheme.copyWith(
      color: theme.cardColor,
      elevation: div(style.cardShadow),
      shadowColor: theme.textColor.withValues(alpha: .10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(style.cardRadius),
        side: BorderSide(color: outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        backgroundColor: WidgetStatePropertyAll(theme.primaryColor),
        foregroundColor: WidgetStatePropertyAll(onPrimary),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.buttonRadius),
          ),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        foregroundColor: WidgetStatePropertyAll(interactivePrimary),
        side: WidgetStatePropertyAll(BorderSide(color: outline)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.buttonRadius),
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        foregroundColor: WidgetStatePropertyAll(interactivePrimary),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.buttonRadius),
          ),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: base.iconButtonTheme.style?.copyWith(
        foregroundColor: WidgetStatePropertyAll(interactivePrimary),
      ),
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: theme.primaryColor,
      foregroundColor: onPrimary,
      elevation: 0,
      focusElevation: 1,
      hoverElevation: 1,
      highlightElevation: 1,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: theme.cardColor,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(style.buttonRadius),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(style.buttonRadius),
        borderSide: BorderSide(color: interactivePrimary, width: 1.6),
      ),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: theme.cardColor,
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
      backgroundColor: theme.cardColor,
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
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: theme.backgroundColor,
      foregroundColor: theme.textColor,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: theme.textColor,
        fontWeight: FontWeight.w800,
      ),
    ),
    dividerTheme: base.dividerTheme.copyWith(color: outline),
    listTileTheme: base.listTileTheme.copyWith(
      iconColor: interactivePrimary,
      textColor: theme.textColor,
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: theme.primaryColor,
      linearTrackColor: primaryContainer,
      circularTrackColor: primaryContainer,
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: theme.cardColor,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: theme.cardColor,
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

double div(StorefrontCardShadow shadow) {
  switch (shadow) {
    case StorefrontCardShadow.none:
      return 0;
    case StorefrontCardShadow.light:
      return 1;
    case StorefrontCardShadow.medium:
      return 2;
    case StorefrontCardShadow.strong:
      return 4;
  }
}
