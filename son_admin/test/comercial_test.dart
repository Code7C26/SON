// Pruebas del área comercial del panel: menú según el tipo de usuario, notas de técnicos
// (adentro de Presupuestos), tablero de seguimiento, fichas de clientes y usuarios.
// Se usa un servidor simulado, no hace falta el backend real.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:son_admin/main.dart';
import 'package:son_admin/pantallas/clientes.dart';
import 'package:son_admin/pantallas/dashboard.dart';
import 'package:son_admin/pantallas/piezas.dart';
import 'package:son_admin/pantallas/por_presupuestar.dart';
import 'package:son_admin/pantallas/precios.dart';
import 'package:son_admin/pantallas/presupuestos.dart';
import 'package:son_admin/services/sesion.dart';
import 'package:son_admin/theme/tema.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

/// Una imagen PNG de 1x1 píxel, para los mosaicos del mapa del Panel de Control (así no dan error en las pruebas).
final _imagenVacia = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

Map<String, dynamic> _presupuesto({
  int id = 1,
  int numero = 3612,
  String cliente = 'Acerbon SRL',
  String estado = 'Enviado',
  String prioridad = 'media',
  String? responsable,
  String? fechaLimite,
  bool facturado = false,
  num totalMensual = 365113,
  num totalUnico = 0,
  String nivelMargen = 'ok',
  String fecha = '2026-10-20',
}) => {
      'id': id,
      'numero': numero,
      'version': 1,
      'etiqueta': '$numero',
      'cliente': cliente,
      'fecha': fecha,
      'estado': estado,
      'prioridad': prioridad,
      'responsable': responsable,
      'fechaLimite': fechaLimite,
      'facturado': facturado,
      'totalMensual': totalMensual,
      'totalUnico': totalUnico,
      'nivelMargen': nivelMargen,
    };

Map<String, dynamic> _detalleDe(Map<String, dynamic> p) => {
      ...p,
      'esUltimaVersion': true,
      'bonificacion': 0,
      'cliente': {'razonSocial': p['cliente']},
      'items': [
        {'descripcion': 'Higiene y seguridad'}
      ],
      'calculo': {
        'totalMensual': p['totalMensual'] ?? 0,
        'totalUnico': p['totalUnico'] ?? 0,
        'nivelMargen': p['nivelMargen'] ?? 'sin_dato',
        'avisos': const [],
      },
    };

Map<String, dynamic> _nota(int id, String empresa, String descripcion, String estado, {int cantidad = 1, bool foto = false, String tecnico = 'Juan Pérez', String? comentario}) => {
      'id': id,
      'empresa_id': empresa.hashCode,
      'empresa': empresa,
      'descripcion': descripcion,
      'cantidad': cantidad,
      'estado': estado,
      'nota_comercial': comentario,
      'tecnico': tecnico,
      'tiene_foto': foto,
      'creada_en': DateTime.now().toUtc().subtract(Duration(minutes: id)).toIso8601String(),
    };

/// Servidor de mentira: guarda los pedidos que recibe y responde como el real.
class _Servidor {
  final List<http.Request> pedidos = [];
  final List<Map<String, dynamic>> solicitudes;
  final List<Map<String, dynamic>> clientes;
  final List<Map<String, dynamic>>? carpetas;
  final List<Map<String, dynamic>> usuarios;
  final List<Map<String, dynamic>> tecnicos;
  final List<Map<String, dynamic>> presupuestos;
  Map<String, dynamic>? yo;
  int codigoYo = 200;

  _Servidor({
    this.solicitudes = const [],
    this.clientes = const [],
    this.carpetas,
    this.usuarios = const [],
    this.tecnicos = const [],
    List<Map<String, dynamic>> presupuestos = const [],
    this.yo,
  }) : presupuestos = List<Map<String, dynamic>>.from(presupuestos);

  http.Response _ok(Object datos) => http.Response(json.encode(datos), 200, headers: _json);
  http.Response _error(int codigo, String mensaje) => http.Response(json.encode({'error': mensaje}), codigo, headers: _json);

  Iterable<http.Request> pedidosA(String metodo, String ruta) => pedidos.where((p) => p.method == metodo && p.url.path == ruta);

  Future<http.Response> responder(http.Request pedido) async {
    pedidos.add(pedido);
    final ruta = pedido.url.path;
    final metodo = pedido.method;
    if (ruta.endsWith('.png')) return http.Response.bytes(_imagenVacia, 200, headers: {'content-type': 'image/png'});
    final cuerpo = pedido.body.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(json.decode(pedido.body) as Map);

    if (ruta == '/api/admin/yo') {
      return codigoYo == 200 ? _ok(yo!) : _error(codigoYo, 'Sesión vencida');
    }
    if (ruta == '/api/solicitudes-presupuesto/resumen') {
      int contar(String estado) => solicitudes.where((s) => s['estado'] == estado).length;
      return _ok({'nuevas': contar('Nueva'), 'en_presupuesto': contar('En presupuesto'), 'presupuestadas': contar('Presupuestada'), 'descartadas': contar('Descartada')});
    }
    if (ruta == '/api/solicitudes-presupuesto' && metodo == 'GET') return _ok(solicitudes);
    final solicitud = RegExp(r'^/api/solicitudes-presupuesto/(\d+)$').firstMatch(ruta);
    if (solicitud != null && metodo == 'PUT') {
      final nota = solicitudes.firstWhere((s) => s['id'] == int.parse(solicitud.group(1)!));
      for (final campo in ['estado', 'descripcion', 'cantidad']) {
        if (cuerpo.containsKey(campo)) nota[campo] = cuerpo[campo];
      }
      if (cuerpo.containsKey('nota')) nota['nota_comercial'] = cuerpo['nota'];
      return _ok(nota);
    }
    // Área técnica: la ven los dos tipos de usuario (acá no hay órdenes cargadas).
    if (ruta == '/api/ordenes' && metodo == 'GET') return _ok(const []);
    if (ruta == '/api/tecnicos' && metodo == 'GET') return _ok(tecnicos);
    // Solo los nombres de los clientes (para sugerirlos al crear una orden): lo pueden pedir los dos tipos de usuario.
    if (ruta == '/api/clientes/nombres') return _ok([for (final c in clientes) {'id': c['id'], 'razon_social': c['razon_social']}]);
    if (ruta == '/api/clientes' && metodo == 'GET') return _ok(clientes);
    if (ruta == '/api/informes/carpetas' && metodo == 'GET') {
      return _ok(carpetas ?? [for (final c in clientes) {'empresa': c['razon_social'], 'carpeta': c['razon_social'], 'cantidad': 0}]);
    }
    if (ruta == '/api/clientes' && metodo == 'POST') {
      if (cuerpo['razon_social'] == 'Repetida SA') return _error(409, 'Ya existe un cliente con ese nombre');
      final nuevo = {'id': 100 + clientes.length, ...cuerpo, 'ordenes': 0, 'por_presupuestar': 0};
      clientes.add(nuevo);
      return _ok(nuevo);
    }
    final ficha = RegExp(r'^/api/clientes/(\d+)$').firstMatch(ruta);
    if (ficha != null && metodo == 'PUT') {
      final cliente = clientes.firstWhere((c) => c['id'] == int.parse(ficha.group(1)!));
      cliente.addAll(cuerpo);
      return _ok(cliente);
    }
    if (ruta == '/api/presupuestos' && metodo == 'GET') return _ok(presupuestos);
    final presupuestoId = RegExp(r'^/api/presupuestos/(\d+)$').firstMatch(ruta);
    if (presupuestoId != null && metodo == 'GET') {
      final p = presupuestos.firstWhere((x) => x['id'] == int.parse(presupuestoId.group(1)!));
      return _ok(_detalleDe(p));
    }
    final estadoPresupuesto = RegExp(r'^/api/presupuestos/(\d+)/estado$').firstMatch(ruta);
    if (estadoPresupuesto != null && metodo == 'PUT') {
      final p = presupuestos.firstWhere((x) => x['id'] == int.parse(estadoPresupuesto.group(1)!));
      p['estado'] = cuerpo['estado'];
      return _ok(_detalleDe(p));
    }
    final seguimiento = RegExp(r'^/api/presupuestos/(\d+)/seguimiento$').firstMatch(ruta);
    if (seguimiento != null && metodo == 'PUT') {
      final p = presupuestos.firstWhere((x) => x['id'] == int.parse(seguimiento.group(1)!));
      for (final campo in ['prioridad', 'responsable', 'fechaLimite', 'facturado', 'notaSeguimiento']) {
        if (cuerpo.containsKey(campo)) p[campo] = cuerpo[campo];
      }
      return _ok(_detalleDe(p));
    }
    if (ruta == '/api/presupuestos/calcular' && metodo == 'POST') {
      return _ok({'mesReferencia': '2026-10', 'items': cuerpo['items'] ?? [], 'calculo': {'totalMensual': 0, 'totalUnico': 0, 'ivaMensual': 0, 'ivaUnico': 0, 'descuentoTotal': 0, 'nivelMargen': 'sin_dato', 'avisos': [], 'lineas': []}});
    }
    if (ruta == '/api/tarifas') return _ok({'tarifas': const [], 'familias': const []});
    if (ruta == '/api/costos') return _ok({'costos': const []});
    if (ruta == '/api/ipc') return _ok({'meses': const [], 'busqueda': {'ok': true}});
    if (ruta == '/api/comercial/config') {
      return _ok({
        'margenMinimo': 20, 'margenIdeal': 35, 'iva': 21, 'proximoNumero': 3612, 'valorModulo': 44000,
        'empresa': const <String, dynamic>{}, 'firma': const <String, dynamic>{}, 'textos': const <String, dynamic>{},
      });
    }
    if (ruta == '/api/admin/admins' && metodo == 'GET') return _ok(usuarios);
    if (ruta == '/api/admin/admins' && metodo == 'POST') {
      final nuevo = {'id': 50 + usuarios.length, 'nombre': cuerpo['nombre'], 'email': cuerpo['email'], 'rol': cuerpo['rol']};
      usuarios.add(nuevo);
      return _ok(nuevo);
    }
    final rol = RegExp(r'^/api/admin/admins/(\d+)/rol$').firstMatch(ruta);
    if (rol != null && metodo == 'PUT') {
      final usuario = usuarios.firstWhere((u) => u['id'] == int.parse(rol.group(1)!));
      usuario['rol'] = cuerpo['rol'];
      return _ok(usuario);
    }
    return _error(404, 'Ruta no simulada: $metodo $ruta');
  }

  Future<void> correr(Future<void> Function() prueba) => http.runWithClient(prueba, () => MockClient(responder));
}

void _pantallaGrande(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _app(Widget hijo) => MaterialApp(theme: temaSon(), home: hijo);

Future<void> _cerrar(WidgetTester tester) async {
  // Se desarma la pantalla para que se cancelen sus relojes internos.
  await tester.pumpWidget(const SizedBox());
}

void main() {
  setUp(SesionAdmin.cerrar);

  group('menú según el tipo de usuario', () {
    // Comercial = la dueña de la empresa (ve todo). Administración = empleados (solo el área técnica).
    const duena = {'id': 5, 'nombre': 'Laura', 'email': 'laura@son.test', 'rol': 'comercial'};
    const empleado = {'id': 6, 'nombre': 'Marcos', 'email': 'marcos@son.test', 'rol': 'admin'};

    // Todo lo que solo puede pedir Comercial: si Administración lo pidiera, el servidor le diría que no.
    bool esDelAreaComercial(http.Request p) =>
        p.url.path.startsWith('/api/solicitudes-presupuesto') ||
        p.url.path == '/api/clientes' ||
        p.url.path.startsWith('/api/admin/admins') ||
        p.url.path.startsWith('/api/presupuestos') ||
        p.url.path.startsWith('/api/tarifas') ||
        p.url.path.startsWith('/api/costos') ||
        p.url.path.startsWith('/api/ipc') ||
        p.url.path == '/api/comercial/config';

    testWidgets('Comercial ve todo el menú y las notas por presupuestar adentro de Presupuestos', (tester) async {
      _pantallaGrande(tester);
      SesionAdmin.guardarPantalla('por_presupuestar');
      final servidor = _Servidor(solicitudes: [
        _nota(1, 'Acerbon SRL', 'Falta un extintor', 'Nueva', cantidad: 2),
        _nota(2, 'Acerbon SRL', 'Luz de emergencia', 'Nueva'),
        _nota(3, 'Metalúrgica Sur', 'Cartel de salida', 'Presupuestada'),
      ]);
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const LayoutAdministrador(adminData: duena)));
        await tester.pumpAndSettle();

        // Los grupos también pueden aparecer como etiqueta del encabezado de la pantalla abierta.
        for (final grupo in ['OPERACIÓN', 'COMERCIAL', 'SISTEMA']) {
          expect(find.text(grupo), findsWidgets, reason: 'falta el grupo $grupo en el menú de Comercial');
        }
        for (final visible in ['Inicio', 'Órdenes', 'Técnicos', 'Informes', 'Análisis', 'Precios', 'Clientes', 'Usuarios']) {
          expect(find.text(visible), findsOneWidget, reason: 'falta $visible en el menú de Comercial');
        }
        expect(find.text('Presupuestos'), findsOneWidget, reason: 'el ítem del menú (el título de la pantalla ahora es "Embudo de presupuestos")');
        expect(find.text('Por presupuestar'), findsNothing, reason: 'ya no es un ítem aparte: vive adentro de Presupuestos');
        expect(find.byType(PantallaPresupuestos), findsOneWidget, reason: 'la pantalla guardada vieja abre Presupuestos');
        expect(find.text('Tablero'), findsOneWidget);
        expect(find.text('Notas de técnicos'), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('insignia_menu')), matching: find.text('2')), findsOneWidget, reason: 'el aviso de notas nuevas quedó en Presupuestos');

        await tester.tap(find.byKey(const Key('tab_notas')));
        await tester.pumpAndSettle();
        expect(find.text('Acerbon SRL'), findsOneWidget, reason: 'las notas de una empresa van juntas');
        expect(find.text('Falta un extintor'), findsOneWidget);
        expect(find.text('Cartel de salida'), findsNothing, reason: 'ya presupuestada: no está en "Abiertas"');

        // El número del menú se actualiza solo cada minuto.
        servidor.solicitudes.add(_nota(4, 'Metalúrgica Sur', 'Matafuego vencido', 'Nueva'));
        await tester.pump(const Duration(seconds: 61));
        await tester.pumpAndSettle();
        expect(find.descendant(of: find.byKey(const Key('insignia_menu')), matching: find.text('3')), findsOneWidget, reason: 'llegó otra nota nueva');
        await _cerrar(tester);
      });
    });

    testWidgets('Administración solo ve el área técnica y no pide nada del área comercial', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(solicitudes: [_nota(1, 'Acerbon SRL', 'Falta un extintor', 'Nueva')]);
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const LayoutAdministrador(adminData: empleado)));
        await tester.pumpAndSettle();
        expect(find.byType(PantallaDashboard), findsOneWidget, reason: 'sin pantalla guardada arranca en Inicio');

        for (final visible in ['OPERACIÓN', 'Inicio', 'Órdenes', 'Técnicos', 'Informes', 'Análisis']) {
          expect(find.text(visible), findsWidgets, reason: 'falta $visible en el menú de Administración');
        }
        for (final oculto in ['COMERCIAL', 'SISTEMA', 'Por presupuestar', 'Presupuestos', 'Precios', 'Clientes', 'Usuarios']) {
          expect(find.text(oculto), findsNothing, reason: '$oculto es solo para Comercial');
        }
        expect(find.byKey(const Key('insignia_menu')), findsNothing, reason: 'Administración no ve las notas por presupuestar');

        // Ni al abrir ni con el paso del tiempo se piden datos del área comercial (darían "sin permiso").
        await tester.pump(const Duration(seconds: 61));
        await tester.pumpAndSettle();
        expect(servidor.pedidos.where(esDelAreaComercial), isEmpty);
        await _cerrar(tester);
      });
    });

    testWidgets('si la pantalla guardada no es para su tipo de usuario, entra en la primera permitida', (tester) async {
      _pantallaGrande(tester);
      SesionAdmin.guardarPantalla('por_presupuestar'); // la dejó guardada cuando era Comercial
      final servidor = _Servidor();
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const LayoutAdministrador(adminData: empleado)));
        await tester.pumpAndSettle();
        expect(find.byType(PantallaDashboard), findsOneWidget, reason: 'el Panel de Control es la primera pantalla de Administración');
        expect(find.byType(PantallaPorPresupuestar), findsNothing);
        expect(servidor.pedidos.where(esDelAreaComercial), isEmpty);
        await _cerrar(tester);
      });
    });

    testWidgets('una cuenta anterior a los tipos de usuario (sin "rol") queda con el menor acceso: Administración', (tester) async {
      _pantallaGrande(tester);
      SesionAdmin.guardarPantalla('clientes');
      final servidor = _Servidor();
      await servidor.correr(() async {
        // Sin "rol" en los datos: así eran las cuentas guardadas antes de los tipos de usuario.
        await tester.pumpWidget(_app(const LayoutAdministrador(adminData: {'id': 1, 'nombre': 'Admin', 'email': 'admin@son.test'})));
        await tester.pumpAndSettle();
        expect(find.text('Inicio'), findsWidgets);
        for (final oculto in ['COMERCIAL', 'SISTEMA', 'Por presupuestar', 'Presupuestos', 'Precios', 'Clientes', 'Usuarios']) {
          expect(find.text(oculto), findsNothing, reason: '$oculto es solo para Comercial');
        }
        expect(find.byType(PantallaClientes), findsNothing);
        expect(servidor.pedidos.where(esDelAreaComercial), isEmpty);
        await _cerrar(tester);
      });
    });

    testWidgets('al refrescar la página se confirma el tipo de usuario con el servidor: si lo subieron a Comercial, gana el área comercial', (tester) async {
      _pantallaGrande(tester);
      // La sesión guardada decía "admin", pero en el servidor ya lo pasaron a Comercial.
      SesionAdmin.guardar('token-de-prueba', {'id': 5, 'nombre': 'Laura', 'email': 'laura@son.test', 'rol': 'admin'});
      SesionAdmin.guardarPantalla('clientes');
      final servidor = _Servidor(yo: {'id': 5, 'nombre': 'Laura', 'email': 'laura@son.test', 'rol': 'comercial'});
      await servidor.correr(() async {
        await tester.pumpWidget(const SonAdmin());
        await tester.pumpAndSettle();
        expect(find.byType(LayoutAdministrador), findsOneWidget);
        expect(find.text('Usuarios'), findsOneWidget, reason: 'ahora el menú es completo');
        expect(find.byType(PantallaClientes), findsOneWidget);
        expect(SesionAdmin.restaurar()?['rol'], 'comercial', reason: 'queda guardado el tipo actual');
        await _cerrar(tester);
      });
    });

    testWidgets('al refrescar la página se confirma el tipo de usuario con el servidor: si lo bajaron a Administración, pierde el área comercial', (tester) async {
      _pantallaGrande(tester);
      // La sesión guardada decía "comercial" (y dejó abierta una pantalla comercial), pero en el servidor ya lo bajaron a Administración.
      SesionAdmin.guardar('token-de-prueba', {'id': 6, 'nombre': 'Marcos', 'email': 'marcos@son.test', 'rol': 'comercial'});
      SesionAdmin.guardarPantalla('clientes');
      final servidor = _Servidor(yo: {'id': 6, 'nombre': 'Marcos', 'email': 'marcos@son.test', 'rol': 'admin'});
      await servidor.correr(() async {
        await tester.pumpWidget(const SonAdmin());
        await tester.pumpAndSettle();
        expect(find.byType(LayoutAdministrador), findsOneWidget);
        for (final oculto in ['COMERCIAL', 'SISTEMA', 'Por presupuestar', 'Presupuestos', 'Precios', 'Clientes', 'Usuarios']) {
          expect(find.text(oculto), findsNothing, reason: '$oculto es solo para Comercial');
        }
        expect(find.byType(PantallaClientes), findsNothing);
        expect(find.byType(PantallaDashboard), findsOneWidget);
        expect(SesionAdmin.restaurar()?['rol'], 'admin', reason: 'queda guardado el tipo actual');
        expect(servidor.pedidos.where(esDelAreaComercial), isEmpty);
        await _cerrar(tester);
      });
    });

    testWidgets('si el servidor ya no reconoce la sesión, vuelve al login', (tester) async {
      SesionAdmin.guardar('token-vencido', {'id': 5, 'nombre': 'Laura', 'email': 'laura@son.test', 'rol': 'comercial'});
      final servidor = _Servidor()..codigoYo = 401;
      await servidor.correr(() async {
        await tester.pumpWidget(const SonAdmin());
        await tester.pumpAndSettle();
        expect(find.byType(PantallaLogin), findsOneWidget);
        expect(SesionAdmin.restaurar(), isNull);
      });
    });
  });

  group('bandeja "Por presupuestar"', () {
    List<Map<String, dynamic>> notas() => [
          _nota(1, 'Acerbon SRL', 'Falta un extintor', 'Nueva', cantidad: 2, foto: true),
          _nota(2, 'Acerbon SRL', 'Luz de emergencia', 'En presupuesto', comentario: 'Pedimos precio al proveedor'),
          _nota(3, 'Metalúrgica Sur', 'Cartel de salida', 'Presupuestada'),
          _nota(4, 'Metalúrgica Sur', 'Matafuego vencido', 'Descartada'),
        ];

    testWidgets('filtra por estado, busca y mantiene los contadores', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(solicitudes: notas());
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaPorPresupuestar())));
        await tester.pumpAndSettle();

        expect(find.text('Abiertas · 2'), findsOneWidget);
        expect(find.text('Nuevas · 1'), findsOneWidget);
        expect(find.text('En presupuesto · 1'), findsOneWidget);
        expect(find.text('Presupuestadas · 1'), findsOneWidget);
        expect(find.text('Descartadas · 1'), findsOneWidget);
        expect(find.text('Todas · 4'), findsOneWidget);

        expect(find.text('Falta un extintor'), findsOneWidget);
        expect(find.text('×2'), findsOneWidget);
        expect(find.text('Pedimos precio al proveedor'), findsOneWidget);
        expect(find.text('Ver foto'), findsOneWidget, reason: 'solo la primera nota tiene foto');
        expect(find.text('Cartel de salida'), findsNothing);

        await tester.tap(find.text('Presupuestadas · 1'));
        await tester.pump();
        expect(find.text('Cartel de salida'), findsOneWidget);
        expect(find.text('Falta un extintor'), findsNothing);

        await tester.tap(find.text('Todas · 4'));
        await tester.pump();
        expect(find.text('Matafuego vencido'), findsOneWidget);
        expect(find.text('Metalúrgica Sur'), findsOneWidget);

        await tester.enterText(find.byKey(const Key('buscar_solicitud')), 'LUZ emergencia');
        await tester.pump();
        expect(find.text('Luz de emergencia'), findsOneWidget);
        expect(find.text('Falta un extintor'), findsNothing);

        await tester.enterText(find.byKey(const Key('buscar_solicitud')), 'nadie');
        await tester.pump();
        expect(find.text('No hay notas con este filtro.'), findsOneWidget);
        await _cerrar(tester);
      });
    });

    testWidgets('"Tomar" pasa la nota a "En presupuesto" y avisa al menú', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(solicitudes: notas());
      var avisos = 0;
      await servidor.correr(() async {
        await tester.pumpWidget(_app(Scaffold(body: PantallaPorPresupuestar(onCambio: () => avisos++))));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('tomar_1')));
        await tester.pumpAndSettle();

        final pedido = servidor.pedidosA('PUT', '/api/solicitudes-presupuesto/1').single;
        expect(json.decode(pedido.body), {'estado': 'En presupuesto'});
        expect(avisos, 1);
        expect(find.text('Nuevas · 0'), findsOneWidget);
        expect(find.text('En presupuesto · 2'), findsOneWidget);
        expect(find.byKey(const Key('tomar_1')), findsNothing, reason: 'ahora el paso siguiente es "Presupuestada"');
        expect(find.byKey(const Key('presupuestada_1')), findsOneWidget);

        await tester.tap(find.byKey(const Key('presupuestada_1')));
        await tester.pumpAndSettle();
        expect(avisos, 2);
        expect(find.text('Presupuestadas · 2'), findsOneWidget);
        expect(find.text('Abiertas · 1'), findsOneWidget);
        expect(find.text('Falta un extintor'), findsNothing, reason: 'sale de "Abiertas"');
        await _cerrar(tester);
      });
    });

    testWidgets('se puede editar la nota y dejar un comentario de comercial', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(solicitudes: notas());
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaPorPresupuestar())));
        await tester.pumpAndSettle();

        // Menú de la primera fila (la nota 1) → "Editar o agregar una nota".
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Editar o agregar una nota'));
        await tester.pumpAndSettle();

        final campos = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
        await tester.enterText(campos.at(0), 'Extintor ABC de 10 kg');
        await tester.enterText(campos.at(1), '3');
        await tester.enterText(campos.at(2), 'Presupuesto enviado el 27/10');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();

        final pedido = servidor.pedidosA('PUT', '/api/solicitudes-presupuesto/1').single;
        expect(json.decode(pedido.body), {'descripcion': 'Extintor ABC de 10 kg', 'cantidad': 3, 'nota': 'Presupuesto enviado el 27/10'});
        expect(find.text('Extintor ABC de 10 kg'), findsOneWidget);
        expect(find.text('×3'), findsOneWidget);
        expect(find.text('Presupuesto enviado el 27/10'), findsOneWidget);
        await _cerrar(tester);
      });
    });

    testWidgets('con el servidor caído muestra el aviso y deja reintentar', (tester) async {
      _pantallaGrande(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaPorPresupuestar())));
        await tester.pumpAndSettle();
        expect(find.text('No se pudo conectar con el servidor'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        await _cerrar(tester);
      }, () => MockClient((_) async => throw http.ClientException('sin conexión')));
    });
  });

  group('clientes', () {
    List<Map<String, dynamic>> fichas() => [
          {
            'id': 7, 'razon_social': 'Acerbon SRL', 'direccion_principal': null, 'contacto': 'Laura Gómez', 'telefono': '351 555-0000', 'email': 'laura@acerbon.com',
            'cuit': '30-71234567-1', 'notas': null, 'actividad': 'Minería', 'riesgo': 'R3', 'categoria': 'B', 'provincia': 'Córdoba', 'departamento': 'Punilla', 'ciudad': 'Cosquín',
            'ordenes': 4, 'por_presupuestar': 2,
          },
          {
            'id': 8, 'razon_social': 'Metalúrgica Sur', 'direccion_principal': 'Ruta 9 km 12', 'contacto': null, 'telefono': null, 'email': null,
            'cuit': null, 'notas': null, 'actividad': null, 'riesgo': null, 'categoria': null, 'provincia': null, 'departamento': null, 'ciudad': null,
            'ordenes': 1, 'por_presupuestar': 0,
          },
        ];

    testWidgets('muestra las fichas con sus datos y busca sin importar acentos', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(clientes: fichas());
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaClientes())));
        await tester.pumpAndSettle();

        expect(find.text('2 clientes'), findsOneWidget);
        expect(find.text('Acerbon SRL'), findsOneWidget);
        expect(find.text('Laura Gómez'), findsOneWidget);
        expect(find.text('Cosquín, Punilla, Córdoba'), findsOneWidget);
        expect(find.text('Minería'), findsOneWidget);
        expect(find.text('Riesgo R3'), findsOneWidget);
        expect(find.text('Categoría B'), findsOneWidget);
        expect(find.text('2 por presupuestar'), findsOneWidget);
        expect(find.text('4 órdenes de trabajo'), findsOneWidget);
        expect(find.text('1 orden de trabajo'), findsOneWidget);
        expect(find.text('Sin datos de contacto todavía. Tocá la ficha para completarlos.'), findsOneWidget);

        await tester.enterText(find.byKey(const Key('buscar_cliente')), 'metalurgica');
        await tester.pump();
        expect(find.text('Metalúrgica Sur'), findsOneWidget);
        expect(find.text('Acerbon SRL'), findsNothing);

        await tester.enterText(find.byKey(const Key('buscar_cliente')), 'cosquin');
        await tester.pump();
        expect(find.text('Acerbon SRL'), findsOneWidget, reason: 'también busca por ciudad');
        await _cerrar(tester);
      });
    });

    testWidgets('muestra las carpetas del disco y no los clientes que solo están en la base', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(
        clientes: fichas(),
        carpetas: [
          {'empresa': 'YPF AGRO', 'carpeta': 'YPF AGRO', 'cantidad': 3},
          {'empresa': 'Acerbon SRL', 'carpeta': 'ACERBON SRL', 'cantidad': 1},
        ],
      );
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaClientes())));
        await tester.pumpAndSettle();

        expect(find.text('2 clientes'), findsOneWidget);
        expect(find.text('YPF AGRO'), findsOneWidget);
        expect(find.text('Acerbon SRL'), findsOneWidget);
        expect(find.text('Metalúrgica Sur'), findsNothing, reason: 'no tiene carpeta en el disco');
        expect(find.text('Sin datos de contacto todavía. Tocá la ficha para completarlos.'), findsOneWidget);
        await _cerrar(tester);
      });
    });

    testWidgets('crea un cliente con riesgo, categoría y ubicación', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(clientes: fichas());
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaClientes())));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('nuevo_cliente')));
        await tester.pumpAndSettle();
        expect(find.text('Nuevo cliente'), findsNWidgets(2), reason: 'botón y título de la ventana');

        await tester.enterText(find.byKey(const Key('campo_nombre')), 'Estación Norte SA');
        await tester.enterText(find.byKey(const Key('campo_cuit')), '30-71234567-1');
        await tester.tap(find.byKey(const Key('campo_riesgo')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('R4').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('campo_categoria')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('C').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('campo_provincia')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Córdoba').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('guardar_cliente')));
        await tester.pumpAndSettle();

        final enviado = json.decode(servidor.pedidosA('POST', '/api/clientes').single.body) as Map;
        expect(enviado['razon_social'], 'Estación Norte SA');
        expect(enviado['cuit'], '30-71234567-1');
        expect(enviado['riesgo'], 'R4');
        expect(enviado['categoria'], 'C');
        expect(enviado['provincia'], 'Córdoba');
        expect(find.byType(DialogoCliente), findsNothing, reason: 'la ventana se cierra al guardar');
        expect(find.text('Cliente creado'), findsOneWidget);
        expect(find.text('Estación Norte SA'), findsOneWidget, reason: 'la lista se recarga con el nuevo cliente');
        await _cerrar(tester);
      });
    });

    testWidgets('si el servidor rechaza los datos, muestra el motivo y no cierra la ventana', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(clientes: fichas());
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaClientes())));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('nuevo_cliente')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('campo_nombre')), 'Repetida SA');
        await tester.tap(find.byKey(const Key('guardar_cliente')));
        await tester.pumpAndSettle();

        expect(find.text('Ya existe un cliente con ese nombre'), findsOneWidget);
        expect(find.byType(DialogoCliente), findsOneWidget);
        await _cerrar(tester);
      });
    });

    testWidgets('al abrir una ficha existente aparecen sus datos y se guardan los cambios con PUT', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(clientes: fichas());
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaClientes())));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('cliente_7')));
        await tester.pumpAndSettle();
        expect(find.text('Ficha del cliente'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Acerbon SRL'), findsOneWidget);
        expect(find.text('R3'), findsOneWidget, reason: 'el riesgo guardado aparece elegido');
        expect(find.text('Córdoba'), findsOneWidget);

        await tester.enterText(find.byKey(const Key('campo_email')), 'nuevo@acerbon.com');
        await tester.tap(find.byKey(const Key('guardar_cliente')));
        await tester.pumpAndSettle();

        final pedido = servidor.pedidosA('PUT', '/api/clientes/7').single;
        final enviado = json.decode(pedido.body) as Map;
        expect(enviado['email'], 'nuevo@acerbon.com');
        expect(enviado['riesgo'], 'R3');
        expect(enviado['categoria'], 'B');
        expect(enviado['razon_social'], 'Acerbon SRL');
        expect(find.text('Cliente actualizado'), findsOneWidget);
        await _cerrar(tester);
      });
    });
  });

  group('usuarios', () {
    // La dueña (Comercial) es quien maneja esta pantalla; los empleados son de Administración.
    List<Map<String, dynamic>> lista() => [
          {'id': 1, 'nombre': 'Laura Dueña', 'email': 'laura@son.test', 'rol': 'comercial'},
          {'id': 2, 'nombre': 'Marcos Empleado', 'email': 'marcos@son.test', 'rol': 'admin'},
          {'id': 3, 'nombre': 'Otro Empleado', 'email': 'otro@son.test', 'rol': 'admin'},
        ];

    testWidgets('muestra el tipo de cada usuario y permite cambiarlo (menos el propio)', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(usuarios: lista());
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaAdministradores(adminActualId: 1))));
        await tester.pumpAndSettle();

        expect(find.text('Usuarios del panel'), findsOneWidget);
        expect(find.text('Comercial'), findsOneWidget);
        expect(find.text('Administración'), findsNWidgets(2));
        expect(find.text('Laura Dueña  (vos)'), findsOneWidget);
        expect(find.byKey(const Key('cambiar_rol_1')), findsNothing, reason: 'nadie cambia su propio tipo');

        // Marcos pasa de Administración a Comercial (acceso total).
        await tester.tap(find.byKey(const Key('cambiar_rol_2')));
        await tester.pumpAndSettle();
        expect(find.text('Pasar a Administración (solo el área técnica)'), findsNothing, reason: 'Marcos ya es de Administración');
        await tester.tap(find.text('Pasar a Comercial (acceso total)'));
        await tester.pumpAndSettle();
        expect(json.decode(servidor.pedidosA('PUT', '/api/admin/admins/2/rol').single.body), {'rol': 'comercial'});
        expect(find.textContaining('Marcos Empleado ahora es usuario Comercial (acceso total)'), findsOneWidget);
        expect(find.text('Comercial'), findsNWidgets(2));
        expect(find.text('Administración'), findsOneWidget);

        // Y se le puede volver a bajar a Administración (solo el área técnica).
        // Primero se deja pasar el aviso anterior, que si no se queda esperando adelante.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('cambiar_rol_2')));
        await tester.pumpAndSettle();
        expect(find.text('Pasar a Comercial (acceso total)'), findsNothing, reason: 'ahora Marcos ya es Comercial');
        await tester.tap(find.text('Pasar a Administración (solo el área técnica)'));
        await tester.pumpAndSettle();
        expect(servidor.pedidosA('PUT', '/api/admin/admins/2/rol').map((p) => json.decode(p.body)).last, {'rol': 'admin'});
        expect(find.textContaining('Marcos Empleado ahora es usuario de Administración (solo el área técnica)'), findsOneWidget);
        expect(find.text('Comercial'), findsOneWidget);
        expect(find.text('Administración'), findsNWidgets(2));
        await _cerrar(tester);
      });
    });

    testWidgets('un usuario nuevo nace con el menor acceso: Administración (solo el área técnica)', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(usuarios: lista());
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaAdministradores(adminActualId: 1))));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('nuevo_usuario')));
        await tester.pumpAndSettle();
        expect(find.text('Administración (solo el área técnica)'), findsOneWidget, reason: 'viene elegido de entrada');
        final campos = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
        await tester.enterText(campos.at(0), 'Nuevo Empleado');
        await tester.enterText(campos.at(1), 'nuevo@son.test');
        await tester.enterText(campos.at(2), 'clave-segura-1');
        await tester.tap(find.text('Crear'));
        await tester.pumpAndSettle();

        final enviado = json.decode(servidor.pedidosA('POST', '/api/admin/admins').single.body) as Map;
        expect(enviado, {'nombre': 'Nuevo Empleado', 'email': 'nuevo@son.test', 'password': 'clave-segura-1', 'rol': 'admin'});
        expect(find.text('Usuario creado'), findsOneWidget);
        await _cerrar(tester);
      });
    });

    testWidgets('al crear un usuario se puede elegir Comercial (acceso total)', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(usuarios: lista());
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaAdministradores(adminActualId: 1))));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('nuevo_usuario')));
        await tester.pumpAndSettle();
        final campos = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
        await tester.enterText(campos.at(0), 'Nuevo Comercial');
        await tester.enterText(campos.at(1), 'comercial@son.test');
        await tester.enterText(campos.at(2), 'clave-segura-2');
        await tester.tap(find.byKey(const Key('tipo_usuario')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Comercial (acceso total)').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Crear'));
        await tester.pumpAndSettle();

        final enviado = json.decode(servidor.pedidosA('POST', '/api/admin/admins').single.body) as Map;
        expect(enviado, {'nombre': 'Nuevo Comercial', 'email': 'comercial@son.test', 'password': 'clave-segura-2', 'rol': 'comercial'});
        expect(find.text('Usuario creado'), findsOneWidget);
        await _cerrar(tester);
      });
    });
  });

  group('órdenes de trabajo', () {
    testWidgets('al crear una orden se sugieren los clientes del área comercial pidiendo solo sus nombres', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(
        tecnicos: [
          {'id': 3, 'nombre': 'Juan Pérez', 'email': 'juan@son.test'},
        ],
        clientes: [
          {'id': 7, 'razon_social': 'Acerbon SRL', 'contacto': 'Laura Gómez', 'email': 'laura@acerbon.com', 'cuit': '30-71234567-1'},
          {'id': 8, 'razon_social': 'Metalúrgica Sur', 'contacto': null, 'email': null, 'cuit': null},
        ],
      );
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaOrdenes())));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Nueva orden'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Empresa / Cliente'), 'a');
        await tester.pumpAndSettle();
        expect(find.text('Acerbon SRL'), findsOneWidget);
        expect(find.text('Metalúrgica Sur'), findsOneWidget);

        await tester.enterText(find.widgetWithText(TextField, 'Empresa / Cliente'), 'metalurgica');
        await tester.pumpAndSettle();
        expect(find.text('Acerbon SRL'), findsNothing, reason: 'la lista se filtra mientras se escribe');
        expect(find.text('Metalúrgica Sur'), findsOneWidget);

        // Administración no puede pedir las fichas completas (datos de contacto): alcanza con los nombres.
        expect(servidor.pedidosA('GET', '/api/clientes'), isEmpty);
        expect(servidor.pedidosA('GET', '/api/clientes/nombres'), hasLength(1));
        await _cerrar(tester);
      });
    });
  });

  group('ayudas de texto', () {
    test('fechaCorta usa Hoy, Ayer o la fecha', () {
      final ahora = DateTime(2026, 10, 27, 18, 0);
      expect(fechaCorta(DateTime(2026, 10, 27, 9, 5), ahora: ahora), 'Hoy 09:05');
      expect(fechaCorta(DateTime(2026, 10, 26, 23, 59), ahora: ahora), 'Ayer 23:59');
      expect(fechaCorta(DateTime(2026, 10, 20, 15, 30), ahora: ahora), '20/10 15:30');
      expect(fechaCorta(DateTime(2025, 12, 31, 8, 0), ahora: ahora), '31/12/2025 08:00');
    });

    test('sinAcentos ignora mayúsculas y tildes', () {
      expect(sinAcentos('  Metalúrgica SUR_Ñandú '), 'metalurgica sur nandu');
    });

    test('coincideBusqueda encuentra por palabras sueltas, sin importar el orden ni los acentos', () {
      const texto = 'Metalúrgica Sur  Luz de emergencia  Juan Pérez';
      expect(coincideBusqueda(texto, ''), isTrue);
      expect(coincideBusqueda(texto, '   '), isTrue);
      expect(coincideBusqueda(texto, 'luz emergencia'), isTrue);
      expect(coincideBusqueda(texto, 'PEREZ sur'), isTrue);
      expect(coincideBusqueda(texto, 'metalurgica'), isTrue);
      expect(coincideBusqueda(texto, 'luz extintor'), isFalse, reason: 'tienen que estar todas las palabras');
    });

    test('pesos agrupa de a tres y numeroDePersona entiende coma y puntos', () {
      expect(pesos(365113), '\$365.113');
      expect(pesos(null), '—');
      expect(pesos(0), '\$0');
      expect(numeroDePersona('2,1'), 2.1);
      expect(numeroDePersona('365.113'), 365113);
      expect(numeroDePersona(''), isNull);
    });

    test('en el tablero Enviado se lee como Contactar y la fecha va día/mes/año', () {
      expect(etiquetaDeColumna('Enviado'), 'Contactar');
      expect(etiquetaDeColumna('Negociando'), 'Negociando');
      expect(fechaDia('2026-11-15'), '15/11/2026');
      expect(fechaDia(null), '');
    });
  });

  group('presupuestos y precios', () {
    const duena = {'id': 5, 'nombre': 'Laura', 'email': 'laura@son.test', 'rol': 'comercial'};

    testWidgets('la lista de presupuestos vacía invita a armar el primero', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor();
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaPresupuestos())));
        await tester.pumpAndSettle();
        expect(find.text('Embudo de presupuestos'), findsOneWidget);
        expect(find.text('Tablero'), findsOneWidget);
        expect(find.text('Lista'), findsOneWidget);
        expect(find.text('Notas de técnicos'), findsOneWidget);
        expect(find.textContaining('Todavía no hay presupuestos'), findsWidgets);
        expect(find.byKey(const Key('nuevo_presupuesto')), findsOneWidget);
        await _cerrar(tester);
      });
    });

    testWidgets('el tablero arma columnas, KPIs y deja mover un presupuesto', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(presupuestos: [
        _presupuesto(id: 1, numero: 3612, cliente: 'Acerbon SRL', estado: 'Enviado', responsable: 'Valentina'),
        _presupuesto(id: 2, numero: 3611, cliente: 'Metalúrgica Sur', estado: 'Negociando', prioridad: 'alta'),
        _presupuesto(id: 3, numero: 3610, cliente: 'Taller Norte', estado: 'Aceptado', facturado: true),
        _presupuesto(id: 4, numero: 3609, cliente: 'Obras del Sur', estado: 'Rechazado'),
        _presupuesto(id: 5, numero: 3608, cliente: 'Borrador SA', estado: 'Borrador'),
      ]);
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaPresupuestos())));
        await tester.pumpAndSettle();

        expect(find.text('Contactar'), findsWidgets);
        expect(find.text('Por contactar'), findsOneWidget);
        expect(find.text('Conversión'), findsOneWidget);
        expect(find.text('50 %'), findsOneWidget, reason: '1 aceptado de 2 cerrados');
        expect(find.byKey(const Key('tablero_1')), findsOneWidget);
        expect(find.text('Valentina'), findsWidgets);
        expect(find.text('Facturado'), findsOneWidget);

        await tester.tap(find.descendant(of: find.byKey(const Key('tablero_1')), matching: find.byIcon(Icons.more_vert)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pasar a Negociando'));
        await tester.pumpAndSettle();
        expect(servidor.pedidosA('PUT', '/api/presupuestos/1/estado'), hasLength(1));
        expect(servidor.presupuestos.firstWhere((p) => p['id'] == 1)['estado'], 'Negociando');
        await _cerrar(tester);
      });
    });

    testWidgets('desde el tablero se carga el seguimiento', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor(presupuestos: [
        _presupuesto(id: 1, numero: 3612, cliente: 'Acerbon SRL', estado: 'Enviado'),
      ]);
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaPresupuestos())));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('tablero_1')));
        await tester.pumpAndSettle();
        expect(find.text('SEGUIMIENTO'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('seguimiento_responsable')), 'Valentina');
        await tester.tap(find.text('Guardar seguimiento'));
        await tester.pumpAndSettle();
        expect(servidor.pedidosA('PUT', '/api/presupuestos/1/seguimiento'), hasLength(1));
        expect(servidor.presupuestos.first['responsable'], 'Valentina');
        expect(find.text('Seguimiento guardado'), findsOneWidget);
        await _cerrar(tester);
      });
    });

    testWidgets('Precios abre en el tarifario', (tester) async {
      _pantallaGrande(tester);
      final servidor = _Servidor();
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const Scaffold(body: PantallaPrecios())));
        await tester.pumpAndSettle();
        expect(find.text('Lista de precios'), findsOneWidget);
        expect(find.text('Tarifario'), findsOneWidget);
        expect(find.byKey(const Key('nueva_tarifa')), findsOneWidget);
        await tester.tap(find.text('Inflación'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('buscar_indec')), findsOneWidget);
        await _cerrar(tester);
      });
    });

    testWidgets('Comercial entra a Presupuestos desde el menú; Administración no lo ve', (tester) async {
      _pantallaGrande(tester);
      SesionAdmin.guardarPantalla('presupuestos');
      final servidor = _Servidor();
      await servidor.correr(() async {
        await tester.pumpWidget(_app(const LayoutAdministrador(adminData: duena)));
        await tester.pumpAndSettle();
        expect(find.byType(PantallaPresupuestos), findsOneWidget);
        expect(find.text('Nuevo presupuesto'), findsOneWidget);
        await _cerrar(tester);
      });
    });
  });
}
