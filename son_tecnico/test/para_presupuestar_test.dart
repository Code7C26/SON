import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:son_tecnico/pantallas/para_presupuestar.dart';
import 'package:son_tecnico/services/almacen.dart';
import 'package:son_tecnico/services/sesion.dart';
import 'package:son_tecnico/services/sincronizacion.dart';
import 'package:son_tecnico/theme/tema.dart';

Widget _envolver(Widget hijo) => MaterialApp(theme: temaSon(), home: Scaffold(body: SingleChildScrollView(child: hijo)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('identificador de la nota', () {
    test('tiene el formato que acepta el servidor y no se repite', () {
      final formato = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
      final vistos = <String>{};
      for (var i = 0; i < 2000; i++) {
        final id = nuevoIdDeNota();
        expect(formato.hasMatch(id), isTrue, reason: id);
        vistos.add(id);
      }
      expect(vistos.length, 2000);
    });
  });

  group('sección "Para presupuestar"', () {
    testWidgets('sin notas invita a anotar', (tester) async {
      await tester.pumpWidget(_envolver(SeccionParaPresupuestar(
        notas: const [],
        fotos: const {},
        pendientes: const {},
        fallidas: const {},
        onAnotar: () {},
      )));
      expect(find.text('Para presupuestar'), findsOneWidget);
      expect(find.text('Anotar para presupuestar'), findsOneWidget);
      expect(find.byKey(const Key('anotar_presupuesto')), findsOneWidget);
    });

    testWidgets('cada nota muestra si ya llegó, si está en el celular o si falló', (tester) async {
      await tester.pumpWidget(_envolver(SeccionParaPresupuestar(
        notas: const [
          {'id': 'a1', 'descripcion': 'Extintor ABC 5 kg', 'cantidad': 2, 'conFoto': false},
          {'id': 'b2', 'descripcion': 'Luz de emergencia', 'cantidad': 1, 'conFoto': true},
          {'id': 'c3', 'descripcion': 'Cartel de salida', 'cantidad': 4, 'conFoto': false},
        ],
        fotos: {'b2': _pngMinimo},
        pendientes: const {'b2'},
        fallidas: const {'c3'},
        onAnotar: () {},
      )));
      expect(find.text('Extintor ABC 5 kg'), findsOneWidget);
      expect(find.text('Cantidad: 2'), findsOneWidget);
      expect(find.text('Enviada'), findsOneWidget);
      expect(find.text('En el celular'), findsOneWidget);
      expect(find.text('No se pudo enviar'), findsOneWidget);
      expect(find.text('Todavía no anotaste nada.'), findsNothing);
    });

    testWidgets('el botón Anotar avisa a la pantalla', (tester) async {
      var toques = 0;
      await tester.pumpWidget(_envolver(SeccionParaPresupuestar(
        notas: const [],
        fotos: const {},
        pendientes: const {},
        fallidas: const {},
        onAnotar: () => toques++,
      )));
      await tester.tap(find.byKey(const Key('anotar_presupuesto')));
      expect(toques, 1);
    });
  });

  group('ventana para anotar', () {
    Future<void> abrir(WidgetTester tester, void Function(NotaNueva?) alCerrar) async {
      await tester.pumpWidget(MaterialApp(
        theme: temaSon(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => alCerrar(await pedirNotaParaPresupuestar(context)),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('no deja anotar si no se escribió nada', (tester) async {
      NotaNueva? resultado;
      var cerro = false;
      await abrir(tester, (nota) {
        resultado = nota;
        cerro = true;
      });
      final boton = tester.widget<ElevatedButton>(find.byKey(const Key('nota_guardar')));
      expect(boton.onPressed, isNull);

      await tester.enterText(find.byKey(const Key('nota_descripcion')), '    ');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('nota_guardar'))).onPressed, isNull, reason: 'solo espacios no cuenta');
      expect(cerro, isFalse);
      expect(resultado, isNull);
    });

    testWidgets('devuelve la descripción y la cantidad elegidas', (tester) async {
      NotaNueva? resultado;
      await abrir(tester, (nota) => resultado = nota);

      await tester.enterText(find.byKey(const Key('nota_descripcion')), '  Falta un extintor  ');
      await tester.pump();
      await tester.tap(find.byKey(const Key('nota_mas')));
      await tester.tap(find.byKey(const Key('nota_mas')));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nota_menos')));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nota_guardar')));
      await tester.pumpAndSettle();
      expect(resultado, isNotNull);
      expect(resultado!.descripcion, 'Falta un extintor');
      expect(resultado!.cantidad, 2);
      expect(resultado!.foto, isNull);
    });

    testWidgets('la cantidad no baja de 1', (tester) async {
      await abrir(tester, (_) {});
      expect(tester.widget<IconButton>(find.byKey(const Key('nota_menos'))).onPressed, isNull);
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('cola del celular', () {
    test('las notas esperan en el celular, no cambian ninguna orden y se distinguen las rechazadas', () async {
      Sesion.iniciar(nuevoToken: 'token-de-prueba', id: 77, nuevoNombre: 'Tecnico', nuevoEmail: 't@son.test');

      await Sincronizador.encolarSolicitud({
        'idCliente': 'nprueba0001',
        'ordenId': 5,
        'cliente': 'Empresa Uno',
        'descripcion': 'Falta un extintor',
        'cantidad': 2,
        'foto': null,
        'creadaEn': '2026-10-27T15:00:00.000Z',
      });
      await Sincronizador.encolarSolicitud({
        'idCliente': 'nprueba0002',
        'ordenId': 5,
        'cliente': 'Empresa Uno',
        'descripcion': 'Luz de emergencia',
        'cantidad': 1,
      });

      expect(await Sincronizador.solicitudesPendientes(), {'nprueba0001', 'nprueba0002'});
      expect(Sincronizador.estado.value.pendientes, 2);

      // Una nota para presupuestar no es un cambio de estado: la orden queda como estaba.
      final ordenes = [
        {'id': 5, 'estado': 'Pendiente'},
      ];
      await Sincronizador.aplicarPendientes(ordenes);
      expect(ordenes.single['estado'], 'Pendiente');

      // Si el servidor rechaza una, pasa a "fallidas" y deja de figurar como pendiente.
      final nombres = await Almacen.listar('cola');
      expect(nombres.length, 2);
      await Almacen.mover('cola/${nombres.first}', 'cola_fallida/${nombres.first}');
      expect((await Sincronizador.solicitudesPendientes()).length, 1);
      expect(await Sincronizador.solicitudesFallidas(), {'nprueba0001'});

      // Lo que dejó otro técnico en el mismo celular no se mezcla.
      Sesion.iniciar(nuevoToken: 'otro', id: 78, nuevoNombre: 'Otro', nuevoEmail: 'o@son.test');
      expect(await Sincronizador.solicitudesPendientes(), isEmpty);
      expect(await Sincronizador.solicitudesFallidas(), isEmpty);

      for (final nombre in await Almacen.listar('cola')) {
        await Almacen.borrar('cola/$nombre');
      }
      for (final nombre in await Almacen.listar('cola_fallida')) {
        await Almacen.borrar('cola_fallida/$nombre');
      }
      Sesion.cerrar();
      Sincronizador.detener();
    });
  });
}

// PNG de 1x1 píxel, solo para que Image.memory tenga algo que dibujar.
final Uint8List _pngMinimo = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
