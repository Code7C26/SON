import 'package:flutter/material.dart';

/// Tipografías de SON (ver CLAUDE.md §2):
/// - Títulos y encabezados: Plus Jakarta Sans.
/// - Interfaz, botones y tablas: Inter.
abstract final class AppTypography {
  static const String display = 'PlusJakartaSans';
  static const String ui = 'Inter';

  /// Tracking cerrado de los titulares.
  static const double trackingTitulo = -0.5;

  /// Tracking amplio de las etiquetas eyebrow.
  static const double trackingEyebrow = 1.2;

  static TextTheme textTheme(Color texto, Color secundario) {
    TextStyle d(double size, FontWeight w, [double? alto]) => TextStyle(
          fontFamily: display,
          fontSize: size,
          fontWeight: w,
          height: alto,
          letterSpacing: trackingTitulo,
          color: texto,
        );
    TextStyle u(double size, FontWeight w, {Color? color, double? alto, double? tracking}) => TextStyle(
          fontFamily: ui,
          fontSize: size,
          fontWeight: w,
          height: alto,
          letterSpacing: tracking,
          color: color ?? texto,
        );

    return TextTheme(
      displayLarge: d(48, FontWeight.w700, 1.1),
      displayMedium: d(40, FontWeight.w700, 1.1),
      displaySmall: d(34, FontWeight.w700, 1.15),
      headlineLarge: d(30, FontWeight.w700, 1.2),
      headlineMedium: d(26, FontWeight.w700, 1.2),
      headlineSmall: d(22, FontWeight.w700, 1.25),
      titleLarge: d(20, FontWeight.w700, 1.3),
      titleMedium: u(16, FontWeight.w600),
      titleSmall: u(14, FontWeight.w600),
      bodyLarge: u(16, FontWeight.w400, alto: 1.5),
      bodyMedium: u(14, FontWeight.w400, alto: 1.45),
      bodySmall: u(13, FontWeight.w400, color: secundario, alto: 1.4),
      labelLarge: u(14, FontWeight.w600),
      labelMedium: u(13, FontWeight.w500, color: secundario),
      labelSmall: u(12, FontWeight.w600, color: secundario, tracking: 0.3),
    );
  }

  /// Número grande de KPI (28–36px, Bold).
  static TextStyle kpi(Color color, {double size = 32}) => TextStyle(
        fontFamily: display,
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: trackingTitulo,
        height: 1.1,
        color: color,
      );

  /// Etiqueta corta debajo de un KPI (13px).
  static TextStyle kpiEtiqueta(Color color) => TextStyle(fontFamily: ui, fontSize: 13, color: color, height: 1.3);

  /// Etiqueta eyebrow: mayúsculas con tracking amplio.
  static TextStyle eyebrow(Color color) => TextStyle(
        fontFamily: ui,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: trackingEyebrow,
        color: color,
      );
}
