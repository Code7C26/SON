import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:son_admin/config/api_config.dart';
import 'package:son_admin/pantallas/piezas.dart';
import 'package:son_admin/services/abrir_informe.dart';
import 'package:son_admin/services/api.dart';
import 'package:son_admin/services/sesion.dart';
import 'package:son_admin/theme/tema.dart';
import 'package:son_admin/ui/componentes.dart';

// Pantallas nuevas pedidas por los técnicos (reunión de noviembre de 2026):
//  - Vencimientos: extintores, mediciones, habilitaciones. Avisa con tiempo.
//  - Gastos y vehículos: lo que antes se cargaba en el Forms (kilometraje, combustible, peajes).
//  - Acceso del cliente: un enlace privado para que el cliente vea sus informes.

String _dos(int n) => n.toString().padLeft(2, '0');
String _iso(DateTime fecha) => '${fecha.year}-${_dos(fecha.month)}-${_dos(fecha.day)}';
String _fecha(dynamic iso) {
  final partes = '${iso ?? ''}'.split('-');
  if (partes.length < 3) return '';
  return '${partes[2].substring(0, 2)}/${partes[1]}/${partes[0]}';
}

Widget _encabezado(String normal, String destacado, List<Widget> acciones) => EncabezadoPantalla(
      eyebrow: 'Operación',
      normal: normal,
      destacado: destacado,
      accion: acciones.isEmpty ? null : Wrap(spacing: AppSpacing.s8, children: acciones),
    );

// =====================================================================
// VENCIMIENTOS
// =====================================================================
class PantallaVencimientos extends StatefulWidget {
  const PantallaVencimientos({super.key});

  @override
  State<PantallaVencimientos> createState() => _PantallaVencimientosState();
}

class _PantallaVencimientosState extends State<PantallaVencimientos> {
  List<Map<String, dynamic>> _lista = [];
  int _diasAviso = 60;
  bool _cargando = true;
  bool _conResueltos = false;
  String? _error;
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
    setState(() { _cargando = true; _error = null; });
    try {
      final respuesta = await apiGet('/api/vencimientos${_conResueltos ? '?todos=1' : ''}');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        final datos = json.decode(respuesta.body) as Map;
        setState(() {
          _lista = (datos['vencimientos'] as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();
          _diasAviso = (datos['diasAviso'] as num?)?.toInt() ?? 60;
          _cargando = false;
        });
      } else {
        setState(() { _error = mensajeError(respuesta, 'No se pudieron leer los vencimientos'); _cargando = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _cargando = false; });
    }
  }

  Future<void> _cambiar(Map v, Map<String, dynamic> cambios) async {
    try {
      final respuesta = await apiSend('PUT', '/api/vencimientos/${v['id']}', json.encode(cambios));
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(respuesta))));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(mensajeSinConexion)));
    }
  }

  Future<void> _borrar(Map v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('¿Borrar el vencimiento?'),
        content: Text('${v['descripcion']} — ${v['empresa']}. Si ya se resolvió, mejor marcalo como resuelto.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(dialogo, true), child: Text('Borrar', style: TextStyle(color: sonRojo))),
        ],
      ),
    );
    if (ok != true) return;
    await apiSend('DELETE', '/api/vencimientos/${v['id']}');
    _cargar();
  }

  Future<void> _nuevo() async {
    final empresa = TextEditingController();
    final descripcion = TextEditingController();
    final cantidad = TextEditingController(text: '1');
    DateTime? vence;
    String? error;
    List<String> empresas = [];
    try {
      final respuesta = await apiGet('/api/clientes/nombres');
      if (respuesta.statusCode == 200) {
        empresas = (json.decode(respuesta.body) as List).map((e) => '${e['razon_social']}').toList();
      }
    } catch (_) {}
    if (!mounted) return;
    final guardado = await showDialog<bool>(
      context: context,
      builder: (dialogo) => StatefulBuilder(
        builder: (dialogo, actualizar) => AlertDialog(
          title: const Text('Nuevo vencimiento'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Autocomplete<String>(
                  optionsBuilder: (valor) => empresas.where((e) => coincideBusqueda(e, valor.text)).take(12),
                  onSelected: (valor) => empresa.text = valor,
                  fieldViewBuilder: (context, control, foco, alEnviar) {
                    control.addListener(() => empresa.text = control.text);
                    return TextField(controller: control, focusNode: foco, decoration: const InputDecoration(labelText: 'Empresa'));
                  },
                ),
                const SizedBox(height: 10),
                TextField(controller: descripcion, decoration: const InputDecoration(labelText: '¿Qué vence?', hintText: 'Ej: Habilitación municipal')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(width: 100, child: TextField(controller: cantidad, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final hoy = DateTime.now();
                          final elegida = await showDatePicker(context: dialogo, initialDate: vence ?? DateTime(hoy.year + 1, hoy.month, hoy.day), firstDate: DateTime(hoy.year - 1), lastDate: DateTime(hoy.year + 10));
                          if (elegida != null) actualizar(() => vence = elegida);
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: Text(vence == null ? 'Fecha de vencimiento' : 'Vence el ${vence!.day}/${vence!.month}/${vence!.year}'),
                      ),
                    ),
                  ],
                ),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (vence == null) return actualizar(() => error = 'Elegí la fecha de vencimiento');
                try {
                  final respuesta = await apiSend('POST', '/api/vencimientos/panel', json.encode({
                    'empresa': empresa.text.trim(),
                    'descripcion': descripcion.text.trim(),
                    'cantidad': int.tryParse(cantidad.text.trim()) ?? 1,
                    'vence': _iso(vence!),
                  }));
                  if (respuesta.statusCode == 200) {
                    if (dialogo.mounted) Navigator.pop(dialogo, true);
                  } else {
                    actualizar(() => error = mensajeError(respuesta));
                  }
                } catch (_) {
                  actualizar(() => error = mensajeSinConexion);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (guardado == true) _cargar();
  }

  Color _color(int dias, bool resuelto) => resuelto ? sonTextoSuave : (dias < 0 ? sonRojo : (dias <= _diasAviso ? sonAmbar : sonLightGreen));

  @override
  Widget build(BuildContext context) {
    final visibles = _lista.where((v) => coincideBusqueda('${v['empresa']} ${v['descripcion']}', _busqueda.text)).toList();
    final vencidos = _lista.where((v) => v['resuelto'] != true && ((v['dias'] as num?) ?? 0) < 0).length;
    final proximos = _lista.where((v) => v['resuelto'] != true && ((v['dias'] as num?) ?? 0) >= 0 && ((v['dias'] as num?) ?? 0) <= _diasAviso).length;
    return Padding(
      padding: AppSpacing.pagina,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _encabezado(
            'Control de',
            'vencimientos',
            [ElevatedButton.icon(onPressed: _nuevo, icon: const Icon(Icons.add), label: const Text('Nuevo'))],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              EtiquetaEstado(texto: '$vencidos vencidos', color: sonRojo),
              EtiquetaEstado(texto: '$proximos en los próximos $_diasAviso días', color: sonAmbar),
              SizedBox(
                width: 320,
                child: TextField(controller: _busqueda, decoration: const InputDecoration(hintText: 'Buscar empresa o qué vence...', prefixIcon: Icon(Icons.search), isDense: true)),
              ),
              FilterChip(
                label: const Text('Ver también los resueltos'),
                selected: _conResueltos,
                onSelected: (valor) {
                  setState(() => _conResueltos = valor);
                  _cargar();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: decoracionTarjeta(),
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: TextStyle(color: sonRojo)))
                      : visibles.isEmpty
                          ? Center(child: Text('No hay vencimientos cargados.', style: TextStyle(color: sonTextoSuave)))
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: visibles.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final v = visibles[i];
                                final dias = (v['dias'] as num?)?.toInt() ?? 0;
                                final resuelto = v['resuelto'] == true;
                                final cuando = resuelto ? 'Resuelto' : (dias < 0 ? 'Vencido hace ${-dias} días' : (dias == 0 ? 'Vence hoy' : 'Faltan $dias días'));
                                return ListTile(
                                  leading: Icon(resuelto ? Icons.check_circle_outline : Icons.event_busy_outlined, color: _color(dias, resuelto)),
                                  title: Text('${v['descripcion']}${((v['cantidad'] as num?) ?? 1) > 1 ? ' (x${v['cantidad']})' : ''}', style: TextStyle(fontWeight: FontWeight.w600, decoration: resuelto ? TextDecoration.lineThrough : null)),
                                  subtitle: Text('${v['empresa']} · vence el ${_fecha(v['vence'])}${v['creado_por'] != null ? ' · cargó ${v['creado_por']}' : ''}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      EtiquetaEstado(texto: cuando, color: _color(dias, resuelto)),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: () => _cambiar(v, {'resuelto': !resuelto}),
                                        child: Text(resuelto ? 'Reabrir' : 'Resuelto'),
                                      ),
                                      IconButton(
                                        tooltip: 'Cambiar fecha',
                                        icon: const Icon(Icons.edit_calendar_outlined),
                                        onPressed: () async {
                                          final actual = DateTime.tryParse('${v['vence']}') ?? DateTime.now();
                                          final elegida = await showDatePicker(context: context, initialDate: actual, firstDate: DateTime(actual.year - 2), lastDate: DateTime(actual.year + 10));
                                          if (elegida != null) _cambiar(v, {'vence': _iso(elegida)});
                                        },
                                      ),
                                      IconButton(tooltip: 'Borrar', icon: Icon(Icons.delete_outline, color: sonRojo), onPressed: () => _borrar(v)),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// GASTOS Y VEHÍCULOS
// =====================================================================
class PantallaGastos extends StatefulWidget {
  const PantallaGastos({super.key});

  @override
  State<PantallaGastos> createState() => _PantallaGastosState();
}

class _PantallaGastosState extends State<PantallaGastos> {
  List<Map<String, dynamic>> _gastos = [];
  List<Map<String, dynamic>> _tecnicos = [];
  bool _cargando = true;
  String? _error;
  late DateTime _desde;
  late DateTime _hasta;
  int? _tecnicoId;
  String _revisado = 'todos';

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _desde = DateTime(hoy.year, hoy.month, 1);
    _hasta = DateTime(hoy.year, hoy.month, hoy.day);
    _cargarTecnicos();
    _cargar();
  }

  String get _filtros {
    final partes = ['desde=${_iso(_desde)}', 'hasta=${_iso(_hasta)}'];
    if (_tecnicoId != null) partes.add('tecnicoId=$_tecnicoId');
    if (_revisado != 'todos') partes.add('revisado=$_revisado');
    return partes.join('&');
  }

  Future<void> _cargarTecnicos() async {
    try {
      final respuesta = await apiGet('/api/tecnicos');
      if (respuesta.statusCode == 200 && mounted) {
        setState(() => _tecnicos = (json.decode(respuesta.body) as List).map((t) => Map<String, dynamic>.from(t as Map)).toList());
      }
    } catch (_) {}
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final respuesta = await apiGet('/api/gastos?$_filtros');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        final datos = json.decode(respuesta.body) as Map;
        setState(() {
          _gastos = (datos['gastos'] as List).map((g) => Map<String, dynamic>.from(g as Map)).toList();
          _cargando = false;
        });
      } else {
        setState(() { _error = mensajeError(respuesta, 'No se pudieron leer los gastos'); _cargando = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _cargando = false; });
    }
  }

  Future<void> _marcar(Map g, bool revisado) async {
    try {
      final respuesta = await apiSend('PUT', '/api/gastos/${g['id']}', json.encode({'revisado': revisado}));
      if (respuesta.statusCode == 200 && mounted) setState(() => g['revisado'] = revisado);
    } catch (_) {}
  }

  Future<void> _verFoto(Map g) async {
    await showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text('${g['tipo']} · ${g['tecnico'] ?? ''}'),
        content: SizedBox(
          width: 520,
          child: FutureBuilder<Uint8List?>(
            future: () async {
              final respuesta = await apiGet('/api/gastos/${g['id']}/foto');
              return respuesta.statusCode == 200 ? respuesta.bodyBytes : null;
            }(),
            builder: (context, foto) {
              if (foto.connectionState != ConnectionState.done) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
              if (foto.data == null) return Text('No se pudo cargar la foto.', style: TextStyle(color: sonRojo));
              return InteractiveViewer(child: Image.memory(foto.data!, fit: BoxFit.contain));
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogo), child: const Text('Cerrar'))],
      ),
    );
  }

  Future<void> _elegirFecha(bool desde) async {
    final elegida = await showDatePicker(context: context, initialDate: desde ? _desde : _hasta, firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (elegida == null) return;
    setState(() => desde ? _desde = elegida : _hasta = elegida);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final total = _gastos.fold<double>(0, (suma, g) => suma + ((g['monto'] as num?)?.toDouble() ?? 0));
    final km = _gastos.fold<int>(0, (suma, g) {
      final inicio = (g['km_inicio'] as num?)?.toInt();
      final fin = (g['km_fin'] as num?)?.toInt();
      return inicio != null && fin != null ? suma + (fin - inicio) : suma;
    });
    final sinRevisar = _gastos.where((g) => g['revisado'] != true).length;
    return Padding(
      padding: AppSpacing.pagina,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _encabezado(
            'Gastos y',
            'vehículos',
            [
              OutlinedButton.icon(
                onPressed: () => abrirInforme('$apiBaseUrl/api/gastos/planilla?$_filtros&token=${SesionAdmin.token}'),
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('Planilla para Excel'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(onPressed: () => _elegirFecha(true), icon: const Icon(Icons.event_outlined), label: Text('Desde ${_desde.day}/${_desde.month}/${_desde.year}')),
              OutlinedButton.icon(onPressed: () => _elegirFecha(false), icon: const Icon(Icons.event_outlined), label: Text('Hasta ${_hasta.day}/${_hasta.month}/${_hasta.year}')),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int?>(
                  initialValue: _tecnicoId,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'Técnico', isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Todos')),
                    ..._tecnicos.map((t) => DropdownMenuItem<int?>(value: (t['id'] as num).toInt(), child: Text('${t['nombre']}'))),
                  ],
                  onChanged: (valor) {
                    setState(() => _tecnicoId = valor);
                    _cargar();
                  },
                ),
              ),
              for (final (valor, texto) in const [('todos', 'Todos'), ('no', 'Sin revisar'), ('si', 'Revisados')])
                ChoiceChip(
                  label: Text(texto),
                  selected: _revisado == valor,
                  onSelected: (_) {
                    setState(() => _revisado = valor);
                    _cargar();
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            children: [
              EtiquetaEstado(texto: 'Total ${pesos(total)}', color: sonLightGreen),
              EtiquetaEstado(texto: '$km km recorridos', color: sonAzul),
              EtiquetaEstado(texto: '$sinRevisar sin revisar', color: sinRevisar > 0 ? sonAmbar : sonTextoSuave),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              decoration: decoracionTarjeta(),
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: TextStyle(color: sonRojo)))
                      : _gastos.isEmpty
                          ? Center(child: Text('No hay gastos en estas fechas.', style: TextStyle(color: sonTextoSuave)))
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _gastos.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final g = _gastos[i];
                                final inicio = (g['km_inicio'] as num?)?.toInt();
                                final fin = (g['km_fin'] as num?)?.toInt();
                                final kmTexto = inicio != null && fin != null ? '${fin - inicio} km ($inicio → $fin)' : (inicio ?? fin)?.toString();
                                return ListTile(
                                  leading: Checkbox(value: g['revisado'] == true, onChanged: (valor) => _marcar(g, valor ?? false)),
                                  title: Text(
                                    [g['tipo'], if (g['monto'] != null) pesos(g['monto'] as num)].join(' · '),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text([
                                    _fecha(g['dia']),
                                    '${g['tecnico'] ?? ''}',
                                    if (g['empresa'] != null) '${g['empresa']}',
                                    if ('${g['vehiculo'] ?? ''}'.isNotEmpty) '${g['vehiculo']}',
                                    if (kmTexto != null) kmTexto,
                                    if ('${g['descripcion'] ?? ''}'.isNotEmpty) '${g['descripcion']}',
                                  ].where((t) => t.isNotEmpty).join(' · ')),
                                  trailing: g['tiene_foto'] == true
                                      ? TextButton.icon(onPressed: () => _verFoto(g), icon: const Icon(Icons.receipt_long_outlined), label: const Text('Ticket'))
                                      : null,
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// ACCESO DEL CLIENTE
// =====================================================================
/// Activa, copia, manda por correo o corta el enlace con el que el cliente ve sus informes.
Future<void> abrirAccesoCliente(BuildContext context, int empresaId, String nombre) {
  return showDialog<void>(context: context, builder: (_) => _DialogoAcceso(empresaId: empresaId, nombre: nombre));
}

class _DialogoAcceso extends StatefulWidget {
  final int empresaId;
  final String nombre;
  const _DialogoAcceso({required this.empresaId, required this.nombre});

  @override
  State<_DialogoAcceso> createState() => _DialogoAccesoState();
}

class _DialogoAccesoState extends State<_DialogoAcceso> {
  Map<String, dynamic>? _estado;
  bool _ocupado = false;
  String? _mensaje;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _pedir('GET', '/api/clientes/${widget.empresaId}/portal');
  }

  Future<void> _pedir(String metodo, String ruta, [Map<String, dynamic>? cuerpo, String? exito]) async {
    setState(() { _ocupado = true; _mensaje = null; });
    try {
      final respuesta = await apiSend(metodo, ruta, cuerpo == null ? null : json.encode(cuerpo));
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        final datos = Map<String, dynamic>.from(json.decode(respuesta.body) as Map);
        setState(() {
          if (datos.containsKey('activo')) _estado = datos;
          _mensaje = exito;
          _error = false;
          _ocupado = false;
        });
      } else {
        setState(() { _mensaje = mensajeError(respuesta); _error = true; _ocupado = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _mensaje = mensajeSinConexion; _error = true; _ocupado = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = _estado;
    final activo = estado?['activo'] == true;
    final enlace = '${estado?['enlace'] ?? ''}';
    return AlertDialog(
      title: Text('Acceso de ${widget.nombre}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Con este enlace el cliente ve los informes de cada visita, las próximas visitas y lo que tiene por vencer. '
              'No necesita usuario. Activalo solo para los clientes que lo pidan.',
              style: TextStyle(color: sonTextoSuave),
            ),
            const SizedBox(height: 16),
            if (estado == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(activo ? 'Acceso activado' : 'Acceso desactivado', style: const TextStyle(fontWeight: FontWeight.bold)),
                value: activo,
                onChanged: _ocupado ? null : (valor) => _pedir('POST', '/api/clientes/${widget.empresaId}/portal', {'activo': valor}),
              ),
              if (activo) ...[
                SelectableText(enlace, style: TextStyle(color: sonAzul)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: enlace));
                        setState(() { _mensaje = 'Enlace copiado'; _error = false; });
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar'),
                    ),
                    OutlinedButton.icon(onPressed: () => abrirInforme(enlace), icon: const Icon(Icons.open_in_new), label: const Text('Ver como el cliente')),
                    OutlinedButton.icon(
                      onPressed: _ocupado ? null : () => _pedir('POST', '/api/clientes/${widget.empresaId}/portal/enviar', {}, 'Enlace enviado a ${estado['email'] ?? 'su correo'}'),
                      icon: const Icon(Icons.outgoing_mail),
                      label: Text(estado['email'] == null ? 'Mandar por correo (falta el correo)' : 'Mandar a ${estado['email']}'),
                    ),
                    TextButton(
                      onPressed: _ocupado ? null : () => _pedir('POST', '/api/clientes/${widget.empresaId}/portal', {'activo': true, 'regenerar': true}, 'Enlace nuevo: el anterior ya no funciona'),
                      child: const Text('Cambiar enlace'),
                    ),
                  ],
                ),
              ],
            ],
            if (_mensaje != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_mensaje!, style: TextStyle(color: _error ? sonRojo : sonLightGreen, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}
