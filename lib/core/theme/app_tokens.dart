import 'package:flutter/material.dart';

/// Design tokens (colours and shadows) for the light and dark themes.
///
/// Read them with `AppTokens.of(context)`. Dark "soft" colours are the accent
/// at 16 % pre-blended over [surface], so they stay opaque and measurable.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.primary,
    required this.primarySoft,
    required this.onPrimarySoft,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.handle,
    required this.heroGradient,
    required this.cardShadow,
    required this.navShadow,
  });

  final Color primary;
  final Color primarySoft;
  final Color onPrimarySoft;
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color outline;
  final Color textPrimary;
  final Color textSecondary;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color handle;
  final LinearGradient heroGradient;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> navShadow;

  static const light = AppTokens(
    primary: Color(0xFFF9671E),
    primarySoft: Color(0xFFFFF1E8),
    onPrimarySoft: Color(0xFFB75115),
    background: Color(0xFFF6F6F9),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF0F0F4),
    outline: Color(0xFFEEEDF2),
    textPrimary: Color(0xFF1C1A33),
    textSecondary: Color(0xFF767586),
    success: Color(0xFF1B7A43),
    successSoft: Color(0xFFE6F6EC),
    warning: Color(0xFFB45309),
    warningSoft: Color(0xFFFEF3C7),
    danger: Color(0xFFC62828),
    dangerSoft: Color(0xFFFEE2E2),
    handle: Color(0xFFE2E1E8),
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFF6A1F), Color(0xFFF0561E)],
    ),
    cardShadow: [BoxShadow(color: Color(0x0F1C1A33), blurRadius: 10, offset: Offset(0, 2))],
    navShadow: [BoxShadow(color: Color(0x1F1C1A33), blurRadius: 24, offset: Offset(0, 8))],
  );

  static const dark = AppTokens(
    primary: Color(0xFFEC7136),
    primarySoft: Color(0xFF402821),
    onPrimarySoft: Color(0xFFFF9A5F),
    background: Color(0xFF121214),
    surface: Color(0xFF1C1C21),
    surfaceMuted: Color(0xFF242429),
    outline: Color(0xFF2A2A2F),
    textPrimary: Color(0xFFF4F2F0),
    textSecondary: Color(0xFF9A969B),
    success: Color(0xFF4ADE80),
    successSoft: Color(0xFF233B30),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0xFF403621),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF3F2A2E),
    handle: Color(0xFF3A3A40),
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFF7A3A), Color(0xFFD9541A)],
    ),
    cardShadow: [],
    navShadow: [],
  );

  static AppTokens of(BuildContext context) => Theme.of(context).extension<AppTokens>()!;

  @override
  AppTokens copyWith({
    Color? primary,
    Color? primarySoft,
    Color? onPrimarySoft,
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? outline,
    Color? textPrimary,
    Color? textSecondary,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? handle,
    LinearGradient? heroGradient,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? navShadow,
  }) =>
      AppTokens(
        primary: primary ?? this.primary,
        primarySoft: primarySoft ?? this.primarySoft,
        onPrimarySoft: onPrimarySoft ?? this.onPrimarySoft,
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceMuted: surfaceMuted ?? this.surfaceMuted,
        outline: outline ?? this.outline,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        success: success ?? this.success,
        successSoft: successSoft ?? this.successSoft,
        warning: warning ?? this.warning,
        warningSoft: warningSoft ?? this.warningSoft,
        danger: danger ?? this.danger,
        dangerSoft: dangerSoft ?? this.dangerSoft,
        handle: handle ?? this.handle,
        heroGradient: heroGradient ?? this.heroGradient,
        cardShadow: cardShadow ?? this.cardShadow,
        navShadow: navShadow ?? this.navShadow,
      );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      primary: c(primary, other.primary),
      primarySoft: c(primarySoft, other.primarySoft),
      onPrimarySoft: c(onPrimarySoft, other.onPrimarySoft),
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      outline: c(outline, other.outline),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      handle: c(handle, other.handle),
      heroGradient: LinearGradient.lerp(heroGradient, other.heroGradient, t)!,
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t)!,
      navShadow: BoxShadow.lerpList(navShadow, other.navShadow, t)!,
    );
  }
}
