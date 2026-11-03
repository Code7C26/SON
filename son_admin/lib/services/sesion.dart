import 'dart:convert';

import 'package:son_admin/services/almacen_sesion.dart';

class SesionAdmin {
  static const _claveToken = 'son_admin_token';
  static const _claveAdmin = 'son_admin_datos';
  static const _clavePantalla = 'son_admin_pantalla';

  static String? token;

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Guarda la sesión para que al refrescar la página no haya que volver a ingresar.
  static void guardar(String nuevoToken, Map<String, dynamic> datosAdmin) {
    token = nuevoToken;
    escribirAlmacen(_claveToken, nuevoToken);
    escribirAlmacen(_claveAdmin, json.encode(datosAdmin));
  }

  /// Actualiza solo los datos del perfil (nombre, email) de la sesión guardada.
  static void guardarAdmin(Map<String, dynamic> datosAdmin) {
    escribirAlmacen(_claveAdmin, json.encode(datosAdmin));
  }

  /// Devuelve los datos del admin si había una sesión guardada (y deja el token listo para usar).
  static Map<String, dynamic>? restaurar() {
    try {
      final guardado = leerAlmacen(_claveToken);
      final datos = leerAlmacen(_claveAdmin);
      if (guardado == null || guardado.isEmpty || datos == null) return null;
      final admin = json.decode(datos);
      if (admin is! Map || admin['id'] is! num) return null;
      token = guardado;
      return Map<String, dynamic>.from(admin);
    } catch (_) {
      return null;
    }
  }

  /// Identificador de la última pantalla que se estaba mirando (por ejemplo 'clientes').
  static String? pantallaGuardada() {
    final id = leerAlmacen(_clavePantalla);
    return id == null || id.isEmpty ? null : id;
  }

  static void guardarPantalla(String id) => escribirAlmacen(_clavePantalla, id);

  static void cerrar() {
    token = null;
    borrarAlmacen(_claveToken);
    borrarAlmacen(_claveAdmin);
    borrarAlmacen(_clavePantalla);
  }
}
