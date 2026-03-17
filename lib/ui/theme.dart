/// Kabuk design tokens and theme configuration.
///
/// Modern dark theme with vibrant teal accents and clean typography.
library;

import 'package:flutter/material.dart';

/// Kabuk design tokens and theme configuration.
///
/// All colors, spacing values, and border radii are centralized here.
/// The [darkTheme] getter produces a complete [ThemeData] for the app.
abstract final class KabukTheme {
  // ---------------------------------------------------------------------------
  // Colors
  // ---------------------------------------------------------------------------

  /// Primary teal-ish green.
  static const Color primaryGreen = Color(0xFF00897B);

  /// Lighter accent green.
  static const Color accentGreen = Color(0xFF26A69A);

  /// Warm accent for highlights.
  static const Color warmAccent = Color(0xFFFFAB40);

  /// Blue accent for info states.
  static const Color blueAccent = Color(0xFF42A5F5);

  /// Purple accent for agent/AI related elements.
  static const Color purpleAccent = Color(0xFFAB47BC);

  /// Default surface color.
  static const Color surface = Color(0xFF1A1A1A);

  /// Elevated surface (cards, sheets).
  static const Color surfaceElevated = Color(0xFF222222);

  /// Variant surface for inputs and secondary containers.
  static const Color surfaceVariant = Color(0xFF2A2A2A);

  /// Scaffold background.
  static const Color background = Color(0xFF0F0F0F);

  /// Card background.
  static const Color cardColor = Color(0xFF1C1C1C);

  /// Primary text color.
  static const Color textPrimary = Color(0xFFF0F0F0);

  /// Secondary / muted text color.
  static const Color textSecondary = Color(0xFF8A8A8A);

  /// Tertiary / hint text color.
  static const Color textTertiary = Color(0xFF5A5A5A);

  /// Divider color.
  static const Color divider = Color(0xFF2A2A2A);

  /// Error color (Material dark error).
  static const Color error = Color(0xFFCF6679);

  /// Success color.
  static const Color success = Color(0xFF66BB6A);

  /// Reddit brand orange.
  static const redditOrange = Color(0xFFFF4500);

  /// Nostr/relay purple accent.
  static const nostrPurple = Color(0xFF9B6DFF);

  /// Default avatar color palette for contacts and profiles.
  static const avatarColors = [
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
    Color(0xFFFF7043),
    Color(0xFFFFCA28),
  ];

  // ---------------------------------------------------------------------------
  // Spacing
  // ---------------------------------------------------------------------------

  /// Extra-small spacing (4 dp).
  static const double spacingXs = 4.0;

  /// Small spacing (8 dp).
  static const double spacingSm = 8.0;

  /// Medium spacing (16 dp).
  static const double spacingMd = 16.0;

  /// Large spacing (24 dp).
  static const double spacingLg = 24.0;

  /// Extra-large spacing (32 dp).
  static const double spacingXl = 32.0;

  // ---------------------------------------------------------------------------
  // Border radius
  // ---------------------------------------------------------------------------

  /// Small border radius (8 dp).
  static const double radiusSm = 8.0;

  /// Medium border radius (12 dp).
  static const double radiusMd = 12.0;

  /// Large border radius (16 dp).
  static const double radiusLg = 16.0;

  /// Extra-large border radius (24 dp).
  static const double radiusXl = 24.0;

  // ---------------------------------------------------------------------------
  // Theme
  // ---------------------------------------------------------------------------

  /// The main dark [ThemeData] for the Kabuk app.
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'SF Pro Display',
    colorScheme: const ColorScheme.dark(
      primary: primaryGreen,
      secondary: accentGreen,
      surface: surface,
      surfaceContainerHighest: surfaceElevated,
      error: error,
    ),
    scaffoldBackgroundColor: background,
    cardColor: cardColor,
    dividerColor: divider,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: accentGreen,
      unselectedItemColor: textSecondary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: primaryGreen.withAlpha(50),
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: accentGreen, size: 24);
        }
        return const IconThemeData(color: textSecondary, size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            color: accentGreen,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          );
        }
        return const TextStyle(
          color: textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        );
      }),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        side: const BorderSide(color: divider, width: 0.5),
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceVariant,
      selectedColor: primaryGreen.withAlpha(40),
      labelStyle: const TextStyle(fontSize: 12, color: textPrimary),
      side: const BorderSide(color: divider, width: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSm),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        borderSide: BorderSide(color: divider, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        borderSide: BorderSide(color: primaryGreen, width: 1.5),
      ),
      hintStyle: TextStyle(color: textTertiary, fontSize: 14),
      contentPadding: EdgeInsets.symmetric(
        horizontal: spacingMd,
        vertical: spacingSm + 4,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: spacingLg,
          vertical: spacingMd,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        side: const BorderSide(color: divider),
        padding: const EdgeInsets.symmetric(
          horizontal: spacingLg,
          vertical: spacingMd,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 32,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 24,
        letterSpacing: -0.3,
      ),
      headlineSmall: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 20,
      ),
      titleLarge: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
      titleMedium: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
      titleSmall: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      bodyLarge: TextStyle(color: textPrimary, fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(color: textSecondary, fontSize: 14, height: 1.5),
      bodySmall: TextStyle(color: textTertiary, fontSize: 12, height: 1.4),
      labelLarge: TextStyle(
        color: textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      labelMedium: TextStyle(
        color: textSecondary,
        fontWeight: FontWeight.w500,
        fontSize: 12,
      ),
      labelSmall: TextStyle(
        color: textTertiary,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    ),
  );
}
