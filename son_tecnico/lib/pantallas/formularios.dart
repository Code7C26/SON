import 'package:flutter/material.dart';
import 'package:son_tecnico/pantallas/planilla_excel.dart';
import 'package:son_tecnico/theme/colores.dart';

// Formularios de control en la visita (tableros, extintores, almacenaje...). Hay dos tipos:
//  - 'lista': preguntas fijas; se toca la respuesta (SI / NO / NC) de cada una.
//  - 'planilla': una fila por cada cosa revisada (cada tablero, cada extintor), con sus datos.
// Las respuestas se guardan en el borrador del trabajo (sirven sin señal) y viajan con el informe.

Map<String, dynamic> _definicion(Map formulario) => Map<String, dynamic>.from(formulario['definicion'] as Map? ?? {});

List<String> _lista(dynamic valor) => (valor as List? ?? []).map((e) => '$e').toList();

/// "8 de 13 respondidas" / "3 tableros cargados".
String avanceDeFormulario(Map formulario, Map? respuestas) {
  final d = _definicion(formulario);
  if (d['tipo'] == 'excel') {
    final cargados = (respuestas?['valores'] as Map? ?? {}).length;
    return cargados == 0 ? 'Sin completar' : '$cargados casillero${cargados == 1 ? '' : 's'} cargado${cargados == 1 ? '' : 's'}';
  }
  if (d['tipo'] == 'planilla') {
    final filas = (respuestas?['filas'] as List? ?? []).length;
    final elemento = '${d['elemento'] ?? 'elemento'}'.toLowerCase();
    return filas == 0 ? 'Sin cargar' : (filas == 1 ? '1 $elemento cargado' : '$filas cargados');
  }
  final preguntas = (d['preguntas'] as List? ?? []);
  final total = preguntas.where((p) => p is Map && p['seccion'] != true).length;
  final lista = respuestas?['respuestas'] as List? ?? [];
  var hechas = 0;
  for (var i = 0; i < preguntas.length && i < lista.length; i++) {
    final r = lista[i];
    if (r is Map && (r['valores'] as List? ?? []).any((v) => v != null)) hechas++;
  }
  return hechas == 0 ? 'Sin completar' : '$hechas de $total respondidas';
}

bool formularioEmpezado(Map formulario, Map? respuestas) {
  final d = _definicion(formulario);
  if (d['tipo'] == 'excel') return (respuestas?['valores'] as Map? ?? {}).isNotEmpty;
  if (d['tipo'] == 'planilla') return (respuestas?['filas'] as List? ?? []).isNotEmpty;
  return (respuestas?['respuestas'] as List? ?? []).any((r) => r is Map && (r['valores'] as List? ?? []).any((v) => v != null));
}

/// Abre el formulario. Devuelve las respuestas (o null si se cerró sin cambios).
Future<Map<String, dynamic>?> completarFormulario(BuildContext context, Map formulario, Map? respuestas, {String? cliente}) {
  // Los que se subieron desde Excel se completan sobre la misma planilla.
  final esExcel = _definicion(formulario)['tipo'] == 'excel';
  return Navigator.push<Map<String, dynamic>>(
    context,
    MaterialPageRoute(
      builder: (_) => esExcel
          ? PantallaPlanillaExcel(formulario: formulario, respuestas: respuestas, cliente: cliente)
          : PantallaFormulario(formulario: formulario, respuestas: respuestas),
    ),
  );
}

class PantallaFormulario extends StatefulWidget {
  final Map formulario;
  final Map? respuestas;
  const PantallaFormulario({super.key, required this.formulario, this.respuestas});

  @override
  State<PantallaFormulario> createState() => _PantallaFormularioState();
}

class _PantallaFormularioState extends State<PantallaFormulario> {
  late final Map<String, dynamic> d = _definicion(widget.formulario);
  late final bool _esPlanilla = d['tipo'] == 'planilla';
  late final List<String> _opciones = _lista(d['opciones']);
  late final List<String> _columnas = _lista(d['columnas']);
  late final List<Map<String, dynamic>> _preguntas = (d['preguntas'] as List? ?? []).map((p) => Map<String, dynamic>.from(p as Map)).toList();
  late final List<Map<String, dynamic>> _campos = (d['campos'] as List? ?? []).map((c) => Map<String, dynamic>.from(c as Map)).toList();

  // Lista: respuestas[i] = { valores: [...una por columna], obs }
  late final List<Map<String, dynamic>?> _respuestas = List.generate(_preguntas.length, (i) {
    if (_preguntas[i]['seccion'] == true) return null;
    final guardada = (widget.respuestas?['respuestas'] as List? ?? []);
    final previa = i < guardada.length && guardada[i] is Map ? Map<String, dynamic>.from(guardada[i] as Map) : <String, dynamic>{};
    final columnas = _columnas.isEmpty ? 1 : _columnas.length;
    final valores = List<String?>.generate(columnas, (k) {
      final lista = previa['valores'] as List? ?? [];
      return k < lista.length && lista[k] != null ? '${lista[k]}' : null;
    });
    return {'valores': valores, 'obs': '${previa['obs'] ?? ''}'};
  });
  late final Map<int, TextEditingController> _obs = {};
  final Set<int> _conObservacion = {};

  // Planilla: filas = [{ valores: [...uno por campo], obs }]
  late final List<Map<String, dynamic>> _filas = (widget.respuestas?['filas'] as List? ?? [])
      .map((f) => Map<String, dynamic>.from(f as Map))
      .toList();

  late final TextEditingController _observacion = TextEditingController(text: '${widget.respuestas?['observacion'] ?? ''}');

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _respuestas.length; i++) {
      final r = _respuestas[i];
      if (r == null) continue;
      _obs[i] = TextEditingController(text: '${r['obs'] ?? ''}');
      if ('${r['obs'] ?? ''}'.isNotEmpty) _conObservacion.add(i);
    }
  }

  @override
  void dispose() {
    for (final c in _obs.values) {
      c.dispose();
    }
    _observacion.dispose();
    super.dispose();
  }

  Map<String, dynamic> _resultado() {
    if (_esPlanilla) return {'filas': _filas, 'observacion': _observacion.text.trim()};
    for (final entrada in _obs.entries) {
      _respuestas[entrada.key]?['obs'] = entrada.value.text.trim();
    }
    return {'respuestas': _respuestas, 'observacion': _observacion.text.trim()};
  }

  void _listo() => Navigator.pop(context, _resultado());

  /// SI / NO / NC como botones: tocar de nuevo la elegida la borra.
  Widget _botones(List<String> opciones, String? actual, ValueChanged<String?> alElegir) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: opciones
          .map((opcion) => ChoiceChip(
                label: Text(opcion, style: const TextStyle(fontWeight: FontWeight.bold)),
                selected: actual == opcion,
                selectedColor: sonLightGreen.withValues(alpha: 0.35),
                onSelected: (_) => alElegir(actual == opcion ? null : opcion),
              ))
          .toList(),
    );
  }

  Widget _pregunta(int i) {
    final p = _preguntas[i];
    if (p['seccion'] == true) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
        child: Text('${p['texto']}'.toUpperCase(), style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, letterSpacing: 1)),
      );
    }
    final r = _respuestas[i]!;
    final valores = r['valores'] as List<String?>;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: decoracionTarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${p['texto']}', style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 10),
          if (_columnas.isEmpty)
            _botones(_opciones, valores[0], (v) => setState(() => valores[0] = v))
          else
            for (var k = 0; k < _columnas.length; k++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(width: 96, child: Text(_columnas[k], style: TextStyle(color: sonTextoSuave, fontSize: 13))),
                    Expanded(child: _botones(_opciones, valores[k], (v) => setState(() => valores[k] = v))),
                  ],
                ),
              ),
          if (_conObservacion.contains(i))
            TextField(controller: _obs[i], decoration: const InputDecoration(labelText: 'Observación', isDense: true))
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _conObservacion.add(i)),
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Observación'),
              ),
            ),
        ],
      ),
    );
  }

  String _valorLegible(Map campo, dynamic valor) {
    if (valor == null || '$valor'.isEmpty) return '—';
    if (campo['tipo'] == 'fecha') {
      final partes = '$valor'.split('-');
      if (partes.length == 3) return '${partes[2]}/${partes[1]}/${partes[0]}';
    }
    return '$valor';
  }

  Future<void> _editarFila({int? indice, Map<String, dynamic>? base}) async {
    final inicial = indice != null ? _filas[indice] : base;
    final fila = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => _PantallaFila(definicion: d, campos: _campos, inicial: inicial, numero: indice != null ? indice + 1 : _filas.length + 1)),
    );
    if (fila == null || !mounted) return;
    setState(() {
      if (indice != null) {
        _filas[indice] = fila;
      } else {
        _filas.add(fila);
      }
    });
  }

  Widget _tarjetaFila(int i) {
    final fila = _filas[i];
    final valores = fila['valores'] as List? ?? [];
    final titulo = valores.isNotEmpty && valores[0] != null && '${valores[0]}'.isNotEmpty ? '${valores[0]}' : '${d['elemento'] ?? 'Elemento'} ${i + 1}';
    final resumen = <String>[];
    for (var k = 1; k < _campos.length && k < valores.length; k++) {
      if (valores[k] != null) resumen.add('${_campos[k]['etiqueta']}: ${_valorLegible(_campos[k], valores[k])}');
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: decoracionTarjeta(),
      child: ListTile(
        onTap: () => _editarFila(indice: i),
        leading: CircleAvatar(backgroundColor: sonTarjetaAlta, child: Text('${i + 1}', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold))),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(resumen.isEmpty ? 'Sin datos' : resumen.join(' · '), maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          onSelected: (accion) {
            if (accion == 'copiar') _editarFila(base: {'valores': List.from(valores)..[0] = null, 'obs': ''});
            if (accion == 'borrar') setState(() => _filas.removeAt(i));
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'copiar', child: Text('Copiar en una nueva')),
            PopupMenuItem(value: 'borrar', child: Text('Borrar', style: TextStyle(color: sonRojo))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final elemento = '${d['elemento'] ?? 'elemento'}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _listo();
      },
      child: Scaffold(
        backgroundColor: sonFondo,
        appBar: AppBar(
          title: Text('${widget.formulario['nombre']}', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
          backgroundColor: sonPanel,
          actions: [TextButton(onPressed: _listo, child: Text('Listo', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, fontSize: 16)))],
        ),
        floatingActionButton: _esPlanilla
            ? FloatingActionButton.extended(
                backgroundColor: sonLightGreen,
                onPressed: () => _editarFila(),
                icon: Icon(Icons.add, color: sonDarkGreen),
                label: Text('Agregar ${elemento.toLowerCase()}', style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold)),
              )
            : null,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (_esPlanilla) ...[
              Text('Cargá una fila por cada ${elemento.toLowerCase()} que revises.', style: TextStyle(color: sonTextoSuave)),
              const SizedBox(height: 12),
              if (_filas.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: Text('Todavía no cargaste ninguno.', style: TextStyle(color: sonTextoSuave))),
                ),
              for (var i = 0; i < _filas.length; i++) _tarjetaFila(i),
            ] else
              for (var i = 0; i < _preguntas.length; i++) _pregunta(i),
            const SizedBox(height: 12),
            TextField(
              controller: _observacion,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Observaciones del formulario (opcional)'),
            ),
            const SizedBox(height: 16),
            SizedBox(height: 50, child: ElevatedButton(onPressed: _listo, child: const Text('Listo', style: TextStyle(fontSize: 16)))),
          ],
        ),
      ),
    );
  }
}

/// Una fila de la planilla (un tablero, un extintor...).
class _PantallaFila extends StatefulWidget {
  final Map<String, dynamic> definicion;
  final List<Map<String, dynamic>> campos;
  final Map<String, dynamic>? inicial;
  final int numero;
  const _PantallaFila({required this.definicion, required this.campos, this.inicial, required this.numero});

  @override
  State<_PantallaFila> createState() => _PantallaFilaState();
}

class _PantallaFilaState extends State<_PantallaFila> {
  late final List<dynamic> _valores = List.generate(widget.campos.length, (k) {
    final lista = widget.inicial?['valores'] as List? ?? [];
    return k < lista.length ? lista[k] : null;
  });
  late final Map<int, TextEditingController> _textos = {
    for (var k = 0; k < widget.campos.length; k++)
      if (widget.campos[k]['tipo'] == 'texto' || widget.campos[k]['tipo'] == 'numero') k: TextEditingController(text: _valores[k] == null ? '' : '${_valores[k]}'),
  };
  late final TextEditingController _obs = TextEditingController(text: '${widget.inicial?['obs'] ?? ''}');

  @override
  void dispose() {
    for (final c in _textos.values) {
      c.dispose();
    }
    _obs.dispose();
    super.dispose();
  }

  void _guardar() {
    for (final entrada in _textos.entries) {
      final texto = entrada.value.text.trim();
      _valores[entrada.key] = texto.isEmpty ? null : texto;
    }
    Navigator.pop(context, {'valores': _valores, 'obs': _obs.text.trim()});
  }

  Widget _campo(int k) {
    final campo = widget.campos[k];
    final etiqueta = '${campo['etiqueta']}';
    switch (campo['tipo']) {
      case 'opciones':
        final opciones = _lista(campo['opciones']).isNotEmpty ? _lista(campo['opciones']) : _lista(widget.definicion['opciones']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etiqueta, style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: opciones
                  .map((opcion) => ChoiceChip(
                        label: Text(opcion, style: const TextStyle(fontWeight: FontWeight.bold)),
                        selected: _valores[k] == opcion,
                        selectedColor: sonLightGreen.withValues(alpha: 0.35),
                        onSelected: (_) => setState(() => _valores[k] = _valores[k] == opcion ? null : opcion),
                      ))
                  .toList(),
            ),
          ],
        );
      case 'fecha':
        final valor = _valores[k] as String?;
        final partes = (valor ?? '').split('-');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etiqueta, style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final hoy = DateTime.now();
                    final elegida = await showDatePicker(
                      context: context,
                      initialDate: DateTime.tryParse(valor ?? '') ?? hoy,
                      firstDate: DateTime(hoy.year - 10),
                      lastDate: DateTime(hoy.year + 15),
                    );
                    if (elegida != null) {
                      setState(() => _valores[k] = '${elegida.year}-${elegida.month.toString().padLeft(2, '0')}-${elegida.day.toString().padLeft(2, '0')}');
                    }
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(partes.length == 3 ? '${partes[2]}/${partes[1]}/${partes[0]}' : 'Elegir fecha'),
                ),
                if (valor != null) IconButton(tooltip: 'Borrar fecha', onPressed: () => setState(() => _valores[k] = null), icon: const Icon(Icons.close)),
              ],
            ),
          ],
        );
      default:
        return TextField(
          controller: _textos[k],
          keyboardType: campo['tipo'] == 'numero' ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: etiqueta),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: sonFondo,
      appBar: AppBar(
        title: Text('${widget.definicion['elemento'] ?? 'Elemento'} ${widget.numero}', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
        backgroundColor: sonPanel,
        actions: [TextButton(onPressed: _guardar, child: Text('Guardar', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, fontSize: 16)))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (var k = 0; k < widget.campos.length; k++) Padding(padding: const EdgeInsets.only(bottom: 16), child: _campo(k)),
          TextField(controller: _obs, maxLines: 2, decoration: const InputDecoration(labelText: 'Observación (opcional)')),
          const SizedBox(height: 16),
          SizedBox(height: 50, child: ElevatedButton(onPressed: _guardar, child: const Text('Guardar', style: TextStyle(fontSize: 16)))),
        ],
      ),
    );
  }
}
