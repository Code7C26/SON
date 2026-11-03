import 'package:web/web.dart' as web;

/// Versión para navegador: usa el almacenamiento local del navegador.
class AlmacenFisico {
  static const String _prefijo = 'son_datos/';

  static Future<String?> leer(String nombre) async => web.window.localStorage.getItem('$_prefijo$nombre');

  static Future<void> escribir(String nombre, String texto) async {
    web.window.localStorage.setItem('$_prefijo$nombre', texto);
  }

  static Future<void> borrar(String nombre) async {
    web.window.localStorage.removeItem('$_prefijo$nombre');
  }

  static Future<List<String>> listar(String subcarpeta) async {
    final inicio = '$_prefijo$subcarpeta/';
    final storage = web.window.localStorage;
    final nombres = <String>[];
    for (var i = 0; i < storage.length; i++) {
      final clave = storage.key(i);
      if (clave != null && clave.startsWith(inicio) && clave.endsWith('.json')) {
        nombres.add(clave.substring(inicio.length));
      }
    }
    return nombres;
  }
}
