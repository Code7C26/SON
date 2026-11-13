import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:son_admin/services/api.dart';
import 'package:son_admin/services/elegir_imagen.dart';
import 'package:son_admin/pantallas/planilla_excel.dart';
import 'package:son_admin/theme/tema.dart';

// Formularios de control (tableros, extintores, almacenaje...): se suben desde el Excel que ya usan,
// se revisan acá y después se eligen en cada orden. El técnico los completa en la app y salen en el
// informe como tareas realizadas.

const List<(String, String)> tiposDeCampo = [
  ('texto', 'Texto'),
  ('numero', 'Número'),
  ('fecha', 'Fecha'),
  ('opciones', 'Opciones (SI / NO...)'),
];

String resumenDeFormulario(Map definicion) {
  if (definicion['tipo'] == 'excel') {
    return 'Igual al Excel · ${(definicion['campos'] as List? ?? []).length} casilleros para completar';
  }
  if (definicion['tipo'] == 'planilla') {
    final campos = (definicion['campos'] as List? ?? []).length;
    return 'Planilla: una fila por cada ${('${definicion['elemento'] ?? 'elemento'}').toLowerCase()} · $campos campos';
  }
  final preguntas = (definicion['preguntas'] as List? ?? []).where((p) => p is Map && p['seccion'] != true).length;
  final columnas = (definicion['columnas'] as List? ?? []);
  return 'Lista de $preguntas preguntas · ${(definicion['opciones'] as List? ?? []).join(' / ')}${columnas.isEmpty ? '' : ' · ${columnas.join(', ')}'}';
}

void _avisar(BuildContext context, String texto) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
}

/// Sube el Excel, lo convierte y abre el editor para revisarlo. Devuelve el formulario guardado (o null).
Future<Map<String, dynamic>?> importarFormularioDesdeExcel(BuildContext context) async {
  final archivo = await elegirArchivo(aceptar: '.xls,.xlsx,application/vnd.ms-excel,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  if (archivo == null || !context.mounted) return null;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leyendo el Excel...'), duration: Duration(seconds: 2)));
  try {
    final respuesta = await apiSend('POST', '/api/formularios/importar', json.encode({'archivo': archivo.nombre, 'contenido': archivo.datos}));
    if (!context.mounted) return null;
    if (respuesta.statusCode != 200) {
      _avisar(context, mensajeError(respuesta, 'No se pudo leer el Excel'));
      return null;
    }
    final datos = Map<String, dynamic>.from(json.decode(respuesta.body) as Map);
    return await abrirEditorFormulario(
      context,
      nombre: '${datos['nombre'] ?? ''}',
      definicion: Map<String, dynamic>.from(datos['definicion'] as Map),
      archivo: archivo.nombre,
      avisos: (datos['avisos'] as List? ?? []).map((a) => '$a').toList(),
    );
  } catch (_) {
    if (context.mounted) _avisar(context, mensajeSinConexion);
    return null;
  }
}

/// Arma un formulario desde cero. Devuelve el formulario guardado (o null).
Future<Map<String, dynamic>?> crearFormularioAMano(BuildContext context) {
  return abrirEditorFormulario(context, nombre: '', definicion: {'tipo': 'lista', 'opciones': ['SI', 'NO', 'NC'], 'columnas': [], 'preguntas': []});
}

/// Abre un formulario guardado para corregirlo o borrarlo.
/// Devuelve el formulario actualizado, {'borrado': true} si se borró, o null si no cambió nada.
Future<Map<String, dynamic>?> editarFormulario(BuildContext context, Map<String, dynamic> formulario) {
  return abrirEditorFormulario(
    context,
    id: (formulario['id'] as num).toInt(),
    nombre: '${formulario['nombre']}',
    definicion: Map<String, dynamic>.from(formulario['definicion'] as Map? ?? {}),
    archivo: formulario['archivo'] as String?,
  );
}

// =====================================================================
// EDITOR: revisar lo que salió del Excel (o armarlo a mano)
// =====================================================================
Future<Map<String, dynamic>?> abrirEditorFormulario(
  BuildContext context, {
  int? id,
  required String nombre,
  required Map<String, dynamic> definicion,
  String? archivo,
  List<String> avisos = const [],
}) async {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EditorFormulario(id: id, nombre: nombre, definicion: definicion, archivo: archivo, avisos: avisos),
  );
}

class _Campo {
  final TextEditingController etiqueta;
  final TextEditingController opciones;
  String tipo;
  _Campo(String texto, this.tipo, String opcionesTexto)
      : etiqueta = TextEditingController(text: texto),
        opciones = TextEditingController(text: opcionesTexto);
}

class _EditorFormulario extends StatefulWidget {
  final int? id;
  final String nombre;
  final Map<String, dynamic> definicion;
  final String? archivo;
  final List<String> avisos;
  const _EditorFormulario({this.id, required this.nombre, required this.definicion, this.archivo, required this.avisos});

  @override
  State<_EditorFormulario> createState() => _EditorFormularioState();
}

class _EditorFormularioState extends State<_EditorFormulario> {
  late final TextEditingController _nombre = TextEditingController(text: widget.nombre);
  late String _tipo = widget.definicion['tipo'] == 'planilla' ? 'planilla' : 'lista';
  late final TextEditingController _opciones = TextEditingController(text: (widget.definicion['opciones'] as List? ?? ['SI', 'NO', 'NC']).join(', '));
  late final TextEditingController _columnas = TextEditingController(text: (widget.definicion['columnas'] as List? ?? []).join(', '));
  late final TextEditingController _preguntas = TextEditingController(
    text: (widget.definicion['preguntas'] as List? ?? []).map((p) => p is Map ? (p['seccion'] == true ? '# ${p['texto']}' : '${p['texto']}') : '$p').join('\n'),
  );
  late final TextEditingController _elemento = TextEditingController(text: '${widget.definicion['elemento'] ?? 'Elemento'}');
  late final List<_Campo> _campos = (widget.definicion['campos'] as List? ?? [])
      .map((c) => _Campo('${c['etiqueta']}', '${c['tipo'] ?? 'texto'}', (c['opciones'] as List? ?? []).join(', ')))
      .toList();
  bool _ocupado = false;
  String? _error;

  List<String> _separar(String texto) => texto.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  // Los que vienen de un Excel se guardan tal cual: no hay nada que convertir ni corregir.
  bool get _esExcel => widget.definicion['tipo'] == 'excel';

  Map<String, dynamic> _definicion() {
    if (_esExcel) return widget.definicion;
    final opciones = _separar(_opciones.text);
    if (_tipo == 'lista') {
      final preguntas = _preguntas.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).map((l) {
        final seccion = l.startsWith('#');
        return {'texto': seccion ? l.replaceFirst(RegExp(r'^#+\s*'), '') : l, 'seccion': seccion};
      }).toList();
      return {'tipo': 'lista', 'opciones': opciones, 'columnas': _separar(_columnas.text), 'preguntas': preguntas};
    }
    return {
      'tipo': 'planilla',
      'opciones': opciones,
      'elemento': _elemento.text.trim(),
      'campos': _campos
          .where((c) => c.etiqueta.text.trim().isNotEmpty)
          .map((c) => {
                'etiqueta': c.etiqueta.text.trim(),
                'tipo': c.tipo,
                if (c.tipo == 'opciones' && _separar(c.opciones.text).length >= 2) 'opciones': _separar(c.opciones.text),
              })
          .toList(),
    };
  }

  Future<void> _guardar() async {
    setState(() { _ocupado = true; _error = null; });
    try {
      final cuerpo = json.encode({'nombre': _nombre.text.trim(), 'definicion': _definicion(), if (widget.archivo != null) 'archivo': widget.archivo});
      final respuesta = widget.id == null ? await apiSend('POST', '/api/formularios', cuerpo) : await apiSend('PUT', '/api/formularios/${widget.id}', cuerpo);
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        Navigator.pop(context, Map<String, dynamic>.from(json.decode(respuesta.body) as Map));
      } else {
        setState(() { _error = mensajeError(respuesta); _ocupado = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _ocupado = false; });
    }
  }

  Future<void> _borrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text('¿Borrar "${_nombre.text}"?'),
        content: const Text('Deja de aparecer para elegir en las órdenes nuevas. Las órdenes que ya lo tienen lo conservan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(dialogo, true), child: Text('Borrar', style: TextStyle(color: sonRojo))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      final respuesta = await apiSend('DELETE', '/api/formularios/${widget.id}');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        Navigator.pop(context, {'borrado': true, 'id': widget.id});
      } else {
        setState(() { _error = mensajeError(respuesta); _ocupado = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = mensajeSinConexion; _ocupado = false; });
    }
  }

  Widget _filaCampo(int i) {
    final campo = _campos[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, child: Padding(padding: const EdgeInsets.only(top: 14), child: Text('${i + 1}.', style: TextStyle(color: sonTextoSuave)))),
          Expanded(
            flex: 5,
            child: TextField(
              controller: campo.etiqueta,
              maxLines: null,
              decoration: InputDecoration(isDense: true, labelText: i == 0 ? 'Qué identifica cada fila' : 'Pregunta o dato'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              initialValue: tiposDeCampo.any((t) => t.$1 == campo.tipo) ? campo.tipo : 'texto',
              isDense: true,
              decoration: const InputDecoration(isDense: true, labelText: 'Tipo'),
              items: tiposDeCampo.map((t) => DropdownMenuItem(value: t.$1, child: Text(t.$2))).toList(),
              onChanged: (valor) => setState(() => campo.tipo = valor ?? 'texto'),
            ),
          ),
          if (campo.tipo == 'opciones') ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 130,
              child: TextField(controller: campo.opciones, decoration: const InputDecoration(isDense: true, labelText: 'Opciones', hintText: 'las generales')),
            ),
          ],
          Column(
            children: [
              IconButton(
                tooltip: 'Subir',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: i == 0 ? null : () => setState(() => _campos.insert(i - 1, _campos.removeAt(i))),
              ),
              IconButton(
                tooltip: 'Quitar',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 18, color: sonRojo),
                onPressed: () => setState(() => _campos.removeAt(i)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Vista previa de la planilla: así la ve el técnico (los casilleros para completar, apenas marcados).
  Widget _vistaExcel() {
    final campos = (widget.definicion['campos'] as List? ?? []);
    final cuenta = <String, int>{};
    for (final campo in campos.whereType<Map>()) {
      cuenta['${campo['tipo']}'] = (cuenta['${campo['tipo']}'] ?? 0) + 1;
    }
    final ancho = (widget.definicion['anchos'] as List? ?? []).fold<double>(0, (a, b) => a + (b as num).toDouble());
    final alto = (widget.definicion['altos'] as List? ?? []).fold<double>(0, (a, b) => a + (b as num).toDouble());
    final escala = ancho > 0 ? (780 / ancho).clamp(0.3, 1.6).toDouble() : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre del formulario')),
        const SizedBox(height: 12),
        Text(
          'Se usa igual que el Excel. El técnico toca los casilleros para completarlos: '
          '${cuenta['marca'] ?? 0} para marcar con X (SI / NO / NC), ${cuenta['fecha'] ?? 0} de fecha y ${cuenta['texto'] ?? 0} para escribir. '
          'Las fechas de "vencimiento" pasan solas a Vencimientos.',
          style: TextStyle(color: sonTextoSuave),
        ),
        const SizedBox(height: 10),
        Container(
          height: (alto * escala).clamp(200, 560).toDouble(),
          width: double.infinity,
          decoration: BoxDecoration(border: Border.all(color: sonBorde), borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.hardEdge,
          child: InteractiveViewer(
            constrained: false,
            minScale: 0.2,
            maxScale: 4,
            transformationController: TransformationController(Matrix4.identity()..scaleByDouble(escala, escala, 1, 1)),
            child: PlanillaExcel(definicion: widget.definicion, cliente: 'Nombre del cliente', fecha: 'dd/mm/aaaa'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_esExcel) {
      return AlertDialog(
        title: Text(widget.id == null ? 'Así queda el formulario' : 'Formulario'),
        content: SizedBox(
          width: 820,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.archivo != null) Text('De ${widget.archivo}', style: TextStyle(color: sonTextoSuave)),
                for (final aviso in widget.avisos)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: sonAmbar.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: sonAmbar.withValues(alpha: 0.5))),
                    child: Row(children: [Icon(Icons.info_outline, color: sonAmbar, size: 18), const SizedBox(width: 8), Expanded(child: Text(aviso))]),
                  ),
                const SizedBox(height: 12),
                _vistaExcel(),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ),
        actions: [
          if (widget.id != null)
            TextButton.icon(
              onPressed: _ocupado ? null : _borrar,
              icon: Icon(Icons.delete_outline, color: sonRojo),
              label: Text('Borrar formulario', style: TextStyle(color: sonRojo)),
            ),
          TextButton(onPressed: _ocupado ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(onPressed: _ocupado ? null : _guardar, child: Text(widget.id == null ? 'Guardar formulario' : 'Guardar')),
        ],
      );
    }
    return AlertDialog(
      title: Text(widget.id == null ? (widget.archivo == null ? 'Nuevo formulario' : 'Revisá el formulario convertido') : 'Editar formulario'),
      content: SizedBox(
        width: 820,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.archivo != null) Text('Convertido de ${widget.archivo}', style: TextStyle(color: sonTextoSuave)),
              for (final aviso in widget.avisos)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: sonAmbar.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: sonAmbar.withValues(alpha: 0.5))),
                  child: Row(children: [Icon(Icons.info_outline, color: sonAmbar, size: 18), const SizedBox(width: 8), Expanded(child: Text(aviso))]),
                ),
              const SizedBox(height: 12),
              TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre del formulario')),
              const SizedBox(height: 14),
              Text('¿Cómo se completa?', style: TextStyle(color: sonTextoSuave, fontSize: 13)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'lista', icon: Icon(Icons.checklist), label: Text('Lista de preguntas fijas')),
                  ButtonSegment(value: 'planilla', icon: Icon(Icons.table_rows_outlined), label: Text('Planilla: una fila por cada cosa revisada')),
                ],
                selected: {_tipo},
                onSelectionChanged: (valor) => setState(() => _tipo = valor.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _opciones,
                decoration: const InputDecoration(labelText: 'Opciones de respuesta', helperText: 'Separadas por comas. Ej: SI, NO, NC  ·  BIEN, MAL  ·  S, I'),
              ),
              const SizedBox(height: 14),
              if (_tipo == 'lista') ...[
                TextField(
                  controller: _columnas,
                  decoration: const InputDecoration(
                    labelText: 'Columnas (opcional)',
                    helperText: 'Si cada pregunta se contesta para varios lugares. Ej: Baño M, Baño H, Vestuario, Comedor. Vacío = una sola respuesta.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _preguntas,
                  minLines: 8,
                  maxLines: 18,
                  decoration: const InputDecoration(
                    labelText: 'Preguntas (una por renglón)',
                    alignLabelWithHint: true,
                    helperText: 'Un renglón que empieza con # es un título de sección. Ej: # Luces',
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _elemento,
                  decoration: const InputDecoration(labelText: 'Cada fila es un...', helperText: 'Ej: Tablero, Extintor, Máquina. La app muestra "Agregar tablero".'),
                ),
                const SizedBox(height: 16),
                Text('Campos de cada fila', style: TextStyle(fontWeight: FontWeight.bold, color: sonTexto)),
                Text('El primero identifica cada fila (por ejemplo, la ubicación del tablero). Las fechas que dicen "vencimiento" se cargan solas en Vencimientos.', style: TextStyle(color: sonTextoSuave, fontSize: 12.5)),
                const SizedBox(height: 10),
                for (var i = 0; i < _campos.length; i++) _filaCampo(i),
                TextButton.icon(
                  onPressed: () => setState(() => _campos.add(_Campo('', 'opciones', ''))),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar campo'),
                ),
              ],
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.id != null)
          TextButton.icon(
            onPressed: _ocupado ? null : _borrar,
            icon: Icon(Icons.delete_outline, color: sonRojo),
            label: Text('Borrar formulario', style: TextStyle(color: sonRojo)),
          ),
        TextButton(onPressed: _ocupado ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _ocupado ? null : _guardar, child: const Text('Guardar formulario')),
      ],
    );
  }
}

// =====================================================================
// En la orden: elegir formularios
// =====================================================================
/// Lista de formularios guardados (id y nombre), para elegir en la orden.
Future<List<Map<String, dynamic>>> listaDeFormularios() async {
  try {
    final respuesta = await apiGet('/api/formularios');
    if (respuesta.statusCode == 200) {
      return (json.decode(respuesta.body) as List).map((f) => Map<String, dynamic>.from(f as Map)).toList();
    }
  } catch (_) {}
  return [];
}

/// Los formularios de la orden como chips (tocar uno lo abre para corregirlo) y el botón "Agregar
/// formulario", que deja elegir uno ya guardado, subir el Excel o crearlo a mano.
class SelectorFormularios extends StatelessWidget {
  final List<Map<String, dynamic>> disponibles;
  final List<int> elegidos;
  final ValueChanged<List<int>> alCambiar;
  final ValueChanged<List<Map<String, dynamic>>> alCambiarDisponibles;
  const SelectorFormularios({
    super.key,
    required this.disponibles,
    required this.elegidos,
    required this.alCambiar,
    required this.alCambiarDisponibles,
  });

  static const int _subirExcel = -1;
  static const int _aMano = -2;

  Future<void> _agregar(BuildContext context, int opcion) async {
    if (opcion >= 0) return alCambiar([...elegidos, opcion]);
    final nuevo = opcion == _subirExcel ? await importarFormularioDesdeExcel(context) : await crearFormularioAMano(context);
    if (nuevo == null || nuevo['id'] == null) return;
    final id = (nuevo['id'] as num).toInt();
    alCambiarDisponibles([...disponibles.where((f) => (f['id'] as num).toInt() != id), nuevo]);
    alCambiar([...elegidos.where((e) => e != id), id]);
  }

  Future<void> _editar(BuildContext context, int id) async {
    final formulario = disponibles.firstWhere((f) => (f['id'] as num).toInt() == id, orElse: () => {});
    if (formulario.isEmpty) return;
    final resultado = await editarFormulario(context, formulario);
    if (resultado == null) return;
    if (resultado['borrado'] == true) {
      alCambiarDisponibles(disponibles.where((f) => (f['id'] as num).toInt() != id).toList());
      alCambiar(elegidos.where((e) => e != id).toList());
    } else {
      alCambiarDisponibles(disponibles.map((f) => (f['id'] as num).toInt() == id ? resultado : f).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombres = {for (final f in disponibles) (f['id'] as num).toInt(): '${f['nombre']}'};
    final faltan = disponibles.where((f) => !elegidos.contains((f['id'] as num).toInt())).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Formularios de control', style: TextStyle(color: sonTextoSuave, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final id in elegidos)
              InputChip(
                label: Text(nombres[id] ?? 'Formulario #$id'),
                avatar: const Icon(Icons.fact_check_outlined, size: 18),
                tooltip: 'Tocá para ver o corregir el formulario',
                onPressed: () => _editar(context, id),
                onDeleted: () => alCambiar(elegidos.where((e) => e != id).toList()),
              ),
            PopupMenuButton<int>(
              tooltip: 'Agregar formulario',
              onSelected: (opcion) => _agregar(context, opcion),
              itemBuilder: (_) => [
                // Primero subir o crear (siempre a la vista), después los ya guardados.
                const PopupMenuItem<int>(
                  value: _subirExcel,
                  child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.upload_file), title: Text('Subir un Excel'), subtitle: Text('Se convierte solo y lo revisás')),
                ),
                const PopupMenuItem<int>(
                  value: _aMano,
                  child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.edit_note), title: Text('Crear uno a mano')),
                ),
                if (faltan.isNotEmpty) const PopupMenuDivider(),
                for (final f in faltan)
                  PopupMenuItem<int>(
                    value: (f['id'] as num).toInt(),
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.fact_check_outlined),
                      title: Text('${f['nombre']}'),
                      subtitle: Text(resumenDeFormulario(Map<String, dynamic>.from(f['definicion'] as Map? ?? {})), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ],
              child: const Chip(avatar: Icon(Icons.add, size: 18), label: Text('Agregar formulario')),
            ),
          ],
        ),
      ],
    );
  }
}
