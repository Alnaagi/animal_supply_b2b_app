import 'package:flutter/material.dart';

class AppTheme {
  static const green = Color(0xff168a63);
  static const darkGreen = Color(0xff173f32);
  static const brown = Color(0xff8a623f);
  static const sand = Color(0xfff7f2ea);
  static const softGray = Color(0xfff3f5f3);
  static const orange = Color(0xffff8a2a);
  static const red = Color(0xffd64c4c);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: green,
      primary: green,
      secondary: brown,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: sand,
      fontFamily: 'NotoSansArabic',
      textTheme: ThemeData.light().textTheme.apply(
            fontFamily: 'NotoSansArabic',
            bodyColor: darkGreen,
            displayColor: darkGreen,
          ),
      appBarTheme: const AppBarTheme(centerTitle: true, backgroundColor: sand),
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black12,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: green)),
      ),
    );
  }
}
