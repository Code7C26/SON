import 'package:flutter/material.dart';

/// Tokens de color de SON. Solo la paleta original de la marca:
/// coral #FF6147, dorado #D99C13, tinta #2E2E2E, gris claro #F4F4F4 y sus grises neutros.
/// No agregar colores nuevos ni hardcodear colores fuera de acá.
abstract final class AppColors {
  // Marca
  static const Color canvas = Color(0xFFF4F4F4);
  static const Color superficie = Color(0xFFFFFFFF);
  static const Color tinta = Color(0xFF2E2E2E);
  static const Color acento = Color(0xFFFF6147);
  /// Texto e íconos sobre el coral: tinta (4.56:1). El blanco daba 2.98:1.
  static const Color sobreAcento = tinta;
  static const Color oro = Color(0xFFD99C13);
  static const Color sobreOro = tinta;

  // Etiquetas suaves (eyebrow pills): coral sobre coral muy suave.
  static const Color eyebrowFondo = Color(0x1FFF6147);
  static const Color eyebrowTexto = acento;

  // Textos
  static const Color texto = tinta;
  static const Color textoSecundario = Color(0xFF6E6E6E);
  static const Color textoTenue = Color(0xFF9A9A9A);

  // Bordes y rellenos
  static const Color borde = Color(0xFFD5D5D5);
  static const Color superficieAlta = Color(0xFFE7E7E7);

  // Vidrio esmerilado (glassmorphism suave): blanco o panel oscuro translúcido.
  static const Color vidrio = Color(0xB8FFFFFF);
  static const Color vidrioBorde = Color(0xCCFFFFFF);
  static const Color vidrioOscuro = Color(0xB8353535);
  static const Color vidrioOscuroBorde = Color(0x804C4C4C);

  // Estados (con la misma paleta)
  static const Color exito = acento;
  static const Color alerta = oro;
  static const Color error = Color(0xFFC62828);
  static const Color progreso = Color(0xFFC46A3A);

  // Modo oscuro (base #2E2E2E, como estaba)
  static const Color oscuroFondo = tinta;
  static const Color oscuroPanel = Color(0xFF262626);
  static const Color oscuroSuperficie = Color(0xFF353535);
  static const Color oscuroSuperficieAlta = Color(0xFF3F3F3F);
  static const Color oscuroBorde = Color(0xFF4C4C4C);
  static const Color oscuroTexto = canvas;
  static const Color oscuroTextoSecundario = Color(0xFFB3B3B3);
  static const Color oscuroTextoTenue = Color(0xFF8C8C8C);
  static const Color oscuroError = Color(0xFFFF8A80);
  static const Color oscuroProgreso = Color(0xFFE08A55);
}
