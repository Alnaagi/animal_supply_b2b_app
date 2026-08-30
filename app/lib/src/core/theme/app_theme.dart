import 'package:flutter/material.dart';

/// Shared responsive breakpoints for customer and admin experiences.
abstract final class AppBreakpoints {
  static const compact = 600.0;
  static const expanded = 1024.0;
  static const wide = 1440.0;

  static bool isCompact(double width) => width < compact;
  static bool isMedium(double width) => width >= compact && width < expanded;
  static bool isExpanded(double width) => width >= expanded;
  static bool isWide(double width) => width >= wide;
}

/// A small spacing scale keeps surfaces visually related without forcing
/// every screen into the same density.
abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class AppRadii {
  static const small = 10.0;
  static const medium = 16.0;
  static const large = 22.0;
  static const hero = 28.0;
  static const pill = 999.0;
}

abstract final class AppMotion {
  static const quick = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 240);
  static const emphasized = Duration(milliseconds: 360);

  static const standardCurve = Curves.easeOutCubic;
}

class AppTheme {
  // Arabic-first brand palette. The darker primary keeps normal white button
  // labels above WCAG AA contrast while retaining the established green.
  static const green = Color(0xff146c4e);
  static const darkGreen = Color(0xff173f32);
  static const primaryContainer = Color(0xffd9f0e6);
  static const brown = Color(0xff8a623f);
  static const secondaryContainer = Color(0xfff4e6d4);
  static const sand = Color(0xfff7f2ea);
  static const softGray = Color(0xfff3f5f3);
  static const mutedText = Color(0xff5f6f68);
  static const outline = Color(0xffd8e1dc);

  // Semantic colors stay fixed even when the storefront brand is customized.
  static const success = Color(0xff247a4c);
  static const warning = Color(0xff9a6700);
  static const info = Color(0xff175cd3);
  static const orange = warning;
  static const red = Color(0xffb42318);
  static const whatsapp = Color(0xff25d366);

  static ThemeData get light {
    final seeded = ColorScheme.fromSeed(
      seedColor: green,
      brightness: Brightness.light,
    );
    final scheme = seeded.copyWith(
      primary: green,
      onPrimary: Colors.white,
      primaryContainer: primaryContainer,
      onPrimaryContainer: darkGreen,
      secondary: brown,
      onSecondary: Colors.white,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: const Color(0xff4b331f),
      tertiary: const Color(0xff2b6488),
      onTertiary: Colors.white,
      error: red,
      onError: Colors.white,
      errorContainer: const Color(0xfffecdca),
      onErrorContainer: const Color(0xff55160c),
      surface: Colors.white,
      onSurface: darkGreen,
      onSurfaceVariant: mutedText,
      outline: const Color(0xff87958e),
      outlineVariant: outline,
      surfaceTint: green,
    );
    final textTheme = _arabicTextTheme(
      ThemeData.light(useMaterial3: true).textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: sand,
      fontFamily: 'NotoSansArabic',
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: sand,
        foregroundColor: darkGreen,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: darkGreen,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: .08),
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.large),
          side: const BorderSide(color: outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: outline,
          disabledForegroundColor: mutedText,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: green,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: outline),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: green,
          minimumSize: const Size(44, 44),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: darkGreen,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 15,
        ),
        labelStyle: const TextStyle(color: mutedText),
        hintStyle: const TextStyle(color: mutedText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          borderSide: const BorderSide(color: green, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          borderSide: const BorderSide(color: red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          borderSide: const BorderSide(color: red, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: Colors.white,
        indicatorColor: primaryContainer,
        selectedIconTheme: const IconThemeData(color: green),
        unselectedIconTheme: const IconThemeData(color: mutedText),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: green,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: mutedText,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.large),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkGreen,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: green,
        textColor: darkGreen,
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: darkGreen,
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
      ),
    );
  }

  static TextTheme _arabicTextTheme(TextTheme base) {
    final themed = base.apply(
      fontFamily: 'NotoSansArabic',
      bodyColor: darkGreen,
      displayColor: darkGreen,
    );
    return themed.copyWith(
      displayLarge: themed.displayLarge?.copyWith(
        fontSize: 44,
        height: 1.24,
        fontWeight: FontWeight.w800,
      ),
      displayMedium: themed.displayMedium?.copyWith(
        fontSize: 36,
        height: 1.25,
        fontWeight: FontWeight.w800,
      ),
      displaySmall: themed.displaySmall?.copyWith(
        fontSize: 30,
        height: 1.28,
        fontWeight: FontWeight.w800,
      ),
      headlineLarge: themed.headlineLarge?.copyWith(
        fontSize: 28,
        height: 1.3,
        fontWeight: FontWeight.w800,
      ),
      headlineMedium: themed.headlineMedium?.copyWith(
        fontSize: 24,
        height: 1.3,
        fontWeight: FontWeight.w800,
      ),
      headlineSmall: themed.headlineSmall?.copyWith(
        fontSize: 21,
        height: 1.32,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: themed.titleLarge?.copyWith(
        fontSize: 20,
        height: 1.32,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: themed.titleMedium?.copyWith(
        fontSize: 17,
        height: 1.36,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: themed.titleSmall?.copyWith(
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: themed.bodyLarge?.copyWith(fontSize: 16, height: 1.52),
      bodyMedium: themed.bodyMedium?.copyWith(fontSize: 14, height: 1.48),
      bodySmall: themed.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.42,
        color: mutedText,
      ),
      labelLarge: themed.labelLarge?.copyWith(
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: themed.labelMedium?.copyWith(
        fontSize: 12.5,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      labelSmall: themed.labelSmall?.copyWith(
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
