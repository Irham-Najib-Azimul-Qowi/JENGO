import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Warna Neon & Dark Premium
  static const Color darkBackground = Color(0xFF0B0F19); // Biru hitam pekat
  static const Color darkSurface = Color(0xFF161D30); // Card container
  static const Color neonBlue = Color(0xFF00D2FF); // Primary neon blue
  static const Color neonGreen = Color(0xFF00F5A0); // Success neon green
  static const Color neonPink = Color(0xFFF35588); // Accent neon pink
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      primaryColor: neonBlue,
      cardColor: darkSurface,
      colorScheme: const ColorScheme.dark(
        background: darkBackground,
        surface: darkSurface,
        primary: neonBlue,
        secondary: neonGreen,
        tertiary: neonPink,
        error: Colors.redAccent,
      ),
      textTheme: TextTheme(
        headlineLarge: GoogleFonts.outfit(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineMedium: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        titleLarge: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          color: textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          color: textSecondary,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        shape: RoundedCornerShape(16),
        elevation: 4,
      ),
      buttonTheme: const ButtonThemeData(
        buttonColor: neonBlue,
        textTheme: ButtonTextTheme.primary,
      ),
    );
  }
}

// Helper Rounded Corner Shape
class RoundedCornerShape extends RoundedRectangleBorder {
  RoundedCornerShape(double radius)
      : super(borderRadius: BorderRadius.circular(radius));
}
