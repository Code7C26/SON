import 'package:flutter/material.dart';

import '../theme/tema.dart';
import 'traducciones_en.dart';

/// Idioma de SON: español (el de origen) o inglés.
///
/// Los textos se escriben en español en el código y `tr()` los pasa al inglés
/// buscando en [traduccionesEn]. Lo que no está en el diccionario se muestra
/// tal cual, así que nunca falta un texto: a lo sumo queda en español.
class ControlIdioma extends ChangeNotifier {
  String codigo = 'es';
  void Function(String codigo)? alGuardar;

  bool get ingles => codigo == 'en';
  Locale get locale => Locale(codigo);

  void establecer(String nuevo, {bool avisar = true, bool guardar = false}) {
    if (nuevo != 'es' && nuevo != 'en') return;
    if (nuevo == codigo) return;
    codigo = nuevo;
    _cache.clear();
    if (avisar) notifyListeners();
    if (guardar) alGuardar?.call(nuevo);
  }

  void alternar() => establecer(ingles ? 'es' : 'en', guardar: true);
}

final controlIdioma = ControlIdioma();

const idiomasSoportados = [Locale('es'), Locale('en')];

/// Traduce un texto escrito en español al idioma elegido.
String tr(String texto) {
  if (!controlIdioma.ingles || texto.isEmpty) return texto;
  final enCache = _cache[texto];
  if (enCache != null) return enCache;
  final resultado = _traducir(texto);
  if (_cache.length > 4000) _cache.clear();
  _cache[texto] = resultado;
  return resultado;
}

/// Titular de dos partes (normal + destacado). Si el diccionario tiene la
/// pareja "normal|destacado" se traduce junta, porque en inglés cambia el orden.
(String, String) trPar(String normal, String destacado) {
  if (controlIdioma.ingles) {
    final par = traduccionesEn['$normal|$destacado'];
    final i = par?.indexOf('|') ?? -1;
    if (par != null && i > 0) return (par.substring(0, i), par.substring(i + 1));
  }
  return (tr(normal), tr(destacado));
}

/// Igual que [tr] pero acepta nulos (para `tooltip`, `errorText`, etc.).
String? trn(String? texto) => texto == null ? null : tr(texto);

final Map<String, String> _cache = {};

String _traducir(String texto) {
  final directo = _buscar(texto);
  if (directo != null) return directo;

  // Espacios o signos al principio o al final ("Total: ", "• Pendiente").
  final m = RegExp(r'^([\s•·\-–—:(¿¡]*)(.*?)([\s:.,;…!?)]*)$', dotAll: true).firstMatch(texto);
  if (m != null) {
    final centro = m.group(2)!;
    if (centro.isNotEmpty && centro != texto) {
      final t = _buscar(centro);
      if (t != null) return '${_signos(m.group(1)!)}$t${m.group(3)}';
    }
  }

  for (final plantilla in _plantillas) {
    final r = plantilla.aplicar(texto);
    if (r != null) return r;
  }
  return texto;
}

/// En inglés no se usan los signos de apertura.
String _signos(String inicio) => inicio.replaceAll('¿', '').replaceAll('¡', '');

String? _buscar(String texto) {
  final t = traduccionesEn[texto];
  if (t != null) return t;
  // TODO EN MAYÚSCULAS (etiquetas) o todo en minúsculas (estados que vienen del servidor).
  final clave = texto.toLowerCase();
  final base = _minusculas[clave];
  if (base == null) return null;
  if (texto == texto.toUpperCase() && texto != clave) return base.toUpperCase();
  if (texto == clave) return base.toLowerCase();
  if (texto.isNotEmpty && texto[0] == texto[0].toUpperCase()) {
    return base.isEmpty ? base : base[0].toUpperCase() + base.substring(1);
  }
  return base;
}

final Map<String, String> _minusculas = {
  for (final e in traduccionesEn.entries)
    if (!e.key.contains('{}') && !e.key.contains('{#}')) e.key.toLowerCase(): e.value,
};

/// Textos con partes variables: "{} órdenes" → "{} orders".
/// En la traducción se puede usar {1}, {2}… para cambiar el orden.
/// Las partes variables también se traducen ("hace {} min" dentro de otra frase).
class _Plantilla {
  final RegExp patron;
  final String destino;
  _Plantilla(this.patron, this.destino);

  String? aplicar(String texto) {
    final m = patron.firstMatch(texto);
    if (m == null) return null;
    var i = 0;
    String parte(int n) {
      final valor = m.group(n) ?? '';
      return valor.isEmpty ? valor : _traducir(valor);
    }

    var salida = destino.replaceAllMapped(RegExp(r'\{(\d+)\}'), (x) => parte(int.parse(x.group(1)!)));
    salida = salida.replaceAllMapped(RegExp(r'\{\}'), (_) => parte(++i));
    return salida;
  }
}

final List<_Plantilla> _plantillas = [
  for (final e in traduccionesEn.entries)
    if (e.key.contains('{}') || e.key.contains('{#}'))
      _Plantilla(RegExp('^${_patron(e.key)}\$', dotAll: true), e.value),
]..sort((a, b) => b.patron.pattern.length.compareTo(a.patron.pattern.length));

/// {} es cualquier texto (puede ir vacío) y {#} solo un número.
String _patron(String clave) {
  final partes = <String>[];
  var resto = clave;
  while (resto.isNotEmpty) {
    final i = resto.indexOf('{');
    if (i < 0) {
      partes.add(RegExp.escape(resto));
      break;
    }
    if (resto.startsWith('{}', i)) {
      partes..add(RegExp.escape(resto.substring(0, i)))..add('(.*?)');
      resto = resto.substring(i + 2);
    } else if (resto.startsWith('{#}', i)) {
      partes..add(RegExp.escape(resto.substring(0, i)))..add(r'(\d[\d.,]*)');
      resto = resto.substring(i + 3);
    } else {
      partes.add(RegExp.escape(resto.substring(0, i + 1)));
      resto = resto.substring(i + 1);
    }
  }
  return partes.join();
}

/// `Text` que se traduce solo. Se puede usar con `const` igual que `Text`.
class Tx extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  const Tx(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  @override
  Widget build(BuildContext context) => Text(
        tr(data),
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: trn(semanticsLabel),
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
}

/// Selector de idioma ES / EN en forma de píldora.
/// Con [compacto] muestra un solo botón redondo que alterna entre los dos.
class SelectorIdioma extends StatelessWidget {
  final bool compacto;
  const SelectorIdioma({super.key, this.compacto = false});

  @override
  Widget build(BuildContext context) {
    final ingles = controlIdioma.ingles;
    if (compacto) {
      return IconButton(
        tooltip: ingles ? 'Cambiar a español' : 'Switch to English',
        onPressed: controlIdioma.alternar,
        icon: Text(
          ingles ? 'EN' : 'ES',
          style: TextStyle(fontFamily: AppTypography.ui, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.6, color: sonTexto),
        ),
      );
    }
    return Semantics(
      label: ingles ? 'Language' : 'Idioma',
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: sonTarjeta,
          borderRadius: AppRadius.rPildora,
          border: Border.all(color: sonBorde),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OpcionIdioma(codigo: 'es', texto: 'ES', nombre: 'Español', activo: !ingles),
            _OpcionIdioma(codigo: 'en', texto: 'EN', nombre: 'English', activo: ingles),
          ],
        ),
      ),
    );
  }
}

class _OpcionIdioma extends StatelessWidget {
  final String codigo;
  final String texto;
  final String nombre;
  final bool activo;
  const _OpcionIdioma({required this.codigo, required this.texto, required this.nombre, required this.activo});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: nombre,
      child: Semantics(
        button: true,
        selected: activo,
        label: nombre,
        child: InkWell(
          borderRadius: AppRadius.rPildora,
          onTap: activo ? null : () => controlIdioma.establecer(codigo, guardar: true),
          child: AnimatedContainer(
            duration: AppMotion.media,
            curve: AppMotion.curva,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: activo ? sonTexto : Colors.transparent,
              borderRadius: AppRadius.rPildora,
            ),
            child: Text(
              texto,
              style: TextStyle(
                fontFamily: AppTypography.ui,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: activo ? sonFondo : sonTextoSuave,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
