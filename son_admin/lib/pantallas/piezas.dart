import 'package:flutter/material.dart';
import 'package:son_admin/theme/tema.dart';

/// Pasa a minúsculas y saca los acentos, para buscar sin importar cómo se escribió.
String sinAcentos(String texto) {
  const con = 'áàäâéèëêíìïîóòöôúùüûñ';
  const sin = 'aaaaeeeeiiiioooouuuun';
  var resultado = texto.toLowerCase().replaceAll('_', ' ').trim();
  for (var i = 0; i < con.length; i++) {
    resultado = resultado.replaceAll(con[i], sin[i]);
  }
  return resultado;
}

/// Busca por palabras sueltas: "luz emergencia" encuentra "Luz de emergencia".
/// Una búsqueda vacía encuentra todo.
bool coincideBusqueda(String texto, String consulta) {
  final palabras = sinAcentos(consulta).split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (palabras.isEmpty) return true;
  final normalizado = sinAcentos(texto);
  return palabras.every(normalizado.contains);
}

/// Fecha corta y fácil de leer: "Hoy 15:30", "Ayer 09:10" o "27/10 15:30".
String fechaCorta(DateTime fecha, {DateTime? ahora}) {
  final actual = ahora ?? DateTime.now();
  String dos(int numero) => numero.toString().padLeft(2, '0');
  final hora = '${dos(fecha.hour)}:${dos(fecha.minute)}';
  final hoy = DateTime.utc(actual.year, actual.month, actual.day);
  final dia = DateTime.utc(fecha.year, fecha.month, fecha.day);
  final dias = hoy.difference(dia).inDays;
  if (dias == 0) return 'Hoy $hora';
  if (dias == 1) return 'Ayer $hora';
  final anio = fecha.year == actual.year ? '' : '/${fecha.year}';
  return '${dos(fecha.day)}/${dos(fecha.month)}$anio $hora';
}

/// Botón redondeado para filtrar una lista ("Abiertas · 4").
class PildoraFiltro extends StatelessWidget {
  final String texto;
  final bool activo;
  final Color color;
  final VoidCallback alTocar;

  const PildoraFiltro({super.key, required this.texto, required this.activo, required this.alTocar, this.color = const Color(0xFFFF6147)});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: alTocar,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: activo ? color.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: activo ? color : sonBorde),
        ),
        child: Text(texto, style: TextStyle(color: activo ? color : sonTextoSuave, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Etiqueta de color con el estado de algo ("Nueva", "En presupuesto"...).
class EtiquetaEstado extends StatelessWidget {
  final String texto;
  final Color color;

  const EtiquetaEstado({super.key, required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12.5)),
    );
  }
}

/// Plata en pesos argentinos: 365113 → "$365.113".
String pesos(num? valor) {
  if (valor == null) return '—';
  final n = valor.round();
  final cifras = n.abs().toString();
  final conPuntos = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < cifras.length; i++) {
    if (i > 0 && (cifras.length - i) % 3 == 0) conPuntos.write('.');
    conPuntos.write(cifras[i]);
  }
  return '\$$conPuntos';
}

/// Número que escribió la persona: acepta "2,1", "2.1" o "365.113".
num? numeroDePersona(String texto) {
  final limpio = texto.trim().replaceAll(' ', '');
  if (limpio.isEmpty) return null;
  if (limpio.contains(',')) return num.tryParse(limpio.replaceAll('.', '').replaceAll(',', '.'));
  final partes = limpio.split('.');
  if (partes.length > 1 && partes.last.length == 3 && partes.every((p) => RegExp(r'^\d+$').hasMatch(p))) {
    return num.tryParse(partes.join());
  }
  return num.tryParse(limpio);
}

Color colorDeMargen(String? nivel) => switch (nivel) {
      'bajo' => sonRojo,
      'medio' => sonAmbar,
      'ok' => sonLightGreen,
      _ => sonTextoSuave,
    };

String textoDeMargen(String? nivel) => switch (nivel) {
      'bajo' => 'Margen bajo',
      'medio' => 'Margen justo',
      'ok' => 'Margen OK',
      _ => 'Sin costo',
    };

Color colorEstadoPresupuesto(String estado) => switch (estado) {
      'Borrador' => sonTextoSuave,
      'Enviado' => sonAzul,
      'Negociando' => sonAmbar,
      'Aceptado' => sonLightGreen,
      'Rechazado' => sonRojo,
      _ => sonTextoSuave,
    };

/// Un dato chico con su ícono (técnico, fecha, teléfono...).
class DatoConIcono extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color? color;
  final int lineas;

  const DatoConIcono({super.key, required this.icono, required this.texto, this.color, this.lineas = 1});

  @override
  Widget build(BuildContext context) {
    final tinta = color ?? sonTextoSuave;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icono, size: 15, color: tinta)),
        const SizedBox(width: 6),
        Flexible(child: Text(texto, maxLines: lineas, overflow: TextOverflow.ellipsis, style: TextStyle(color: tinta, fontSize: 13, height: 1.25))),
      ],
    );
  }
}
