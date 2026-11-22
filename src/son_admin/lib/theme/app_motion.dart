import 'package:flutter/animation.dart';

/// Tiempos y curvas de las micro-animaciones de SON (250–350ms, easeOutCubic).
abstract final class AppMotion {
  static const Duration rapida = Duration(milliseconds: 250);
  static const Duration media = Duration(milliseconds: 300);
  static const Duration lenta = Duration(milliseconds: 350);

  /// Retraso entre tarjetas en una aparición escalonada.
  static const Duration escalon = Duration(milliseconds: 40);

  static const Curve curva = Curves.easeOutCubic;

  /// Desplazamiento vertical al aparecer (en píxeles).
  static const double desplazamiento = 8;
}
