import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:son_admin/config/api_config.dart';
import 'package:son_admin/pantallas/piezas.dart';
import 'package:son_admin/services/abrir_informe.dart';
import 'package:son_admin/services/api.dart';
import 'package:son_admin/services/sesion.dart';
import 'package:son_admin/theme/tema.dart';
import 'package:son_admin/ui/componentes.dart';

// CRM comercial dentro de Presupuestos (lo que hacía el "CRM Comercial SIMA"):
//  - Clientes y contactos: semáforo de días sin contacto según el tipo de cliente, y la ficha con la
//    bitácora (llamadas, visitas, mails...) y los pendientes con fecha y responsable.
//  - Pendientes: los compromisos de todos los clientes, del más atrasado al más lejano.
//  - Conversión: de los presupuestos enviados, cuántos se ganaron, por servicio, por responsable y
//    por qué se perdieron.

String _dos(int n) => n.toString().padLeft(2, '0');
String _iso(DateTime fecha) => '${fecha.year}-${_dos(fecha.month)}-${_dos(fecha.day)}';
String _hoy() => _iso(DateTime.now());
String _fechaTexto(dynamic iso) {
  final partes = '${iso ?? ''}'.split('-');
  if (partes.length < 3) return '';
  return '${partes[2].substring(0, 2)}/${partes[1]}/${partes[0].substring(2)}';
}

Color colorAlerta(String estado) => switch (estado) {
      'rojo' => sonRojo,
      'amarillo' => sonAmbar,
      'verde' => sonLightGreen,
      _ => sonTextoSuave,
    };

String textoAlerta(Map alerta) {
  final estado = '${alerta['estado']}';
  if (estado == 'sin') return 'Sin contacto';
  final dias = (alerta['dias'] as num?)?.toInt() ?? 0;
  return dias == 0 ? 'Hoy' : (dias == 1 ? 'Hace 1 día' : 'Hace $dias días');
}

/// Configuración del CRM (tipos de cliente con sus umbrales, servicios, responsables, razones de pérdida).
class ConfigCrm {
  static Map<String, dynamic>? _cache;

  static Future<Map<String, dynamic>> leer({bool forzar = false}) async {
    if (_cache != null && !forzar) return _cache!;
    try {
      final respuesta = await apiGet('/api/crm/config');
      if (respuesta.statusCode == 200) _cache = Map<String, dynamic>.from(json.decode(respuesta.body) as Map);
    } catch (_) {}
    return _cache ?? {'umbrales': {'Prospecto': 7, 'Mensualizado': 30, 'Eventual': 60, 'Ex Cliente': 180, 'Otro': 60}, 'tiposNota': ['Visita', 'Llamada', 'Mail', 'WhatsApp', 'Reunión', 'Interna'], 'servicios': <String>[], 'responsables': <String>[], 'razonesPerdida': <String>[]};
  }

  static List<String> lista(Map<String, dynamic> config, String clave) => (config[clave] as List? ?? []).map((e) => '$e').toList();
  static List<String> tiposCliente(Map<String, dynamic> config) => (config['umbrales'] as Map? ?? {}).keys.map((e) => '$e').toList();

  static void olvidar() => _cache = null;
}

Widget _botonesPlanilla() => PopupMenuButton<String>(
      tooltip: 'Planilla para Excel',
      onSelected: (tipo) => abrirInforme('$apiBaseUrl/api/crm/planilla?tipo=$tipo&token=${SesionAdmin.token}'),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'clientes', child: Text('Clientes y días sin contacto')),
        PopupMenuItem(value: 'presupuestos', child: Text('Presupuestos')),
        PopupMenuItem(value: 'bitacora', child: Text('Bitácora y pendientes')),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.table_view_outlined, size: 18), SizedBox(width: 6), Text('Exportar Excel')]),
      ),
    );

// =====================================================================
// CLIENTES Y CONTACTOS
// =====================================================================
class PestanaClientesCrm extends StatefulWidget {
  const PestanaClientesCrm({super.key});

  @override
  State<PestanaClientesCrm> createState() => _PestanaClientesCrmState();
}

class _PestanaClientesCrmState extends State<PestanaClientesCrm> {
  List<Map<String, dynamic>> _clientes = [];
  Map<String, dynamic> _config = {};
  bool _cargando = true;
  String? _error;
  String _alerta = '';
  String _tipo = '';
  final TextEditingController _busqueda = TextEditingController();

  @override
  void initState() {
    super.initState();
    _busqueda.addListener(() => setState(() {}));
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final config = await ConfigCrm.leer();
      final respuesta = await apiGet('/api/crm/clientes');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        setState(() {
          _config = config;
          _clientes = (json.decode(respuesta.body) as List).map((c) => Map<String, dynamic>.from(c as Map)).toList();
          _cargando = false;
          _error = null;
        });
      } else {
        setState(() { _error = mensajeError(respuesta, 'No se pudieron leer los clientes'); _cargando = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _cargando = false; });
    }
  }

  Future<void> _cambiarTipo(Map c, String? tipo) async {
    try {
      final respuesta = await apiSend('PUT', '/api/crm/clientes/${c['id']}', json.encode({'tipo_cliente': tipo}));
      if (respuesta.statusCode == 200) _cargar();
    } catch (_) {}
  }

  Future<void> _abrirFicha(Map<String, dynamic> c) async {
    await abrirFichaCrm(context, c);
    if (mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EstadoError(
        mensaje: _error!,
        alReintentar: () {
          setState(() => _cargando = true);
          _cargar();
        },
      );
    }
    const orden = {'rojo': 0, 'amarillo': 1, 'sin': 2, 'verde': 3};
    final visibles = _clientes.where((c) {
      final alerta = '${(c['alerta'] as Map?)?['estado'] ?? 'sin'}';
      if (_alerta.isNotEmpty && alerta != _alerta) return false;
      if (_tipo.isNotEmpty && '${c['tipo_cliente'] ?? ''}' != _tipo) return false;
      return coincideBusqueda('${c['razon_social']} ${c['contacto'] ?? ''}', _busqueda.text);
    }).toList()
      ..sort((a, b) {
        final ea = orden['${(a['alerta'] as Map?)?['estado']}'] ?? 9;
        final eb = orden['${(b['alerta'] as Map?)?['estado']}'] ?? 9;
        if (ea != eb) return ea.compareTo(eb);
        final da = ((a['alerta'] as Map?)?['dias'] as num?) ?? 0;
        final db = ((b['alerta'] as Map?)?['dias'] as num?) ?? 0;
        return db.compareTo(da);
      });
    final cuenta = {for (final e in ['rojo', 'amarillo', 'verde', 'sin']) e: _clientes.where((c) => (c['alerta'] as Map?)?['estado'] == e).length};
    final tipos = ConfigCrm.tiposCliente(_config);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(controller: _busqueda, decoration: const InputDecoration(hintText: 'Buscar empresa o contacto...', prefixIcon: Icon(Icons.search, size: 20), isDense: true)),
            ),
            PildoraFiltro(texto: 'Todos', activo: _alerta.isEmpty, alTocar: () => setState(() => _alerta = '')),
            PildoraFiltro(texto: 'Sin contacto hace mucho · ${cuenta['rojo']}', activo: _alerta == 'rojo', color: sonRojo, alTocar: () => setState(() => _alerta = 'rojo')),
            PildoraFiltro(texto: 'Por vencer · ${cuenta['amarillo']}', activo: _alerta == 'amarillo', color: sonAmbar, alTocar: () => setState(() => _alerta = 'amarillo')),
            PildoraFiltro(texto: 'Al día · ${cuenta['verde']}', activo: _alerta == 'verde', color: sonLightGreen, alTocar: () => setState(() => _alerta = 'verde')),
            PildoraFiltro(texto: 'Sin registro · ${cuenta['sin']}', activo: _alerta == 'sin', alTocar: () => setState(() => _alerta = 'sin')),
            DropdownButton<String>(
              value: _tipo,
              underline: const SizedBox.shrink(),
              items: [const DropdownMenuItem(value: '', child: Text('Todos los tipos')), ...tipos.map((t) => DropdownMenuItem(value: t, child: Text(t)))],
              onChanged: (valor) => setState(() => _tipo = valor ?? ''),
            ),
            _botonesPlanilla(),
            IconButton(
              tooltip: 'Configurar CRM',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () async {
                final cambio = await abrirConfigCrm(context);
                if (cambio && mounted) _cargar();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: decoracionTarjeta(),
            child: visibles.isEmpty
                ? Center(child: Text('Ningún cliente coincide con el filtro.', style: TextStyle(color: sonTextoSuave)))
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: visibles.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = visibles[i];
                      final alerta = Map<String, dynamic>.from(c['alerta'] as Map? ?? {});
                      final color = colorAlerta('${alerta['estado']}');
                      final tipo = '${c['tipo_cliente'] ?? ''}';
                      return ListTile(
                        onTap: () => _abrirFicha(c),
                        leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        title: Text('${c['razon_social']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          if ('${c['contacto'] ?? ''}'.isNotEmpty) '${c['contacto']}',
                          c['ultimo_contacto'] == null ? 'Nunca contactado' : 'Último contacto ${_fechaTexto(c['ultimo_contacto'])}',
                          'umbral ${alerta['umbral']} días',
                        ].join(' · ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((c['pendientes'] as num? ?? 0) > 0) ...[EtiquetaEstado(texto: '${c['pendientes']} pend.', color: sonAmbar), const SizedBox(width: 6)],
                            if ((c['presupuestos_abiertos'] as num? ?? 0) > 0) ...[EtiquetaEstado(texto: '${c['presupuestos_abiertos']} presup.', color: sonAzul), const SizedBox(width: 6)],
                            EtiquetaEstado(texto: textoAlerta(alerta), color: color),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: tipos.contains(tipo) ? tipo : null,
                              hint: const Text('Tipo'),
                              underline: const SizedBox.shrink(),
                              items: tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                              onChanged: (valor) => _cambiarTipo(c, valor),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// FICHA DEL CLIENTE: nota rápida y bitácora
// =====================================================================
Future<void> abrirFichaCrm(BuildContext context, Map<String, dynamic> cliente) {
  return showDialog<void>(context: context, builder: (_) => _FichaCrm(cliente: cliente));
}

class _FichaCrm extends StatefulWidget {
  final Map<String, dynamic> cliente;
  const _FichaCrm({required this.cliente});

  @override
  State<_FichaCrm> createState() => _FichaCrmState();
}

class _FichaCrmState extends State<_FichaCrm> {
  List<Map<String, dynamic>> _notas = [];
  Map<String, dynamic> _config = {};
  bool _cargando = true;
  bool _ocupado = false;
  String? _error;
  final _texto = TextEditingController();
  final _pendiente = TextEditingController();
  String _tipoNota = 'Llamada';
  DateTime _fecha = DateTime.now();
  DateTime? _pendienteFecha;
  String? _responsable;
  bool _conPendiente = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _texto.dispose();
    _pendiente.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final config = await ConfigCrm.leer();
      final respuesta = await apiGet('/api/crm/notas?empresaId=${widget.cliente['id']}');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        setState(() {
          _config = config;
          _notas = (json.decode(respuesta.body) as List).map((n) => Map<String, dynamic>.from(n as Map)).toList();
          _cargando = false;
        });
      } else {
        setState(() { _error = mensajeError(respuesta); _cargando = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _cargando = false; });
    }
  }

  Future<void> _guardar() async {
    if (_texto.text.trim().isEmpty && !(_conPendiente && _pendiente.text.trim().isNotEmpty)) {
      setState(() => _error = 'Escribí la nota o el pendiente');
      return;
    }
    setState(() { _ocupado = true; _error = null; });
    try {
      final respuesta = await apiSend('POST', '/api/crm/notas', json.encode({
        'empresaId': widget.cliente['id'],
        'fecha': _iso(_fecha),
        'tipo': _tipoNota,
        'texto': _texto.text.trim(),
        if (_conPendiente) 'pendiente': _pendiente.text.trim(),
        if (_conPendiente && _pendienteFecha != null) 'pendienteFecha': _iso(_pendienteFecha!),
        if (_conPendiente) 'pendienteResponsable': _responsable,
      }));
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        _texto.clear();
        _pendiente.clear();
        setState(() { _conPendiente = false; _pendienteFecha = null; _ocupado = false; _fecha = DateTime.now(); });
        _cargar();
      } else {
        setState(() { _error = mensajeError(respuesta); _ocupado = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _ocupado = false; });
    }
  }

  Future<void> _tildar(Map n, bool hecho) async {
    try {
      final respuesta = await apiSend('PUT', '/api/crm/notas/${n['id']}', json.encode({'pendienteHecho': hecho}));
      if (respuesta.statusCode == 200) _cargar();
    } catch (_) {}
  }

  Future<void> _borrar(Map n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('¿Borrar la nota?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(dialogo, true), child: Text('Borrar', style: TextStyle(color: sonRojo))),
        ],
      ),
    );
    if (ok != true) return;
    await apiSend('DELETE', '/api/crm/notas/${n['id']}');
    _cargar();
  }

  Future<DateTime?> _elegirFecha(DateTime? inicial) => showDatePicker(
        context: context,
        initialDate: inicial ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 730)),
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;
    final alerta = Map<String, dynamic>.from(c['alerta'] as Map? ?? {});
    final tiposNota = ConfigCrm.lista(_config, 'tiposNota');
    final responsables = ConfigCrm.lista(_config, 'responsables');
    if (tiposNota.isNotEmpty && !tiposNota.contains(_tipoNota)) _tipoNota = tiposNota.first;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text('${c['razon_social']}')),
          if (alerta.isNotEmpty) EtiquetaEstado(texto: textoAlerta(alerta), color: colorAlerta('${alerta['estado']}')),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: _cargando
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        if ('${c['tipo_cliente'] ?? ''}'.isNotEmpty) '${c['tipo_cliente']}',
                        if ('${c['contacto'] ?? ''}'.isNotEmpty) '${c['contacto']}',
                        if ('${c['telefono'] ?? ''}'.isNotEmpty) '${c['telefono']}',
                        if ('${c['email'] ?? ''}'.isNotEmpty) '${c['email']}',
                      ].join(' · '),
                      style: TextStyle(color: sonTextoSuave),
                    ),
                    const SizedBox(height: 14),
                    Text('NOTA RÁPIDA', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1)),
                    const SizedBox(height: 8),
                    TextField(controller: _texto, maxLines: 3, enabled: !_ocupado, decoration: const InputDecoration(hintText: 'Qué pasó con este cliente (llamada, visita, mail...)')),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<String>(
                          value: tiposNota.contains(_tipoNota) ? _tipoNota : null,
                          items: tiposNota.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (valor) => setState(() => _tipoNota = valor ?? 'Llamada'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final elegida = await _elegirFecha(_fecha);
                            if (elegida != null) setState(() => _fecha = elegida);
                          },
                          icon: const Icon(Icons.event_outlined, size: 18),
                          label: Text('${_fecha.day}/${_fecha.month}/${_fecha.year}'),
                        ),
                        FilterChip(label: const Text('Deja un pendiente'), selected: _conPendiente, onSelected: (v) => setState(() => _conPendiente = v)),
                      ],
                    ),
                    if (_conPendiente) ...[
                      const SizedBox(height: 8),
                      TextField(controller: _pendiente, decoration: const InputDecoration(labelText: 'Qué hay que hacer', hintText: 'Ej: Enviar presupuesto de mediciones')),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final elegida = await _elegirFecha(_pendienteFecha);
                              if (elegida != null) setState(() => _pendienteFecha = elegida);
                            },
                            icon: const Icon(Icons.flag_outlined, size: 18),
                            label: Text(_pendienteFecha == null ? 'Para cuándo' : 'Para el ${_pendienteFecha!.day}/${_pendienteFecha!.month}/${_pendienteFecha!.year}'),
                          ),
                          DropdownButton<String?>(
                            value: responsables.contains(_responsable) ? _responsable : null,
                            hint: const Text('Responsable'),
                            items: responsables.map((r) => DropdownMenuItem<String?>(value: r, child: Text(r))).toList(),
                            onChanged: (valor) => setState(() => _responsable = valor),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: ElevatedButton(onPressed: _ocupado ? null : _guardar, child: const Text('Guardar nota'))),
                    if (_error != null) Text(_error!, style: TextStyle(color: sonRojo)),
                    const SizedBox(height: 14),
                    Text('BITÁCORA (${_notas.length})', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1)),
                    const SizedBox(height: 6),
                    if (_notas.isEmpty)
                      Text('Todavía no hay notas. La primera nota de contacto arranca el contador de días.', style: TextStyle(color: sonTextoSuave)),
                    for (final n in _notas)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: decoracionTarjeta(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(_fechaTexto(n['fecha']), style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                EtiquetaEstado(texto: '${n['tipo']}', color: n['tipo'] == 'Interna' ? sonTextoSuave : sonAzul),
                                const SizedBox(width: 8),
                                Expanded(child: Text('${n['autor'] ?? ''}', style: TextStyle(color: sonTextoSuave, fontSize: 12))),
                                IconButton(tooltip: 'Borrar', visualDensity: VisualDensity.compact, icon: Icon(Icons.delete_outline, size: 18, color: sonRojo), onPressed: () => _borrar(n)),
                              ],
                            ),
                            if ('${n['texto'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${n['texto']}')),
                            if (n['pendiente'] != null)
                              Row(
                                children: [
                                  Checkbox(value: n['pendiente_hecho'] == true, onChanged: (v) => _tildar(n, v ?? false)),
                                  Expanded(
                                    child: Text(
                                      [
                                        '${n['pendiente']}',
                                        if (n['pendiente_fecha'] != null) _fechaTexto(n['pendiente_fecha']),
                                        if (n['pendiente_responsable'] != null) '${n['pendiente_responsable']}',
                                      ].join(' · '),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        decoration: n['pendiente_hecho'] == true ? TextDecoration.lineThrough : null,
                                        color: n['pendiente_hecho'] != true && n['pendiente_fecha'] != null && '${n['pendiente_fecha']}'.compareTo(_hoy()) < 0 ? sonRojo : sonTexto,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}

// =====================================================================
// PENDIENTES
// =====================================================================
class PestanaPendientesCrm extends StatefulWidget {
  const PestanaPendientesCrm({super.key});

  @override
  State<PestanaPendientesCrm> createState() => _PestanaPendientesCrmState();
}

class _PestanaPendientesCrmState extends State<PestanaPendientesCrm> {
  List<Map<String, dynamic>> _lista = [];
  bool _cargando = true;
  bool _conHechos = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final respuesta = await apiGet('/api/crm/pendientes${_conHechos ? '?hechos=1' : ''}');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        setState(() {
          _lista = (json.decode(respuesta.body) as List).map((n) => Map<String, dynamic>.from(n as Map)).toList();
          _cargando = false;
          _error = null;
        });
      } else {
        setState(() { _error = mensajeError(respuesta); _cargando = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _cargando = false; });
    }
  }

  Future<void> _tildar(Map n, bool hecho) async {
    try {
      final respuesta = await apiSend('PUT', '/api/crm/notas/${n['id']}', json.encode({'pendienteHecho': hecho}));
      if (respuesta.statusCode == 200) _cargar();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EstadoError(
        mensaje: _error!,
        alReintentar: () {
          setState(() => _cargando = true);
          _cargar();
        },
      );
    }
    final hoy = _hoy();
    final enSiete = _iso(DateTime.now().add(const Duration(days: 7)));
    final grupos = <String, List<Map<String, dynamic>>>{'Vencidos': [], 'Próximos 7 días': [], 'Más adelante': [], 'Sin fecha': [], 'Hechos': []};
    for (final n in _lista) {
      final fecha = n['pendiente_fecha'] as String?;
      if (n['pendiente_hecho'] == true) {
        grupos['Hechos']!.add(n);
      } else if (fecha == null) {
        grupos['Sin fecha']!.add(n);
      } else if (fecha.compareTo(hoy) < 0) {
        grupos['Vencidos']!.add(n);
      } else if (fecha.compareTo(enSiete) <= 0) {
        grupos['Próximos 7 días']!.add(n);
      } else {
        grupos['Más adelante']!.add(n);
      }
    }
    final colores = {'Vencidos': sonRojo, 'Próximos 7 días': sonAmbar, 'Más adelante': sonAzul, 'Sin fecha': sonTextoSuave, 'Hechos': sonLightGreen};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Los pendientes se crean desde la ficha del cliente (Clientes y contactos), marcando "Deja un pendiente".', style: TextStyle(color: sonTextoSuave))),
            FilterChip(
              label: const Text('Mostrar hechos'),
              selected: _conHechos,
              onSelected: (v) {
                setState(() => _conHechos = v);
                _cargar();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _lista.isEmpty
              ? Center(child: Text('No hay pendientes abiertos.', style: TextStyle(color: sonTextoSuave)))
              : ListView(
                  children: [
                    for (final entrada in grupos.entries)
                      if (entrada.value.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 6),
                          child: Row(children: [
                            Text(entrada.key.toUpperCase(), style: TextStyle(color: colores[entrada.key], fontWeight: FontWeight.bold, letterSpacing: 1.1, fontSize: 12)),
                            const SizedBox(width: 8),
                            EtiquetaEstado(texto: '${entrada.value.length}', color: colores[entrada.key]!),
                          ]),
                        ),
                        for (final n in entrada.value)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: decoracionTarjeta(borde: colores[entrada.key]!.withValues(alpha: 0.5)),
                            child: ListTile(
                              leading: Checkbox(value: n['pendiente_hecho'] == true, onChanged: (v) => _tildar(n, v ?? false)),
                              title: Text('${n['pendiente']}', style: TextStyle(fontWeight: FontWeight.w600, decoration: n['pendiente_hecho'] == true ? TextDecoration.lineThrough : null)),
                              subtitle: Text([
                                '${n['empresa']}',
                                if (n['pendiente_responsable'] != null) '${n['pendiente_responsable']}',
                                if ('${n['texto'] ?? ''}'.isNotEmpty) '${n['texto']}'.length > 80 ? '${'${n['texto']}'.substring(0, 80)}…' : '${n['texto']}',
                              ].join(' · ')),
                              trailing: Text(n['pendiente_fecha'] == null ? '—' : _fechaTexto(n['pendiente_fecha']), style: TextStyle(fontWeight: FontWeight.bold, color: colores[entrada.key])),
                            ),
                          ),
                      ],
                  ],
                ),
        ),
      ],
    );
  }
}

// =====================================================================
// CONVERSIÓN
// =====================================================================
class PestanaConversionCrm extends StatefulWidget {
  const PestanaConversionCrm({super.key});

  @override
  State<PestanaConversionCrm> createState() => _PestanaConversionCrmState();
}

class _PestanaConversionCrmState extends State<PestanaConversionCrm> {
  static const List<(String, String)> _periodos = [
    ('mes', 'Este mes'),
    ('mesant', 'Mes anterior'),
    ('trim', 'Este trimestre'),
    ('anio', 'Este año'),
    ('12m', 'Últimos 12 meses'),
    ('todo', 'Todo'),
  ];
  String _periodo = 'trim';
  Map<String, dynamic>? _datos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  (String?, String?) _rango() {
    final hoy = DateTime.now();
    switch (_periodo) {
      case 'mes':
        return (_iso(DateTime(hoy.year, hoy.month, 1)), _iso(hoy));
      case 'mesant':
        return (_iso(DateTime(hoy.year, hoy.month - 1, 1)), _iso(DateTime(hoy.year, hoy.month, 0)));
      case 'trim':
        return (_iso(DateTime(hoy.year, ((hoy.month - 1) ~/ 3) * 3 + 1, 1)), _iso(hoy));
      case 'anio':
        return (_iso(DateTime(hoy.year, 1, 1)), _iso(hoy));
      case '12m':
        return (_iso(hoy.subtract(const Duration(days: 365))), _iso(hoy));
      default:
        return (null, null);
    }
  }

  Future<void> _cargar() async {
    final (desde, hasta) = _rango();
    final filtros = [if (desde != null) 'desde=$desde', if (hasta != null) 'hasta=$hasta'].join('&');
    try {
      final respuesta = await apiGet('/api/crm/conversion${filtros.isEmpty ? '' : '?$filtros'}');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        setState(() { _datos = Map<String, dynamic>.from(json.decode(respuesta.body) as Map); _error = null; });
      } else {
        setState(() => _error = mensajeError(respuesta));
      }
    } catch (_) {
      if (mounted) setState(() => _error = mensajeSinConexion);
    }
  }

  Widget _barra(double fraccion, Color color) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: fraccion.clamp(0, 1), minHeight: 8, color: color, backgroundColor: sonBorde),
      );

  Widget _panel(String titulo, List grupos, {bool razones = false}) {
    final perdidos = (_datos?['perdidos'] as num? ?? 0).toDouble();
    return Container(
      width: 380,
      padding: const EdgeInsets.all(16),
      decoration: decoracionTarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          if (grupos.isEmpty) Text('Sin datos en el período.', style: TextStyle(color: sonTextoSuave)),
          for (final g in grupos)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(razones ? '${g['razon']}' : '${g['nombre']}', overflow: TextOverflow.ellipsis)),
                  Expanded(
                    flex: 2,
                    child: razones
                        ? _barra(perdidos == 0 ? 0 : (g['cantidad'] as num) / perdidos, sonRojo)
                        : _barra((g['enviados'] as num) == 0 ? 0 : (g['ganados'] as num) / (g['enviados'] as num), sonLightGreen),
                  ),
                  const SizedBox(width: 10),
                  Text(razones ? '${g['cantidad']}' : '${g['ganados']}/${g['enviados']}', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (valor, texto) in _periodos)
                ChoiceChip(
                  label: Text(texto),
                  selected: _periodo == valor,
                  onSelected: (_) {
                    setState(() => _periodo = valor);
                    _cargar();
                  },
                ),
              _botonesPlanilla(),
            ],
          ),
          const SizedBox(height: 6),
          Text('Cuenta los presupuestos enviados en el período (tienen fecha de envío). Ganado = Aceptado, perdido = Rechazado.', style: TextStyle(color: sonTextoSuave, fontSize: 13)),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!, style: TextStyle(color: sonRojo)),
          if (d == null && _error == null) const Center(child: CircularProgressIndicator()),
          if (d != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: decoracionTarjeta(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(d['porcentaje'] == null ? '—' : '${d['porcentaje']}%', style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: sonTexto)),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('${d['ganados']} ganados de ${d['enviados']} enviados', style: TextStyle(color: sonTextoSuave, fontSize: 16)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    children: [
                      EtiquetaEstado(texto: 'Ganados ${d['ganados']}', color: sonLightGreen),
                      EtiquetaEstado(texto: 'Negociando ${d['negociando']}', color: sonAzul),
                      EtiquetaEstado(texto: 'Perdidos ${d['perdidos']}', color: sonRojo),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _panel('Por servicio presupuestado', d['porServicio'] as List? ?? []),
                _panel('Por responsable', d['porResponsable'] as List? ?? []),
                _panel('Razones de pérdida', d['razonesPerdida'] as List? ?? [], razones: true),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// =====================================================================
// CONFIGURACIÓN
// =====================================================================
Future<bool> abrirConfigCrm(BuildContext context) async {
  final cambio = await showDialog<bool>(context: context, builder: (_) => const _ConfigCrm());
  return cambio == true;
}

class _ConfigCrm extends StatefulWidget {
  const _ConfigCrm();

  @override
  State<_ConfigCrm> createState() => _ConfigCrmState();
}

class _ConfigCrmState extends State<_ConfigCrm> {
  final _umbrales = TextEditingController();
  final _umbralPresupuesto = TextEditingController();
  final _servicios = TextEditingController();
  final _responsables = TextEditingController();
  final _razones = TextEditingController();
  final _tiposNota = TextEditingController();
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    ConfigCrm.leer(forzar: true).then((config) {
      if (!mounted) return;
      final umbrales = Map<String, dynamic>.from(config['umbrales'] as Map? ?? {});
      setState(() {
        _umbrales.text = umbrales.entries.map((e) => '${e.key}: ${e.value}').join('\n');
        _umbralPresupuesto.text = '${config['umbralPresupuesto'] ?? 14}';
        _servicios.text = ConfigCrm.lista(config, 'servicios').join('\n');
        _responsables.text = ConfigCrm.lista(config, 'responsables').join('\n');
        _razones.text = ConfigCrm.lista(config, 'razonesPerdida').join('\n');
        _tiposNota.text = ConfigCrm.lista(config, 'tiposNota').join('\n');
        _cargando = false;
      });
    });
  }

  List<String> _renglones(TextEditingController control) => control.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  Future<void> _guardar() async {
    final umbrales = <String, int>{};
    for (final linea in _renglones(_umbrales)) {
      final partes = linea.split(':');
      final dias = partes.length == 2 ? int.tryParse(partes[1].trim()) : null;
      if (dias == null) return setState(() => _error = 'Cada tipo de cliente va así: "Prospecto: 7"');
      umbrales[partes[0].trim()] = dias;
    }
    try {
      final respuesta = await apiSend('PUT', '/api/crm/config', json.encode({
        'umbrales': umbrales,
        'umbralPresupuesto': int.tryParse(_umbralPresupuesto.text.trim()) ?? 14,
        'servicios': _renglones(_servicios),
        'responsables': _renglones(_responsables),
        'razonesPerdida': _renglones(_razones),
        'tiposNota': _renglones(_tiposNota),
      }));
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        ConfigCrm.olvidar();
        Navigator.pop(context, true);
      } else {
        setState(() => _error = mensajeError(respuesta));
      }
    } catch (_) {
      if (mounted) setState(() => _error = mensajeSinConexion);
    }
  }

  Widget _campo(String titulo, TextEditingController control, {String? ayuda}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: control, maxLines: 5, minLines: 2, decoration: InputDecoration(labelText: titulo, helperText: ayuda, helperMaxLines: 2)),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configurar CRM'),
      content: SizedBox(
        width: 560,
        child: _cargando
            ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  children: [
                    _campo('Tipos de cliente y días sin contacto', _umbrales, ayuda: 'Uno por renglón, así: "Prospecto: 7". Pasado ese número de días el cliente se pone en rojo.'),
                    TextField(controller: _umbralPresupuesto, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Días máximos con un presupuesto abierto')),
                    const SizedBox(height: 12),
                    _campo('Servicios que se presupuestan', _servicios, ayuda: 'Uno por renglón.'),
                    _campo('Responsables comerciales', _responsables, ayuda: 'Uno por renglón.'),
                    _campo('Razones de pérdida', _razones, ayuda: 'Uno por renglón.'),
                    _campo('Tipos de nota', _tiposNota, ayuda: 'Las notas "Interna" no cuentan como contacto con el cliente.'),
                    if (_error != null) Text(_error!, style: TextStyle(color: sonRojo)),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _cargando ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
