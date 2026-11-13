import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:son_tecnico/pantallas/para_presupuestar.dart' show nuevoIdDeNota;
import 'package:son_tecnico/services/almacen.dart';
import 'package:son_tecnico/services/api.dart';
import 'package:son_tecnico/services/sesion.dart';
import 'package:son_tecnico/services/sincronizacion.dart';
import 'package:son_tecnico/theme/colores.dart';

// Lo que pidieron los técnicos en la reunión de noviembre de 2026: gastos del auto, vencimientos,
// ver en qué quedó cada presupuesto pedido y usar la firma con sello cargada en el perfil.

String _dos(int n) => n.toString().padLeft(2, '0');
String fechaIso(DateTime fecha) => '${fecha.year}-${_dos(fecha.month)}-${_dos(fecha.day)}';
String fechaCorta(String? iso) {
  final partes = (iso ?? '').split('-');
  if (partes.length < 3) return '';
  return '${partes[2].substring(0, 2)}/${partes[1]}/${partes[0]}';
}

/// "08:00 a 12:00", "08:00" o "" según lo que tenga la orden.
String rangoHorario(Map orden) {
  final desde = '${orden['hora'] ?? ''}'.trim();
  final hasta = '${orden['hora_hasta'] ?? ''}'.trim();
  String corta(String hora) => hora.length > 5 ? hora.substring(0, 5) : hora;
  if (desde.isEmpty) return '';
  return hasta.isEmpty ? corta(desde) : '${corta(desde)} a ${corta(hasta)}';
}

// ---------------------------------------------------
// PERFIL: si el técnico tiene cargada su firma con sello, no tiene que firmar en cada visita.
// ---------------------------------------------------
class PerfilTecnico {
  static String _archivo(int id) => 'perfil_$id.json';

  /// Lo guardado en el celular (sirve sin señal).
  static Future<Map<String, dynamic>?> guardado(int id) async {
    final datos = await Almacen.leer(_archivo(id));
    return datos is Map ? Map<String, dynamic>.from(datos) : null;
  }

  /// Pide el perfil al servidor y lo guarda. Sin señal devuelve lo último guardado.
  static Future<Map<String, dynamic>?> actualizar(int id) async {
    try {
      final respuesta = await apiGet('/api/tecnicos/yo');
      if (respuesta.statusCode == 200) {
        final datos = Map<String, dynamic>.from(json.decode(respuesta.body) as Map);
        await Almacen.escribir(_archivo(id), datos);
        return datos;
      }
    } catch (_) {}
    return guardado(id);
  }
}

// ---------------------------------------------------
// GASTOS Y KILOMETRAJE
// ---------------------------------------------------
const List<String> tiposDeGasto = ['Combustible', 'Peaje', 'Estacionamiento', 'Comida', 'Hospedaje', 'Materiales', 'Otro'];

/// Abre la ventana para cargar un gasto. Se guarda en el celular y se manda apenas haya señal.
/// Devuelve true si se cargó algo.
/// Se pueden cargar varios seguidos ("Guardar y cargar otro"). Los gastos van solo a Administración:
/// no salen en el informe del cliente. Devuelve un resumen de cada gasto cargado (sin la foto).
Future<List<Map<String, dynamic>>> cargarGasto(BuildContext context, {Map? orden}) async {
  final cargados = <Map<String, dynamic>>[];
  var otro = true;
  while (otro && context.mounted) {
    final gasto = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: sonTarjeta,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FormularioGasto(orden: orden, cargadosAntes: cargados.length),
    );
    if (gasto == null) break;
    otro = gasto.remove('otro') == true;
    await Sincronizador.encolarGasto(gasto);
    cargados.add({
      'idCliente': gasto['idCliente'],
      'tipo': gasto['tipo'],
      'monto': gasto['monto'],
      'kmInicio': gasto['kmInicio'],
      'kmFin': gasto['kmFin'],
      'vehiculo': gasto['vehiculo'],
      'descripcion': gasto['descripcion'],
      'conFoto': gasto['foto'] != null,
    });
  }
  if (cargados.isEmpty) return cargados;
  unawaited(Sincronizador.sincronizar());
  if (context.mounted) {
    final texto = cargados.length == 1 ? 'Gasto guardado.' : '${cargados.length} gastos guardados.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$texto Le llega a Administración.')));
  }
  return cargados;
}

/// "Combustible · \$ 50.000 · 80 km" para mostrar un gasto en una línea.
String resumenDeGasto(Map gasto) {
  final partes = <String>['${gasto['tipo'] ?? 'Gasto'}'];
  final monto = double.tryParse('${gasto['monto'] ?? ''}');
  if (monto != null) {
    final entero = monto.truncate().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    final decimales = ((monto - monto.truncate()) * 100).round();
    partes.add('\$ $entero${decimales > 0 ? ',${decimales.toString().padLeft(2, '0')}' : ''}');
  }
  final inicio = (gasto['kmInicio'] as num?)?.toInt();
  final fin = (gasto['kmFin'] as num?)?.toInt();
  if (inicio != null && fin != null) partes.add('${fin - inicio} km');
  if ('${gasto['descripcion'] ?? ''}'.isNotEmpty) partes.add('${gasto['descripcion']}');
  return partes.join(' · ');
}

class _FormularioGasto extends StatefulWidget {
  final Map? orden;
  final int cargadosAntes;
  const _FormularioGasto({this.orden, this.cargadosAntes = 0});

  @override
  State<_FormularioGasto> createState() => _FormularioGastoState();
}

class _FormularioGastoState extends State<_FormularioGasto> {
  final _vehiculo = TextEditingController();
  final _monto = TextEditingController();
  final _kmInicio = TextEditingController();
  final _kmFin = TextEditingController();
  final _detalle = TextEditingController();
  final _picker = ImagePicker();
  String _tipo = 'Combustible';
  Uint8List? _foto;
  String? _error;

  @override
  void initState() {
    super.initState();
    // El auto que usó la última vez ya viene escrito.
    Almacen.leer('vehiculo.json').then((guardado) {
      if (mounted && guardado is String && _vehiculo.text.isEmpty) setState(() => _vehiculo.text = guardado);
    });
  }

  @override
  void dispose() {
    for (final control in [_vehiculo, _monto, _kmInicio, _kmFin, _detalle]) {
      control.dispose();
    }
    super.dispose();
  }

  Future<void> _sacarFoto() async {
    try {
      final foto = await _picker.pickImage(source: ImageSource.camera, imageQuality: 60, maxWidth: 1600);
      if (foto == null) return;
      final bytes = await foto.readAsBytes();
      if (mounted) setState(() => _foto = bytes);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo abrir la cámara');
    }
  }

  void _guardar({bool otro = false}) {
    final monto = _monto.text.trim().replaceAll('.', '').replaceAll(',', '.');
    final kmInicio = int.tryParse(_kmInicio.text.trim());
    final kmFin = int.tryParse(_kmFin.text.trim());
    if (monto.isNotEmpty && double.tryParse(monto) == null) return setState(() => _error = 'El monto tiene que ser un número');
    if (_kmInicio.text.trim().isNotEmpty && kmInicio == null) return setState(() => _error = 'El kilometraje tiene que ser un número entero');
    if (_kmFin.text.trim().isNotEmpty && kmFin == null) return setState(() => _error = 'El kilometraje tiene que ser un número entero');
    if (kmInicio != null && kmFin != null && kmFin < kmInicio) return setState(() => _error = 'El kilometraje final es menor que el inicial');
    if (monto.isEmpty && kmInicio == null && kmFin == null && _foto == null) return setState(() => _error = 'Cargá el monto, el kilometraje o una foto');
    final vehiculo = _vehiculo.text.trim();
    if (vehiculo.isNotEmpty) unawaited(Almacen.escribir('vehiculo.json', vehiculo));
    Navigator.pop(context, {
      'idCliente': nuevoIdDeNota(),
      'ordenId': widget.orden?['id'],
      'cliente': widget.orden?['cliente'],
      'vehiculo': vehiculo,
      'tipo': _tipo,
      'monto': monto.isEmpty ? null : monto,
      'kmInicio': kmInicio,
      'kmFin': kmFin,
      'descripcion': _detalle.text.trim(),
      'foto': _foto == null ? null : 'data:image/jpeg;base64,${base64Encode(_foto!)}',
      'creadoEn': DateTime.now().toUtc().toIso8601String(),
      'otro': otro,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.cargadosAntes == 0 ? 'Vehículo y gastos' : 'Otro gasto (${widget.cargadosAntes} ya cargado${widget.cargadosAntes == 1 ? '' : 's'})',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: sonTexto),
            ),
            if (widget.orden != null) Text('${widget.orden!['cliente'] ?? ''}', style: TextStyle(color: sonTextoSuave)),
            const SizedBox(height: 16),
            TextField(controller: _vehiculo, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Auto que usaste hoy', hintText: 'Ej: Clio')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: TextField(controller: _kmInicio, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Km al salir'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _kmFin, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Km al volver'))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _tipo,
                    decoration: const InputDecoration(labelText: 'Gasto'),
                    items: tiposDeGasto.map((tipo) => DropdownMenuItem(value: tipo, child: Text(tipo))).toList(),
                    onChanged: (valor) => setState(() => _tipo = valor ?? 'Otro'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _monto, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Monto \$'))),
              ],
            ),
            const SizedBox(height: 10),
            TextField(controller: _detalle, maxLength: 500, decoration: const InputDecoration(labelText: 'Detalle (opcional)', hintText: 'Ej: YPF ruta 5')),
            if (_foto == null)
              OutlinedButton.icon(onPressed: _sacarFoto, icon: const Icon(Icons.receipt_long_outlined), label: const Text('Foto del ticket'))
            else
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: sonBorde)),
                    clipBehavior: Clip.hardEdge,
                    child: Image.memory(_foto!, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () => setState(() => _foto = null),
                    icon: Icon(Icons.delete_outline, color: sonRojo),
                    label: Text('Quitar foto', style: TextStyle(color: sonRojo)),
                  ),
                ],
              ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600))),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(onPressed: () => _guardar(otro: true), child: const Text('Guardar y cargar otro', textAlign: TextAlign.center)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(height: 50, child: ElevatedButton(onPressed: _guardar, child: const Text('Guardar', style: TextStyle(fontSize: 16)))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Va solo a Administración: no sale en el informe del cliente.', style: TextStyle(color: sonTextoSuave, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------
// VENCIMIENTOS
// ---------------------------------------------------
/// Anota algo que vence en el cliente de la orden. Devuelve el vencimiento anotado (o null).
Future<Map<String, dynamic>?> anotarVencimiento(BuildContext context, {required Map orden}) async {
  final vencimiento = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: sonTarjeta,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _FormularioVencimiento(orden: orden),
  );
  if (vencimiento == null) return null;
  await Sincronizador.encolarVencimiento(vencimiento);
  unawaited(Sincronizador.sincronizar());
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vencimiento anotado. Avisa antes de que venza.')));
  }
  return vencimiento;
}

class _FormularioVencimiento extends StatefulWidget {
  final Map orden;
  const _FormularioVencimiento({required this.orden});

  @override
  State<_FormularioVencimiento> createState() => _FormularioVencimientoState();
}

class _FormularioVencimientoState extends State<_FormularioVencimiento> {
  final _descripcion = TextEditingController();
  int _cantidad = 1;
  DateTime? _vence;
  String? _error;

  @override
  void dispose() {
    _descripcion.dispose();
    super.dispose();
  }

  void _guardar() {
    if (_descripcion.text.trim().isEmpty) return setState(() => _error = 'Escribí qué es lo que vence');
    if (_vence == null) return setState(() => _error = 'Elegí la fecha de vencimiento');
    Navigator.pop(context, {
      'idCliente': nuevoIdDeNota(),
      'ordenId': widget.orden['id'],
      'cliente': widget.orden['cliente'],
      'descripcion': _descripcion.text.trim(),
      'cantidad': _cantidad,
      'vence': fechaIso(_vence!),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Anotar un vencimiento', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: sonTexto)),
            Text('Avisa a vos y a la oficina dos meses antes.', style: TextStyle(color: sonTextoSuave)),
            const SizedBox(height: 16),
            TextField(
              controller: _descripcion,
              autofocus: true,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: '¿Qué vence?', hintText: 'Ej: Extintores ABC 5 kg (carga)'),
            ),
            Row(
              children: [
                Text('Cantidad', style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null, icon: const Icon(Icons.remove_circle_outline)),
                SizedBox(width: 44, child: Center(child: Text('$_cantidad', style: TextStyle(color: sonTexto, fontSize: 18, fontWeight: FontWeight.bold)))),
                IconButton(onPressed: _cantidad < 999 ? () => setState(() => _cantidad++) : null, icon: const Icon(Icons.add_circle_outline)),
              ],
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final hoy = DateTime.now();
                final elegida = await showDatePicker(
                  context: context,
                  initialDate: _vence ?? DateTime(hoy.year + 1, hoy.month, hoy.day),
                  firstDate: hoy.subtract(const Duration(days: 365)),
                  lastDate: hoy.add(const Duration(days: 3650)),
                );
                if (elegida != null) setState(() => _vence = elegida);
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(_vence == null ? 'Fecha de vencimiento' : 'Vence el ${_vence!.day}/${_vence!.month}/${_vence!.year}'),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _guardar, child: const Text('Anotar', style: TextStyle(fontSize: 16)))),
          ],
        ),
      ),
    );
  }
}

/// Lista guardada en el celular que se actualiza desde el servidor cuando hay señal.
Future<List<Map<String, dynamic>>?> _listaDelServidor(String ruta, String archivo) async {
  try {
    final respuesta = await apiGet(ruta);
    if (respuesta.statusCode == 200) {
      final datos = (json.decode(respuesta.body) as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
      await Almacen.escribir(archivo, datos);
      return datos;
    }
  } catch (_) {}
  final guardado = await Almacen.leer(archivo);
  return guardado is List ? guardado.map((item) => Map<String, dynamic>.from(item as Map)).toList() : null;
}

Future<List<Map<String, dynamic>>?> vencimientosDeMisClientes() =>
    _listaDelServidor('/api/vencimientos/mios', 'vencimientos_${Sesion.tecnicoId}.json');

Future<List<Map<String, dynamic>>?> misPedidosDePresupuesto() =>
    _listaDelServidor('/api/solicitudes-presupuesto/mias', 'pedidos_${Sesion.tecnicoId}.json');

Color colorDeVencimiento(int dias) => dias < 0 ? sonRojo : (dias <= 60 ? sonAmbar : sonLightGreen);

String textoDeVencimiento(int dias) => dias < 0 ? 'Vencido' : (dias == 0 ? 'Vence hoy' : 'En $dias días');

Widget _chip(String texto, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
      child: Text(texto, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );

Widget filaVencimiento(Map v, {bool conEmpresa = true}) {
  final dias = (v['dias'] as num?)?.toInt() ?? 0;
  return ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    leading: Icon(Icons.event_busy_outlined, color: colorDeVencimiento(dias)),
    title: Text('${v['descripcion']}${((v['cantidad'] as num?) ?? 1) > 1 ? ' (x${v['cantidad']})' : ''}', style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600)),
    subtitle: Text([if (conEmpresa) '${v['empresa'] ?? ''}', 'Vence el ${fechaCorta('${v['vence']}')}'].where((t) => t.isNotEmpty).join(' · ')),
    trailing: _chip(textoDeVencimiento(dias), colorDeVencimiento(dias)),
  );
}

class PantallaVencimientos extends StatefulWidget {
  const PantallaVencimientos({super.key});

  @override
  State<PantallaVencimientos> createState() => _PantallaVencimientosState();
}

class _PantallaVencimientosState extends State<PantallaVencimientos> {
  List<Map<String, dynamic>>? _lista;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await vencimientosDeMisClientes();
    if (mounted) setState(() { _lista = lista; _cargando = false; });
  }

  @override
  Widget build(BuildContext context) {
    final lista = _lista ?? [];
    return Scaffold(
      backgroundColor: sonFondo,
      appBar: AppBar(title: Text('Vencimientos de mis clientes', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)), backgroundColor: sonFondo),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_lista == null) Text('Sin conexión y sin datos guardados.', style: TextStyle(color: sonTextoSuave)),
                  if (_lista != null && lista.isEmpty) Text('No hay nada por vencer en los próximos 4 meses.', style: TextStyle(color: sonTextoSuave)),
                  if (lista.isNotEmpty) Container(decoration: decoracionTarjeta(), child: Column(children: lista.map((v) => filaVencimiento(v)).toList())),
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------
// PRESUPUESTOS QUE PIDIÓ EL TÉCNICO
// ---------------------------------------------------
const List<String> pasosDelPresupuesto = ['Pedido', 'Presupuestado', 'Enviado', 'Aprobado'];

Color colorDePedido(String estado) => switch (estado) {
      'Aprobado' => sonLightGreen,
      'Enviado' => sonAzul,
      'Rechazado' || 'Descartado' => sonRojo,
      'Pedido' => sonAmbar,
      _ => sonTextoSuave,
    };

/// Pedido → Presupuestado → Enviado → Aprobado, con el paso actual marcado.
class LineaDelPedido extends StatelessWidget {
  final String estado;
  const LineaDelPedido({super.key, required this.estado});

  @override
  Widget build(BuildContext context) {
    if (estado == 'Rechazado' || estado == 'Descartado') return _chip(estado, sonRojo);
    final actual = estado == 'Presupuestando' ? 0 : pasosDelPresupuesto.indexOf(estado);
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < pasosDelPresupuesto.length; i++) ...[
          if (i > 0) Icon(Icons.chevron_right, size: 14, color: sonTextoSuave),
          Text(
            pasosDelPresupuesto[i],
            style: TextStyle(
              fontSize: 12,
              fontWeight: i == actual ? FontWeight.bold : FontWeight.normal,
              color: i <= actual ? colorDePedido(pasosDelPresupuesto[actual]) : sonTextoSuave,
            ),
          ),
        ],
      ],
    );
  }
}

Widget filaPedido(Map p, {bool conEmpresa = true}) {
  final estado = '${p['estado_visible'] ?? 'Pedido'}';
  final cantidad = (p['cantidad'] as num?)?.toInt() ?? 1;
  final creada = '${p['creada_en'] ?? ''}';
  return Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${p['descripcion']}${cantidad > 1 ? ' (x$cantidad)' : ''}', style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          [
            if (conEmpresa) '${p['empresa'] ?? ''}',
            if (creada.length >= 10) 'Pedido el ${fechaCorta(creada.substring(0, 10))}',
            if (p['presupuesto'] != null) 'Presupuesto ${p['presupuesto']}',
            if (p['fecha_envio'] != null) 'enviado el ${fechaCorta('${p['fecha_envio']}')}',
          ].where((t) => t.isNotEmpty).join(' · '),
          style: TextStyle(color: sonTextoSuave, fontSize: 13),
        ),
        const SizedBox(height: 6),
        LineaDelPedido(estado: estado),
      ],
    ),
  );
}

class PantallaMisPresupuestos extends StatefulWidget {
  const PantallaMisPresupuestos({super.key});

  @override
  State<PantallaMisPresupuestos> createState() => _PantallaMisPresupuestosState();
}

class _PantallaMisPresupuestosState extends State<PantallaMisPresupuestos> {
  List<Map<String, dynamic>>? _lista;
  bool _cargando = true;
  bool _soloAbiertos = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await misPedidosDePresupuesto();
    if (mounted) setState(() { _lista = lista; _cargando = false; });
  }

  @override
  Widget build(BuildContext context) {
    final todos = _lista ?? [];
    const cerrados = ['Aprobado', 'Rechazado', 'Descartado'];
    final lista = _soloAbiertos ? todos.where((p) => !cerrados.contains(p['estado_visible'])).toList() : todos;
    return Scaffold(
      backgroundColor: sonFondo,
      appBar: AppBar(title: Text('Mis pedidos de presupuesto', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)), backgroundColor: sonFondo),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Antes de volver al cliente, fijate si ya se le mandó el presupuesto.', style: TextStyle(color: sonTextoSuave)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Solo los que siguen abiertos'),
                    value: _soloAbiertos,
                    onChanged: (valor) => setState(() => _soloAbiertos = valor),
                  ),
                  if (_lista == null) Text('Sin conexión y sin datos guardados.', style: TextStyle(color: sonTextoSuave)),
                  if (_lista != null && lista.isEmpty) Text('No hay pedidos para mostrar.', style: TextStyle(color: sonTextoSuave)),
                  if (lista.isNotEmpty)
                    Container(
                      decoration: decoracionTarjeta(),
                      child: Column(
                        children: [
                          for (var i = 0; i < lista.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            filaPedido(lista[i]),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// En el detalle de una orden: lo que vence y lo que se pidió presupuestar en ese cliente.
class ResumenDelCliente extends StatefulWidget {
  final Map orden;
  const ResumenDelCliente({super.key, required this.orden});

  @override
  State<ResumenDelCliente> createState() => _ResumenDelClienteState();
}

class _ResumenDelClienteState extends State<ResumenDelCliente> {
  List<Map<String, dynamic>> _vencimientos = [];
  List<Map<String, dynamic>> _pedidos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  bool _esDelCliente(Map item) {
    final empresaId = widget.orden['empresa_id'];
    if (empresaId != null && item['empresa_id'] != null) return item['empresa_id'] == empresaId;
    return '${item['empresa'] ?? ''}'.trim().toLowerCase() == '${widget.orden['cliente'] ?? ''}'.trim().toLowerCase();
  }

  Future<void> _cargar() async {
    final vencimientos = await vencimientosDeMisClientes() ?? [];
    final pedidos = await misPedidosDePresupuesto() ?? [];
    const cerrados = ['Aprobado', 'Rechazado', 'Descartado'];
    if (!mounted) return;
    setState(() {
      _vencimientos = vencimientos.where(_esDelCliente).toList();
      _pedidos = pedidos.where((p) => _esDelCliente(p) && !cerrados.contains(p['estado_visible'])).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_vencimientos.isEmpty && _pedidos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_vencimientos.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Vencimientos de este cliente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: sonTexto)),
          const SizedBox(height: 8),
          Container(decoration: decoracionTarjeta(), child: Column(children: _vencimientos.map((v) => filaVencimiento(v, conEmpresa: false)).toList())),
        ],
        if (_pedidos.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Presupuestos pedidos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: sonTexto)),
          const SizedBox(height: 8),
          Container(
            decoration: decoracionTarjeta(),
            child: Column(
              children: [
                for (var i = 0; i < _pedidos.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  filaPedido(_pedidos[i], conEmpresa: false),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
