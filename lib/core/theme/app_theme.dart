import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_tokens.dart';

/// Thème global de l'application — typographie Outfit (titres) + Inter (texte),
/// couleurs issues de [AppTokens] (modes clair et sombre).
class AppTheme {
  AppTheme._();

  static final _radius14 = BorderRadius.circular(14);
  static final _radius12 = BorderRadius.circular(12);

  static final ThemeData light = _build(AppTokens.light, Brightness.light);
  static final ThemeData dark = _build(AppTokens.dark, Brightness.dark);

  static ThemeData _build(AppTokens t, Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: t.primary, brightness: b).copyWith(
      primary: t.primary,
      surface: t.surface,
      error: t.danger,
      outline: t.outline,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.background,
      splashFactory: InkSparkle.splashFactory,
      extensions: [t],
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      // Échelle courte et contrastée : un très grand (display), des titres
      // (headline/title), un corps (body) et des libellés (label ≥ 13 px).
      displayLarge: GoogleFonts.outfit(
          fontWeight: FontWeight.w800, fontSize: 44, height: 1.0, letterSpacing: -1, color: t.textPrimary),
      displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 24, color: t.textPrimary),
      displaySmall: GoogleFonts.outfit(
          fontWeight: FontWeight.w700, fontSize: 26, height: 1.1, letterSpacing: -0.4, color: t.textPrimary),
      headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 32, height: 1, color: t.textPrimary),
      headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 20, color: t.textPrimary),
      headlineSmall: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 22, height: 1.35, color: t.textPrimary),
      titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 17, color: t.textPrimary),
      titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15, color: t.textPrimary),
      titleSmall: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: t.textPrimary),
      labelMedium: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13, color: t.textSecondary),
      labelSmall: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13, color: t.textSecondary),
      bodyLarge: GoogleFonts.inter(fontSize: 15, height: 1.45, color: t.textPrimary),
      bodyMedium: GoogleFonts.inter(fontSize: 14, height: 1.45, color: t.textSecondary),
      labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: t.textPrimary),
    );

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(borderRadius: _radius14, borderSide: BorderSide(color: color, width: width));

    return base.copyWith(
      textTheme: textTheme,
      // Transition de page douce (fondu + glissement) sur toutes les plateformes.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.headlineMedium,
        iconTheme: IconThemeData(color: t.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: t.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: GoogleFonts.inter(fontSize: 13.5, color: t.textSecondary),
        helperStyle: GoogleFonts.inter(fontSize: 13, color: t.textSecondary),
        errorStyle: GoogleFonts.inter(fontSize: 13, color: t.danger, fontWeight: FontWeight.w500),
        prefixIconColor: t.textSecondary,
        suffixIconColor: t.textSecondary,
        border: border(Colors.transparent),
        enabledBorder: border(Colors.transparent),
        disabledBorder: border(Colors.transparent),
        focusedBorder: border(t.primary, 1.6),
        errorBorder: border(t.danger, 1.2),
        focusedErrorBorder: border(t.danger, 1.6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      // « Secondaire » = aplat tonal, jamais un contour 1px.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          side: BorderSide.none,
          backgroundColor: t.surfaceMuted,
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: t.handle,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: b == Brightness.light ? t.textPrimary : t.surfaceMuted,
        shape: RoundedRectangleBorder(borderRadius: _radius12),
        contentTextStyle: GoogleFonts.inter(fontSize: 13.5, color: b == Brightness.light ? Colors.white : t.textPrimary, fontWeight: FontWeight.w500),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : t.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primary : t.outline,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.primary),
      listTileTheme: ListTileThemeData(iconColor: t.textSecondary),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: t.surface,
        selectedItemColor: t.primary,
        unselectedItemColor: t.textSecondary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 8,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.surfaceMuted,
        selectedColor: t.primary,
        labelStyle: textTheme.bodyMedium?.copyWith(color: t.textPrimary),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
      dividerTheme: DividerThemeData(color: t.outline, thickness: 1),
    );
  }
}
