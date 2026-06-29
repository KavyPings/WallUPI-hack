import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Wallupi — Aura Pay Design System v2
/// Tactile Minimalism + Editorial Fintech
/// Palette: Deep Graphite base, Periwinkle primary, Muted Cobalt actions
class AppTheme {
  // ═══════════════════════════════════════════════════════════
  // COLOR PALETTE
  // ═══════════════════════════════════════════════════════════

  // Layer 0 — Base canvas (warm black)
  static const Color background         = Color(0xFF121315);
  static const Color surface            = Color(0xFF121315);
  static const Color surfaceDim         = Color(0xFF121315);

  // Elevated surfaces — tonal layering
  static const Color surfaceContainerLowest  = Color(0xFF0D0E10);
  static const Color surfaceContainerLow     = Color(0xFF1B1C1E); // cards
  static const Color surfaceContainer        = Color(0xFF1F2022); // nav bg
  static const Color surfaceContainerHigh    = Color(0xFF292A2C); // hover/pressed
  static const Color surfaceContainerHighest = Color(0xFF343537); // chips/badges
  static const Color surfaceBright           = Color(0xFF38393B);

  // Text
  static const Color onSurface        = Color(0xFFE3E2E4); // primary text
  static const Color onSurfaceVariant = Color(0xFFC3C5D7); // secondary text (blue tint)

  // Outline
  static const Color outline        = Color(0xFF8D90A0); // muted labels, icons
  static const Color outlineVariant = Color(0xFF434654); // 1px borders/dividers

  // Primary — Periwinkle Lavender (nav active, small accents)
  static const Color primary             = Color(0xFFB5C4FF);
  static const Color onPrimary           = Color(0xFF00297A);
  static const Color primaryContainer    = Color(0xFF638AFF); // cobalt blue
  static const Color onPrimaryContainer  = Color(0xFF00236B);
  static const Color primaryFixed        = Color(0xFFDBE1FF);

  // Accent — Muted Cobalt (action buttons, CTA)
  static const Color accent    = Color(0xFF4B7BFF);
  static const Color onAccent  = Color(0xFFFFFFFF);

  // Secondary — Champagne (secondary accents, ghost borders)
  static const Color secondary          = Color(0xFFD1C4B8);
  static const Color onSecondary        = Color(0xFF372F26);
  static const Color secondaryContainer = Color(0xFF50483E);

  // Error
  static const Color error          = Color(0xFFFFB4AB);
  static const Color onError        = Color(0xFF690005);
  static const Color errorContainer = Color(0xFF93000A);

  // Risk semantic — adjusted for dark legibility
  static const Color riskSafe     = Color(0xFF4DB374);
  static const Color riskMedium   = Color(0xFFE3A838);
  static const Color riskHigh     = Color(0xFFEF5350);
  static const Color riskCritical = Color(0xFFB71C1C);
  static const Color danger       = Color(0xFFEF5350);
  static const Color warningOrange = Color(0xFFFF8C00);

  // Legacy aliases — keep for backward compat with existing screens
  static const Color cardColor      = surfaceContainerLow;
  static const Color textPrimary    = onSurface;
  static const Color textSecondary  = onSurfaceVariant;
  static const Color textLight      = outline;
  static const Color divider        = outlineVariant;
  static const Color onPrimary2     = onPrimary; // old onPrimary slot
  static const Color dangerLight    = Color(0xFFFF8A80);
  static const Color warning        = riskMedium;

  // ═══════════════════════════════════════════════════════════
  // ELEVATION / SHADOWS
  // Depth = tonal layers + inner highlight. No drop shadows.
  // ═══════════════════════════════════════════════════════════

  static List<BoxShadow> get softShadow => const [];
  static List<BoxShadow> get cardShadow => const [];

  /// Subtle 1px inner highlight — simulates beveled / milled card edge
  static const BoxShadow innerHighlight = BoxShadow(
    color: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    offset: Offset(0, 1),
    blurRadius: 0,
    blurStyle: BlurStyle.inner,
  );

  /// Cobalt ambient glow for primary action buttons
  static const BoxShadow cobaltGlow = BoxShadow(
    color: Color(0x334B7BFF), // rgba(75,123,255,0.2)
    blurRadius: 12,
    offset: Offset(0, 4),
  );

  // ═══════════════════════════════════════════════════════════
  // BORDER RADIUS  (8px base unit)
  // ═══════════════════════════════════════════════════════════

  static const double radiusXS     = 4.0;   // 0.25rem — tiny chips
  static const double radiusSmall  = 8.0;   // rounded-lg — buttons, inputs
  static const double radiusMedium = 12.0;  // rounded-xl — form sections
  static const double radiusLarge  = 16.0;  // larger modals
  static const double radiusCard   = 24.0;  // rounded-2xl — hero cards

  // ═══════════════════════════════════════════════════════════
  // SPACING  (8px base unit)
  // ═══════════════════════════════════════════════════════════

  static const double spacingXS = 4.0;
  static const double spacingS  = 8.0;
  static const double spacingM  = 16.0;
  static const double spacingL  = 24.0;   // gutter / card padding
  static const double spacingXL = 48.0;   // stack-lg

  // ═══════════════════════════════════════════════════════════
  // GRADIENTS  (only for ambient decorative glows)
  // ═══════════════════════════════════════════════════════════

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFB71C1C), Color(0xFFEF5350)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Kept for legacy references — renders solid on dark bg
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [surfaceContainerHigh, surfaceContainerHighest],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [surfaceContainerLow, surfaceContainerHigh],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ═══════════════════════════════════════════════════════════
  // THEME DATA
  // ═══════════════════════════════════════════════════════════

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary:                  primary,
        onPrimary:                onPrimary,
        primaryContainer:         primaryContainer,
        onPrimaryContainer:       onPrimaryContainer,
        secondary:                secondary,
        onSecondary:              onSecondary,
        secondaryContainer:       secondaryContainer,
        error:                    error,
        onError:                  onError,
        surface:                  surfaceContainerLow,
        onSurface:                onSurface,
        outline:                  outlineVariant,
        surfaceContainerHighest:  surfaceContainerHighest,
        surfaceContainerHigh:     surfaceContainerHigh,
        surfaceContainer:         surfaceContainer,
        surfaceContainerLow:      surfaceContainerLow,
        surfaceContainerLowest:   surfaceContainerLowest,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: 'Inter',
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 36, fontWeight: FontWeight.w600,
          color: onSurface, letterSpacing: -36 * 0.03,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 28, fontWeight: FontWeight.w600,
          color: onSurface, letterSpacing: -28 * 0.02,
        ),
        headlineLarge: GoogleFonts.inter(
          fontSize: 24, fontWeight: FontWeight.w500,
          color: onSurface, letterSpacing: -24 * 0.02,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 20, fontWeight: FontWeight.w600,
          color: onSurface, letterSpacing: -0.3,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 18, fontWeight: FontWeight.w500, color: onSurface,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w500, color: onSurface,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 18, fontWeight: FontWeight.w400, color: onSurface,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 16, fontWeight: FontWeight.w400, color: onSurface,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.w400, color: onSurfaceVariant,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 12, fontWeight: FontWeight.w600, color: onSurface,
          letterSpacing: 12 * 0.06,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 11, fontWeight: FontWeight.w500, color: onSurfaceVariant,
          letterSpacing: 11 * 0.02,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 10, fontWeight: FontWeight.w500, color: outline,
          letterSpacing: 0.5,
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17, fontWeight: FontWeight.w600,
          color: onSurface, letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: onSurface, size: 22),
        actionsIconTheme: const IconThemeData(color: primary, size: 22),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        shape: const Border(
          bottom: BorderSide(color: outlineVariant, width: 1),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,        // Muted Cobalt CTA
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: secondary,
          side: const BorderSide(color: secondary, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      cardTheme: CardThemeData(
        color: surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: outlineVariant, width: 1),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(fontSize: 15, color: outline),
        labelStyle: GoogleFonts.inter(fontSize: 14, color: onSurfaceVariant),
        prefixIconColor: outline,
        suffixIconColor: outline,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceContainer,
        selectedItemColor: primary,
        unselectedItemColor: onSurfaceVariant,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 10),
      ),

      dividerTheme: const DividerThemeData(
        color: outlineVariant,
        thickness: 1,
        space: 1,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainerHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: outlineVariant),
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18, fontWeight: FontWeight.w600, color: onSurface,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14, color: onSurfaceVariant,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceContainerHighest,
        contentTextStyle: GoogleFonts.inter(color: onSurface, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusCard)),
          side: BorderSide(color: outlineVariant),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? accent : onSurfaceVariant),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? accent.withValues(alpha: 0.3)
                : surfaceContainerHigh),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? accent : surfaceContainerHigh),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: outlineVariant),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainerHigh,
        selectedColor: accent.withValues(alpha: 0.15),
        labelStyle: GoogleFonts.inter(fontSize: 12, color: onSurface),
        side: const BorderSide(color: outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(100),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // COMPONENT DECORATION HELPERS
  // ═══════════════════════════════════════════════════════════

  /// Layer-1 card — 24px radius, outlineVariant border, inner highlight
  static BoxDecoration cardDecoration({
    Color? color,
    double radius = radiusCard,
    Color? borderColor,
    bool withHighlight = true,
  }) =>
      BoxDecoration(
        color: color ?? surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? outlineVariant, width: 1),
        boxShadow: withHighlight ? const [innerHighlight] : [],
      );

  /// Circle avatar / icon container
  static BoxDecoration circleDecoration({
    Color? color,
    Color? borderColor,
  }) =>
      BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? surfaceContainerHighest,
        border: Border.all(color: borderColor ?? outlineVariant, width: 1),
        boxShadow: const [innerHighlight],
      );

  /// Action button decoration (cobalt with glow)
  static BoxDecoration accentButtonDecoration({double radius = radiusSmall}) =>
      BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [cobaltGlow],
      );

  // ═══════════════════════════════════════════════════════════
  // RISK HELPERS
  // ═══════════════════════════════════════════════════════════

  static Color getRiskColor(int score) {
    if (score >= 95) return riskCritical;
    if (score >= 80) return riskHigh;
    if (score >= 50) return riskMedium;
    return riskSafe;
  }

  static String getRiskLabel(int score) {
    if (score >= 95) return 'Critical';
    if (score >= 80) return 'High Risk';
    if (score >= 50) return 'Caution';
    if (score >= 20) return 'Low Risk';
    return 'Safe';
  }

  static IconData getRiskIcon(int score) {
    if (score >= 80) return Icons.warning_rounded;
    if (score >= 50) return Icons.info_rounded;
    return Icons.check_circle_rounded;
  }
}
