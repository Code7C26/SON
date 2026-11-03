import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:son_admin/config/api_config.dart';
import 'package:son_admin/pantallas/armar_presupuesto.dart';
import 'package:son_admin/pantallas/piezas.dart';
import 'package:son_admin/pantallas/por_presupuestar.dart';
import 'package:son_admin/services/abrir_informe.dart';
import 'package:son_admin/services/api.dart';
import 'package:son_admin/services/sesion.dart';
import 'package:son_admin/theme/tema.dart';

const List<String> estadosPresupuesto = ['Borrador', 'Enviado', 'Negociando', 'Aceptado', 'Rechazado'];
const List<String> prioridadesPresupuesto = ['baja', 'media', 'alta'];

/// En el tablero, "Enviado" se muestra como "Contactar": ya salió y hay que hacer el seguimiento.
String etiquetaDeColumna(String estado) => estado == 'Enviado' ? 'Contactar' : estado;

Color colorDePrioridad(String? prioridad) => switch (prioridad) {
      'alta' => sonRojo,
      'baja' => sonTextoSuave,
      _ => sonAmbar,
    };

String fechaDia(String? fecha) {
  final partes = (fecha ?? '').split('-');
  if (partes.length != 3) return fecha ?? '';
  return '${partes[2]}/${partes[1]}/${partes[0]}';
}

bool _vencido(Map<String, dynamic> p) {
  final limite = '${p['fechaLimite'] ?? ''}';
  if (limite.length < 10) return false;
  final estado = '${p['estado']}';
  if (estado != 'Enviado' && estado != 'Negociando') return false;
  final hoy = DateTime.now();
  final marca = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
  return limite.compareTo(marca) < 0;
}

/// Presupuestos: tablero de seguimiento, lista y notas de los técnicos.
class PantallaPresupuestos extends StatefulWidget {
  final VoidCallback? onCambioNotas;
  final bool abrirNotas;

  const PantallaPresupuestos({super.key, this.onCambioNotas, this.abrirNotas = false});

  @override
  State<PantallaPresupuestos> createState() => _PantallaPresupuestosState();
}

class _PantallaPresupuestosState extends State<PantallaPresupuestos> with SingleTickerProviderStateMixin {
  late final TabController _pestanas = TabController(length: 3, vsync: this, initialIndex: widget.abrirNotas ? 2 : 0);
  List<Map<String, dynamic>> _lista = [];
  bool _cargando = true;
  String? _error;
  String _filtro = '';
  final TextEditingController _busqueda = TextEditingController();

  @override
  void initState() {
    super.initState();
    _busqueda.addListener(() => setState(() {}));
    _pestanas.addListener(() => setState(() {}));
    _cargar();
  }

  @override
  void dispose() {
    _pestanas.dispose();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (!_cargando) setState(() => _cargando = true);
    try {
      final respuesta = await apiGet('/api/presupuestos');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        setState(() {
          _lista = (json.decode(respuesta.body) as List).map((p) => Map<String, dynamic>.from(p as Map)).toList();
          _error = null;
          _cargando = false;
        });
      } else {
        setState(() {
          _error = mensajeError(respuesta, 'No se pudo leer la lista de presupuestos');
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _cargando = false; });
    }
  }

  Future<void> _abrir({int? id, List<Map<String, dynamic>>? notas}) async {
    final cambiado = await armarPresupuesto(context, id: id, notas: notas);
    if (cambiado && mounted) _cargar();
  }

  Future<void> _ver(Map<String, dynamic> fila) async {
    if (fila['estado'] == 'Borrador') {
      await _abrir(id: (fila['id'] as num).toInt());
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _DialogoPresupuesto(id: (fila['id'] as num).toInt(), alCambiar: _cargar),
    );
    if (mounted) _cargar();
  }

  Future<void> _mover(Map<String, dynamic> fila, String estado) async {
    try {
      final respuesta = await apiSend('PUT', '/api/presupuestos/${fila['id']}/estado', json.encode({'estado': estado}));
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(respuesta, 'No se pudo mover'))));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(mensajeSinConexion)));
    }
  }

  List<Map<String, dynamic>> get _visibles {
    return _lista.where((p) {
      if (_filtro.isNotEmpty && p['estado'] != _filtro) return false;
      return coincideBusqueda('${p['etiqueta']} ${p['cliente']} ${p['estado']} ${p['responsable'] ?? ''}', _busqueda.text);
    }).toList();
  }

  Widget _tarjeta(Map<String, dynamic> p) {
    final estado = '${p['estado']}';
    final mensual = p['totalMensual'] as num? ?? 0;
    final unico = p['totalUnico'] as num? ?? 0;
    return InkWell(
      key: Key('presupuesto_${p['id']}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => _ver(p),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
        decoration: decoracionTarjeta(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Nº ${p['etiqueta']}', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4)),
                const Spacer(),
                EtiquetaEstado(texto: etiquetaDeColumna(estado), color: colorEstadoPresupuesto(estado)),
              ],
            ),
            const SizedBox(height: 10),
            Text('${p['cliente']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold, fontSize: 17, height: 1.25)),
            const SizedBox(height: 8),
            DatoConIcono(icono: Icons.event_outlined, texto: fechaDia('${p['fecha']}')),
            if ('${p['responsable'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: DatoConIcono(icono: Icons.person_outline, texto: '${p['responsable']}')),
            const Spacer(),
            if (mensual > 0) Text('Mensual ${pesos(mensual)}', style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600)),
            if (unico > 0) Text('Pago único ${pesos(unico)}', style: TextStyle(color: sonTextoSuave, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              EtiquetaEstado(texto: textoDeMargen('${p['nivelMargen']}'), color: colorDeMargen('${p['nivelMargen']}')),
              if (p['facturado'] == true) EtiquetaEstado(texto: 'Facturado', color: sonLightGreen),
              if (_vencido(p)) EtiquetaEstado(texto: 'Vencido', color: sonRojo),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _cuerpoLista() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, style: TextStyle(color: sonRojo)), SizedBox(height: 12), OutlinedButton.icon(onPressed: _cargar, icon: Icon(Icons.refresh), label: Text('Reintentar'))]));
    }
    if (_lista.isEmpty) {
      return Center(child: Text('Todavía no hay presupuestos. Armá el primero con "Nuevo presupuesto".', style: TextStyle(color: sonTextoSuave)));
    }
    final visibles = _visibles;
    if (visibles.isEmpty) return Center(child: Text('No hay presupuestos con ese filtro.', style: TextStyle(color: sonTextoSuave)));
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 380, mainAxisExtent: 250, crossAxisSpacing: 18, mainAxisSpacing: 18),
      itemCount: visibles.length,
      itemBuilder: (_, i) => _tarjeta(visibles[i]),
    );
  }

  Widget _kpis() {
    final visibles = _visibles;
    int de(String estado) => visibles.where((p) => p['estado'] == estado).length;
    final aceptados = de('Aceptado');
    final rechazados = de('Rechazado');
    final cerrados = aceptados + rechazados;
    final conversion = cerrados == 0 ? null : (aceptados * 100 / cerrados).round();
    final vencidos = visibles.where(_vencido).length;
    Widget ficha(String titulo, String valor, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: decoracionTarjeta(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TextStyle(color: sonTextoSuave, fontSize: 12)),
                const SizedBox(height: 4),
                Text(valor, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 22)),
              ],
            ),
          ),
        );
    return Row(children: [
      ficha('Por contactar', '${de('Enviado')}', sonAzul),
      const SizedBox(width: 10),
      ficha('Negociando', '${de('Negociando')}', sonAmbar),
      const SizedBox(width: 10),
      ficha('Aceptados', '$aceptados', sonLightGreen),
      const SizedBox(width: 10),
      ficha('Conversión', conversion == null ? '—' : '$conversion %', sonTexto),
      if (vencidos > 0) ...[const SizedBox(width: 10), ficha('Vencidos', '$vencidos', sonRojo)],
    ]);
  }

  Widget _columnaTablero(String estado) {
    final items = _visibles.where((p) => p['estado'] == estado).toList();
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(color: sonTarjeta.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14), border: Border.all(color: sonBorde)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EtiquetaEstado(texto: etiquetaDeColumna(estado), color: colorEstadoPresupuesto(estado)),
              const Spacer(),
              Text('${items.length}', style: TextStyle(color: sonTextoSuave, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text('Nada acá', style: TextStyle(color: sonTextoSuave, fontSize: 12.5)))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _tarjetaTablero(items[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaTablero(Map<String, dynamic> p) {
    final mensual = p['totalMensual'] as num? ?? 0;
    final unico = p['totalUnico'] as num? ?? 0;
    final vencida = _vencido(p);
    return InkWell(
      key: Key('tablero_${p['id']}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _ver(p),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: sonTarjetaAlta,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: vencida ? sonRojo : sonBorde),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: colorDePrioridad('${p['prioridad']}'), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text('Nº ${p['etiqueta']}', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, fontSize: 12))),
                PopupMenuButton<String>(
                  tooltip: 'Mover',
                  padding: EdgeInsets.zero,
                  onSelected: (estado) => _mover(p, estado),
                  itemBuilder: (_) => [
                    for (final e in estadosPresupuesto.where((e) => e != p['estado']))
                      PopupMenuItem(value: e, child: Text('Pasar a ${etiquetaDeColumna(e)}')),
                  ],
                  child: Icon(Icons.more_vert, size: 18, color: sonTextoSuave),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${p['cliente']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.25)),
            const SizedBox(height: 6),
            if (mensual > 0) Text(pesos(mensual), style: const TextStyle(fontSize: 13)),
            if (unico > 0 && mensual == 0) Text(pesos(unico), style: const TextStyle(fontSize: 13)),
            if ('${p['responsable'] ?? ''}'.isNotEmpty)
              Padding(padding: EdgeInsets.only(top: 4), child: Text('${p['responsable']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTextoSuave, fontSize: 12))),
            if ('${p['fechaLimite'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(vencida ? 'Venció ${fechaDia('${p['fechaLimite']}')}' : 'Hasta ${fechaDia('${p['fechaLimite']}')}', style: TextStyle(color: vencida ? sonRojo : sonTextoSuave, fontSize: 12)),
              ),
            if (p['facturado'] == true) Padding(padding: EdgeInsets.only(top: 4), child: EtiquetaEstado(texto: 'Facturado', color: sonLightGreen)),
          ],
        ),
      ),
    );
  }

  Widget _tablero() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, style: TextStyle(color: sonRojo)), SizedBox(height: 12), OutlinedButton.icon(onPressed: _cargar, icon: Icon(Icons.refresh), label: Text('Reintentar'))]));
    }
    if (_lista.isEmpty) {
      return Center(child: Text('Todavía no hay presupuestos. Armá el primero con "Nuevo presupuesto".', style: TextStyle(color: sonTextoSuave)));
    }
    return Column(
      children: [
        _kpis(),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [for (final estado in estadosPresupuesto) _columnaTablero(estado)],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final enNotas = _pestanas.index == 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Presupuestos', style: estiloTituloPantalla),
                  ],
                ),
              ),
              if (!enNotas)
                ElevatedButton.icon(
                  key: const Key('nuevo_presupuesto'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18)),
                  icon: Icon(Icons.add, color: sonDarkGreen),
                  label: Text('Nuevo presupuesto', style: TextStyle(color: sonDarkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                  onPressed: () => _abrir(),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _pestanas,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Tablero'),
              Tab(text: 'Lista'),
              Tab(key: Key('tab_notas'), text: 'Notas de técnicos'),
            ],
          ),
          if (!enNotas) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    key: const Key('buscar_presupuesto'),
                    controller: _busqueda,
                    decoration: InputDecoration(
                      hintText: 'Buscar por número, cliente o responsable...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      suffixIcon: _busqueda.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _busqueda.clear),
                    ),
                  ),
                ),
                if (_pestanas.index == 1) ...[
                  PildoraFiltro(texto: 'Todos', activo: _filtro.isEmpty, alTocar: () => setState(() => _filtro = '')),
                  for (final estado in estadosPresupuesto)
                    PildoraFiltro(
                      texto: etiquetaDeColumna(estado),
                      activo: _filtro == estado,
                      color: colorEstadoPresupuesto(estado),
                      alTocar: () => setState(() => _filtro = estado),
                    ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _pestanas,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _tablero(),
                _cuerpoLista(),
                PantallaPorPresupuestar(embebida: true, onCambio: widget.onCambioNotas),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Detalle de un presupuesto que ya se envió: ver, PDF, seguimiento, cambiar estado o crear una versión "act".
class _DialogoPresupuesto extends StatefulWidget {
  final int id;
  final VoidCallback alCambiar;
  const _DialogoPresupuesto({required this.id, required this.alCambiar});

  @override
  State<_DialogoPresupuesto> createState() => _DialogoPresupuestoState();
}

class _DialogoPresupuestoState extends State<_DialogoPresupuesto> {
  Map<String, dynamic>? _detalle;
  String? _error;
  bool _cargando = true;
  bool _ocupado = false;
  String _prioridad = 'media';
  bool _facturado = false;
  late final TextEditingController _responsable = TextEditingController();
  late final TextEditingController _fechaLimite = TextEditingController();
  late final TextEditingController _nota = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _responsable.dispose();
    _fechaLimite.dispose();
    _nota.dispose();
    super.dispose();
  }

  void _llenar(Map<String, dynamic> d) {
    _detalle = d;
    _prioridad = '${d['prioridad'] ?? 'media'}';
    if (!prioridadesPresupuesto.contains(_prioridad)) _prioridad = 'media';
    _facturado = d['facturado'] == true;
    _responsable.text = '${d['responsable'] ?? ''}';
    _fechaLimite.text = '${d['fechaLimite'] ?? ''}';
    _nota.text = '${d['notaSeguimiento'] ?? ''}';
  }

  Future<void> _cargar() async {
    try {
      final respuesta = await apiGet('/api/presupuestos/${widget.id}');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        setState(() {
          _llenar(Map<String, dynamic>.from(json.decode(respuesta.body) as Map));
          _error = null;
          _cargando = false;
        });
      } else {
        setState(() { _error = mensajeError(respuesta, 'No se pudo leer el presupuesto'); _cargando = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _cargando = false; });
    }
  }

  Future<void> _estado(String estado) async {
    setState(() => _ocupado = true);
    try {
      final respuesta = await apiSend('PUT', '/api/presupuestos/${widget.id}/estado', json.encode({'estado': estado}));
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        widget.alCambiar();
        setState(() {
          _llenar(Map<String, dynamic>.from(json.decode(respuesta.body) as Map));
          _ocupado = false;
        });
      } else {
        setState(() { _error = mensajeError(respuesta, 'No se pudo cambiar el estado'); _ocupado = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _ocupado = false; });
    }
  }

  Future<void> _guardarSeguimiento() async {
    setState(() => _ocupado = true);
    try {
      final respuesta = await apiSend(
        'PUT',
        '/api/presupuestos/${widget.id}/seguimiento',
        json.encode({
          'prioridad': _prioridad,
          'responsable': _responsable.text,
          'fechaLimite': _fechaLimite.text.trim(),
          'facturado': _facturado,
          'notaSeguimiento': _nota.text,
        }),
      );
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        widget.alCambiar();
        setState(() {
          _llenar(Map<String, dynamic>.from(json.decode(respuesta.body) as Map));
          _ocupado = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seguimiento guardado')));
      } else {
        setState(() { _error = mensajeError(respuesta, 'No se pudo guardar el seguimiento'); _ocupado = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _ocupado = false; });
    }
  }

  Future<void> _actualizar({required bool repreciar}) async {
    setState(() => _ocupado = true);
    try {
      final respuesta = await apiSend('POST', '/api/presupuestos/${widget.id}/actualizar', json.encode({'repreciar': repreciar}));
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        final nuevo = Map<String, dynamic>.from(json.decode(respuesta.body) as Map);
        widget.alCambiar();
        if (!context.mounted) return;
        final nav = Navigator.of(context);
        nav.pop();
        await nav.push<bool>(
          MaterialPageRoute(builder: (_) => PantallaArmarPresupuesto(presupuestoId: (nuevo['id'] as num).toInt())),
        );
      } else {
        setState(() { _error = mensajeError(respuesta, 'No se pudo crear la versión actualizada'); _ocupado = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _ocupado = false; });
    }
  }

  void _pdf() {
    abrirInforme('$apiBaseUrl/api/presupuestos/${widget.id}/pdf?token=${SesionAdmin.token}');
  }

  Future<void> _elegirFecha() async {
    final partes = _fechaLimite.text.split('-');
    final inicial = partes.length == 3 ? DateTime.tryParse(_fechaLimite.text) : DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: inicial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 800)),
    );
    if (elegida == null) return;
    _fechaLimite.text = '${elegida.year}-${elegida.month.toString().padLeft(2, '0')}-${elegida.day.toString().padLeft(2, '0')}';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final d = _detalle;
    final calculo = d == null ? null : Map<String, dynamic>.from(d['calculo'] as Map? ?? {});
    return AlertDialog(
      title: Text(d == null ? 'Presupuesto' : 'Presupuesto ${d['etiqueta']}'),
      content: SizedBox(
        width: 560,
        child: _cargando
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : d == null
                ? Text(_error ?? 'No se pudo leer')
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          EtiquetaEstado(texto: etiquetaDeColumna('${d['estado']}'), color: colorEstadoPresupuesto('${d['estado']}')),
                          EtiquetaEstado(texto: textoDeMargen('${calculo?['nivelMargen']}'), color: colorDeMargen('${calculo?['nivelMargen']}')),
                        ]),
                        const SizedBox(height: 12),
                        Text('${(d['cliente'] as Map?)?['razonSocial'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        if ((calculo?['totalMensual'] as num? ?? 0) > 0) Text('Total mensual ${pesos(calculo!['totalMensual'] as num)}', style: const TextStyle(fontSize: 15)),
                        if ((calculo?['totalUnico'] as num? ?? 0) > 0) Text('Pago único ${pesos(calculo!['totalUnico'] as num)}'),
                        if (d['bonificacion'] != 0) Text('Bonificación ${d['bonificacion']} %', style: TextStyle(color: sonTextoSuave)),
                        const SizedBox(height: 16),
                        Text('SEGUIMIENTO', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1)),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _prioridad,
                              decoration: const InputDecoration(labelText: 'Prioridad', isDense: true),
                              items: const [
                                DropdownMenuItem(value: 'baja', child: Text('Baja')),
                                DropdownMenuItem(value: 'media', child: Text('Media')),
                                DropdownMenuItem(value: 'alta', child: Text('Alta')),
                              ],
                              onChanged: _ocupado ? null : (v) => setState(() => _prioridad = v ?? 'media'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: TextField(key: const Key('seguimiento_responsable'), controller: _responsable, enabled: !_ocupado, decoration: const InputDecoration(labelText: 'Responsable', isDense: true))),
                        ]),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _fechaLimite,
                          readOnly: true,
                          onTap: _ocupado ? null : _elegirFecha,
                          decoration: InputDecoration(
                            labelText: 'Fecha límite',
                            isDense: true,
                            suffixIcon: IconButton(tooltip: 'Elegir fecha', onPressed: _ocupado ? null : _elegirFecha, icon: const Icon(Icons.event_outlined)),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Ya se facturó'),
                          value: _facturado,
                          onChanged: _ocupado ? null : (v) => setState(() => _facturado = v),
                        ),
                        TextField(controller: _nota, enabled: !_ocupado, maxLines: 2, decoration: const InputDecoration(labelText: 'Nota de seguimiento')),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton(onPressed: _ocupado ? null : _guardarSeguimiento, child: const Text('Guardar seguimiento')),
                        ),
                        const SizedBox(height: 8),
                        for (final item in (d['items'] as List? ?? []))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('· ${item['descripcion']}', style: TextStyle(color: sonTextoSuave, height: 1.3)),
                          ),
                        if ((calculo?['avisos'] as List? ?? []).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (final aviso in (calculo!['avisos'] as List))
                            Text('${aviso['mensaje']}', style: TextStyle(color: sonAmbar, fontSize: 13)),
                        ],
                        if (_error != null) Padding(padding: EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: sonRojo))),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cerrar', style: TextStyle(color: sonTextoSuave))),
        if (d != null) TextButton.icon(onPressed: _pdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Ver PDF')),
        if (d != null && d['esUltimaVersion'] == true && !_ocupado)
          PopupMenuButton<String>(
            tooltip: 'Cambiar estado',
            onSelected: _estado,
            itemBuilder: (_) => [
              for (final e in estadosPresupuesto.where((e) => e != d['estado'] && e != 'Borrador'))
                PopupMenuItem(value: e, child: Text(etiquetaDeColumna(e))),
            ],
            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text('Estado')),
          ),
        if (d != null && d['esUltimaVersion'] == true)
          ElevatedButton(
            onPressed: _ocupado ? null : () => _actualizar(repreciar: true),
            child: const Text('Actualizar (act)'),
          ),
      ],
    );
  }
}
