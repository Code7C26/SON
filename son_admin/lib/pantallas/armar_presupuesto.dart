import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:son_admin/config/api_config.dart';
import 'package:son_admin/pantallas/piezas.dart';
import 'package:son_admin/services/abrir_informe.dart';
import 'package:son_admin/services/api.dart';
import 'package:son_admin/services/sesion.dart';
import 'package:son_admin/theme/tema.dart';

/// Pantalla para armar o editar un presupuesto (borrador).
class PantallaArmarPresupuesto extends StatefulWidget {
  final int? presupuestoId;
  final List<Map<String, dynamic>>? notas;

  const PantallaArmarPresupuesto({super.key, this.presupuestoId, this.notas});

  @override
  State<PantallaArmarPresupuesto> createState() => _PantallaArmarPresupuestoState();
}

class _Linea {
  int? tarifaId;
  String? tarifaNombre;
  int? costoId;
  final descripcion = TextEditingController();
  final cantidad = TextEditingController(text: '1');
  final precio = TextEditingController();
  final horas = TextEditingController();
  final alcance = TextEditingController();
  String periodicidad = 'mensual';
  final cuotas = TextEditingController();
  bool bonificable = true;

  void dispose() {
    descripcion.dispose();
    cantidad.dispose();
    precio.dispose();
    horas.dispose();
    alcance.dispose();
    cuotas.dispose();
  }

  Map<String, dynamic> aCuerpo() {
    final cuerpo = <String, dynamic>{
      'descripcion': descripcion.text,
      'alcance': alcance.text,
      'cantidad': numeroDePersona(cantidad.text) ?? 1,
      'periodicidad': periodicidad,
      'bonificable': bonificable,
    };
    if (tarifaId != null) cuerpo['tarifaId'] = tarifaId;
    final precioManual = numeroDePersona(precio.text);
    if (precioManual != null) cuerpo['precioManual'] = precioManual;
    if (periodicidad == 'unico') {
      final n = int.tryParse(cuotas.text.trim());
      if (n != null && n >= 2) cuerpo['prorratearMeses'] = n;
    }
    final horasN = numeroDePersona(horas.text);
    if (costoId != null && horasN != null) {
      cuerpo['costeo'] = [{'costoId': costoId, 'cantidad': horasN}];
    }
    return cuerpo;
  }
}

class _PantallaArmarPresupuestoState extends State<PantallaArmarPresupuesto> {
  final List<_Linea> _lineas = [];
  final List<int> _solicitudIds = [];
  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _tarifas = [];
  List<Map<String, dynamic>> _costos = [];
  int? _id;
  int? _empresaId;
  String _estado = 'Borrador';
  String? _etiqueta;
  bool _editable = true;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  Map<String, dynamic>? _calculo;
  List<Map<String, dynamic>> _itemsCalc = [];
  Timer? _reloj;

  final _cliente = TextEditingController();
  final _atencion = TextEditingController();
  final _bonificacion = TextEditingController();
  final _observaciones = TextEditingController();
  final _referencia = TextEditingController();
  final _formaPago = TextEditingController();
  final _plazo = TextEditingController();
  final _validez = TextEditingController();
  final _focoCliente = FocusNode();

  @override
  void initState() {
    super.initState();
    for (final c in [_cliente, _atencion, _bonificacion, _observaciones, _referencia, _formaPago, _plazo, _validez]) {
      c.addListener(_programarCalculo);
    }
    _preparar();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    for (final c in [_cliente, _atencion, _bonificacion, _observaciones, _referencia, _formaPago, _plazo, _validez]) {
      c.dispose();
    }
    _focoCliente.dispose();
    for (final l in _lineas) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _preparar() async {
    try {
      await Future.wait([_cargarCatalogos(), if (widget.presupuestoId != null) _cargarPresupuesto() else Future.value()]);
      if (widget.presupuestoId == null) _cargarNotas();
      if (_lineas.isEmpty) _agregarLinea();
      if (!mounted) return;
      setState(() => _cargando = false);
      _calcular();
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _cargando = false; });
    }
  }

  Future<void> _cargarCatalogos() async {
    final respuestas = await Future.wait([apiGet('/api/clientes'), apiGet('/api/tarifas'), apiGet('/api/costos'), apiGet('/api/comercial/config')]);
    if (respuestas[0].statusCode == 200) {
      _clientes = (json.decode(respuestas[0].body) as List).map((c) => Map<String, dynamic>.from(c as Map)).toList();
    }
    if (respuestas[1].statusCode == 200) {
      final datos = json.decode(respuestas[1].body) as Map;
      _tarifas = (datos['tarifas'] as List).map((t) => Map<String, dynamic>.from(t as Map)).where((t) => t['activa'] != false).toList();
    }
    if (respuestas[2].statusCode == 200) {
      final datos = json.decode(respuestas[2].body) as Map;
      _costos = (datos['costos'] as List).map((c) => Map<String, dynamic>.from(c as Map)).toList();
    }
    if (respuestas[3].statusCode == 200 && widget.presupuestoId == null) {
      final config = json.decode(respuestas[3].body) as Map;
      final textos = Map<String, dynamic>.from(config['textos'] as Map? ?? {});
      _formaPago.text = '${textos['forma_pago'] ?? ''}';
      _plazo.text = '${textos['plazo_entrega'] ?? ''}';
      _validez.text = '${textos['validez'] ?? ''}';
    }
  }

  Future<void> _cargarPresupuesto() async {
    final respuesta = await apiGet('/api/presupuestos/${widget.presupuestoId}');
    if (respuesta.statusCode != 200) {
      _error = mensajeError(respuesta, 'No se pudo abrir el presupuesto');
      return;
    }
    final d = json.decode(respuesta.body) as Map;
    _id = (d['id'] as num).toInt();
    _etiqueta = '${d['etiqueta']}';
    _estado = '${d['estado']}';
    _editable = d['editable'] == true;
    _empresaId = (d['empresaId'] as num?)?.toInt();
    final cliente = Map<String, dynamic>.from(d['cliente'] as Map? ?? {});
    _cliente.text = '${cliente['razonSocial'] ?? ''}';
    _atencion.text = '${cliente['atencion'] ?? ''}';
    _bonificacion.text = d['bonificacion'] == 0 || d['bonificacion'] == null ? '' : '${d['bonificacion']}';
    _observaciones.text = '${d['observaciones'] ?? ''}';
    _referencia.text = '${d['referencia'] ?? ''}';
    _formaPago.text = '${d['formaPago'] ?? ''}';
    _plazo.text = '${d['plazoEntrega'] ?? ''}';
    _validez.text = '${d['validez'] ?? ''}';
    _solicitudIds.addAll(((d['solicitudIds'] as List?) ?? []).map((x) => (x as num).toInt()));
    for (final item in (d['items'] as List? ?? [])) {
      final mapa = Map<String, dynamic>.from(item as Map);
      final linea = _Linea();
      linea.tarifaId = (mapa['tarifaId'] as num?)?.toInt();
      linea.descripcion.text = '${mapa['descripcion'] ?? ''}';
      linea.alcance.text = '${mapa['alcance'] ?? ''}';
      linea.cantidad.text = '${mapa['cantidad'] ?? 1}';
      if (mapa['precioOrigen'] == 'manual') linea.precio.text = '${(mapa['precioUnitario'] as num?)?.round() ?? ''}';
      linea.periodicidad = '${mapa['periodicidad'] ?? 'mensual'}';
      if (mapa['prorratearMeses'] != null) linea.cuotas.text = '${mapa['prorratearMeses']}';
      linea.bonificable = mapa['bonificable'] != false;
      final costeo = (mapa['costeo'] as List? ?? []);
      if (costeo.isNotEmpty) {
        final parte = Map<String, dynamic>.from(costeo.first as Map);
        linea.costoId = (parte['costoId'] as num?)?.toInt();
        linea.horas.text = '${parte['cantidad'] ?? ''}';
      }
      _escuchar(linea);
      _lineas.add(linea);
    }
  }

  void _cargarNotas() {
    final notas = widget.notas ?? [];
    if (notas.isEmpty) return;
    _empresaId = (notas.first['empresa_id'] as num?)?.toInt();
    _cliente.text = '${notas.first['empresa'] ?? ''}';
    for (final nota in notas) {
      _solicitudIds.add((nota['id'] as num).toInt());
      final linea = _Linea();
      linea.descripcion.text = '${nota['descripcion'] ?? ''}';
      linea.cantidad.text = '${nota['cantidad'] ?? 1}';
      linea.periodicidad = 'unico';
      linea.bonificable = false;
      _escuchar(linea);
      _lineas.add(linea);
    }
  }

  void _escuchar(_Linea linea) {
    for (final c in [linea.descripcion, linea.cantidad, linea.precio, linea.horas, linea.alcance, linea.cuotas]) {
      c.addListener(_programarCalculo);
    }
  }

  void _agregarLinea() {
    final linea = _Linea();
    _escuchar(linea);
    setState(() => _lineas.add(linea));
    _programarCalculo();
  }

  void _sacarLinea(int i) {
    setState(() {
      _lineas.removeAt(i).dispose();
    });
    _programarCalculo();
  }

  void _programarCalculo() {
    _reloj?.cancel();
    _reloj = Timer(const Duration(milliseconds: 400), _calcular);
  }

  Map<String, dynamic> _cuerpo() {
    Map<String, dynamic>? clienteElegido;
    for (final c in _clientes) {
      if ('${c['razon_social']}'.toLowerCase() == _cliente.text.trim().toLowerCase()) {
        clienteElegido = c;
        break;
      }
    }
    return {
      if ((_empresaId ?? (clienteElegido?['id'] as num?)?.toInt()) != null) 'empresaId': _empresaId ?? (clienteElegido!['id'] as num).toInt(),
      'cliente': {
        'razonSocial': _cliente.text,
        'atencion': _atencion.text,
      },
      'bonificacion': numeroDePersona(_bonificacion.text) ?? 0,
      'observaciones': _observaciones.text,
      'referencia': _referencia.text,
      'formaPago': _formaPago.text,
      'plazoEntrega': _plazo.text,
      'validez': _validez.text,
      'items': [for (final l in _lineas) l.aCuerpo()],
      'solicitudIds': _solicitudIds,
    };
  }

  Future<void> _calcular() async {
    if (!mounted) return;
    try {
      final respuesta = await apiSend('POST', '/api/presupuestos/calcular', json.encode(_cuerpo()));
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        final datos = json.decode(respuesta.body) as Map;
        setState(() {
          _calculo = Map<String, dynamic>.from(datos['calculo'] as Map);
          _itemsCalc = (datos['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _elegirTarifa(_Linea linea) async {
    final elegida = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoElegirTarifa(tarifas: _tarifas),
    );
    if (elegida == null || !mounted) return;
    setState(() {
      linea.tarifaId = (elegida['id'] as num).toInt();
      linea.tarifaNombre = [elegida['familia'], elegida['servicio'], elegida['tramo']].where((x) => '$x'.trim().isNotEmpty).join(' · ');
      if (linea.descripcion.text.trim().isEmpty) {
        linea.descripcion.text = [elegida['servicio'], elegida['tramo']].where((x) => '$x'.trim().isNotEmpty).join(' — ');
      }
      if ('${elegida['alcance'] ?? ''}'.trim().isNotEmpty && linea.alcance.text.trim().isEmpty) {
        linea.alcance.text = '${elegida['alcance']}';
      }
      linea.precio.clear();
    });
    _programarCalculo();
  }

  Future<bool> _guardar({bool enviar = false}) async {
    if (_guardando) return false;
    setState(() { _error = null; _guardando = true; });
    try {
      final cuerpo = json.encode(_cuerpo());
      final respuesta = _id == null
          ? await apiSend('POST', '/api/presupuestos', cuerpo)
          : await apiSend('PUT', '/api/presupuestos/$_id', cuerpo);
      if (!mounted) return false;
      if (respuesta.statusCode != 200) {
        setState(() { _error = mensajeError(respuesta, 'No se pudo guardar'); _guardando = false; });
        return false;
      }
      final detalle = Map<String, dynamic>.from(json.decode(respuesta.body) as Map);
      _id = (detalle['id'] as num).toInt();
      _etiqueta = '${detalle['etiqueta']}';
      if (enviar) {
        final envio = await apiSend('PUT', '/api/presupuestos/$_id/estado', json.encode({'estado': 'Enviado'}));
        if (!mounted) return false;
        if (envio.statusCode != 200) {
          setState(() { _error = mensajeError(envio, 'Se guardó, pero no se pudo marcar como enviado'); _guardando = false; });
          return false;
        }
        _estado = 'Enviado';
        _editable = false;
      }
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(enviar ? 'Presupuesto ${_etiqueta ?? ''} enviado' : 'Borrador guardado')));
      return true;
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _guardando = false; });
      return false;
    }
  }

  Future<void> _borrar() async {
    if (_id == null) {
      Navigator.pop(context, false);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar borrador'),
        content: const Text('¿Borrar este borrador? No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final respuesta = await apiSend('DELETE', '/api/presupuestos/$_id');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = mensajeError(respuesta, 'No se pudo borrar'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = mensajeSinConexion);
    }
  }

  Widget _lineaWidget(_Linea linea, int i) {
    final calc = i < _itemsCalc.length ? _itemsCalc[i] : null;
    final lineaCalc = i < ((_calculo?['lineas'] as List?)?.length ?? 0) ? Map<String, dynamic>.from((_calculo!['lineas'] as List)[i] as Map) : null;
    final precioTarifa = calc?['precioTarifa'];
    return Container(
      key: Key('linea_$i'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: decoracionTarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 12, backgroundColor: sonTarjetaAlta, child: Text('${i + 1}', style: TextStyle(fontSize: 12, color: sonLightGreen))),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  linea.tarifaNombre ?? (linea.tarifaId == null ? 'Ítem suelto' : 'Del tarifario'),
                  style: TextStyle(color: sonTextoSuave, fontSize: 12.5),
                ),
              ),
              if (_editable) ...[
                TextButton(onPressed: () => _elegirTarifa(linea), child: const Text('Del tarifario')),
                IconButton(tooltip: 'Sacar ítem', onPressed: _lineas.length == 1 ? null : () => _sacarLinea(i), icon: Icon(Icons.close, size: 18, color: sonTextoSuave)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          TextField(controller: linea.descripcion, enabled: _editable, maxLines: 2, decoration: const InputDecoration(labelText: 'Descripción')),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(width: 90, child: TextField(controller: linea.cantidad, enabled: _editable, decoration: const InputDecoration(labelText: 'Cant.'))),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: linea.precio,
                  enabled: _editable,
                  decoration: InputDecoration(
                    labelText: 'Precio a mano (opcional)',
                    hintText: precioTarifa == null ? null : 'Tarifa: ${pesos(precioTarifa as num)}',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  initialValue: linea.periodicidad,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Cómo se cobra'),
                  items: const [
                    DropdownMenuItem(value: 'mensual', child: Text('Por mes')),
                    DropdownMenuItem(value: 'unico', child: Text('Pago único')),
                  ],
                  onChanged: !_editable ? null : (v) {
                    setState(() => linea.periodicidad = v ?? 'mensual');
                    _programarCalculo();
                  },
                ),
              ),
            ],
          ),
          if (linea.periodicidad == 'unico') ...[
            const SizedBox(height: 8),
            SizedBox(width: 220, child: TextField(controller: linea.cuotas, enabled: _editable, decoration: const InputDecoration(labelText: 'Prorratear en N meses (vacío = no)'))),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              FilterChip(
                label: const Text('Aplica bonificación'),
                selected: linea.bonificable,
                onSelected: !_editable ? null : (v) {
                  setState(() => linea.bonificable = v);
                  _programarCalculo();
                },
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<int?>(
                  initialValue: linea.costoId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Costo interno', isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Sin costo')),
                    for (final c in _costos) DropdownMenuItem<int?>(value: (c['id'] as num).toInt(), child: Text('${c['concepto']}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: !_editable ? null : (v) {
                    setState(() => linea.costoId = v);
                    _programarCalculo();
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 110, child: TextField(controller: linea.horas, enabled: _editable, decoration: const InputDecoration(labelText: 'Cant. costo'))),
              const Spacer(),
              if (lineaCalc != null)
                Text(pesos(lineaCalc['neto'] as num?), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resumen() {
    final c = _calculo;
    final avisos = (c?['avisos'] as List? ?? []).map((a) => Map<String, dynamic>.from(a as Map)).toList();
    return Container(
      width: 320,
      padding: const EdgeInsets.all(18),
      decoration: decoracionTarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cuentas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 14),
          _filaResumen('Mensual', pesos(c?['totalMensual'] as num?)),
          _filaResumen('Pago único', pesos(c?['totalUnico'] as num?)),
          if ((c?['descuentoTotal'] as num? ?? 0) > 0) _filaResumen('Descuento', pesos(c!['descuentoTotal'] as num)),
          const Divider(height: 24),
          _filaResumen('IVA mensual', pesos(c?['ivaMensual'] as num?)),
          _filaResumen('IVA pago único', pesos(c?['ivaUnico'] as num?)),
          const SizedBox(height: 8),
          EtiquetaEstado(texto: textoDeMargen('${c?['nivelMargen']}'), color: colorDeMargen('${c?['nivelMargen']}')),
          if (c?['margen'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Margen ${c!['margen']} %', style: TextStyle(color: sonTextoSuave, fontSize: 13))),
          if (avisos.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final aviso in avisos)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${aviso['mensaje']}', style: TextStyle(color: sonAmbar, fontSize: 12.5, height: 1.3)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _filaResumen(String rotulo, String valor) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [Expanded(child: Text(rotulo, style: TextStyle(color: sonTextoSuave))), Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: sonFondo,
      appBar: AppBar(
        title: Text(_etiqueta == null ? 'Nuevo presupuesto' : 'Presupuesto $_etiqueta'),
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _id != null),
        ),
        actions: [
          if (_id != null) TextButton.icon(onPressed: () => abrirInforme('$apiBaseUrl/api/presupuestos/$_id/pdf?token=${SesionAdmin.token}'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF')),
          if (_editable && _id != null) TextButton(onPressed: _guardando ? null : _borrar, child: const Text('Borrar')),
          if (_editable) TextButton(onPressed: _guardando ? null : () async { if (await _guardar() && context.mounted) Navigator.pop(context, true); }, child: const Text('Guardar borrador')),
          if (_editable)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton(
                key: const Key('enviar_presupuesto'),
                onPressed: _guardando ? null : () async { if (await _guardar(enviar: true) && context.mounted) Navigator.pop(context, true); },
                child: const Text('Guardar y enviar'),
              ),
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(
                      children: [
                        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600))),
                        if (!_editable) Padding(padding: const EdgeInsets.only(bottom: 12), child: EtiquetaEstado(texto: 'Estado: $_estado. Para cambiarlo, creá una versión actualizada ("act") desde la lista.', color: sonAzul)),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 360,
                              child: RawAutocomplete<Map<String, dynamic>>(
                                textEditingController: _cliente,
                                focusNode: _focoCliente,
                                displayStringForOption: (c) => '${c['razon_social']}',
                                optionsBuilder: (valor) {
                                  final buscado = sinAcentos(valor.text);
                                  if (buscado.isEmpty) return _clientes;
                                  return _clientes.where((c) => sinAcentos('${c['razon_social']}').contains(buscado));
                                },
                                onSelected: (c) {
                                  _empresaId = (c['id'] as num).toInt();
                                  _cliente.text = '${c['razon_social']}';
                                  if (_atencion.text.isEmpty) _atencion.text = '${c['contacto'] ?? ''}';
                                  _programarCalculo();
                                },
                                fieldViewBuilder: (context, controlador, foco, alEnviar) => TextField(
                                  key: const Key('cliente_presupuesto'),
                                  controller: controlador,
                                  focusNode: foco,
                                  enabled: _editable,
                                  decoration: const InputDecoration(labelText: 'Cliente *', hintText: 'Elegí de la lista o escribí el nombre'),
                                ),
                                optionsViewBuilder: (context, alElegir, opciones) => Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    elevation: 4,
                                    borderRadius: BorderRadius.circular(8),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
                                      child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: [
                                        for (final c in opciones) ListTile(dense: true, title: Text('${c['razon_social']}'), onTap: () => alElegir(c)),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 220, child: TextField(controller: _atencion, enabled: _editable, decoration: const InputDecoration(labelText: 'Atención'))),
                            SizedBox(width: 140, child: TextField(controller: _bonificacion, enabled: _editable, decoration: const InputDecoration(labelText: 'Bonificación %'))),
                          ],
                        ),
                        const SizedBox(height: 18),
                        for (var i = 0; i < _lineas.length; i++) _lineaWidget(_lineas[i], i),
                        if (_editable)
                          OutlinedButton.icon(key: const Key('agregar_item'), onPressed: _agregarLinea, icon: const Icon(Icons.add), label: const Text('Agregar ítem')),
                        const SizedBox(height: 16),
                        TextField(controller: _observaciones, enabled: _editable, maxLines: 3, decoration: const InputDecoration(labelText: 'Observaciones')),
                        const SizedBox(height: 10),
                        TextField(controller: _referencia, enabled: _editable, decoration: const InputDecoration(labelText: 'Valor de referencia (cómo se actualiza el precio)')),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: TextField(controller: _formaPago, enabled: _editable, decoration: const InputDecoration(labelText: 'Forma de pago'))),
                          const SizedBox(width: 10),
                          Expanded(child: TextField(controller: _plazo, enabled: _editable, decoration: const InputDecoration(labelText: 'Plazo de entrega'))),
                        ]),
                        const SizedBox(height: 10),
                        TextField(controller: _validez, enabled: _editable, maxLines: 2, decoration: const InputDecoration(labelText: 'Validez de la oferta')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  _resumen(),
                ],
              ),
            ),
    );
  }
}

/// Abre el armado de un presupuesto, opcionalmente con notas de técnicos ya elegidas.
Future<bool> armarPresupuesto(BuildContext context, {int? id, List<Map<String, dynamic>>? notas}) async {
  final cambiado = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => PantallaArmarPresupuesto(presupuestoId: id, notas: notas)),
  );
  return cambiado == true;
}

class _DialogoElegirTarifa extends StatefulWidget {
  final List<Map<String, dynamic>> tarifas;
  const _DialogoElegirTarifa({required this.tarifas});

  @override
  State<_DialogoElegirTarifa> createState() => _DialogoElegirTarifaState();
}

class _DialogoElegirTarifaState extends State<_DialogoElegirTarifa> {
  final _busqueda = TextEditingController();

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibles = widget.tarifas.where((t) {
      final texto = '${t['familia']} ${t['servicio']} ${t['tramo']} ${t['detalle'] ?? ''}';
      return coincideBusqueda(texto, _busqueda.text);
    }).toList();
    return AlertDialog(
      title: const Text('Elegir del tarifario'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          children: [
            TextField(controller: _busqueda, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar...')),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: visibles.length,
                itemBuilder: (_, i) {
                  final t = visibles[i];
                  final sinValor = t['valorActual'] == null;
                  return ListTile(
                    title: Text('${t['servicio']}'),
                    subtitle: Text([t['familia'], t['tramo']].where((x) => '$x'.trim().isNotEmpty).join(' · ')),
                    trailing: Text(sinValor ? 'Sin valor' : pesos(t['valorActual'] as num?), style: TextStyle(color: sinValor ? sonAmbar : sonTexto, fontWeight: FontWeight.bold)),
                    onTap: () => Navigator.pop(context, t),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
    );
  }
}
