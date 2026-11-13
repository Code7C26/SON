import 'package:flutter/material.dart';

/// Espaciados en múltiplos de 8, radios y sombras de SON (ver CLAUDE.md §3-4).
abstract final class AppSpacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;

  /// Área táctil mínima (48x48dp).
  static const double tactilMinimo = 48;

  static const EdgeInsets pagina = EdgeInsets.fromLTRB(s32, s32, s32, s24);
  static const EdgeInsets paginaMovil = EdgeInsets.fromLTRB(s16, s16, s16, s24);
}

abstract final class AppRadius {
  static const double chico = 12;
  static const double tarjeta = 24;
  static const double tarjetaGrande = 32;
  static const double pildora = 999;

  /// Inputs en píldora: con 56dp de alto, 28 de radio es una cápsula completa;
  /// en campos de varias líneas queda como tarjeta muy redondeada.
  static const double input = 28;

  static const BorderRadius rChico = BorderRadius.all(Radius.circular(chico));
  static const BorderRadius rTarjeta = BorderRadius.all(Radius.circular(tarjeta));
  static const BorderRadius rTarjetaGrande = BorderRadius.all(Radius.circular(tarjetaGrande));
  static const BorderRadius rInput = BorderRadius.all(Radius.circular(input));
  static const BorderRadius rPildora = BorderRadius.all(Radius.circular(pildora));
}

abstract final class AppShadows {
  /// Sombra muy suave: blur 20, opacidad 4%.
  static const List<BoxShadow> suave = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 20, offset: Offset(0, 4)),
  ];

  /// Sombra de los paneles de vidrio: muy difusa para que floten sobre los orbes.
  static const List<BoxShadow> vidrio = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 32, offset: Offset(0, 8)),
  ];

  /// Elevación leve para hover.
  static const List<BoxShadow> elevada = [
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}
