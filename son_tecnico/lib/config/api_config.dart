/// URL del servidor de SON.
///
/// En el celular compilado usa el servidor de SIMA. En el navegador usa la dirección
/// desde la que se abrió: sonoperation.com para SIMA, demo.sonoperation.com para la
/// base vacía, o localhost cuando se prueba en esta computadora.
/// Se puede forzar otra dirección al compilar:
///   flutter build apk --dart-define=API_URL=https://sonoperation.com
import 'package:flutter/foundation.dart';

const String _definida = String.fromEnvironment('API_URL', defaultValue: '');

String _forzada = _definida;

String get apiBaseUrl {
  if (_forzada.isNotEmpty) return _forzada;
  if (kIsWeb) return Uri.base.origin;
  return 'https://sonoperation.com';
}

set apiBaseUrl(String valor) {
  _forzada = valor;
}

Uri apiUri(String path) => Uri.parse('$apiBaseUrl$path');
