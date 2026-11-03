import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:son_admin/config/api_config.dart';
import 'package:son_admin/services/sesion.dart';

Future<http.Response> apiGet(String path) => http.get(apiUri(path), headers: SesionAdmin.headers);

Future<http.Response> apiSend(String method, String path, [Object? body]) {
  final url = apiUri(path);
  switch (method) {
    case 'POST':
      return http.post(url, headers: SesionAdmin.headers, body: body);
    case 'PUT':
      return http.put(url, headers: SesionAdmin.headers, body: body);
    case 'DELETE':
      return http.delete(url, headers: SesionAdmin.headers);
    default:
      return http.get(url, headers: SesionAdmin.headers);
  }
}

/// Mensaje de error que mandó el servidor (por ejemplo "Ese correo ya está registrado").
String mensajeError(http.Response respuesta, [String porDefecto = 'Ocurrió un error, probá de nuevo']) {
  try {
    final datos = json.decode(respuesta.body);
    if (datos is Map && datos['error'] != null) return '${datos['error']}';
  } catch (_) {}
  return porDefecto;
}

const String mensajeSinConexion = 'No se pudo conectar con el servidor';
