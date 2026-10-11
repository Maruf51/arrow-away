import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // The game now uses a single dark purple theme (no light mode theming)
  static bool isDark = true;

  static void updateTheme(bool dark) {
    isDark = true; // always dark
  }

  // ── Brand Purple/Gold palette ──────────────────────────────────────────────
  static const Color purple        = Color(0xFF7B2FBE); // deep vivid purple
  static const Color purpleDark    = Color(0xFF4A1A8C); // darker purple
  static const Color purpleLight   = Color(0xFF9B4FDE); // lighter purple
  static const Color purpleVibrant = Color(0xFF8B35D6); // mid purple

  static const Color gold          = Color(0xFFF5A623); // golden yellow
  static const Color goldLight     = Color(0xFFFFCC44); // lighter gold
  static const Color goldDark      = Color(0xFFD4881A); // darker gold

  static const Color green         = Color(0xFF2ECC71); // play button green
  static const Color greenDark     = Color(0xFF27AE60);

  static const Color red           = Color(0xFFE74C3C); // hearts / danger
  static const Color heartRed      = Color(0xFFFF4757);

  // Background — deep purple/indigo gradient
  static const Color bgTop         = Color(0xFF1A0A3C);
  static const Color bgMid         = Color(0xFF1E1045);
  static const Color bgBottom      = Color(0xFF120830);

  // Surface card (cream/beige for settings dialogs like the reference)
  static const Color cardCream     = Color(0xFFF5EFE0);
  static const Color cardBorder    = Color(0xFFE8DCC0);

  // Text
  static const Color textWhite     = Color(0xFFFFFFFF);
  static const Color textGold      = Color(0xFFF5A623);
  static const Color textPurple    = Color(0xFF7B2FBE);
  static const Color textDark      = Color(0xFF2C1A6B);
  static const Color textMuted     = Color(0xFF9E8FBF);

  // ── Aliases used by existing code ─────────────────────────────────────────
  static Color get primary        => purple;
  static Color get primaryLight   => purpleLight;
  static Color get primaryDark    => purpleDark;
  static Color get accent         => gold;
  static Color get accentGold     => gold;
  static Color get accentGreen    => green;
  static Color get accentOrange   => gold;

  static Color get background     => bgBottom;
  static Color get surface        => const Color(0xFF2A1A5E); // dark purple card
  static Color get surfaceLight   => const Color(0xFF3D2880); // lighter surface

  static Color get gridBg         => bgBottom;

  // Arrow direction colors
  static Color get arrowUp    => textWhite;
  static Color get arrowDown  => textWhite;
  static Color get arrowLeft  => textWhite;
  static Color get arrowRight => textWhite;

  // Difficulty colors
  static Color get easy   => green;
  static Color get medium => gold;
  static Color get hard   => purple;
  static Color get expert => const Color(0xFFE74C3C);
  static Color get master => const Color(0xFFB33939);

  // UI
  static Color get heartEmpty  => const Color(0xFF3D2880);
  static Color get streakFire  => gold;
  static Color get coinGold    => gold;
  static Color get starYellow  => gold;
  static Color get borderGlow  => purple;

  // Text aliases
  static Color get textPrimary    => textWhite;
  static Color get textSecondary  => const Color(0xFFCCBBEE);
  static Color get textMutedAlias => textMuted;

  // ── Group Colors (unchanged — still maximally distinct) ───────────────────
  static const List<Color> _groupColorsDark = [
    Color(0xFFFF2A4B),
    Color(0xFF2979FF),
    Color(0xFF00E676),
    Color(0xFFD500F9),
    Color(0xFFFF8B00),
    Color(0xFF00E5FF),
    Color(0xFFFF52A1),
    Color(0xFFFFD600),
    Color(0xFFAEEA00),
    Color(0xFF1DE9B6),
    Color(0xFF7575FF),
    Color(0xFFFF4081),
  ];

  static int get pairColorCount => _groupColorsDark.length;

  static Color getGroupColor(int groupIndex) {
    return _groupColorsDark[groupIndex % _groupColorsDark.length];
  }

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient bgGradient = LinearGradient(
    colors: [bgTop, bgMid, bgBottom],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient purpleGradient = LinearGradient(
    colors: [purpleLight, purpleDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [goldLight, gold, goldDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient greenGradient = LinearGradient(
    colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Legacy alias
  static LinearGradient get primaryGradient   => purpleGradient;
  static LinearGradient get secondaryGradient => purpleGradient;
  static LinearGradient get successGradient   => greenGradient;
  static LinearGradient get dangerGradient    => const LinearGradient(
    colors: [Color(0xFFE74C3C), Color(0xFFC0392B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
