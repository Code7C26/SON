import 'package:http/http.dart' as http;
import 'package:son_tecnico/config/api_config.dart';
import 'package:son_tecnico/services/sesion.dart';

// Sin señal una conexión puede quedar colgada mucho tiempo: con un límite la app
// se da cuenta enseguida de que no hay internet y sigue trabajando con lo guardado.
const Duration _esperaCorta = Duration(seconds: 15);
const Duration _esperaEnvio = Duration(seconds: 30);

Future<http.Response> apiGet(String path, {Duration? espera}) {
  return http.get(apiUri(path), headers: Sesion.headers).timeout(espera ?? _esperaCorta);
}

Future<http.Response> apiPost(String path, Object body, {Duration? espera}) {
  return http.post(apiUri(path), headers: Sesion.headers, body: body).timeout(espera ?? _esperaEnvio);
}

Future<http.Response> apiPut(String path, Object body, {Duration? espera}) {
  return http.put(apiUri(path), headers: Sesion.headers, body: body).timeout(espera ?? _esperaEnvio);
}
