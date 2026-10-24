import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF090B10);
  static const surface = Color(0xFF141820);
  static const surfaceHigh = Color(0xFF1C222D);
  static const border = Color(0xFF2A3240);
  static const accent = Color(0xFFF04B56);
  static const textPrimary = Color(0xFFF5F6F8);
  static const textSecondary = Color(0xFFA8B0BF);
  static const live = Color(0xFFFF453A);

  /// Dunkler Grund für Senderlogos (mit feinem Rand, damit auch dunkle Logos Kontur haben).
  static const logoSurface = Color(0xFF1E222D);

  /// Heller Grund für dunkle Logos, die auf [logoSurface] verschwinden würden.
  static const logoLight = Color(0xFFE6E8EC);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
    primary: AppColors.accent,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
  );
  final textTheme = ThemeData.dark().textTheme.apply(
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    dividerColor: AppColors.border,
    textTheme: textTheme.copyWith(
      titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.15),
      bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.45),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.background,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      selectedColor: AppColors.textPrimary,
      selectedTileColor: AppColors.surfaceHigh,
      iconColor: AppColors.textSecondary,
    ),
    popupMenuTheme: const PopupMenuThemeData(color: AppColors.surfaceHigh),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.textPrimary,
      thumbColor: AppColors.textPrimary,
      inactiveTrackColor: Color(0x55FFFFFF),
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
  );
}
