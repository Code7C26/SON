import 'package:flutter/foundation.dart' show kIsWeb;

/// Dirección del servidor.
///
/// El panel lo sirve el propio servidor, así que en la web usa la misma dirección desde la que
/// se abrió (http://localhost:3000 en la PC, o https://sonoperation.com desde internet).
/// Si hace falta otra, se indica al compilar: flutter build web --dart-define=API_URL=https://...
const String _urlConfigurada = String.fromEnvironment('API_URL');

String get apiBaseUrl {
  if (_urlConfigurada.isNotEmpty) return _urlConfigurada;
  if (kIsWeb) return Uri.base.origin;
  return 'http://127.0.0.1:3000';
}

Uri apiUri(String path) => Uri.parse('$apiBaseUrl$path');
