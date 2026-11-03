// Prueba el modo sin conexión contra un servidor real.
//
// Necesita un backend de prueba y un técnico creado. Se lanza con:
//   flutter test test/sincronizacion_test.dart \
//     --dart-define=API_URL=http://127.0.0.1:3001 \
//     --dart-define=TEC_EMAIL=... --dart-define=TEC_PASSWORD=... --dart-define=ORDEN_ID=...
// Si falta algún dato, la prueba se omite.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:son_tecnico/config/api_config.dart';
import 'package:son_tecnico/services/api.dart';
import 'package:son_tecnico/services/sesion.dart';
import 'package:son_tecnico/services/sincronizacion.dart';

const _email = String.fromEnvironment('TEC_EMAIL');
const _password = String.fromEnvironment('TEC_PASSWORD');
const _ordenId = int.fromEnvironment('ORDEN_ID', defaultValue: 0);
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _RutasFalsas extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String ruta;
  _RutasFalsas(this.ruta);

  @override
  Future<String?> getApplicationDocumentsPath() async => ruta;
}

Map<String, dynamic> _informe(String fin) => {
      'ordenId': _ordenId,
      'cliente': 'acerbon srl',
      'direccion': 'Ruta 9 Km 123',
      'latitud': -31.42,
      'longitud': -64.18,
      'comentarios': 'Hecho sin internet',
      'checklist': [
        {'tarea': 'Revisar tablero', 'hecho': true},
      ],
      'evidencias': [_png],
      'firmaTecnico': _png,
      'firmaCliente': _png,
      'inicio': '2026-10-19T14:00:00.000Z',
      'fin': fin,
    };

void main() {
  final configurado = _email.isNotEmpty && _password.isNotEmpty && _ordenId > 0;
  final urlReal = apiBaseUrl;

  test('trabajo sin internet: se guarda en el celular y se envía al volver la conexión', () async {
    final carpeta = Directory.systemTemp.createTempSync('son_test_celular');
    PathProviderPlatform.instance = _RutasFalsas(carpeta.path);

    // 1) Con internet: ingresa y baja sus órdenes (quedan guardadas en el celular).
    final login = await apiPost('/api/tecnicos/login', json.encode({'email': _email, 'password': _password}));
    expect(login.statusCode, 200);
    final datos = json.decode(login.body) as Map<String, dynamic>;
    Sesion.iniciar(nuevoToken: datos['token'], id: (datos['id'] as num).toInt(), nuevoNombre: 'Prueba', nuevoEmail: _email);
    final tecnicoId = Sesion.tecnicoId!;

    final conInternet = await cargarOrdenes(tecnicoId);
    expect(conInternet.sinConexion, isFalse);
    expect(conInternet.ordenes.any((o) => o['id'] == _ordenId), isTrue);

    // 2) Se corta internet: check-in y finalización quedan guardados.
    apiBaseUrl = 'http://127.0.0.1:1';
    await Sincronizador.encolarEstado(_ordenId, 'En progreso');
    await Sincronizador.encolarInforme(_informe('2026-10-19T15:30:00.000Z'));
    await Sincronizador.sincronizar();
    expect(Sincronizador.estado.value.pendientes, 2, reason: 'sin internet no se debe perder nada');
    expect(Sincronizador.estado.value.sinConexion, isTrue);

    // 3) Sin internet la app sigue mostrando las órdenes guardadas, con el estado que dejó el técnico.
    final sinInternet = await cargarOrdenes(tecnicoId);
    expect(sinInternet.sinConexion, isTrue);
    final orden = sinInternet.ordenes.firstWhere((o) => o['id'] == _ordenId);
    expect(orden['estado'], 'Completada');

    // 4) Vuelve internet: todo se envía en orden y la cola queda vacía.
    apiBaseUrl = urlReal;
    final version = Sincronizador.version.value;
    await Sincronizador.sincronizar();
    expect(Sincronizador.estado.value.pendientes, 0);
    expect(Sincronizador.estado.value.fallidos, 0);
    expect(Sincronizador.version.value, greaterThan(version));

    final servidor = await cargarOrdenes(tecnicoId);
    expect(servidor.sinConexion, isFalse);
    expect(servidor.ordenes.firstWhere((o) => o['id'] == _ordenId)['estado'], 'Completada');

    // 5) Si por falta de señal el mismo informe se reenvía, el servidor no lo duplica.
    await Sincronizador.encolarInforme(_informe('2026-10-19T15:30:00.000Z'));
    await Sincronizador.sincronizar();
    expect(Sincronizador.estado.value.pendientes, 0);

    Sincronizador.detener();
    carpeta.deleteSync(recursive: true);
  }, skip: configurado ? false : 'Faltan datos del servidor de prueba (ver el comentario del archivo)');
}
