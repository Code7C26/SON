import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:son_tecnico/services/almacen.dart';
import 'package:son_tecnico/services/api.dart';
import 'package:son_tecnico/services/sesion.dart';

class EstadoSync {
  final int pendientes;
  final int fallidos;
  final bool sincronizando;
  final bool sinConexion;
  final bool sinSesion;

  const EstadoSync({
    this.pendientes = 0,
    this.fallidos = 0,
    this.sincronizando = false,
    this.sinConexion = false,
    this.sinSesion = false,
  });
}

enum _Resultado { ok, fallido, sinConexion, sinSesion }

/// Cola de envíos pendientes. Cada acción del técnico (check-in, informe final) se guarda
/// primero en el celular y se manda al servidor apenas haya internet.
class Sincronizador {
  static const String _cola = 'cola';
  static const String _colaFallida = 'cola_fallida';

  static final ValueNotifier<EstadoSync> estado = ValueNotifier(const EstadoSync());

  /// Sube cada vez que se envió algo con éxito: las pantallas lo usan para recargar.
  static final ValueNotifier<int> version = ValueNotifier(0);

  static Timer? _timer;
  static bool _corriendo = false;
  static bool _sinConexion = false;
  static bool _sinSesion = false;

  static void iniciar() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => sincronizar());
    sincronizar();
  }

  static void detener() {
    _timer?.cancel();
    _timer = null;
    _sinConexion = false;
    _sinSesion = false;
    estado.value = const EstadoSync();
  }

  static Future<void> encolarEstado(int ordenId, String nuevoEstado) {
    return _encolar('estado', {'ordenId': ordenId, 'estado': nuevoEstado});
  }

  static Future<void> encolarInforme(Map<String, dynamic> informe) {
    return _encolar('informe', informe);
  }

  /// Algo que falta presupuestar en la visita (por ejemplo "falta un extintor"). Lleva un
  /// `idCliente` propio: si se reenvía por falta de señal, el servidor no lo duplica.
  static Future<void> encolarSolicitud(Map<String, dynamic> solicitud) {
    return _encolar('solicitud', solicitud);
  }

  /// Identificadores de las notas para presupuestar que todavía no llegaron al servidor.
  static Future<Set<String>> solicitudesPendientes() async {
    final ids = <String>{};
    for (final (_, item) in await _leerCola()) {
      if (item['tipo'] != 'solicitud') continue;
      final datos = item['datos'];
      if (datos is Map && datos['idCliente'] != null) ids.add('${datos['idCliente']}');
    }
    return ids;
  }

  /// Notas para presupuestar que el servidor rechazó (quedan aparte, no se pierden).
  static Future<Set<String>> solicitudesFallidas() async {
    final ids = <String>{};
    for (final nombre in await Almacen.listar(_colaFallida)) {
      final dato = await Almacen.leer('$_colaFallida/$nombre');
      if (dato is! Map || dato['tecnicoId'] != Sesion.tecnicoId || dato['tipo'] != 'solicitud') continue;
      final datos = dato['datos'];
      if (datos is Map && datos['idCliente'] != null) ids.add('${datos['idCliente']}');
    }
    return ids;
  }

  static Future<void> _encolar(String tipo, Map<String, dynamic> datos) async {
    final nombre = '$_cola/${DateTime.now().microsecondsSinceEpoch}_$tipo.json';
    await Almacen.escribir(nombre, {'tipo': tipo, 'tecnicoId': Sesion.tecnicoId, 'datos': datos});
    await _publicar();
  }

  static Future<List<(String, Map<String, dynamic>)>> _leerCola() async {
    final resultado = <(String, Map<String, dynamic>)>[];
    for (final nombre in await Almacen.listar(_cola)) {
      final ruta = '$_cola/$nombre';
      final dato = await Almacen.leer(ruta);
      if (dato is Map && dato['tecnicoId'] == Sesion.tecnicoId) {
        resultado.add((ruta, Map<String, dynamic>.from(dato)));
      }
    }
    return resultado;
  }

  static Future<void> _publicar({bool sincronizando = false}) async {
    final pendientes = (await _leerCola()).length;
    final fallidos = (await Almacen.listar(_colaFallida)).length;
    estado.value = EstadoSync(
      pendientes: pendientes,
      fallidos: fallidos,
      sincronizando: sincronizando,
      sinConexion: _sinConexion && pendientes > 0,
      sinSesion: _sinSesion,
    );
  }

  /// Marca la sesión como vencida (el servidor respondió 401).
  static void sesionVencida() {
    _sinSesion = true;
    _publicar();
  }

  /// Aplica sobre la lista de órdenes lo que el técnico hizo y todavía no llegó al servidor.
  static Future<List<Map<String, dynamic>>> aplicarPendientes(List<Map<String, dynamic>> ordenes) async {
    for (final (_, item) in await _leerCola()) {
      // Las notas para presupuestar no cambian el estado de ninguna orden.
      if (item['tipo'] != 'estado' && item['tipo'] != 'informe') continue;
      final datos = Map<String, dynamic>.from(item['datos'] as Map);
      final nuevoEstado = item['tipo'] == 'informe' ? 'Completada' : datos['estado'];
      for (final orden in ordenes) {
        if (orden['id'] == datos['ordenId']) orden['estado'] = nuevoEstado;
      }
    }
    return ordenes;
  }

  static Future<void> sincronizar() async {
    if (_corriendo || !Sesion.activa) return;
    _corriendo = true;
    var huboExito = false;
    try {
      await _publicar(sincronizando: true);
      _sinConexion = false;
      for (final (ruta, item) in await _leerCola()) {
        final resultado = await _enviar(item);
        if (resultado == _Resultado.ok) {
          await Almacen.borrar(ruta);
          huboExito = true;
          _sinSesion = false;
        } else if (resultado == _Resultado.fallido) {
          // El servidor lo rechazó (por ejemplo, la orden ya no es del técnico): no se pierde,
          // queda aparte para revisarlo y no bloquea el resto de la cola.
          await Almacen.mover(ruta, ruta.replaceFirst(_cola, _colaFallida));
        } else if (resultado == _Resultado.sinSesion) {
          _sinSesion = true;
          break;
        } else {
          _sinConexion = true;
          break;
        }
      }
    } finally {
      _corriendo = false;
      await _publicar();
    }
    if (huboExito) version.value++;
  }

  static Future<_Resultado> _enviar(Map<String, dynamic> item) async {
    try {
      final datos = Map<String, dynamic>.from(item['datos'] as Map);
      final http.Response respuesta;
      switch (item['tipo']) {
        case 'estado':
          respuesta = await apiPut('/api/ordenes/${datos['ordenId']}/estado', json.encode({'estado': datos['estado']}));
        case 'informe':
          respuesta = await apiPost(
            '/api/generar-informe',
            json.encode({...datos, 'sinPdf': true}),
            espera: const Duration(minutes: 3),
          );
        case 'solicitud':
          respuesta = await apiPost('/api/solicitudes-presupuesto', json.encode(datos), espera: const Duration(minutes: 1));
        default:
          return _Resultado.fallido;
      }
      final codigo = respuesta.statusCode;
      if (codigo >= 200 && codigo < 300) return _Resultado.ok;
      if (codigo == 401) return _Resultado.sinSesion;
      if (codigo >= 400 && codigo < 500) return _Resultado.fallido;
      return _Resultado.sinConexion;
    } catch (_) {
      return _Resultado.sinConexion;
    }
  }
}

class ResultadoOrdenes {
  final List<Map<String, dynamic>> ordenes;
  final bool sinConexion;
  const ResultadoOrdenes(this.ordenes, this.sinConexion);
}

/// Las últimas órdenes guardadas en el celular (sirve para mostrar algo al instante).
/// Devuelve null si todavía no hay nada guardado.
Future<List<Map<String, dynamic>>?> ordenesGuardadas(int tecnicoId) async {
  final guardado = await Almacen.leer('ordenes_$tecnicoId.json');
  if (guardado is! List) return null;
  final lista = guardado.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  return Sincronizador.aplicarPendientes(lista);
}

/// Pide las órdenes al servidor y las guarda. Si no hay internet devuelve las últimas guardadas.
Future<ResultadoOrdenes> cargarOrdenes(int tecnicoId) async {
  final archivo = 'ordenes_$tecnicoId.json';
  List<Map<String, dynamic>>? lista;
  var sinConexion = false;

  try {
    final respuesta = await apiGet('/api/ordenes/tecnico/$tecnicoId');
    if (respuesta.statusCode == 200) {
      final datos = json.decode(respuesta.body) as List;
      lista = datos.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      await Almacen.escribir(archivo, lista);
    } else {
      if (respuesta.statusCode == 401) Sincronizador.sesionVencida();
      sinConexion = true;
    }
  } catch (_) {
    sinConexion = true;
  }

  if (lista == null) {
    final guardado = await Almacen.leer(archivo);
    lista = guardado is List ? guardado.map((item) => Map<String, dynamic>.from(item as Map)).toList() : <Map<String, dynamic>>[];
  }

  return ResultadoOrdenes(await Sincronizador.aplicarPendientes(lista), sinConexion);
}

/// Trabajo que el técnico dejó a medias (para retomarlo si se cierra la app).
class Borrador {
  static String _nombre(int tecnicoId) => 'borrador_$tecnicoId.json';

  static Future<Map<String, dynamic>?> leer(int tecnicoId) async {
    final datos = await Almacen.leer(_nombre(tecnicoId));
    return datos is Map ? Map<String, dynamic>.from(datos) : null;
  }

  static Future<void> guardar(int tecnicoId, Map<String, dynamic> datos) => Almacen.escribir(_nombre(tecnicoId), datos);

  static Future<void> borrar(int tecnicoId) => Almacen.borrar(_nombre(tecnicoId));
}
