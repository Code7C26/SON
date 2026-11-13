import 'package:flutter/material.dart';

// Formulario "igual al Excel": se dibuja la planilla tal cual (celdas, bordes, anchos) y el técnico
// toca los casilleros vacíos para completarlos. Lo que carga se ve en azul, como en el informe.

const Color colorCargado = Color(0xFF1F4E9A);
const Color _colorTinta = Color(0xFF222222);
const Color _colorCasillero = Color(0x14FFB300); // casillero para completar: apenas marcado

List<Map<String, dynamic>> _mapas(dynamic lista) => (lista as List? ?? []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
List<double> _numeros(dynamic lista) => (lista as List? ?? []).map((n) => (n as num).toDouble()).toList();

String fechaLegibleDeCasillero(String iso) {
  final partes = iso.split('-');
  return partes.length == 3 ? '${partes[2]}/${partes[1]}/${partes[0]}' : iso;
}

/// Dibuja la planilla. Si [alTocar] es null es solo de lectura (por ejemplo, la vista previa del panel).
class PlanillaExcel extends StatelessWidget {
  final Map<String, dynamic> definicion;
  final Map<String, String> valores;
  final String? cliente;
  final String? fecha;
  final void Function(Map<String, dynamic> campo)? alTocar;

  const PlanillaExcel({super.key, required this.definicion, this.valores = const {}, this.cliente, this.fecha, this.alTocar});

  @override
  Widget build(BuildContext context) {
    final anchos = _numeros(definicion['anchos']);
    final altos = _numeros(definicion['altos']);
    final xs = <double>[0];
    for (final a in anchos) {
      xs.add(xs.last + a);
    }
    final ys = <double>[0];
    for (final a in altos) {
      ys.add(ys.last + a);
    }
    Rect caja(Map celda) {
      final f = (celda['f'] as num).toInt();
      final c = (celda['c'] as num).toInt();
      final f2 = ((celda['f2'] ?? f) as num).toInt().clamp(f, altos.length - 1);
      final c2 = ((celda['c2'] ?? c) as num).toInt().clamp(c, anchos.length - 1);
      return Rect.fromLTRB(xs[c], ys[f], xs[c2 + 1], ys[f2 + 1]);
    }

    final celdas = _mapas(definicion['celdas']);
    final porPosicion = {for (final celda in celdas) '${celda['f']},${celda['c']}': celda};
    final hijos = <Widget>[];

    for (final celda in celdas) {
      final r = caja(celda);
      if (r.width <= 0 || r.height <= 0) continue;
      var texto = '${celda['t'] ?? ''}';
      if (celda['auto'] == 'empresa' && (cliente ?? '').isNotEmpty) texto = '$texto $cliente';
      if (celda['auto'] == 'fecha' && (fecha ?? '').isNotEmpty) texto = '$texto $fecha';
      final b = (celda['b'] as List? ?? [0, 0, 0, 0]).map((x) => (x as num).toInt()).toList();
      BorderSide lado(int estilo) => estilo == 0
          ? BorderSide.none
          : BorderSide(color: _colorTinta, width: [2, 8, 10, 12].contains(estilo) ? 1.3 : ([5, 6].contains(estilo) ? 2 : 0.6));
      hijos.add(Positioned.fromRect(
        rect: r,
        child: Container(
          decoration: BoxDecoration(border: Border(left: lado(b[0]), right: lado(b[1]), top: lado(b[2]), bottom: lado(b[3]))),
          child: texto.isEmpty ? null : _TextoDeCelda(texto: texto, celda: celda, color: _colorTinta),
        ),
      ));
    }

    // Casilleros para completar: lo cargado en azul; tocar abre la carga.
    for (final campo in _mapas(definicion['campos'])) {
      final clave = '${campo['f']},${campo['c']}';
      final celda = porPosicion[clave] ?? {'f': campo['f'], 'c': campo['c']};
      final r = caja(celda);
      if (r.width <= 0 || r.height <= 0) continue;
      final valor = valores[clave];
      final texto = valor == null ? '' : (campo['tipo'] == 'fecha' ? fechaLegibleDeCasillero(valor) : valor);
      hijos.add(Positioned.fromRect(
        rect: r.deflate(0.6),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: alTocar == null ? null : () => alTocar!(campo),
          child: Container(
            color: alTocar != null && valor == null ? _colorCasillero : Colors.transparent,
            child: texto.isEmpty
                ? null
                : _TextoDeCelda(
                    texto: texto,
                    celda: {...celda, 'h': campo['tipo'] == 'marca' ? 'c' : (celda['h'] ?? 'c'), 'v': 'c', 'r': 0, 'n': campo['tipo'] == 'marca'},
                    color: colorCargado,
                  ),
          ),
        ),
      ));
    }

    return Container(
      color: Colors.white,
      width: xs.last,
      height: ys.last,
      child: Stack(children: hijos),
    );
  }
}

class _TextoDeCelda extends StatelessWidget {
  final String texto;
  final Map celda;
  final Color color;
  const _TextoDeCelda({required this.texto, required this.celda, required this.color});

  @override
  Widget build(BuildContext context) {
    final alineacion = switch (celda['h']) { 'c' => TextAlign.center, 'r' => TextAlign.right, _ => TextAlign.left };
    final vertical = switch (celda['v']) { 't' => -1.0, 'c' => 0.0, _ => 1.0 };
    final horizontal = switch (celda['h']) { 'c' => 0.0, 'r' => 1.0, _ => -1.0 };
    final giro = (celda['r'] as num?)?.toInt() ?? 0;
    final tamano = ((celda['z'] as num?)?.toDouble() ?? 10).clamp(4, 40).toDouble();
    final contenido = giro == 255 ? texto.split('').join('\n') : texto;
    return LayoutBuilder(builder: (context, caja) {
      final girado = giro == 90 || giro == -90;
      final ancho = ((girado ? caja.maxHeight : caja.maxWidth) - 3).clamp(1, 4000).toDouble();
      Widget hijo = SizedBox(
        width: ancho,
        child: Text(
          contenido,
          textAlign: alineacion,
          style: TextStyle(color: color, fontSize: tamano, height: 1.1, fontWeight: celda['n'] == true ? FontWeight.bold : FontWeight.normal),
        ),
      );
      hijo = FittedBox(fit: BoxFit.scaleDown, child: hijo); // si no entra, se achica (como Excel al imprimir)
      if (girado) hijo = RotatedBox(quarterTurns: giro == 90 ? 3 : 1, child: hijo);
      return Padding(padding: const EdgeInsets.all(1.5), child: Align(alignment: Alignment(horizontal, vertical), child: hijo));
    });
  }
}

/// Pantalla para completar la planilla en la visita.
class PantallaPlanillaExcel extends StatefulWidget {
  final Map formulario;
  final Map? respuestas;
  final String? cliente;
  const PantallaPlanillaExcel({super.key, required this.formulario, this.respuestas, this.cliente});

  @override
  State<PantallaPlanillaExcel> createState() => _PantallaPlanillaExcelState();
}

class _PantallaPlanillaExcelState extends State<PantallaPlanillaExcel> {
  late final Map<String, dynamic> d = Map<String, dynamic>.from(widget.formulario['definicion'] as Map? ?? {});
  late final Map<String, String> _valores = {
    for (final e in (widget.respuestas?['valores'] as Map? ?? {}).entries)
      if (e.value != null) '${e.key}': '${e.value}',
  };
  late final TextEditingController _observacion = TextEditingController(text: '${widget.respuestas?['observacion'] ?? ''}');
  final TransformationController _vista = TransformationController();
  bool _ajustada = false;

  String get _hoy {
    final h = DateTime.now();
    return '${h.day.toString().padLeft(2, '0')}/${h.month.toString().padLeft(2, '0')}/${h.year}';
  }

  @override
  void dispose() {
    _observacion.dispose();
    _vista.dispose();
    super.dispose();
  }

  void _listo() => Navigator.pop(context, {'valores': _valores, 'observacion': _observacion.text.trim()});

  List<String> get _sugerencias => <String>{
        ...(d['sugerencias'] as List? ?? []).map((s) => '$s'),
        ...(d['opciones'] as List? ?? []).map((s) => '$s'),
        'X',
      }.toList();

  Future<void> _tocar(Map<String, dynamic> campo) async {
    final clave = '${campo['f']},${campo['c']}';
    switch (campo['tipo']) {
      case 'marca':
        setState(() {
          if (_valores.containsKey(clave)) {
            _valores.remove(clave);
          } else {
            // Una sola marca por grupo en el renglón (SI / NO / NC de la misma pregunta).
            if (campo['grupo'] != null) {
              for (final otro in (d['campos'] as List).whereType<Map>()) {
                if (otro['f'] == campo['f'] && otro['grupo'] == campo['grupo']) _valores.remove('${otro['f']},${otro['c']}');
              }
            }
            _valores[clave] = 'X';
          }
        });
      case 'fecha':
        final actual = DateTime.tryParse(_valores[clave] ?? '');
        final hoy = DateTime.now();
        final elegida = await showDatePicker(
          context: context,
          helpText: '${campo['encabezado'] ?? 'Fecha'}'.toUpperCase(),
          initialDate: actual ?? hoy,
          firstDate: DateTime(hoy.year - 10),
          lastDate: DateTime(hoy.year + 15),
          cancelText: _valores.containsKey(clave) ? 'Borrar' : 'Cancelar',
        );
        if (!mounted) return;
        setState(() {
          if (elegida != null) {
            _valores[clave] = '${elegida.year}-${elegida.month.toString().padLeft(2, '0')}-${elegida.day.toString().padLeft(2, '0')}';
          } else if (actual != null) {
            _valores.remove(clave); // "Borrar"
          }
        });
      default:
        final texto = await _pedirTexto(campo, _valores[clave] ?? '');
        if (texto == null || !mounted) return;
        setState(() => texto.isEmpty ? _valores.remove(clave) : _valores[clave] = texto);
    }
  }

  Future<String?> _pedirTexto(Map campo, String actual) {
    final control = TextEditingController(text: actual);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (hoja) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(hoja).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${campo['encabezado'] ?? 'Casillero'}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _sugerencias
                  .map((s) => ActionChip(label: Text(s, style: const TextStyle(fontWeight: FontWeight.bold)), onPressed: () => Navigator.pop(hoja, s)))
                  .toList(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: control,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (v) => Navigator.pop(hoja, v.trim()),
              decoration: const InputDecoration(hintText: 'Escribí acá'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(hoja, ''), child: const Text('Borrar')),
                const Spacer(),
                ElevatedButton(onPressed: () => Navigator.pop(hoja, control.text.trim()), child: const Text('Guardar')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _ajustar(BoxConstraints caja) {
    if (_ajustada) return;
    final ancho = _numeros(d['anchos']).fold<double>(0, (a, b) => a + b);
    if (ancho <= 0) return;
    final escala = (caja.maxWidth / ancho).clamp(0.2, 3.0).toDouble();
    _vista.value = Matrix4.identity()..scaleByDouble(escala, escala, 1, 1);
    _ajustada = true;
  }

  @override
  Widget build(BuildContext context) {
    final cargados = _valores.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _listo();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.formulario['nombre']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [TextButton(onPressed: _listo, child: const Text('Listo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Colors.black12,
              child: Text(
                'Tocá un casillero para completarlo. Con dos dedos agrandás. $cargados cargado${cargados == 1 ? '' : 's'}.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, caja) {
                _ajustar(caja);
                return InteractiveViewer(
                  transformationController: _vista,
                  constrained: false,
                  minScale: 0.2,
                  maxScale: 5,
                  boundaryMargin: const EdgeInsets.all(200),
                  child: PlanillaExcel(definicion: d, valores: _valores, cliente: widget.cliente, fecha: _hoy, alTocar: _tocar),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _observacion,
                      decoration: const InputDecoration(labelText: 'Observaciones del formulario (opcional)', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(onPressed: _listo, child: const Text('Listo')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
