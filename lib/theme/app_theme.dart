import 'package:flutter/material.dart';

/// PhotoLink 统一视觉主题（青绿主色，避免通用紫系）
class PhotoLinkTheme {
  PhotoLinkTheme._();

  static const Color brand = Color(0xFF0B6E6B);
  static const Color brandDark = Color(0xFF084F4D);
  static const Color accent = Color(0xFFE07A3D);
  static const Color softBg = Color(0xFFF3F7F6);
  static const Color cardBg = Color(0xFFFFFFFF);

  static ThemeData light({bool centerTitle = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      primary: brand,
      secondary: accent,
      brightness: Brightness.light,
      surface: softBg,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: softBg,
      appBarTheme: AppBarTheme(
        centerTitle: centerTitle,
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF163A38),
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: const TextStyle(
          color: Color(0xFF163A38),
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: brand.withValues(alpha: 0.08)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
