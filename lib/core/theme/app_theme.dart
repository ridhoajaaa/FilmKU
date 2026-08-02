import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  /// Android & desktop theme — the classic Netflix-inspired dark UI.
  static ThemeData get dark {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        surface: AppColors.charcoal,
        onSurface: AppColors.textPrimary,
      ),
      scaffoldBackgroundColor: AppColors.black,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.black,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.charcoal,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceLight,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.accent),
      dividerColor: AppColors.surfaceLight,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: TextStyle(color: AppColors.textMuted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }

  /// iOS-only "liquid glass" theme.
  ///
  /// A distinct, translucent glass aesthetic for iOS (the Android build keeps
  /// [dark]). Deep indigo-black base with vivid aqua/blue accents, frosted
  /// surfaces (low-alpha whites), hairline glass borders and extra-large
  /// corner radii — the Material 3 tokens are tuned so the shared widgets
  /// (cards, chips, app bars, dialogs) read as frosted glass without any
  /// per-widget platform checks.
  static ThemeData get ios {
    // Liquid-glass palette: deep space base + aqua accent + frosted whites.
    const Color glassBase = Color(0xFF08080F);
    const Color glassSurface = Color(0xFF16162A);
    const Color accent = Color(0xFF4DE1FF); // electric aqua
    const Color accentSecondary = Color(0xFF7C6BFF); // violet

    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentSecondary,
        surface: glassSurface,
        onSurface: Colors.white,
        surfaceContainerLowest: glassBase,
        surfaceContainerLow: Color(0xFF101022),
        surfaceContainer: glassSurface,
        surfaceContainerHigh: Color(0xFF1E1E38),
        surfaceContainerHighest: Color(0xFF262647),
        outline: Color(0x33FFFFFF),
      ),
      scaffoldBackgroundColor: glassBase,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        // Inner widgets must NOT be marked const here — they're already in
        // the const context of AppBarTheme (matching the dark theme above),
        // and redundant consts trip the unnecessary_const lint.
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xE6262647),
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: accent),
      dividerColor: const Color(0x1AFFFFFF),
      cardTheme: const CardThemeData(
        color: Color(0x14FFFFFF), // frosted white
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          side: BorderSide(color: Color(0x24FFFFFF)), // hairline glass edge
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: const Color(0x14FFFFFF),
        side: const BorderSide(color: Color(0x24FFFFFF)),
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFF00151D),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0x33FFFFFF)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0x14FFFFFF),
        hintStyle: const TextStyle(color: Colors.white38),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0x24FFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      ),
      // NOTE: BorderRadius.circular is NOT a const constructor in this Flutter
      // version (const_with_non_const inside const contexts) — always use
      // BorderRadius.all(Radius.circular(...)) in const contexts instead.
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xF2141428),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
          side: BorderSide(color: Color(0x24FFFFFF)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xF2141428),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0x1AFFFFFF)),
    );
  }
}
