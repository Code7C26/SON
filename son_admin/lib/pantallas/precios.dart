import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:son_admin/pantallas/piezas.dart';
import 'package:son_admin/services/api.dart';
import 'package:son_admin/theme/tema.dart';

/// Tarifario, costos internos, inflación y parámetros del presupuestador.
class PantallaPrecios extends StatefulWidget {
  const PantallaPrecios({super.key});

  @override
  State<PantallaPrecios> createState() => _PantallaPreciosState();
}

class _PantallaPreciosState extends State<PantallaPrecios> with SingleTickerProviderStateMixin {
  late final TabController _pestanas = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _pestanas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Precios', style: estiloTituloPantalla),
          const SizedBox(height: 20),
          TabBar(
            controller: _pestanas,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Tarifario'),
              Tab(text: 'Costos'),
              Tab(text: 'Inflación'),
              Tab(text: 'Parámetros'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _pestanas,
              children: const [
                _PestanaTarifas(),
                _PestanaCostos(),
                _PestanaInflacion(),
                _PestanaParametros(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Tarifario ----------

class _PestanaTarifas extends StatefulWidget {
  const _PestanaTarifas();

  @override
  State<_PestanaTarifas> createState() => _PestanaTarifasState();
}

class _PestanaTarifasState extends State<_PestanaTarifas> {
  List<Map<String, dynamic>> _tarifas = [];
  List<String> _familias = [];
  bool _cargando = true;
  String? _error;
  String _familia = '';
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
    if (!_cargando) setState(() => _cargando = true);
    try {
      final respuesta = await apiGet('/api/tarifas');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        final datos = json.decode(respuesta.body) as Map;
        setState(() {
          _tarifas = (datos['tarifas'] as List).map((t) => Map<String, dynamic>.from(t as Map)).toList();
          _familias = (datos['familias'] as List).map((f) => '$f').toList();
          _error = null;
          _cargando = false;
        });
      } else {
        setState(() {
          _error = mensajeError(respuesta, 'No se pudo leer el tarifario');
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _cargando = false; });
    }
  }

  Future<void> _abrir([Map<String, dynamic>? tarifa]) async {
    final guardado = await showDialog<bool>(context: context, builder: (_) => _DialogoTarifa(tarifa: tarifa, familias: _familias));
    if (guardado == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tarifa == null ? 'Tarifa creada' : 'Tarifa actualizada')));
      _cargar();
    }
  }

  Future<void> _borrar(Map<String, dynamic> tarifa) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar tarifa'),
        content: Text('¿Borrar "${tarifa['servicio']}"? Los presupuestos ya armados no se tocan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final respuesta = await apiSend('DELETE', '/api/tarifas/${tarifa['id']}');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarifa borrada')));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(respuesta, 'No se pudo borrar'))));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(mensajeSinConexion)));
    }
  }

  List<Map<String, dynamic>> get _visibles {
    return _tarifas.where((t) {
      if (_familia.isNotEmpty && t['familia'] != _familia) return false;
      final texto = '${t['familia']} ${t['servicio']} ${t['tramo']} ${t['detalle'] ?? ''}';
      return coincideBusqueda(texto, _busqueda.text);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, style: TextStyle(color: sonRojo)), SizedBox(height: 12), OutlinedButton.icon(onPressed: _cargar, icon: Icon(Icons.refresh), label: Text('Reintentar'))]));
    }
    final visibles = _visibles;
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                key: const Key('buscar_tarifa'),
                controller: _busqueda,
                decoration: InputDecoration(
                  hintText: 'Buscar servicio o tramo...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  suffixIcon: _busqueda.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _busqueda.clear),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                key: const Key('filtro_familia'),
                initialValue: _familia,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, labelText: 'Familia'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Todas')),
                  for (final f in _familias) DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _familia = v ?? ''),
              ),
            ),
            const SizedBox(width: 12),
            Text('${visibles.length} tarifas', style: TextStyle(color: sonTextoSuave)),
            const Spacer(),
            ElevatedButton.icon(
              key: const Key('nueva_tarifa'),
              onPressed: () => _abrir(),
              icon: Icon(Icons.add, color: sonDarkGreen),
              label: Text('Nueva tarifa', style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: visibles.isEmpty
              ? Center(child: Text('No hay tarifas con esa búsqueda.', style: TextStyle(color: sonTextoSuave)))
              : ListView.separated(
                  itemCount: visibles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final t = visibles[i];
                    final sinValor = t['valorActual'] == null && t['modulos'] == null;
                    return InkWell(
                      key: Key('tarifa_${t['id']}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _abrir(t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: decoracionTarjeta(),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${t['servicio']}', style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Text(
                                    [t['familia'], t['tramo'], t['detalle']].where((x) => '$x'.trim().isNotEmpty).join(' · '),
                                    style: TextStyle(color: sonTextoSuave, fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            if (t['indexa'] == true && t['modulos'] == null)
                              Padding(padding: EdgeInsets.only(right: 12), child: Tooltip(message: 'Se actualiza por inflación', child: Icon(Icons.trending_up, size: 18, color: sonAzul))),
                            Text(
                              sinValor ? 'Sin valor' : pesos(t['valorActual'] as num?),
                              style: TextStyle(color: sinValor ? sonAmbar : sonTexto, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            IconButton(tooltip: 'Borrar', onPressed: () => _borrar(t), icon: Icon(Icons.delete_outline, color: sonTextoSuave)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DialogoTarifa extends StatefulWidget {
  final Map<String, dynamic>? tarifa;
  final List<String> familias;
  const _DialogoTarifa({this.tarifa, required this.familias});

  @override
  State<_DialogoTarifa> createState() => _DialogoTarifaState();
}

class _DialogoTarifaState extends State<_DialogoTarifa> {
  late final TextEditingController _familia = TextEditingController(text: '${widget.tarifa?['familia'] ?? ''}');
  late final TextEditingController _servicio = TextEditingController(text: '${widget.tarifa?['servicio'] ?? ''}');
  late final TextEditingController _tramo = TextEditingController(text: '${widget.tarifa?['tramo'] ?? ''}');
  late final TextEditingController _detalle = TextEditingController(text: '${widget.tarifa?['detalle'] ?? ''}');
  late final TextEditingController _valor = TextEditingController(text: widget.tarifa?['valorBase'] == null ? '' : '${widget.tarifa!['valorBase']}');
  late final TextEditingController _mes = TextEditingController(text: '${widget.tarifa?['mesBase'] ?? ''}');
  late final TextEditingController _modulos = TextEditingController(text: widget.tarifa?['modulos'] == null ? '' : '${widget.tarifa!['modulos']}');
  late final TextEditingController _alcance = TextEditingController(text: '${widget.tarifa?['alcance'] ?? ''}');
  late bool _indexa = widget.tarifa?['indexa'] != false;
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in [_familia, _servicio, _tramo, _detalle, _valor, _mes, _modulos, _alcance]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() { _error = null; _guardando = true; });
    final cuerpo = json.encode({
      'familia': _familia.text,
      'servicio': _servicio.text,
      'tramo': _tramo.text,
      'detalle': _detalle.text,
      'valorBase': numeroDePersona(_valor.text),
      'mesBase': _mes.text.trim().isEmpty ? null : _mes.text.trim(),
      'modulos': numeroDePersona(_modulos.text),
      'alcance': _alcance.text,
      'indexa': _indexa,
    });
    try {
      final respuesta = widget.tarifa == null
          ? await apiSend('POST', '/api/tarifas', cuerpo)
          : await apiSend('PUT', '/api/tarifas/${widget.tarifa!['id']}', cuerpo);
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        Navigator.pop(context, true);
        return;
      }
      setState(() { _error = mensajeError(respuesta, 'No se pudo guardar'); _guardando = false; });
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _guardando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.tarifa == null ? 'Nueva tarifa' : 'Editar tarifa'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _familia, decoration: InputDecoration(labelText: 'Familia (CIEC, Colegio de Geólogos...)', suffixIcon: PopupMenuButton<String>(
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (v) => _familia.text = v,
                itemBuilder: (_) => [for (final f in widget.familias) PopupMenuItem(value: f, child: Text(f))],
              ))),
              const SizedBox(height: 12),
              TextField(controller: _servicio, decoration: const InputDecoration(labelText: 'Servicio *')),
              const SizedBox(height: 12),
              TextField(controller: _tramo, decoration: const InputDecoration(labelText: 'Tramo (1 a 15 trabajadores...)')),
              const SizedBox(height: 12),
              TextField(controller: _detalle, decoration: const InputDecoration(labelText: 'Detalle')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: _valor, decoration: const InputDecoration(labelText: 'Valor de lista (pesos)'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _mes, decoration: const InputDecoration(labelText: 'Mes del valor (AAAA-MM)'))),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _modulos, decoration: const InputDecoration(labelText: 'Módulos (si se cobra por módulo, en vez del valor)')),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Se actualiza por inflación (IPC)'),
                value: _indexa,
                onChanged: (v) => setState(() => _indexa = v),
              ),
              TextField(controller: _alcance, maxLines: 4, decoration: const InputDecoration(labelText: 'Alcance (sale en el PDF, hoja aparte)')),
              if (_error != null) Padding(padding: EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.pop(context, false), child: Text('Cancelar', style: TextStyle(color: sonTextoSuave))),
        ElevatedButton(onPressed: _guardando ? null : _guardar, child: Text(widget.tarifa == null ? 'Crear' : 'Guardar')),
      ],
    );
  }
}

// ---------- Costos ----------

class _PestanaCostos extends StatefulWidget {
  const _PestanaCostos();

  @override
  State<_PestanaCostos> createState() => _PestanaCostosState();
}

class _PestanaCostosState extends State<_PestanaCostos> {
  List<Map<String, dynamic>> _costos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!_cargando) setState(() => _cargando = true);
    try {
      final respuesta = await apiGet('/api/costos');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        final datos = json.decode(respuesta.body) as Map;
        setState(() {
          _costos = (datos['costos'] as List).map((c) => Map<String, dynamic>.from(c as Map)).toList();
          _error = null;
          _cargando = false;
        });
      } else {
        setState(() { _error = mensajeError(respuesta, 'No se pudieron leer los costos'); _cargando = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _cargando = false; });
    }
  }

  Future<void> _abrir([Map<String, dynamic>? costo]) async {
    final guardado = await showDialog<bool>(context: context, builder: (_) => _DialogoCosto(costo: costo));
    if (guardado == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(costo == null ? 'Costo creado' : 'Costo actualizado')));
      _cargar();
    }
  }

  Future<void> _borrar(Map<String, dynamic> costo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar costo'),
        content: Text('¿Borrar "${costo['concepto']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final respuesta = await apiSend('DELETE', '/api/costos/${costo['id']}');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Costo borrado')));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(respuesta, 'No se pudo borrar'))));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(mensajeSinConexion)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, style: TextStyle(color: sonRojo)), SizedBox(height: 12), OutlinedButton.icon(onPressed: _cargar, icon: Icon(Icons.refresh), label: Text('Reintentar'))]));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Spacer(),
            ElevatedButton.icon(
              key: const Key('nuevo_costo'),
              onPressed: () => _abrir(),
              icon: Icon(Icons.add, color: sonDarkGreen),
              label: Text('Nuevo costo', style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _costos.isEmpty
              ? Center(child: Text('Todavía no hay costos. Cargá la hora del técnico, viáticos, hotel...', style: TextStyle(color: sonTextoSuave)))
              : ListView.separated(
                  itemCount: _costos.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = _costos[i];
                    final sinValor = c['valorActual'] == null;
                    return InkWell(
                      key: Key('costo_${c['id']}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _abrir(c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: decoracionTarjeta(),
                        child: Row(
                          children: [
                            Expanded(child: Text('${c['concepto']}', style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600, fontSize: 15))),
                            Text('${c['unidad'] ?? ''}', style: TextStyle(color: sonTextoSuave)),
                            const SizedBox(width: 16),
                            Text(sinValor ? 'Sin valor' : pesos(c['valorActual'] as num?), style: TextStyle(color: sinValor ? sonAmbar : sonTexto, fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(tooltip: 'Borrar', onPressed: () => _borrar(c), icon: Icon(Icons.delete_outline, color: sonTextoSuave)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DialogoCosto extends StatefulWidget {
  final Map<String, dynamic>? costo;
  const _DialogoCosto({this.costo});

  @override
  State<_DialogoCosto> createState() => _DialogoCostoState();
}

class _DialogoCostoState extends State<_DialogoCosto> {
  late final TextEditingController _concepto = TextEditingController(text: '${widget.costo?['concepto'] ?? ''}');
  late final TextEditingController _unidad = TextEditingController(text: '${widget.costo?['unidad'] ?? 'unidad'}');
  late final TextEditingController _valor = TextEditingController(text: widget.costo?['valorBase'] == null ? '' : '${widget.costo!['valorBase']}');
  late final TextEditingController _mes = TextEditingController(text: '${widget.costo?['mesBase'] ?? ''}');
  late bool _indexa = widget.costo?['indexa'] != false;
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _concepto.dispose();
    _unidad.dispose();
    _valor.dispose();
    _mes.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() { _error = null; _guardando = true; });
    final cuerpo = json.encode({
      'concepto': _concepto.text,
      'unidad': _unidad.text,
      'valorBase': numeroDePersona(_valor.text),
      'mesBase': _mes.text.trim().isEmpty ? null : _mes.text.trim(),
      'indexa': _indexa,
    });
    try {
      final respuesta = widget.costo == null ? await apiSend('POST', '/api/costos', cuerpo) : await apiSend('PUT', '/api/costos/${widget.costo!['id']}', cuerpo);
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        Navigator.pop(context, true);
        return;
      }
      setState(() { _error = mensajeError(respuesta, 'No se pudo guardar'); _guardando = false; });
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _guardando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.costo == null ? 'Nuevo costo' : 'Editar costo'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _concepto, decoration: const InputDecoration(labelText: 'Nombre (Hora Técnico, Viáticos...)')),
            const SizedBox(height: 12),
            TextField(controller: _unidad, decoration: const InputDecoration(labelText: 'Unidad (hora, km, noche...)')),
            const SizedBox(height: 12),
            TextField(controller: _valor, decoration: const InputDecoration(labelText: 'Valor (pesos). Dejalo vacío si todavía no lo tienen.')),
            const SizedBox(height: 12),
            TextField(controller: _mes, decoration: const InputDecoration(labelText: 'Mes del valor (AAAA-MM)')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Se actualiza por inflación'), value: _indexa, onChanged: (v) => setState(() => _indexa = v)),
            if (_error != null) Text(_error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.pop(context, false), child: Text('Cancelar', style: TextStyle(color: sonTextoSuave))),
        ElevatedButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

// ---------- Inflación ----------

class _PestanaInflacion extends StatefulWidget {
  const _PestanaInflacion();

  @override
  State<_PestanaInflacion> createState() => _PestanaInflacionState();
}

class _PestanaInflacionState extends State<_PestanaInflacion> {
  List<Map<String, dynamic>> _meses = [];
  Map<String, dynamic>? _busqueda;
  bool _cargando = true;
  bool _buscando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!_cargando) setState(() => _cargando = true);
    try {
      final respuesta = await apiGet('/api/ipc');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        final datos = json.decode(respuesta.body) as Map;
        setState(() {
          _meses = (datos['meses'] as List).map((m) => Map<String, dynamic>.from(m as Map)).toList();
          _busqueda = datos['busqueda'] is Map ? Map<String, dynamic>.from(datos['busqueda'] as Map) : null;
          _error = null;
          _cargando = false;
        });
      } else {
        setState(() { _error = mensajeError(respuesta, 'No se pudo leer la inflación'); _cargando = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _cargando = false; });
    }
  }

  Future<void> _sincronizar() async {
    setState(() => _buscando = true);
    try {
      final respuesta = await apiSend('POST', '/api/ipc/sincronizar');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        final datos = json.decode(respuesta.body) as Map;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('INDEC: ${datos['nuevos']} meses nuevos, ${datos['actualizados']} actualizados. Último: ${datos['ultimoMes'] ?? '—'}.')));
        await _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(respuesta, 'No se pudo consultar al INDEC'))));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(mensajeSinConexion)));
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _cargarAMano() async {
    final mes = TextEditingController();
    final porcentaje = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cargar un mes a mano'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: mes, decoration: const InputDecoration(labelText: 'Mes (AAAA-MM)', hintText: '2026-08')),
              const SizedBox(height: 12),
              TextField(controller: porcentaje, decoration: const InputDecoration(labelText: 'Inflación de ese mes (%)', hintText: '1,7')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final respuesta = await apiSend('PUT', '/api/ipc/${mes.text.trim()}', json.encode({'porcentaje': porcentaje.text}));
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mes guardado (no lo pisa la búsqueda del INDEC)')));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(respuesta, 'No se pudo guardar'))));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(mensajeSinConexion)));
    }
  }

  Future<void> _borrar(String mes) async {
    try {
      final respuesta = await apiSend('DELETE', '/api/ipc/$mes');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(respuesta, 'No se pudo borrar'))));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(mensajeSinConexion)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, style: TextStyle(color: sonRojo)), SizedBox(height: 12), OutlinedButton.icon(onPressed: _cargar, icon: Icon(Icons.refresh), label: Text('Reintentar'))]));
    }
    final aviso = _busqueda != null && _busqueda!['ok'] == false ? '${_busqueda!['error'] ?? ''}' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(aviso.isEmpty ? 'Se busca sola en el INDEC. Lo que cargues a mano no se pisa.' : 'Última búsqueda falló: $aviso', style: TextStyle(color: aviso.isEmpty ? sonTextoSuave : sonAmbar))),
            OutlinedButton.icon(onPressed: _buscando ? null : _cargarAMano, icon: const Icon(Icons.edit_outlined), label: const Text('Cargar a mano')),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              key: const Key('buscar_indec'),
              onPressed: _buscando ? null : _sincronizar,
              icon: _buscando ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.cloud_download_outlined, color: sonDarkGreen),
              label: Text('Buscar en INDEC', style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _meses.isEmpty
              ? Center(child: Text('Todavía no hay meses cargados. Tocá "Buscar en INDEC".', style: TextStyle(color: sonTextoSuave)))
              : ListView.separated(
                  itemCount: _meses.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = _meses[i];
                    final manual = m['fuente'] == 'Manual';
                    return ListTile(
                      dense: true,
                      title: Text('${m['mes']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${m['porcentaje']} %', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 12),
                          EtiquetaEstado(texto: manual ? 'Manual' : 'INDEC', color: manual ? sonAmbar : sonAzul),
                          IconButton(tooltip: 'Borrar', onPressed: () => _borrar('${m['mes']}'), icon: Icon(Icons.delete_outline, size: 18, color: sonTextoSuave)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------- Parámetros ----------

class _PestanaParametros extends StatefulWidget {
  const _PestanaParametros();

  @override
  State<_PestanaParametros> createState() => _PestanaParametrosState();
}

class _PestanaParametrosState extends State<_PestanaParametros> {
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  late final TextEditingController _margenMin = TextEditingController();
  late final TextEditingController _margenIdeal = TextEditingController();
  late final TextEditingController _iva = TextEditingController();
  late final TextEditingController _modulo = TextEditingController();
  late final TextEditingController _proximo = TextEditingController();
  late final TextEditingController _titulo = TextEditingController();
  late final TextEditingController _razon = TextEditingController();
  late final TextEditingController _cuit = TextEditingController();
  late final TextEditingController _direccion = TextEditingController();
  late final TextEditingController _telefonos = TextEditingController();
  late final TextEditingController _ivaCond = TextEditingController();
  late final TextEditingController _celular = TextEditingController();
  late final TextEditingController _email = TextEditingController();
  late final TextEditingController _web = TextEditingController();
  late final TextEditingController _firmaNombre = TextEditingController();
  late final TextEditingController _firmaCargo = TextEditingController();
  late final TextEditingController _firmaEmpresa = TextEditingController();
  late final TextEditingController _formaPago = TextEditingController();
  late final TextEditingController _plazo = TextEditingController();
  late final TextEditingController _validez = TextEditingController();
  late final TextEditingController _codigo = TextEditingController();

  List<TextEditingController> get _todos => [_margenMin, _margenIdeal, _iva, _modulo, _proximo, _titulo, _razon, _cuit, _direccion, _telefonos, _ivaCond, _celular, _email, _web, _firmaNombre, _firmaCargo, _firmaEmpresa, _formaPago, _plazo, _validez, _codigo];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _todos) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final respuesta = await apiGet('/api/comercial/config');
      if (!mounted) return;
      if (respuesta.statusCode != 200) {
        setState(() { _error = mensajeError(respuesta, 'No se pudo leer la configuración'); _cargando = false; });
        return;
      }
      final d = json.decode(respuesta.body) as Map;
      final empresa = Map<String, dynamic>.from(d['empresa'] as Map? ?? {});
      final firma = Map<String, dynamic>.from(d['firma'] as Map? ?? {});
      final textos = Map<String, dynamic>.from(d['textos'] as Map? ?? {});
      _margenMin.text = '${d['margenMinimo'] ?? ''}';
      _margenIdeal.text = '${d['margenIdeal'] ?? ''}';
      _iva.text = '${d['iva'] ?? ''}';
      _modulo.text = '${d['valorModulo'] ?? ''}';
      _proximo.text = '${d['proximoNumero'] ?? ''}';
      _titulo.text = '${empresa['titulo'] ?? ''}';
      _razon.text = '${empresa['razon_social'] ?? ''}';
      _cuit.text = '${empresa['cuit'] ?? ''}';
      _direccion.text = '${empresa['direccion'] ?? ''}';
      _telefonos.text = '${empresa['telefonos'] ?? ''}';
      _ivaCond.text = '${empresa['iva'] ?? ''}';
      _celular.text = '${empresa['celular'] ?? ''}';
      _email.text = '${empresa['email'] ?? ''}';
      _web.text = '${empresa['web'] ?? ''}';
      _firmaNombre.text = '${firma['nombre'] ?? ''}';
      _firmaCargo.text = '${firma['cargo'] ?? ''}';
      _firmaEmpresa.text = '${firma['empresa'] ?? ''}';
      _formaPago.text = '${textos['forma_pago'] ?? ''}';
      _plazo.text = '${textos['plazo_entrega'] ?? ''}';
      _validez.text = '${textos['validez'] ?? ''}';
      _codigo.text = '${textos['codigo_formulario'] ?? ''}';
      setState(() { _error = null; _cargando = false; });
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _cargando = false; });
    }
  }

  Future<void> _guardar() async {
    setState(() { _error = null; _guardando = true; });
    final cuerpo = json.encode({
      'margenMinimo': numeroDePersona(_margenMin.text),
      'margenIdeal': numeroDePersona(_margenIdeal.text),
      'iva': numeroDePersona(_iva.text),
      'valorModulo': numeroDePersona(_modulo.text),
      'proximoNumero': int.tryParse(_proximo.text.trim()),
      'empresa': {
        'titulo': _titulo.text, 'razon_social': _razon.text, 'cuit': _cuit.text, 'direccion': _direccion.text,
        'telefonos': _telefonos.text, 'iva': _ivaCond.text, 'celular': _celular.text, 'email': _email.text, 'web': _web.text,
      },
      'firma': {'nombre': _firmaNombre.text, 'cargo': _firmaCargo.text, 'empresa': _firmaEmpresa.text},
      'textos': {'forma_pago': _formaPago.text, 'plazo_entrega': _plazo.text, 'validez': _validez.text, 'codigo_formulario': _codigo.text},
    });
    try {
      final respuesta = await apiSend('PUT', '/api/comercial/config', cuerpo);
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parámetros guardados')));
      } else {
        setState(() { _error = mensajeError(respuesta, 'No se pudo guardar'); _guardando = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _guardando = false; });
    }
  }

  Widget _campo(String etiqueta, TextEditingController c, {int lineas = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: c, maxLines: lineas, decoration: InputDecoration(labelText: etiqueta)),
      );

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              Text('Márgenes y números', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _campo('Margen mínimo (%)', _margenMin)),
                const SizedBox(width: 12),
                Expanded(child: _campo('Margen ideal (%)', _margenIdeal)),
                const SizedBox(width: 12),
                Expanded(child: _campo('IVA (%)', _iva)),
              ]),
              Row(children: [
                Expanded(child: _campo('Valor del módulo (Colegio de Geólogos)', _modulo)),
                const SizedBox(width: 12),
                Expanded(child: _campo('Próximo número de presupuesto', _proximo)),
              ]),
              const SizedBox(height: 8),
              Text('Datos de SIMA en el PDF', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 10),
              _campo('Título', _titulo),
              Row(children: [Expanded(child: _campo('Razón social', _razon)), const SizedBox(width: 12), Expanded(child: _campo('CUIT', _cuit))]),
              _campo('Dirección', _direccion),
              Row(children: [Expanded(child: _campo('Teléfonos', _telefonos)), const SizedBox(width: 12), Expanded(child: _campo('Celular', _celular))]),
              Row(children: [Expanded(child: _campo('IVA', _ivaCond)), const SizedBox(width: 12), Expanded(child: _campo('Correo', _email))]),
              _campo('Página web', _web),
              Text('Firma', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 10),
              Row(children: [Expanded(child: _campo('Nombre', _firmaNombre)), const SizedBox(width: 12), Expanded(child: _campo('Cargo', _firmaCargo)), const SizedBox(width: 12), Expanded(child: _campo('Empresa', _firmaEmpresa))]),
              Text('Textos por defecto del presupuesto', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 10),
              _campo('Forma de pago', _formaPago),
              _campo('Plazo de entrega', _plazo),
              _campo('Validez de la oferta', _validez, lineas: 2),
              _campo('Código del formulario', _codigo),
              if (_error != null) Text(_error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            key: const Key('guardar_parametros'),
            onPressed: _guardando ? null : _guardar,
            child: const Text('Guardar parámetros'),
          ),
        ),
      ],
    );
  }
}
