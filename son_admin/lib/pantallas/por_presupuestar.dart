import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:son_admin/pantallas/armar_presupuesto.dart';
import 'package:son_admin/pantallas/piezas.dart';
import 'package:son_admin/services/api.dart';
import 'package:son_admin/theme/tema.dart';
import 'package:son_admin/ui/componentes.dart';

// 'Enviada' y 'Aprobada' son para lo que se presupuesta por fuera (WhatsApp, mail): el técnico ve en la app en qué quedó.
const List<String> estadosSolicitud = ['Nueva', 'En presupuesto', 'Presupuestada', 'Enviada', 'Aprobada', 'Descartada'];

Color colorEstadoSolicitud(String estado) => switch (estado) {
      'Nueva' => sonAmbar,
      'En presupuesto' => sonAzul,
      'Presupuestada' => sonLightGreen,
      'Enviada' => sonAzul,
      'Aprobada' => sonLightGreen,
      _ => sonTextoSuave,
    };

/// Bandeja del área comercial: lo que los técnicos anotaron en las visitas para presupuestar.
class PantallaPorPresupuestar extends StatefulWidget {
  /// Se llama cuando el usuario cambia algo, para que el menú actualice el contador de nuevas.
  final VoidCallback? onCambio;

  /// Si está adentro de Presupuestos, no muestra el título grande ni el padding de pantalla.
  final bool embebida;

  const PantallaPorPresupuestar({super.key, this.onCambio, this.embebida = false});

  @override
  State<PantallaPorPresupuestar> createState() => _PantallaPorPresupuestarState();
}

class _PantallaPorPresupuestarState extends State<PantallaPorPresupuestar> {
  static const List<(String, String)> _filtros = [
    ('abiertas', 'Abiertas'),
    ('Nueva', 'Nuevas'),
    ('En presupuesto', 'En presupuesto'),
    ('Presupuestada', 'Presupuestadas'),
    ('Enviada', 'Enviadas'),
    ('Aprobada', 'Aprobadas'),
    ('Descartada', 'Descartadas'),
    ('todas', 'Todas'),
  ];

  List<Map<String, dynamic>> _notas = [];
  bool _cargando = true;
  String? _error;
  String _filtro = 'abiertas';
  final TextEditingController _busqueda = TextEditingController();
  final Set<int> _ocupadas = {};
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _busqueda.addListener(() => setState(() {}));
    _cargar();
    // Mientras la pantalla está abierta se revisa sola si los técnicos anotaron algo nuevo.
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) => _cargar(silencioso: true));
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso && !_cargando) setState(() => _cargando = true);
    try {
      final respuesta = await apiGet('/api/solicitudes-presupuesto');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        setState(() {
          _notas = (json.decode(respuesta.body) as List).map((nota) => Map<String, dynamic>.from(nota as Map)).toList();
          _error = null;
          _cargando = false;
        });
      } else if (!silencioso) {
        setState(() {
          _error = mensajeError(respuesta, 'No se pudo leer la bandeja');
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted && !silencioso) {
        setState(() {
          _error = mensajeSinConexion;
          _cargando = false;
        });
      }
    }
  }

  bool _coincideFiltro(Map<String, dynamic> nota, String filtro) {
    final estado = '${nota['estado']}';
    return switch (filtro) {
      'abiertas' => estado == 'Nueva' || estado == 'En presupuesto',
      'todas' => true,
      _ => estado == filtro,
    };
  }

  List<Map<String, dynamic>> get _visibles {
    return _notas.where((nota) {
      if (!_coincideFiltro(nota, _filtro)) return false;
      final texto = '${nota['empresa']} ${nota['descripcion']} ${nota['tecnico'] ?? ''} ${nota['nota_comercial'] ?? ''}';
      return coincideBusqueda(texto, _busqueda.text);
    }).toList();
  }

  Future<void> _cambiarEstado(Map<String, dynamic> nota, String estado) async {
    final id = (nota['id'] as num).toInt();
    if (_ocupadas.contains(id)) return;
    setState(() => _ocupadas.add(id));
    String? mensaje;
    try {
      final respuesta = await apiSend('PUT', '/api/solicitudes-presupuesto/$id', json.encode({'estado': estado}));
      if (respuesta.statusCode == 200) {
        final nueva = Map<String, dynamic>.from(json.decode(respuesta.body) as Map);
        if (mounted) {
          setState(() {
            final posicion = _notas.indexWhere((n) => n['id'] == id);
            if (posicion >= 0) _notas[posicion] = nueva;
          });
        }
        widget.onCambio?.call();
      } else {
        mensaje = mensajeError(respuesta, 'No se pudo cambiar el estado');
      }
    } catch (_) {
      mensaje = mensajeSinConexion;
    }
    if (!mounted) return;
    setState(() => _ocupadas.remove(id));
    if (mensaje != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _editar(Map<String, dynamic> nota) async {
    final nueva = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _DialogoNota(nota: nota));
    if (nueva == null || !mounted) return;
    setState(() {
      final posicion = _notas.indexWhere((n) => n['id'] == nota['id']);
      if (posicion >= 0) _notas[posicion] = nueva;
    });
    widget.onCambio?.call();
  }

  void _verFoto(Map<String, dynamic> nota) {
    showDialog<void>(context: context, builder: (_) => _VisorFoto(id: (nota['id'] as num).toInt(), titulo: '${nota['descripcion']}'));
  }

  Widget _barraFiltros() {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (valor, texto) in _filtros)
          PildoraFiltro(
            texto: '$texto · ${_notas.where((n) => _coincideFiltro(n, valor)).length}',
            activo: _filtro == valor,
            color: estadosSolicitud.contains(valor) ? colorEstadoSolicitud(valor) : sonLightGreen,
            alTocar: () => setState(() => _filtro = valor),
          ),
        SizedBox(
          width: 280,
          child: TextField(
            key: const Key('buscar_solicitud'),
            controller: _busqueda,
            decoration: InputDecoration(
              hintText: 'Buscar empresa, técnico o texto',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              suffixIcon: _busqueda.text.isEmpty
                  ? null
                  : IconButton(tooltip: 'Borrar búsqueda', icon: const Icon(Icons.close, size: 18), onPressed: _busqueda.clear),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: sonRojo)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _cargar, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (_notas.isEmpty) {
      return Center(
        child: Text(
          'Todavía no hay notas. Cuando un técnico anote algo que falta en una visita, aparece acá.',
          textAlign: TextAlign.center,
          style: TextStyle(color: sonTextoSuave),
        ),
      );
    }
    final visibles = _visibles;
    if (visibles.isEmpty) {
      return Center(child: Text('No hay notas con este filtro.', style: TextStyle(color: sonTextoSuave)));
    }

    // Se agrupan por empresa; la primera es la que tiene la nota más reciente.
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final nota in visibles) {
      grupos.putIfAbsent('${nota['empresa_id'] ?? nota['empresa']}', () => []).add(nota);
    }
    final lista = grupos.values.toList();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: lista.length,
      itemBuilder: (_, i) => _tarjetaEmpresa(lista[i]),
    );
  }

  Widget _tarjetaEmpresa(List<Map<String, dynamic>> notas) {
    final empresa = '${notas.first['empresa']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: decoracionTarjeta(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Icon(Icons.business_outlined, color: sonLightGreen, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text(empresa, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold, fontSize: 17))),
                Text(notas.length == 1 ? '1 nota' : '${notas.length} notas', style: TextStyle(color: sonTextoSuave, fontSize: 13)),
                if (notas.any((n) => n['estado'] == 'Nueva' || n['estado'] == 'En presupuesto')) ...[
                  const SizedBox(width: 12),
                  TextButton.icon(
                    key: Key('armar_${notas.first['id']}'),
                    onPressed: () async {
                      final abiertas = notas.where((n) => n['estado'] == 'Nueva' || n['estado'] == 'En presupuesto').toList();
                      final armado = await armarPresupuesto(context, notas: abiertas);
                      if (armado) {
                        widget.onCambio?.call();
                        _cargar();
                      }
                    },
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Armar presupuesto'),
                  ),
                ],
              ],
            ),
          ),
          for (final nota in notas) _fila(nota),
        ],
      ),
    );
  }

  Widget _fila(Map<String, dynamic> nota) {
    final estado = '${nota['estado']}';
    final color = colorEstadoSolicitud(estado);
    final id = (nota['id'] as num).toInt();
    final fecha = DateTime.tryParse('${nota['creada_en']}')?.toLocal();
    final comentario = '${nota['nota_comercial'] ?? ''}'.trim();
    final descartada = estado == 'Descartada';
    final tieneFoto = nota['tiene_foto'] == true;

    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: sonBorde))),
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: sonTarjetaAlta, borderRadius: BorderRadius.circular(10)),
            child: Text('×${nota['cantidad']}', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${nota['descripcion']}',
                  style: TextStyle(
                    color: descartada ? sonTextoSuave : sonTexto,
                    fontWeight: FontWeight.w600,
                    fontSize: 15.5,
                    height: 1.3,
                    decoration: descartada ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    DatoConIcono(icono: Icons.person_outline, texto: '${nota['tecnico'] ?? 'Técnico eliminado'}'),
                    if (fecha != null) DatoConIcono(icono: Icons.schedule, texto: fechaCorta(fecha)),
                    if (tieneFoto)
                      InkWell(
                        onTap: () => _verFoto(nota),
                        child: DatoConIcono(icono: Icons.photo_outlined, texto: 'Ver foto', color: sonAzul),
                      ),
                  ],
                ),
                if (comentario.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: sonTarjetaAlta.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
                      child: DatoConIcono(icono: Icons.sticky_note_2_outlined, texto: comentario, lineas: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              EtiquetaEstado(texto: estado, color: color),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_ocupadas.contains(id))
                    const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)))
                  else
                    _accionPrincipal(nota, estado),
                  PopupMenuButton<String>(
                    tooltip: 'Más opciones',
                    icon: Icon(Icons.more_vert, color: sonTextoSuave),
                    onSelected: (opcion) {
                      if (opcion == 'editar') {
                        _editar(nota);
                      } else if (opcion == 'foto') {
                        _verFoto(nota);
                      } else {
                        _cambiarEstado(nota, opcion);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'editar', child: Text('Editar o agregar una nota')),
                      if (tieneFoto) const PopupMenuItem(value: 'foto', child: Text('Ver foto')),
                      const PopupMenuDivider(),
                      for (final otro in estadosSolicitud.where((e) => e != estado)) PopupMenuItem(value: otro, child: Text('Pasar a "$otro"')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// El paso más común según el estado actual, a un solo toque.
  Widget _accionPrincipal(Map<String, dynamic> nota, String estado) {
    if (estado == 'Nueva') {
      return ElevatedButton.icon(
        key: Key('tomar_${nota['id']}'),
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
        onPressed: () => _cambiarEstado(nota, 'En presupuesto'),
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: const Text('Tomar'),
      );
    }
    if (estado == 'En presupuesto') {
      return ElevatedButton.icon(
        key: Key('presupuestada_${nota['id']}'),
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
        onPressed: () => _cambiarEstado(nota, 'Presupuestada'),
        icon: const Icon(Icons.check_rounded, size: 18),
        label: const Text('Presupuestada'),
      );
    }
    return TextButton(onPressed: () => _cambiarEstado(nota, 'Nueva'), child: const Text('Reabrir'));
  }

  @override
  Widget build(BuildContext context) {
    final filtrosYLista = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _barraFiltros(),
        const SizedBox(height: 16),
        Expanded(child: _cuerpo()),
      ],
    );
    if (widget.embebida) return filtrosYLista;
    return Padding(
      padding: AppSpacing.pagina,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EncabezadoPantalla(eyebrow: 'Comercial', normal: 'Por', destacado: 'presupuestar'),
                  ],
                ),
              ),
              IconButton(tooltip: 'Actualizar', onPressed: () => _cargar(), icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 28),
          Expanded(child: filtrosYLista),
        ],
      ),
    );
  }
}

/// Ventana para corregir la descripción o la cantidad y dejar una nota de comercial.
class _DialogoNota extends StatefulWidget {
  final Map<String, dynamic> nota;

  const _DialogoNota({required this.nota});

  @override
  State<_DialogoNota> createState() => _DialogoNotaState();
}

class _DialogoNotaState extends State<_DialogoNota> {
  late final TextEditingController _descripcion = TextEditingController(text: '${widget.nota['descripcion']}');
  late final TextEditingController _cantidad = TextEditingController(text: '${widget.nota['cantidad']}');
  late final TextEditingController _comentario = TextEditingController(text: '${widget.nota['nota_comercial'] ?? ''}');
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _descripcion.dispose();
    _cantidad.dispose();
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() {
      _error = null;
      _guardando = true;
    });
    try {
      final respuesta = await apiSend(
        'PUT',
        '/api/solicitudes-presupuesto/${widget.nota['id']}',
        json.encode({
          'descripcion': _descripcion.text,
          'cantidad': _cantidad.text.trim().isEmpty ? 1 : int.tryParse(_cantidad.text.trim()) ?? 0,
          'nota': _comentario.text,
        }),
      );
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        Navigator.pop(context, Map<String, dynamic>.from(json.decode(respuesta.body) as Map));
        return;
      }
      setState(() {
        _error = mensajeError(respuesta, 'No se pudo guardar la nota');
        _guardando = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = mensajeSinConexion;
          _guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.nota['empresa']}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _descripcion, maxLines: 3, maxLength: 500, decoration: const InputDecoration(labelText: 'Qué hay que presupuestar')),
              const SizedBox(height: 8),
              TextField(
                controller: _cantidad,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Cantidad'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _comentario,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'Nota de comercial (opcional)', hintText: 'Ej: presupuesto enviado el 27/10'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: Text('Cancelar', style: TextStyle(color: sonTextoSuave))),
        ElevatedButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Muestra la foto que sacó el técnico (se pide al servidor recién cuando se abre).
class _VisorFoto extends StatefulWidget {
  final int id;
  final String titulo;

  const _VisorFoto({required this.id, required this.titulo});

  @override
  State<_VisorFoto> createState() => _VisorFotoState();
}

class _VisorFotoState extends State<_VisorFoto> {
  late final Future<Uint8List?> _foto = _pedir();

  Future<Uint8List?> _pedir() async {
    try {
      final respuesta = await apiGet('/api/solicitudes-presupuesto/${widget.id}/foto');
      return respuesta.statusCode == 200 ? respuesta.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(child: Text(widget.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold))),
                  IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<Uint8List?>(
                future: _foto,
                builder: (context, estado) {
                  if (estado.connectionState != ConnectionState.done) {
                    return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
                  }
                  final bytes = estado.data;
                  if (bytes == null) {
                    return SizedBox(height: 160, child: Center(child: Text('No se pudo cargar la foto.', style: TextStyle(color: sonRojo))));
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
