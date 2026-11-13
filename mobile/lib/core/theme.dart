import 'package:flutter/material.dart';

class CommunityTheme {
  static const teal = Color(0xFF075E54);
  static const green = Color(0xFF25D366);
  static const beige = Color(0xFFECE5DD);
  static const bubbleOut = Color(0xFFDCF8C6);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: false,
      scaffoldBackgroundColor: Colors.white,
      primaryColor: teal,
      colorScheme: const ColorScheme.light(
        primary: teal,
        secondary: green,
        surface: Colors.white,
        onPrimary: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: green,
        foregroundColor: Colors.white,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontSize: 17, height: 1.4),
      ),
    );
  }
}
