import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:son_admin/pantallas/analisis.dart';
import 'package:son_admin/theme/tema.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

Map<String, dynamic> _analisis() => {
      'periodo': 'mes',
      'desde': '2026-11-01',
      'hasta': '2026-11-30',
      'comparacion': 'vs mes anterior',
      'opciones': {
        'clientes': [
          {'id': 4, 'nombre': 'Acerbon SRL'}
        ],
        'tecnicos': [
          {'id': 3, 'nombre': 'Juan Pérez'}
        ],
      },
      'kpis': {
        'ordenes': 4,
        'variacion': 100,
        'pendientes': 2,
        'vencidas': 1,
        'checklist': 50,
        'checklistHechos': 1,
        'checklistTotal': 2,
        'completadas': 2,
        'tasaCierre': 50,
        'promedioMinutos': 60,
      },
      'serie': {
        'modo': 'mes',
        'puntos': [
          {'etiqueta': 'oct', 'ordenes': 4, 'completadas': 4},
          {'etiqueta': 'nov', 'ordenes': 5, 'completadas': 0},
        ],
      },
      'porCliente': [
        {'nombre': 'Acerbon SRL', 'ordenes': 6, 'completadas': 2},
      ],
      'comentarios': [
        {
          'ordenId': 7,
          'cliente': 'Acerbon SRL',
          'fecha': '2026-11-02',
          'tecnico': 'Juan Pérez',
          'texto': 'Recargar extintores del depósito',
          'solicitudId': null,
          'empresaId': 4,
        }
      ],
      'tecnicos': [
        {
          'id': 3,
          'nombre': 'Juan Pérez',
          'asignadas': 2,
          'completadas': 1,
          'checklist': 50,
          'promedioMinutos': 90,
          'minutos': 90,
          'visitas': 1,
          'calificacion': 5,
          'respuestas': 1,
        }
      ],
      'encuestas': {
        'enviados': 2,
        'respondidas': 2,
        'tasa': 100,
        'promedio': 3.5,
        'respuestas': 2,
        'distribucion': [0, 1, 0, 0, 1],
        'detalle': [
          {'puntaje': 5, 'comentario': 'Todo bien', 'cliente': 'Cliente Alto', 'tecnico': 'Juan Pérez', 'cuando': '02/11/2026 10:00'},
          {'puntaje': 2, 'comentario': '', 'cliente': 'Cliente Bajo', 'tecnico': 'Ana Gómez', 'cuando': '01/11/2026 09:00'},
        ],
      },
    };

class _Servidor {
  final List<http.Request> pedidos = [];

  http.Response _ok(Object datos) => http.Response(json.encode(datos), 200, headers: _json);

  Future<http.Response> responder(http.Request pedido) async {
    pedidos.add(pedido);
    final ruta = pedido.url.path;
    if (ruta == '/api/analisis' && pedido.method == 'GET') return _ok(_analisis());
    if (ruta == '/api/analisis/comentarios/7/presupuesto' && pedido.method == 'POST') {
      return _ok({'id': 15, 'empresa_id': 4, 'empresa': 'Acerbon SRL', 'descripcion': 'Recargar extintores del depósito', 'cantidad': 1, 'estado': 'Nueva'});
    }
    if (ruta == '/api/clientes') return _ok(const []);
    if (ruta == '/api/tarifas') return _ok({'tarifas': const []});
    if (ruta == '/api/costos') return _ok({'costos': const []});
    if (ruta == '/api/comercial/config') return _ok({'textos': const {}});
    if (ruta == '/api/presupuestos/calcular') {
      return _ok({
        'calculo': {'totalMensual': 0, 'totalUnico': 0, 'nivelMargen': 'sin_dato', 'avisos': const []},
        'items': const [],
      });
    }
    return http.Response(json.encode({'error': 'Ruta no simulada: ${pedido.method} $ruta'}), 404, headers: _json);
  }

  Future<void> correr(Future<void> Function() prueba) => http.runWithClient(prueba, () => MockClient(responder));
}

void _pantallaGrande(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _app(Widget hijo) => MaterialApp(theme: temaSon(), home: Scaffold(body: hijo));

void main() {
  testWidgets('muestra los indicadores, filtra las encuestas y cambia el período', (tester) async {
    _pantallaGrande(tester);
    final servidor = _Servidor();
    await servidor.correr(() async {
      await tester.pumpWidget(_app(const PantallaAnalisis()));
      await tester.pumpAndSettle();

      expect(find.descendant(of: find.byKey(const Key('kpi_ordenes')), matching: find.text('4')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('kpi_ordenes')), matching: find.text('+100% vs mes anterior')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('kpi_pendientes')), matching: find.text('1 vencida')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('kpi_checklist')), matching: find.text('50%')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('kpi_checklist')), matching: find.text('1 de 2 tareas')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('kpi_cierre')), matching: find.text('2')), findsOneWidget);
      expect(find.text('Verificación de órdenes'), findsOneWidget);
      expect(find.text('Cómo están'), findsNothing);
      expect(find.text('Órdenes por mes'), findsOneWidget);
      expect(find.text('oct'), findsOneWidget);
      expect(find.text('Por cliente'), findsOneWidget);
      expect(find.text('6 · 2 cerradas'), findsOneWidget);
      expect(find.text('Mails enviados'), findsOneWidget);
      expect(find.text('Controles que más quedan sin hacer'), findsNothing);
      expect(find.text('Cliente Alto'), findsOneWidget);
      expect(find.byKey(const Key('crear_presupuesto_7')), findsNothing);

      await tester.tap(find.byKey(const Key('encuesta_bajas')));
      await tester.pumpAndSettle();
      expect(find.text('Cliente Alto'), findsNothing);
      expect(find.text('Cliente Bajo'), findsOneWidget);

      await tester.tap(find.byKey(const Key('encuesta_comentarios')));
      await tester.pumpAndSettle();
      expect(find.text('Cliente Alto'), findsOneWidget);
      expect(find.text('Cliente Bajo'), findsNothing);

      await tester.tap(find.text('Hoy'));
      await tester.pumpAndSettle();
      expect(servidor.pedidos.last.url.query, contains('periodo=hoy'));
      expect(servidor.pedidos.first.url.query, contains('periodo=trimestre'));
    });
  });
}
