/// URL del servidor de SON.
///
/// En el celular y en el sitio publicado usa el servidor real. Si abrís la app en esta
/// computadora (localhost), habla con el mismo servidor que el panel, así las órdenes
/// que asignás aparecen en la cuenta del técnico.
/// Se puede forzar otra dirección al compilar:
///   flutter build apk --dart-define=API_URL=https://sonoperation.com
import 'package:flutter/foundation.dart';

const String _definida = String.fromEnvironment('API_URL', defaultValue: '');

String _forzada = _definida;

String get apiBaseUrl {
  if (_forzada.isNotEmpty) return _forzada;
  if (kIsWeb) {
    final host = Uri.base.host;
    if (host == 'localhost' || host == '127.0.0.1') return 'http://$host:3000';
  }
  return 'https://sonoperation.com';
}

set apiBaseUrl(String valor) {
  _forzada = valor;
}

Uri apiUri(String path) => Uri.parse('$apiBaseUrl$path');
