import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Thème global de l'application — typographie Outfit (titres) + Inter (texte).
class AppTheme {
  AppTheme._();

  static final _radius12 = BorderRadius.circular(12);

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        tertiary: AppColors.lavender,
        error: AppColors.danger,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      // Échelle courte et contrastée : un très grand (display), des titres
      // (headline/title), un corps (body) et des libellés (label ≥ 13 px).
      displayLarge: GoogleFonts.outfit(
          fontWeight: FontWeight.w800, fontSize: 44, height: 1.0, letterSpacing: -1, color: AppColors.textPrimary),
      displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 24, color: AppColors.textPrimary),
      displaySmall: GoogleFonts.outfit(
          fontWeight: FontWeight.w700, fontSize: 26, height: 1.1, letterSpacing: -0.4, color: AppColors.textPrimary),
      headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 32, height: 1, color: AppColors.textPrimary),
      headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 20, color: AppColors.textPrimary),
      headlineSmall: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 22, height: 1.35, color: AppColors.textPrimary),
      titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary),
      titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
      titleSmall: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
      labelMedium: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13, color: AppColors.textSecondary),
      labelSmall: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13, color: AppColors.textSecondary),
      bodyLarge: GoogleFonts.inter(fontSize: 15, height: 1.45, color: AppColors.textPrimary),
      bodyMedium: GoogleFonts.inter(fontSize: 14, height: 1.45, color: AppColors.textSecondary),
      labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
    );

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
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.headlineMedium,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textSecondary.withValues(alpha: 0.75)),
        helperStyle: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textSecondary),
        errorStyle: GoogleFonts.inter(fontSize: 11.5, color: AppColors.danger, fontWeight: FontWeight.w500),
        prefixIconColor: AppColors.lavender,
        suffixIconColor: AppColors.textSecondary,
        border: OutlineInputBorder(borderRadius: _radius12, borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: _radius12, borderSide: const BorderSide(color: AppColors.border)),
        disabledBorder: OutlineInputBorder(
          borderRadius: _radius12,
          borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: _radius12,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: _radius12,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: _radius12,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
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
          minimumSize: const Size(0, 46),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      // « Secondaire » = aplat tonal (un ton au-dessus du fond), jamais un
      // contour 1px.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide.none,
          backgroundColor: AppColors.surfaceTone,
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyLarge,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: _radius12),
        contentTextStyle: GoogleFonts.inter(fontSize: 13.5, color: Colors.white, fontWeight: FontWeight.w500),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.border,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.textSecondary),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 8,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceTone,
        selectedColor: AppColors.primary,
        labelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    );
  }
}
