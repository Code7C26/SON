import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Abre el selector de archivos del navegador y devuelve el archivo elegido como
/// "data:...;base64,..." junto con su nombre. Devuelve null si se cancela o no se puede leer.
Future<({String nombre, String datos})?> elegirArchivo({required String aceptar}) {
  final listo = Completer<({String nombre, String datos})?>();
  void terminar(({String nombre, String datos})? valor) {
    if (!listo.isCompleted) listo.complete(valor);
  }

  final entrada = web.HTMLInputElement()
    ..type = 'file'
    ..accept = aceptar;
  entrada.addEventListener('cancel', ((web.Event _) => terminar(null)).toJS);
  entrada.addEventListener(
    'change',
    ((web.Event _) {
      final archivo = entrada.files?.item(0);
      if (archivo == null) return terminar(null);
      final lector = web.FileReader();
      lector.addEventListener('load', ((web.Event _) {
        final resultado = lector.result;
        terminar(resultado.isA<JSString>() ? (nombre: archivo.name, datos: (resultado as JSString).toDart) : null);
      }).toJS);
      lector.addEventListener('error', ((web.Event _) => terminar(null)).toJS);
      lector.readAsDataURL(archivo);
    }).toJS,
  );
  entrada.click();
  return listo.future;
}

/// La imagen elegida (PNG o JPG) como "data:image/...;base64,...", o null.
Future<String?> elegirImagen() async {
  final archivo = await elegirArchivo(aceptar: 'image/png,image/jpeg');
  return archivo?.datos;
}
