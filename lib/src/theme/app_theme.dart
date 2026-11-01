import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF102129);
  static const inkMuted = Color(0xFF263A43);
  static const paper = Color(0xFFF2F5F1);
  static const paperDeep = Color(0xFFE8ECE7);
  static const surface = Color(0xFFFCFDFB);
  static const line = Color(0xFFD7DED7);
  static const coral = Color(0xFFD94F57);
  static const coralDark = Color(0xFFB83D46);
  static const coralWash = Color(0xFFF7DDE0);
  static const mint = Color(0xFF357461);
  static const mintWash = Color(0xFFDDEBE5);
  static const amber = Color(0xFFAD7724);
  static const amberWash = Color(0xFFF3E7CD);
  static const white = Color(0xFFFFFFFF);
}

ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.light(
    primary: AppColors.coral,
    onPrimary: AppColors.white,
    secondary: AppColors.mint,
    onSecondary: AppColors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    error: AppColors.coralDark,
    onError: AppColors.white,
    outline: AppColors.line,
    outlineVariant: AppColors.paperDeep,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.paper,
    dividerColor: AppColors.line,
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
        .copyWith(
          displayLarge: const TextStyle(
            color: AppColors.ink,
            fontSize: 88,
            height: 0.92,
            fontWeight: FontWeight.w300,
            letterSpacing: 0,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          headlineLarge: const TextStyle(
            color: AppColors.ink,
            fontSize: 32,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          headlineMedium: const TextStyle(
            color: AppColors.ink,
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          titleLarge: const TextStyle(
            color: AppColors.ink,
            fontSize: 18,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          titleMedium: const TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
          bodyLarge: const TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            height: 1.55,
            letterSpacing: 0,
          ),
          bodyMedium: const TextStyle(
            color: AppColors.ink,
            fontSize: 13,
            height: 1.5,
            letterSpacing: 0,
          ),
          labelLarge: const TextStyle(
            color: AppColors.ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
          labelMedium: const TextStyle(
            color: AppColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: AppColors.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        side: WidgetStateProperty.all(const BorderSide(color: AppColors.line)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: AppColors.white, fontSize: 12),
      waitDuration: const Duration(milliseconds: 500),
    ),
  );
}
