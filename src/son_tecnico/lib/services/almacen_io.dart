import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Guarda en archivos dentro del dispositivo (Android, iPhone, Windows...).
class AlmacenFisico {
  static Directory? _raiz;

  static Future<Directory> _carpeta() async {
    final existente = _raiz;
    if (existente != null) return existente;
    final documentos = await getApplicationDocumentsDirectory();
    final dir = Directory('${documentos.path}${Platform.pathSeparator}son_datos');
    if (!await dir.exists()) await dir.create(recursive: true);
    _raiz = dir;
    return dir;
  }

  static Future<File> _archivo(String nombre) async {
    final raiz = await _carpeta();
    final archivo = File('${raiz.path}${Platform.pathSeparator}$nombre');
    await archivo.parent.create(recursive: true);
    return archivo;
  }

  static Future<String?> leer(String nombre) async {
    final archivo = await _archivo(nombre);
    if (!await archivo.exists()) return null;
    return archivo.readAsString();
  }

  /// Escribe primero a un archivo temporal y luego lo renombra, así un corte
  /// de batería o un cierre de la app no deja el archivo a medias.
  static Future<void> escribir(String nombre, String texto) async {
    final archivo = await _archivo(nombre);
    final temporal = File('${archivo.path}.tmp');
    await temporal.writeAsString(texto, flush: true);
    await temporal.rename(archivo.path);
  }

  static Future<void> borrar(String nombre) async {
    final archivo = await _archivo(nombre);
    if (await archivo.exists()) await archivo.delete();
  }

  static Future<List<String>> listar(String subcarpeta) async {
    final raiz = await _carpeta();
    final dir = Directory('${raiz.path}${Platform.pathSeparator}$subcarpeta');
    if (!await dir.exists()) return [];
    final nombres = <String>[];
    await for (final entrada in dir.list()) {
      if (entrada is File && entrada.path.endsWith('.json')) {
        nombres.add(entrada.uri.pathSegments.last);
      }
    }
    return nombres;
  }
}
