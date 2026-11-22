import 'dart:convert';

import 'package:son_tecnico/services/almacen_io.dart' if (dart.library.js_interop) 'package:son_tecnico/services/almacen_web.dart';

/// Guarda datos en el dispositivo para poder trabajar sin internet:
/// sesión, órdenes en caché, trabajo en curso y cola de envíos pendientes.
///
/// Si el almacenamiento del dispositivo falla (plugin sin cargar, disco lleno, etc.)
/// los datos se guardan en memoria: la app sigue funcionando y no se pierde nada
/// mientras esté abierta. Guardar nunca lanza errores hacia el resto de la app.
class Almacen {
  static final Map<String, String> _memoria = {};

  /// Devuelve el JSON guardado, o null si no existe o está dañado.
  static Future<dynamic> leer(String nombre) async {
    String? texto;
    try {
      texto = await AlmacenFisico.leer(nombre);
    } catch (_) {}
    texto ??= _memoria[nombre];
    if (texto == null) return null;
    try {
      return json.decode(texto);
    } catch (_) {
      return null;
    }
  }

  static Future<void> escribir(String nombre, Object datos) async {
    final texto = json.encode(datos);
    try {
      await AlmacenFisico.escribir(nombre, texto);
      _memoria.remove(nombre);
    } catch (_) {
      _memoria[nombre] = texto;
    }
  }

  static Future<void> borrar(String nombre) async {
    _memoria.remove(nombre);
    try {
      await AlmacenFisico.borrar(nombre);
    } catch (_) {}
  }

  static Future<void> mover(String desde, String hacia) async {
    final datos = await leer(desde);
    if (datos == null) return;
    await escribir(hacia, datos as Object);
    await borrar(desde);
  }

  /// Nombres de los archivos `.json` de una subcarpeta, en orden alfabético.
  static Future<List<String>> listar(String subcarpeta) async {
    final nombres = <String>{};
    try {
      nombres.addAll(await AlmacenFisico.listar(subcarpeta));
    } catch (_) {}
    final inicio = '$subcarpeta/';
    for (final clave in _memoria.keys) {
      if (clave.startsWith(inicio) && clave.endsWith('.json')) nombres.add(clave.substring(inicio.length));
    }
    return nombres.toList()..sort();
  }
}
