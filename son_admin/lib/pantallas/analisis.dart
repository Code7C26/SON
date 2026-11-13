import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:son_admin/services/api.dart';
import 'package:son_admin/theme/tema.dart';
import 'package:son_admin/ui/componentes.dart';

/// Análisis operativo: órdenes, tiempos, clientes y encuestas.
class PantallaAnalisis extends StatefulWidget {
  const PantallaAnalisis({super.key});

  @override
  State<PantallaAnalisis> createState() => _PantallaAnalisisState();
}

class _PantallaAnalisisState extends State<PantallaAnalisis> {
  static const _periodos = [
    ('hoy', 'Hoy'),
    ('7d', 'Últimos 7 días'),
    ('mes', 'Este mes'),
    ('trimestre', 'Trimestre'),
    ('custom', 'Personalizado'),
  ];

  Map<String, dynamic>? _datos;
  bool _cargando = true;
  String? _error;
  String _periodo = 'trimestre';
  DateTime? _desde;
  DateTime? _hasta;
  int? _empresaId;
  int? _tecnicoId;
  String _filtroEncuesta = 'todas';
  int _pedido = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final pedido = ++_pedido;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final respuesta = await apiGet(_consulta());
      if (!mounted || pedido != _pedido) return;
      if (respuesta.statusCode == 200) {
        setState(() {
          _datos = Map<String, dynamic>.from(json.decode(respuesta.body) as Map);
          _cargando = false;
        });
      } else {
        setState(() {
          _cargando = false;
          _error = mensajeError(respuesta, 'No se pudieron cargar los indicadores');
        });
      }
    } catch (_) {
      if (mounted && pedido == _pedido) {
        setState(() {
          _cargando = false;
          _error = mensajeSinConexion;
        });
      }
    }
  }

  String _consulta() {
    final partes = <String>['periodo=$_periodo'];
    if (_periodo == 'custom' && _desde != null && _hasta != null) {
      partes.add('desde=${_iso(_desde!)}');
      partes.add('hasta=${_iso(_hasta!)}');
    }
    if (_empresaId != null) partes.add('empresaId=$_empresaId');
    if (_tecnicoId != null) partes.add('tecnicoId=$_tecnicoId');
    return '/api/analisis?${partes.join('&')}';
  }

  Future<void> _elegirPeriodo(String periodo) async {
    if (periodo == 'custom') {
      final ahora = DateTime.now();
      final rango = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(ahora.year + 1, 12, 31),
        initialDateRange: _desde != null && _hasta != null ? DateTimeRange(start: _desde!, end: _hasta!) : null,
        helpText: 'Elegí el período',
        cancelText: 'Cancelar',
        confirmText: 'Aplicar',
        saveText: 'Aplicar',
      );
      if (rango == null || !mounted) return;
      setState(() {
        _periodo = 'custom';
        _desde = rango.start;
        _hasta = rango.end;
      });
    } else {
      setState(() => _periodo = periodo);
    }
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final datos = _datos;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _barraFiltros(datos),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600)),
          ],
          if (_cargando) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: datos == null
                ? Center(child: Text(_cargando ? 'Cargando...' : 'No se pudieron cargar los indicadores.', style: TextStyle(color: sonTextoSuave)))
                : LayoutBuilder(builder: (context, caja) {
                    return ListView(
                      children: [
                        _kpis(caja.maxWidth, Map<String, dynamic>.from(datos['kpis'] as Map? ?? {})),
                        const SizedBox(height: 18),
                        _graficos(caja.maxWidth, datos),
                        const SizedBox(height: 18),
                        _tecnicos(datos),
                        const SizedBox(height: 18),
                        _encuestas(Map<String, dynamic>.from(datos['encuestas'] as Map? ?? {})),
                        const SizedBox(height: 24),
                      ],
                    );
                  }),
          ),
        ],
      ),
    );
  }

  Widget _barraFiltros(Map<String, dynamic>? datos) {
    final opciones = Map<String, dynamic>.from(datos?['opciones'] as Map? ?? {});
    final clientes = ((opciones['clientes'] as List?) ?? []).map((c) => Map<String, dynamic>.from(c as Map)).toList();
    final tecnicos = ((opciones['tecnicos'] as List?) ?? []).map((t) => Map<String, dynamic>.from(t as Map)).toList();
    final etiquetaCustom = _desde != null && _hasta != null ? '${_dia(_desde!)} – ${_dia(_hasta!)}' : 'Personalizado';
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: double.infinity,
          child: EncabezadoPantalla(
            eyebrow: datos != null ? '${_fechaTexto(datos['desde'])} – ${_fechaTexto(datos['hasta'])}' : 'Operación',
            normal: 'Análisis y',
            destacado: 'estadísticas',
          ),
        ),
        SegmentedButton<String>(
          key: const Key('analisis_periodo'),
          showSelectedIcon: false,
          segments: [
            for (final periodo in _periodos)
              ButtonSegment(value: periodo.$1, label: Text(periodo.$1 == 'custom' ? etiquetaCustom : periodo.$2)),
          ],
          selected: {_periodo},
          onSelectionChanged: (elegido) => _elegirPeriodo(elegido.first),
        ),
        SizedBox(
          width: 230,
          child: DropdownButtonFormField<int?>(
            key: const Key('analisis_cliente'),
            initialValue: _empresaId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cliente', isDense: true),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Todos los clientes')),
              for (final cliente in clientes)
                DropdownMenuItem<int?>(value: (cliente['id'] as num).toInt(), child: Text('${cliente['nombre']}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (valor) {
              setState(() => _empresaId = valor);
              _cargar();
            },
          ),
        ),
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<int?>(
            key: const Key('analisis_tecnico'),
            initialValue: _tecnicoId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Técnico', isDense: true),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Todos los técnicos')),
              for (final tecnico in tecnicos)
                DropdownMenuItem<int?>(value: (tecnico['id'] as num).toInt(), child: Text('${tecnico['nombre']}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (valor) {
              setState(() => _tecnicoId = valor);
              _cargar();
            },
          ),
        ),
      ],
    );
  }

  Widget _kpis(double ancho, Map<String, dynamic> kpis) {
    final checklist = (kpis['checklist'] as num?)?.toInt();
    final completadas = (kpis['completadas'] as num?)?.toInt() ?? 0;
    final tarjetas = [
      _kpi('kpi_ordenes', 'Órdenes totales', '${(kpis['ordenes'] as num?)?.toInt() ?? 0}', Icons.assignment_outlined),
      _kpi('kpi_pendientes', 'Pendientes y vencidas', '${(kpis['pendientes'] as num?)?.toInt() ?? 0}', Icons.schedule),
      _kpi('kpi_checklist', 'Cumplimiento de checklist', checklist == null ? 'Sin datos' : '$checklist%', Icons.checklist),
      _kpi('kpi_cierre', 'Completadas', '$completadas', Icons.task_alt),
    ];
    if (ancho < 980) {
      final columna = (ancho - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final tarjeta in tarjetas) SizedBox(width: columna, child: tarjeta)],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < tarjetas.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: tarjetas[i]),
        ],
      ],
    );
  }

  Widget _kpi(String clave, String titulo, String valor, IconData icono) {
    return Container(
      key: Key(clave),
      padding: const EdgeInsets.all(18),
      decoration: decoracionTarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(titulo, style: TextStyle(color: sonTextoSuave))),
              Icon(icono, color: sonLightGreen, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(valor, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: sonTexto)),
        ],
      ),
    );
  }

  Widget _graficos(double ancho, Map<String, dynamic> datos) {
    final serie = Map<String, dynamic>.from(datos['serie'] as Map? ?? {});
    final puntos = ((serie['puntos'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p as Map)).toList();
    final clientes = ((datos['porCliente'] as List?) ?? []).map((c) => Map<String, dynamic>.from(c as Map)).toList();
    final totales = Map<String, dynamic>.from(datos['totales'] as Map? ?? {});
    final tiempo = _seccion(serie['modo'] == 'semana' ? 'Órdenes por semana' : 'Órdenes por mes', _barrasMes(puntos));
    final estados = _seccion('Verificación de órdenes', _barrasEstado(totales));
    final arriba = ancho < 980
        ? Column(children: [tiempo, const SizedBox(height: 16), estados])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: tiempo), const SizedBox(width: 16), Expanded(child: estados)]);
    return Column(
      children: [
        arriba,
        const SizedBox(height: 16),
        _seccion('Por cliente', _barrasCliente(clientes)),
      ],
    );
  }

  Widget _barrasMes(List<Map<String, dynamic>> puntos) {
    if (puntos.isEmpty || puntos.every((p) => ((p['ordenes'] as num?)?.toInt() ?? 0) == 0)) {
      return Text('No hay órdenes en este período.', style: TextStyle(color: sonTextoSuave));
    }
    final maximo = puntos.fold<int>(1, (mayor, p) {
      final n = (p['ordenes'] as num?)?.toInt() ?? 0;
      return n > mayor ? n : mayor;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 168,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final punto in puntos)
                Expanded(child: _columnaMes(punto, maximo)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _leyenda(sonLightGreen, 'Cerradas'),
            const SizedBox(width: 14),
            _leyenda(sonTarjetaAlta, 'Abiertas'),
          ],
        ),
      ],
    );
  }

  Widget _columnaMes(Map<String, dynamic> punto, int maximo) {
    final ordenes = (punto['ordenes'] as num?)?.toInt() ?? 0;
    final cerradas = (punto['completadas'] as num?)?.toInt() ?? 0;
    final alto = 120.0 * ordenes / maximo;
    final altoCerradas = ordenes == 0 ? 0.0 : alto * cerradas / ordenes;
    final altoAbiertas = alto - altoCerradas;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(ordenes == 0 ? '' : '$ordenes', style: TextStyle(color: sonTextoSuave, fontSize: 12)),
          const SizedBox(height: 4),
          SizedBox(
            height: 120,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  height: altoAbiertas,
                  width: 22,
                  decoration: BoxDecoration(
                    color: sonTarjetaAlta,
                    borderRadius: BorderRadius.vertical(top: const Radius.circular(5), bottom: altoCerradas == 0 ? const Radius.circular(5) : Radius.zero),
                  ),
                ),
                Container(
                  height: altoCerradas,
                  width: 22,
                  decoration: BoxDecoration(
                    color: sonLightGreen,
                    borderRadius: BorderRadius.vertical(bottom: const Radius.circular(5), top: altoAbiertas == 0 ? const Radius.circular(5) : Radius.zero),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('${punto['etiqueta']}', style: TextStyle(color: sonTextoSuave, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _barrasEstado(Map<String, dynamic> totales) {
    final filas = [
      ('Completadas', (totales['completadas'] as num?)?.toInt() ?? 0, sonLightGreen),
      ('En progreso', (totales['en_progreso'] as num?)?.toInt() ?? 0, sonAmbar),
      ('Pendientes', (totales['pendientes'] as num?)?.toInt() ?? 0, sonTextoSuave),
      ('Por asignar', (totales['por_asignar'] as num?)?.toInt() ?? 0, sonBorde),
    ].where((fila) => fila.$1 != 'Por asignar' || fila.$2 > 0).toList();
    final maximo = filas.fold<int>(1, (mayor, fila) => fila.$2 > mayor ? fila.$2 : mayor);
    if (filas.every((fila) => fila.$2 == 0)) {
      return Text('No hay órdenes en este período.', style: TextStyle(color: sonTextoSuave));
    }
    return Column(
      children: [
        for (final fila in filas)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(width: 110, child: Text(fila.$1, style: TextStyle(color: sonTexto))),
                Expanded(child: _barra(fila.$2 / maximo, fila.$3)),
                const SizedBox(width: 8),
                SizedBox(width: 28, child: Text('${fila.$2}', style: TextStyle(color: sonTexto, fontWeight: FontWeight.w700))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _barrasCliente(List<Map<String, dynamic>> clientes) {
    if (clientes.isEmpty) {
      return Text('No hay órdenes en este período.', style: TextStyle(color: sonTextoSuave));
    }
    final maximo = clientes.fold<int>(1, (mayor, c) {
      final n = (c['ordenes'] as num?)?.toInt() ?? 0;
      return n > mayor ? n : mayor;
    });
    return Column(
      children: [
        for (final cliente in clientes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${cliente['nombre']}', style: TextStyle(color: sonTexto))),
                    Text(_detalleCliente(cliente), style: TextStyle(color: sonTextoSuave, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                _barra(((cliente['ordenes'] as num?)?.toInt() ?? 0) / maximo, sonLightGreen),
              ],
            ),
          ),
      ],
    );
  }

  String _detalleCliente(Map<String, dynamic> cliente) {
    final ordenes = (cliente['ordenes'] as num?)?.toInt() ?? 0;
    final cerradas = (cliente['completadas'] as num?)?.toInt() ?? 0;
    if (cerradas == 0) return '$ordenes';
    return '$ordenes · $cerradas cerradas';
  }

  Widget _leyenda(Color color, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(texto, style: TextStyle(color: sonTextoSuave, fontSize: 12)),
      ],
    );
  }

  Widget _seccion(String titulo, Widget cuerpo) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: decoracionTarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: sonTexto)),
          const SizedBox(height: 14),
          cuerpo,
        ],
      ),
    );
  }

  Widget _tecnicos(Map<String, dynamic> datos) {
    final filas = ((datos['tecnicos'] as List?) ?? []).map((t) => Map<String, dynamic>.from(t as Map)).toList();
    return _seccion(
      'Rendimiento de técnicos',
      filas.isEmpty
          ? Text('No hay órdenes en este período.', style: TextStyle(color: sonTextoSuave))
          : LayoutBuilder(builder: (context, caja) {
              final ancho = caja.maxWidth < 860 ? 860.0 : caja.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: ancho,
                  child: Column(
                    children: [
                      _filaTecnico(null),
                      for (final fila in filas) _filaTecnico(fila),
                    ],
                  ),
                ),
              );
            }),
    );
  }

  Widget _filaTecnico(Map<String, dynamic>? fila) {
    if (fila == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            _celda('Técnico', 220, titulo: true),
            _celda('Órdenes', 220, titulo: true),
            _celda('% Checklist', 110, titulo: true),
            _celda('Tiempo en planta', 180, titulo: true),
            _celda('Calificación', 130, titulo: true),
          ],
        ),
      );
    }
    final id = (fila['id'] as num?)?.toInt() ?? 0;
    final nombre = '${fila['nombre'] ?? 'Sin técnico'}';
    final asignadas = (fila['asignadas'] as num?)?.toInt() ?? 0;
    final completadas = (fila['completadas'] as num?)?.toInt() ?? 0;
    final checklist = (fila['checklist'] as num?)?.toInt();
    final calificacion = fila['calificacion'] as num?;
    final avance = asignadas == 0 ? 0.0 : completadas / asignadas;
    return Padding(
      key: Key('tecnico_$id'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: sonLightGreen,
                  child: Text(_iniciales(nombre), style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(nombre, style: TextStyle(color: sonTexto))),
              ],
            ),
          ),
          SizedBox(
            width: 220,
            child: Row(
              children: [
                SizedBox(width: 52, child: Text('$completadas / $asignadas', style: TextStyle(color: sonTexto))),
                Expanded(child: _barra(avance, sonLightGreen)),
              ],
            ),
          ),
          _celda(checklist == null ? '—' : '$checklist%', 110),
          _celda(_tiempoDe(fila), 180),
          SizedBox(
            width: 130,
            child: calificacion == null
                ? Text('Sin notas', style: TextStyle(color: sonTextoSuave))
                : Row(
                    children: [
                      _estrellas(calificacion, tamano: 14),
                      const SizedBox(width: 4),
                      Text(_nota(calificacion), style: TextStyle(color: sonTexto, fontWeight: FontWeight.w700)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _encuestas(Map<String, dynamic> encuestas) {
    final enviados = (encuestas['enviados'] as num?)?.toInt() ?? 0;
    final respondidas = (encuestas['respondidas'] as num?)?.toInt() ?? 0;
    final tasa = (encuestas['tasa'] as num?)?.toInt();
    final promedio = encuestas['promedio'] as num?;
    final cruda = ((encuestas['distribucion'] as List?) ?? const []).map((n) => (n as num?)?.toInt() ?? 0).toList();
    final distribucion = List<int>.generate(5, (i) => i < cruda.length ? cruda[i] : 0);
    final detalle = ((encuestas['detalle'] as List?) ?? []).map((r) => Map<String, dynamic>.from(r as Map)).where(_pasaFiltro).toList();
    final maximo = distribucion.fold<int>(1, (mayor, n) => n > mayor ? n : mayor);
    return _seccion(
      'Encuestas por mail',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _pasoEmbudo('$enviados', 'Mails enviados'),
              Icon(Icons.chevron_right, color: sonTextoSuave),
              _pasoEmbudo('$respondidas', 'Encuestas respondidas'),
              Icon(Icons.chevron_right, color: sonTextoSuave),
              _pasoEmbudo(tasa == null ? '—' : '$tasa%', 'Tasa de respuesta'),
            ],
          ),
          const SizedBox(height: 6),
          Text('De los mails que salieron en este período.', style: TextStyle(color: sonTextoSuave, fontSize: 13)),
          const SizedBox(height: 18),
          if (respondidas == 0)
            Text('Todavía no hay respuestas en este período.', style: TextStyle(color: sonTextoSuave))
          else
            LayoutBuilder(builder: (context, caja) {
              final angosta = caja.maxWidth < 760;
              final distribucionPanel = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(promedio == null ? '—' : _nota(promedio), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: sonTexto)),
                          const SizedBox(width: 8),
                          Text('/ 5', style: TextStyle(color: sonTextoSuave)),
                          const SizedBox(width: 8),
                          if (promedio != null) _estrellas(promedio),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (var estrellas = 5; estrellas >= 1; estrellas--)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              SizedBox(width: 16, child: Text('$estrellas', style: TextStyle(color: sonTextoSuave))),
                              const SizedBox(width: 8),
                              Expanded(child: _barra((distribucion[estrellas - 1]) / maximo, sonLightGreen)),
                              const SizedBox(width: 8),
                              SizedBox(width: 24, child: Text('${distribucion[estrellas - 1]}', style: TextStyle(color: sonTextoSuave))),
                            ],
                          ),
                        ),
                    ],
                  );
              final comentariosPanel = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        key: const Key('filtro_encuestas'),
                        spacing: 8,
                        children: [
                          _chipEncuesta('todas', 'Ver todas'),
                          _chipEncuesta('comentarios', 'Con comentarios'),
                          _chipEncuesta('bajas', 'Calificación baja (≤3)'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (detalle.isEmpty)
                        Text('No hay respuestas con este filtro.', style: TextStyle(color: sonTextoSuave))
                      else
                        for (var i = 0; i < detalle.length; i++) _respuesta(detalle[i], i),
                    ],
                  );
              if (angosta) {
                return Column(children: [distribucionPanel, const SizedBox(height: 16), comentariosPanel]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: distribucionPanel),
                  const SizedBox(width: 20),
                  Expanded(child: comentariosPanel),
                ],
              );
            }),
        ],
      ),
    );
  }

  bool _pasaFiltro(Map<String, dynamic> respuesta) {
    final nota = (respuesta['puntaje'] as num?)?.toInt() ?? 0;
    final comentario = '${respuesta['comentario'] ?? ''}'.trim();
    if (_filtroEncuesta == 'comentarios') return comentario.isNotEmpty;
    if (_filtroEncuesta == 'bajas') return nota <= 3;
    return true;
  }

  Widget _chipEncuesta(String valor, String texto) {
    return ChoiceChip(
      key: Key('encuesta_$valor'),
      label: Text(texto),
      selected: _filtroEncuesta == valor,
      onSelected: (_) => setState(() => _filtroEncuesta = valor),
    );
  }

  Widget _respuesta(Map<String, dynamic> respuesta, int indice) {
    final nota = (respuesta['puntaje'] as num?) ?? 0;
    final comentario = '${respuesta['comentario'] ?? ''}'.trim();
    final baja = nota <= 3;
    return Container(
      key: Key('respuesta_$indice'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: sonTarjetaAlta, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${respuesta['cliente']}', style: TextStyle(fontWeight: FontWeight.w700, color: sonTexto))),
              Text('${respuesta['cuando'] ?? ''}', style: TextStyle(color: sonTextoSuave, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 2),
          Text('${respuesta['tecnico'] ?? 'Sin técnico'}', style: TextStyle(color: sonTextoSuave, fontSize: 13)),
          const SizedBox(height: 6),
          Row(children: [_estrellas(nota, tamano: 16), const SizedBox(width: 6), Text(_nota(nota), style: TextStyle(color: sonTexto, fontWeight: FontWeight.w700))]),
          if (comentario.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: sonTarjeta,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: baja ? sonRojo : sonBorde),
              ),
              child: Text(comentario, style: TextStyle(color: sonTexto)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pasoEmbudo(String valor, String etiqueta) {
    return Expanded(
      child: Column(
        children: [
          Text(valor, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: sonTexto)),
          const SizedBox(height: 2),
          Text(etiqueta, textAlign: TextAlign.center, style: TextStyle(color: sonTextoSuave, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _barra(double fraccion, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: fraccion.clamp(0, 1).toDouble(),
        minHeight: 10,
        color: color,
        backgroundColor: sonTarjetaAlta,
      ),
    );
  }

  Widget _celda(String texto, double ancho, {bool titulo = false}) {
    return SizedBox(
      width: ancho,
      child: Text(texto, style: TextStyle(color: titulo ? sonTextoSuave : sonTexto, fontWeight: titulo ? FontWeight.w700 : FontWeight.w500, fontSize: titulo ? 13 : 14)),
    );
  }

  Widget _estrellas(num nota, {double tamano = 18}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            nota >= i ? Icons.star : (nota >= i - 0.5 ? Icons.star_half : Icons.star_border),
            color: sonLightGreen,
            size: tamano,
          ),
      ],
    );
  }

  String _tiempoDe(Map<String, dynamic> fila) {
    final promedio = (fila['promedioMinutos'] as num?)?.toInt();
    final total = (fila['minutos'] as num?)?.toInt() ?? 0;
    if (promedio == null) return 'Sin tiempos';
    return '${_horasMinutos(promedio)} · total ${_horasMinutos(total)}';
  }

  String _horasMinutos(int total) {
    if (total < 60) return '$total min';
    final horas = total ~/ 60;
    final resto = total % 60;
    return resto == 0 ? '$horas h' : '$horas h $resto min';
  }

  String _nota(num valor) {
    final redondo = (valor * 10).round() / 10;
    return redondo == redondo.roundToDouble() ? redondo.toStringAsFixed(0) : redondo.toStringAsFixed(1);
  }

  String _iniciales(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((parte) => parte.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
  }

  String _iso(DateTime fecha) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${fecha.year}-${dos(fecha.month)}-${dos(fecha.day)}';
  }

  String _dia(DateTime fecha) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(fecha.day)}/${dos(fecha.month)}';
  }

  String _fechaTexto(Object? valor) {
    final texto = '$valor';
    final partes = texto.split('-');
    if (partes.length != 3) return texto;
    return '${partes[2]}/${partes[1]}/${partes[0]}';
  }
}
