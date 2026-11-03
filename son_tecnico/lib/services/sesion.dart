import 'package:son_tecnico/config/api_config.dart';
import 'package:son_tecnico/services/almacen.dart';

class Sesion {
  static const String _archivo = 'sesion.json';

  static String? token;
  static int? tecnicoId;
  static String nombre = '';
  static String email = '';

  static bool get activa => token != null && tecnicoId != null;

  static void iniciar({required String nuevoToken, required int id, required String nuevoNombre, required String nuevoEmail}) {
    token = nuevoToken;
    tecnicoId = id;
    nombre = nuevoNombre;
    email = nuevoEmail;
    // Se guarda en el celular para entrar directo aunque no haya internet.
    Almacen.escribir(_archivo, {
      'token': nuevoToken,
      'id': id,
      'nombre': nuevoNombre,
      'email': nuevoEmail,
      'servidor': apiBaseUrl,
    });
  }

  /// Recupera la sesión guardada. Devuelve true si había una.
  static Future<bool> restaurar() async {
    final datos = await Almacen.leer(_archivo);
    if (datos is! Map || datos['token'] == null || datos['id'] == null) return false;
    if (datos['servidor'] != apiBaseUrl) {
      await Almacen.borrar(_archivo);
      return false;
    }
    token = datos['token'] as String;
    tecnicoId = (datos['id'] as num).toInt();
    nombre = (datos['nombre'] ?? 'Técnico') as String;
    email = (datos['email'] ?? '') as String;
    return true;
  }

  static void cerrar() {
    token = null;
    tecnicoId = null;
    nombre = '';
    email = '';
    Almacen.borrar(_archivo);
  }

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
}
