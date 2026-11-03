import 'package:web/web.dart' as web;

// Guarda en el navegador (localStorage) para que al refrescar la página no se pierda la sesión.
// Si el navegador no deja guardar (modo privado, etc.), no se rompe nada: simplemente no se recuerda.
final Map<String, String> _memoria = {};

String? leerAlmacen(String clave) {
  try {
    return web.window.localStorage.getItem(clave) ?? _memoria[clave];
  } catch (_) {
    return _memoria[clave];
  }
}

void escribirAlmacen(String clave, String valor) {
  _memoria[clave] = valor;
  try {
    web.window.localStorage.setItem(clave, valor);
  } catch (_) {}
}

void borrarAlmacen(String clave) {
  _memoria.remove(clave);
  try {
    web.window.localStorage.removeItem(clave);
  } catch (_) {}
}
