import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:son_tecnico/theme/colores.dart';

/// Lo que el técnico escribió en la ventana "Anotar para presupuestar".
class NotaNueva {
  final String descripcion;
  final int cantidad;
  final Uint8List? foto;

  const NotaNueva({required this.descripcion, required this.cantidad, this.foto});
}

/// Identificador propio de cada nota. Lo genera el celular: si el envío se repite por falta
/// de señal, el servidor reconoce que ya la tiene y no la duplica.
String nuevoIdDeNota([Random? azar]) {
  final suerte = azar ?? Random.secure();
  final hora = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final sal = List.generate(6, (_) => suerte.nextInt(36).toRadixString(36)).join();
  return 'n$hora$sal';
}

/// Sección "Para presupuestar" de la pantalla de trabajo: lista lo que el técnico anotó
/// en esta visita y muestra si ya llegó al área comercial.
class SeccionParaPresupuestar extends StatelessWidget {
  /// Cada nota: `id`, `descripcion`, `cantidad` y `conFoto`.
  final List<Map<String, dynamic>> notas;

  /// Miniaturas de las fotos que se sacaron en esta sesión (por id de nota).
  final Map<String, Uint8List> fotos;

  /// Notas que todavía están en el celular esperando señal.
  final Set<String> pendientes;

  /// Notas que el servidor rechazó.
  final Set<String> fallidas;

  final VoidCallback onAnotar;

  const SeccionParaPresupuestar({
    super.key,
    required this.notas,
    required this.fotos,
    required this.pendientes,
    required this.fallidas,
    required this.onAnotar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s12),
          child: Text('Para presupuestar', style: Theme.of(context).textTheme.titleLarge),
        ),
        if (notas.isNotEmpty)
          Container(
            decoration: decoracionTarjeta(radio: AppRadius.tarjetaGrande),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < notas.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _FilaNota(
                    nota: notas[i],
                    foto: fotos['${notas[i]['id']}'],
                    pendiente: pendientes.contains('${notas[i]['id']}'),
                    fallida: fallidas.contains('${notas[i]['id']}'),
                  ),
                ],
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              key: const Key('anotar_presupuesto'),
              onPressed: onAnotar,
              icon: const Icon(Icons.playlist_add_rounded),
              label: const Text('Anotar para presupuestar'),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilaNota extends StatelessWidget {
  final Map<String, dynamic> nota;
  final Uint8List? foto;
  final bool pendiente;
  final bool fallida;

  const _FilaNota({required this.nota, required this.foto, required this.pendiente, required this.fallida});

  @override
  Widget build(BuildContext context) {
    final cantidad = (nota['cantidad'] as num?)?.toInt() ?? 1;
    final (texto, color, icono) = fallida
        ? ('No se pudo enviar', sonRojo, Icons.error_outline)
        : pendiente
            ? ('En el celular', sonAmbar, Icons.schedule)
            : ('Enviada', sonLightGreen, Icons.check_circle_outline);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: sonTarjetaAlta, borderRadius: BorderRadius.circular(8)),
            clipBehavior: Clip.hardEdge,
            child: foto != null
                ? Image.memory(foto!, fit: BoxFit.cover)
                : Icon(nota['conFoto'] == true ? Icons.photo_outlined : Icons.sticky_note_2_outlined, color: sonTextoSuave),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${nota['descripcion']}', style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Cantidad: $cantidad', style: TextStyle(color: sonTextoSuave, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icono, size: 14, color: color),
                const SizedBox(width: 4),
                Text(texto, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre la ventana para anotar algo. Devuelve null si el técnico la cierra sin anotar.
Future<NotaNueva?> pedirNotaParaPresupuestar(BuildContext context) {
  return showModalBottomSheet<NotaNueva>(
    context: context,
    isScrollControlled: true,
    backgroundColor: sonTarjeta,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _FormularioNota(),
  );
}

class _FormularioNota extends StatefulWidget {
  const _FormularioNota();

  @override
  State<_FormularioNota> createState() => _FormularioNotaState();
}

class _FormularioNotaState extends State<_FormularioNota> {
  final TextEditingController _texto = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  int _cantidad = 1;
  Uint8List? _foto;

  @override
  void initState() {
    super.initState();
    _texto.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  bool get _puedeAnotar => _texto.text.trim().isNotEmpty;

  Future<void> _sacarFoto() async {
    try {
      final foto = await _picker.pickImage(source: ImageSource.camera, imageQuality: 60, maxWidth: 1600);
      if (foto == null) return;
      final bytes = await foto.readAsBytes();
      if (mounted) setState(() => _foto = bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir la cámara')));
    }
  }

  void _anotar() {
    Navigator.pop(context, NotaNueva(descripcion: _texto.text.trim(), cantidad: _cantidad, foto: _foto));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Anotar para presupuestar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: sonTexto)),
            const SizedBox(height: 12),
            const SizedBox(height: 16),
            TextField(
              key: const Key('nota_descripcion'),
              controller: _texto,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: '¿Qué hay que presupuestar?', hintText: 'Ej: Extintor ABC de 5 kg'),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Cantidad', style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  key: const Key('nota_menos'),
                  tooltip: 'Menos',
                  onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 44,
                  child: Center(child: Text('$_cantidad', key: Key('nota_cantidad'), style: TextStyle(color: sonTexto, fontSize: 18, fontWeight: FontWeight.bold))),
                ),
                IconButton(
                  key: const Key('nota_mas'),
                  tooltip: 'Más',
                  onPressed: _cantidad < 999 ? () => setState(() => _cantidad++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_foto == null)
              OutlinedButton.icon(
                key: const Key('nota_foto'),
                onPressed: _sacarFoto,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Agregar foto (opcional)'),
              )
            else
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: sonBorde)),
                    clipBehavior: Clip.hardEdge,
                    child: Image.memory(_foto!, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () => setState(() => _foto = null),
                    icon: Icon(Icons.delete_outline, color: sonRojo),
                    label: Text('Quitar foto', style: TextStyle(color: sonRojo)),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                key: const Key('nota_guardar'),
                onPressed: _puedeAnotar ? _anotar : null,
                child: const Text('Anotar', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
