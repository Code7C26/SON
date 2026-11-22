import 'package:flutter/material.dart';
import 'package:son_tecnico/theme/tema.dart';

export 'package:son_tecnico/theme/tema.dart';

/// Colores de la etiqueta de estado de una orden: (fondo, texto).
(Color, Color) coloresEstado(String estado) {
  final color = switch (estado) {
    'Completada' => sonLightGreen,
    'En progreso' => sonAzul,
    _ => sonAmbar,
  };
  return (color.withValues(alpha: 0.16), color);
}
