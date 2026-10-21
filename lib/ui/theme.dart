import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF0A0C10);
  static const surface = Color(0xFF15171D);
  static const surfaceHigh = Color(0xFF1E2129);
  static const border = Color(0xFF2A2E38);
  static const accent = Color(0xFFE50914);
  static const textPrimary = Color(0xFFF2F3F5);
  static const textSecondary = Color(0xFF9AA0AC);
  static const live = Color(0xFFFF453A);

  /// Dunkler Grund für Senderlogos (mit feinem Rand, damit auch dunkle Logos Kontur haben).
  static const logoSurface = Color(0xFF1E222D);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
    primary: AppColors.accent,
    surface: AppColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    dividerColor: AppColors.border,
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
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
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
