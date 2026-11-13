import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract class AppColors {
  static const surface = Color(0xFFFFFFFF);
  static const brand = Color(0xFF1DAA61);
  static const brandContainer = Color(0xFFD9FDD3);
  static const onBrandContainer = Color(0xFF084C23);
  static const textPrimary = Color(0xFF111111);
  static const textSecondary = Color(0xFF5F6163);
  static const searchFill = Color(0xFFF6F5F3);
  static const avatarFallbackBg = Color(0xFFFFDBE7);
  static const avatarFallbackFg = Color(0xFFD43C69);
}

class CommunityTheme {
  static const teal = AppColors.brand;
  static const green = AppColors.brand;
  static const beige = Color(0xFFECE5DD);
  static const bubbleOut = AppColors.brandContainer;

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.surface,
      primaryColor: AppColors.brand,
      splashFactory: InkRipple.splashFactory,
      splashColor: Color(0x14000000),
      colorScheme: const ColorScheme.light(
        primary: AppColors.brand,
        onPrimary: AppColors.surface,
        primaryContainer: AppColors.brandContainer,
        onPrimaryContainer: AppColors.onBrandContainer,
        secondary: AppColors.brand,
        secondaryContainer: AppColors.brandContainer,
        onSecondaryContainer: AppColors.onBrandContainer,
        surface: AppColors.surface,
        surfaceTint: Colors.transparent,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 16,
        toolbarHeight: 56,
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 24),
        actionsIconTheme: IconThemeData(color: AppColors.textPrimary, size: 24),
        titleTextStyle: TextStyle(
          color: AppColors.brand,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.surface,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: AppColors.surface,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.surface,
        elevation: 3,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.brandContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.onBrandContainer
                : AppColors.textPrimary,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          return TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: Colors.transparent,
        thickness: 0,
        space: 0,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brand,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 17,
          height: 1.4,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
