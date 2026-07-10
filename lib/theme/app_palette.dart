import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Monospace font, reserved for algs, letter pairs and times.
const String MONO_FONT = "firaCode";

/// The selectable color themes. The B ("Keycap") layout is shared by all of
/// them; only the palette changes.
enum AppThemeId {
  slate,
  keycap,
  cubeFace;

  String getLocalizedName(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (this) {
      case AppThemeId.keycap:
        return l10n.themeKeycap;
      case AppThemeId.slate:
        return l10n.themeSlate;
      case AppThemeId.cubeFace:
        return l10n.themeCubeFace;
    }
  }

  AppPalette get palette {
    switch (this) {
      case AppThemeId.keycap:
        return AppPalette.keycap;
      case AppThemeId.slate:
        return AppPalette.slate;
      case AppThemeId.cubeFace:
        return AppPalette.cubeFace;
    }
  }
}

/// A full set of color tokens for one theme. Widgets read these via
/// `context.palette`; [buildTheme] derives a matching Material [ThemeData].
class AppPalette {
  final AppThemeId id;
  final Brightness brightness;

  /// Background gradient (top -> bottom). Solid themes use two close colors.
  final List<Color> bgGradient;

  /// Opaque surface for dialogs / dropdown menus (panels can be translucent).
  final Color surfaceOpaque;

  final Color panel; // card / glass fill
  final Color panelBorder;
  final Color inputFill;

  final Color accent; // primary accent
  final Color onAccent;
  final Color pop; // secondary pop (toggles, running time)
  final Color onPop;

  final Color good;
  final Color bad;
  final Color mid;

  final Color textPrimary;
  final Color textMuted;
  final Color textFaint;
  final Color appBarFg;

  // Keycap (type button) tokens.
  final Color keycapTop;
  final Color keycapBottom; // raised "ridge" under the cap
  final Color keycapText;
  final Color keycapSubtext;
  final Color keycapDisabledTop;
  final Color keycapDisabledBottom;
  final Color keycapDisabledText;

  const AppPalette({
    required this.id,
    required this.brightness,
    required this.bgGradient,
    required this.surfaceOpaque,
    required this.panel,
    required this.panelBorder,
    required this.inputFill,
    required this.accent,
    required this.onAccent,
    required this.pop,
    required this.onPop,
    required this.good,
    required this.bad,
    required this.mid,
    required this.textPrimary,
    required this.textMuted,
    required this.textFaint,
    required this.appBarFg,
    required this.keycapTop,
    required this.keycapBottom,
    required this.keycapText,
    required this.keycapSubtext,
    required this.keycapDisabledTop,
    required this.keycapDisabledBottom,
    required this.keycapDisabledText,
  });

  // ---- B · Keycap (default) : indigo gradient, frosted glass, amber pop ----
  static const AppPalette keycap = AppPalette(
    id: AppThemeId.keycap,
    brightness: Brightness.dark,
    bgGradient: [Color(0xFF33285A), Color(0xFF191330)],
    surfaceOpaque: Color(0xFF2A2246),
    panel: Color(0x14FFFFFF),
    panelBorder: Color(0x1FFFFFFF),
    inputFill: Color(0x40000000),
    accent: Color(0xFFB39DDB),
    onAccent: Color(0xFF241A3A),
    pop: Color(0xFFFFCA6B),
    onPop: Color(0xFF3A2A08),
    good: Color(0xFF7BD88F),
    bad: Color(0xFFFF7A85),
    mid: Color(0xFFFFB37A),
    textPrimary: Color(0xFFF2EEFB),
    textMuted: Color(0xFFB0A8C8),
    textFaint: Color(0xFF8078A0),
    appBarFg: Color(0xFFF2EEFB),
    keycapTop: Color(0xFF4E4178),
    keycapBottom: Color(0xFF362D59),
    keycapText: Color(0xFFF2EEFB),
    keycapSubtext: Color(0xFFC8BFE4),
    keycapDisabledTop: Color(0xFF3A3158),
    keycapDisabledBottom: Color(0xFF241D3A),
    keycapDisabledText: Color(0xFF8880A8),
  );

  // ---- A · Slate : charcoal + steel, single cyan accent ----
  static const AppPalette slate = AppPalette(
    id: AppThemeId.slate,
    brightness: Brightness.dark,
    bgGradient: [Color(0xFF1B1F24), Color(0xFF141719)],
    surfaceOpaque: Color(0xFF252B32),
    panel: Color(0xFF252B32),
    panelBorder: Color(0xFF333B43),
    inputFill: Color(0xFF161A1E),
    accent: Color(0xFF4DD0E1),
    onAccent: Color(0xFF062A2E),
    pop: Color(0xFF4DD0E1),
    onPop: Color(0xFF062A2E),
    good: Color(0xFF66BB6A),
    bad: Color(0xFFEF5350),
    mid: Color(0xFFEF9A9A),
    textPrimary: Color(0xFFE8EAED),
    textMuted: Color(0xFF9AA0A6),
    textFaint: Color(0xFF6B7178),
    appBarFg: Color(0xFFE8EAED),
    keycapTop: Color(0xFF2C333B),
    keycapBottom: Color(0xFF14181C),
    keycapText: Color(0xFFE8EAED),
    keycapSubtext: Color(0xFF9AA0A6),
    keycapDisabledTop: Color(0xFF20252B),
    keycapDisabledBottom: Color(0xFF121417),
    keycapDisabledText: Color(0xFF5F666D),
  );

  // ---- C · Cube Face : light Material, blue accent, green pop ----
  static const AppPalette cubeFace = AppPalette(
    id: AppThemeId.cubeFace,
    brightness: Brightness.light,
    bgGradient: [Color(0xFFF4F5F7), Color(0xFFECEEF1)],
    surfaceOpaque: Color(0xFFFFFFFF),
    panel: Color(0xFFFFFFFF),
    panelBorder: Color(0xFFE6E8EC),
    inputFill: Color(0xFFF0F1F4),
    accent: Color(0xFF2D6CDF),
    onAccent: Color(0xFFFFFFFF),
    pop: Color(0xFF37A860),
    onPop: Color(0xFFFFFFFF),
    good: Color(0xFF2E9E56),
    bad: Color(0xFFE8483C),
    mid: Color(0xFFF08A24),
    textPrimary: Color(0xFF1D2126),
    textMuted: Color(0xFF6B7280),
    textFaint: Color(0xFF9AA0A6),
    appBarFg: Color(0xFF1D2126),
    keycapTop: Color(0xFFFFFFFF),
    keycapBottom: Color(0xFFD7DBE0),
    keycapText: Color(0xFF1D2126),
    keycapSubtext: Color(0xFF6B7280),
    keycapDisabledTop: Color(0xFFECEEF1),
    keycapDisabledBottom: Color(0xFFD7DBE0),
    keycapDisabledText: Color(0xFFAEB4BB),
  );
}

/// Builds a Material [ThemeData] whose defaults match [palette], so raw
/// Material widgets (dialogs, dropdowns, snackbars, switches) blend in.
/// Display-size text is monospace (algs / pairs / times); everything else uses
/// the platform sans-serif.
ThemeData buildTheme(AppPalette p) {
  final baseScheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: p.brightness,
  );
  final colorScheme = baseScheme.copyWith(
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.pop,
    onSecondary: p.onPop,
    surface: p.surfaceOpaque,
    onSurface: p.textPrimary,
    error: p.bad,
  );

  TextStyle mono(double size, FontWeight weight, Color color) => TextStyle(
        fontFamily: MONO_FONT,
        fontSize: size,
        fontWeight: weight,
        color: color,
      );
  TextStyle sans(double size, FontWeight weight, Color color) => TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: p.bgGradient.last,
    canvasColor: p.surfaceOpaque,
    // Display styles = monospace (algs, pairs, big numbers, times).
    textTheme: TextTheme(
      displayLarge: mono(88, FontWeight.w700, p.textPrimary),
      displayMedium: mono(44, FontWeight.w500, p.textPrimary),
      displaySmall: mono(30, FontWeight.w500, p.textPrimary),
      // Title / label / body = sans-serif (chrome).
      titleLarge: sans(28, FontWeight.w700, p.textPrimary),
      titleMedium: sans(20, FontWeight.w700, p.textPrimary),
      titleSmall: sans(16, FontWeight.w600, p.textPrimary),
      labelLarge: sans(16, FontWeight.w600, p.textPrimary),
      labelMedium: sans(14, FontWeight.w500, p.textMuted),
      labelSmall: sans(13, FontWeight.w500, p.textMuted),
      bodyLarge: sans(16, FontWeight.w400, p.textPrimary),
      bodyMedium: sans(14, FontWeight.w400, p.textPrimary),
      bodySmall: sans(12, FontWeight.w400, p.textMuted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.appBarFg,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: sans(20, FontWeight.w700, p.appBarFg),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surfaceOpaque,
      surfaceTintColor: Colors.transparent,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.surfaceOpaque),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surfaceOpaque,
      contentTextStyle: sans(14, FontWeight.w500, p.textPrimary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : p.textFaint),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? p.pop : p.panelBorder),
      trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.panelBorder,
    ),
    iconTheme: IconThemeData(color: p.textMuted),
  );
}
