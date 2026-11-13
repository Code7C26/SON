import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/tema.dart';

/// Etiqueta suave en mayúsculas (eyebrow pill) que va sobre un titular.
class Eyebrow extends StatelessWidget {
  final String texto;
  final IconData? icono;
  const Eyebrow(this.texto, {super.key, this.icono});

  @override
  Widget build(BuildContext context) {
    final oscuro = !controlTema.claro;
    final fondo = oscuro ? AppColors.eyebrowTexto.withValues(alpha: 0.18) : AppColors.eyebrowFondo;
    const color = AppColors.eyebrowTexto;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: fondo, borderRadius: AppRadius.rPildora),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[Icon(icono, size: 13, color: color), const SizedBox(width: 6)],
          Text(texto.toUpperCase(), style: AppTypography.eyebrow(color).copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

/// Titular con contraste de pesos: una parte en Regular y otra en Bold.
/// Ej.: TituloContraste(normal: 'Hola,', destacado: 'Francina').
class TituloContraste extends StatelessWidget {
  final String normal;
  final String destacado;
  final double tamano;
  final bool destacadoEnLineaNueva;
  final Color? color;
  const TituloContraste({
    super.key,
    required this.normal,
    required this.destacado,
    this.tamano = 34,
    this.destacadoEnLineaNueva = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: AppTypography.display,
      fontSize: tamano,
      height: 1.15,
      letterSpacing: AppTypography.trackingTitulo,
      color: color ?? sonTexto,
      fontWeight: FontWeight.w400,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: normal),
          TextSpan(text: destacadoEnLineaNueva ? '\n' : ' '),
          TextSpan(text: destacado, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Ícono dentro de un círculo oscuro (tinta #2E2E2E).
class IconoCircular extends StatelessWidget {
  final IconData icono;
  final double tamano;
  final Color? fondo;
  final Color? color;
  const IconoCircular(this.icono, {super.key, this.tamano = 40, this.fondo, this.color});

  @override
  Widget build(BuildContext context) {
    final oscuro = !controlTema.claro;
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: fondo ?? (oscuro ? AppColors.oscuroSuperficieAlta : AppColors.tinta),
        shape: BoxShape.circle,
      ),
      child: Icon(icono, size: tamano * 0.48, color: color ?? AppColors.superficie),
    );
  }
}

/// Número grande protagonista con su etiqueta corta debajo.
class KpiBloque extends StatelessWidget {
  final String valor;
  final String etiqueta;
  final Color? colorValor;
  final Color? colorEtiqueta;
  final double tamano;
  final VoidCallback? alTocar;
  const KpiBloque({
    super.key,
    required this.valor,
    required this.etiqueta,
    this.colorValor,
    this.colorEtiqueta,
    this.tamano = 34,
    this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: AppMotion.lenta,
          curve: AppMotion.curva,
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: Text(valor, style: AppTypography.kpi(colorValor ?? sonTexto, size: tamano)),
        ),
        const SizedBox(height: 4),
        Text(etiqueta, style: AppTypography.kpiEtiqueta(colorEtiqueta ?? sonTextoSuave)),
      ],
    );
    if (alTocar == null) return contenido;
    return _Presionable(alTocar: alTocar!, child: contenido);
  }
}

/// Hace clickeable cualquier bloque con cursor de mano y leve elevación al pasar el mouse.
class _Presionable extends StatefulWidget {
  final Widget child;
  final VoidCallback alTocar;
  const _Presionable({required this.child, required this.alTocar});

  @override
  State<_Presionable> createState() => _PresionableState();
}

class _PresionableState extends State<_Presionable> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.alTocar,
        behavior: HitTestBehavior.opaque,
        child: AnimatedSlide(
          offset: _encima ? const Offset(0, -0.04) : Offset.zero,
          duration: AppMotion.rapida,
          curve: AppMotion.curva,
          child: AnimatedOpacity(
            opacity: _encima ? 0.85 : 1,
            duration: AppMotion.rapida,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Tarjeta blanca de SON: radio 16, borde sutil y elevación leve al pasar el mouse.
class TarjetaSon extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? alTocar;
  final Color? color;
  const TarjetaSon({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpacing.s24), this.alTocar, this.color});

  @override
  State<TarjetaSon> createState() => _TarjetaSonState();
}

class _TarjetaSonState extends State<TarjetaSon> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final elevar = _encima && widget.alTocar != null;
    final tarjeta = AnimatedContainer(
      duration: AppMotion.rapida,
      curve: AppMotion.curva,
      transform: Matrix4.translationValues(0, elevar ? -2 : 0, 0),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.color ?? sonTarjeta,
        borderRadius: AppRadius.rTarjeta,
        border: Border.all(color: sonBorde),
        boxShadow: elevar ? AppShadows.elevada : AppShadows.suave,
      ),
      child: widget.child,
    );
    if (widget.alTocar == null) return tarjeta;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(onTap: widget.alTocar, child: tarjeta),
    );
  }
}

/// Aparición suave (fade + slide de 8px) con retraso opcional para escalonar.
class Aparecer extends StatelessWidget {
  final Widget child;
  final int orden;
  const Aparecer({super.key, required this.child, this.orden = 0});

  @override
  Widget build(BuildContext context) {
    // Con "reducir movimiento" activado en el sistema, aparece directo.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final retraso = AppMotion.escalon.inMilliseconds * orden;
    final total = AppMotion.lenta.inMilliseconds + retraso;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      builder: (context, t, hijo) {
        // Los primeros "retraso" ms se mantiene oculto; después anima con easeOutCubic.
        final inicio = total == 0 ? 0.0 : retraso / total;
        final local = t <= inicio ? 0.0 : (t - inicio) / (1 - inicio);
        final v = AppMotion.curva.transform(local.clamp(0.0, 1.0));
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * AppMotion.desplazamiento), child: hijo),
        );
      },
      child: child,
    );
  }
}

/// Bloque gris animado para estados de carga (skeleton).
class Skeleton extends StatefulWidget {
  final double alto;
  final double? ancho;
  final BorderRadius radio;
  const Skeleton({super.key, this.alto = 16, this.ancho, this.radio = AppRadius.rChico});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.alto,
        width: widget.ancho,
        decoration: BoxDecoration(
          color: Color.lerp(sonTarjetaAlta, sonBorde, _c.value),
          borderRadius: widget.radio,
        ),
      ),
    );
  }
}

/// Estado vacío: ícono + mensaje + acción opcional.
class EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String mensaje;
  final String? accion;
  final VoidCallback? alAccionar;
  const EstadoVacio({super.key, required this.icono, required this.mensaje, this.accion, this.alAccionar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconoCircular(icono, tamano: 56),
            const SizedBox(height: AppSpacing.s16),
            Text(mensaje, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: sonTextoSuave)),
            if (accion != null && alAccionar != null) ...[
              const SizedBox(height: AppSpacing.s16),
              ElevatedButton(onPressed: alAccionar, child: Text(accion!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado de error: mensaje claro + reintentar.
class EstadoError extends StatelessWidget {
  final String mensaje;
  final VoidCallback alReintentar;
  const EstadoError({super.key, required this.mensaje, required this.alReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconoCircular(Icons.cloud_off_rounded, tamano: 56, fondo: sonRojo.withValues(alpha: 0.12), color: sonRojo),
            const SizedBox(height: AppSpacing.s16),
            Text(mensaje, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: sonTexto)),
            const SizedBox(height: AppSpacing.s16),
            OutlinedButton.icon(onPressed: alReintentar, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

/// Encabezado común de cada pantalla del panel: eyebrow opcional, titular con contraste
/// de pesos y la acción principal a la derecha (una sola por vista).
class EncabezadoPantalla extends StatelessWidget {
  final String? eyebrow;
  final String normal;
  final String destacado;
  final Widget? accion;
  const EncabezadoPantalla({super.key, this.eyebrow, required this.normal, required this.destacado, this.accion});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, caja) {
      final angosto = caja.maxWidth < 760;
      final textos = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[Eyebrow(eyebrow!), const SizedBox(height: 12)],
          TituloContraste(normal: normal, destacado: destacado, tamano: angosto ? 28 : 34),
        ],
      );
      if (accion == null) return textos;
      if (angosto) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [textos, const SizedBox(height: AppSpacing.s16), accion!]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: textos), accion!]);
    });
  }
}

/// Píldora de filtro rápido con contador. Activa: bloque oscuro con texto claro.
class PildoraContador extends StatefulWidget {
  final String texto;
  final int cantidad;
  final bool activa;
  final Color? punto;
  final VoidCallback alTocar;
  const PildoraContador({super.key, required this.texto, required this.cantidad, required this.activa, required this.alTocar, this.punto});

  @override
  State<PildoraContador> createState() => _PildoraContadorState();
}

class _PildoraContadorState extends State<PildoraContador> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final oscuro = !controlTema.claro;
    final fondoActivo = oscuro ? AppColors.canvas : AppColors.tinta;
    final textoActivo = oscuro ? AppColors.tinta : AppColors.superficie;
    final activa = widget.activa;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.alTocar,
        child: AnimatedContainer(
          duration: AppMotion.rapida,
          curve: AppMotion.curva,
          height: 40,
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            color: activa ? fondoActivo : (_encima ? sonTarjeta : Colors.transparent),
            borderRadius: AppRadius.rPildora,
            border: Border.all(color: activa ? fondoActivo : sonBorde),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.punto != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.punto, shape: BoxShape.circle)),
                const SizedBox(width: 8),
              ],
              Text(widget.texto, style: TextStyle(color: activa ? textoActivo : sonTexto, fontWeight: FontWeight.w600, fontSize: 13.5)),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 28),
                height: 28,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: activa ? textoActivo.withValues(alpha: 0.16) : sonFondo,
                  borderRadius: AppRadius.rPildora,
                ),
                child: Text('${widget.cantidad}', style: TextStyle(color: activa ? textoActivo : sonTextoSuave, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Buscador en píldora.
class Buscador extends StatelessWidget {
  final String pista;
  final ValueChanged<String> alCambiar;
  final double ancho;
  const Buscador({super.key, this.pista = 'Buscar', required this.alCambiar, this.ancho = 280});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ancho,
      height: 44,
      child: TextField(
        onChanged: alCambiar,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: pista,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: sonTarjeta,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          border: OutlineInputBorder(borderRadius: AppRadius.rPildora, borderSide: BorderSide(color: sonBorde)),
          enabledBorder: OutlineInputBorder(borderRadius: AppRadius.rPildora, borderSide: BorderSide(color: sonBorde)),
          focusedBorder: OutlineInputBorder(borderRadius: AppRadius.rPildora, borderSide: BorderSide(color: sonAcento, width: 1.5)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vidrio esmerilado, orbes y Bento
// ---------------------------------------------------------------------------

/// Fondo del lienzo (#F4F4F4 / #2E2E2E) con orbes coral difuminados detrás del contenido.
/// Los orbes son degradados radiales que se desvanecen a transparente: se ven
/// desenfocados sin el costo de un blur en tiempo real.
class FondoOrbes extends StatelessWidget {
  final Widget child;

  /// Intensidad de los orbes (0–1). Pantallas de trabajo usan menos que el login.
  final double intensidad;
  const FondoOrbes({super.key, required this.child, this.intensidad = 1});

  @override
  Widget build(BuildContext context) {
    final oscuro = !controlTema.claro;
    final fuerza = (oscuro ? 0.22 : 0.30) * intensidad;
    return ColoredBox(
      color: sonFondo,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: LayoutBuilder(builder: (context, caja) {
                  final lado = caja.biggest.shortestSide.clamp(320.0, 1100.0);
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      _orbe(left: caja.maxWidth - lado * 0.55, top: -lado * 0.35, diametro: lado * 0.95, color: AppColors.acento, alfa: fuerza),
                      _orbe(left: -lado * 0.40, top: caja.maxHeight - lado * 0.55, diametro: lado * 0.85, color: AppColors.acento, alfa: fuerza * 0.75),
                      _orbe(left: caja.maxWidth * 0.35, top: caja.maxHeight * 0.30, diametro: lado * 0.55, color: AppColors.oro, alfa: fuerza * 0.35),
                    ],
                  );
                }),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _orbe({required double left, required double top, required double diametro, required Color color, required double alfa}) {
    return Positioned(
      left: left,
      top: top,
      width: diametro,
      height: diametro,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: alfa), color.withValues(alpha: alfa * 0.4), color.withValues(alpha: 0)],
            stops: const [0, 0.45, 1],
          ),
        ),
      ),
    );
  }
}

/// Panel translúcido con desenfoque (backdrop blur) y borde claro de 1px.
/// Va sobre [FondoOrbes]; para contenido denso conviene [TarjetaSon].
class PanelVidrio extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius radio;
  final double desenfoque;
  const PanelVidrio({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radio = AppRadius.rTarjetaGrande,
    this.desenfoque = 24,
  });

  @override
  Widget build(BuildContext context) {
    final oscuro = !controlTema.claro;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radio, boxShadow: AppShadows.vidrio),
      child: ClipRRect(
        borderRadius: radio,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: desenfoque, sigmaY: desenfoque),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: oscuro ? AppColors.vidrioOscuro : AppColors.vidrio,
              borderRadius: radio,
              border: Border.all(color: oscuro ? AppColors.vidrioOscuroBorde : AppColors.vidrioBorde),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Bloque de alto contraste (#2E2E2E) con radio 32 y un orbe coral que asoma desde una esquina.
class BloqueContraste extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool conOrbe;
  const BloqueContraste({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpacing.s32), this.conOrbe = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // En modo oscuro el fondo ya es #2E2E2E: el bloque baja a #262626 para separarse.
        color: controlTema.claro ? AppColors.tinta : AppColors.oscuroPanel,
        borderRadius: AppRadius.rTarjetaGrande,
        border: Border.all(color: AppColors.superficie.withValues(alpha: controlTema.claro ? 0.06 : 0.1)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: conOrbe
              ? RadialGradient(
                  center: const Alignment(1.1, -1.2),
                  radius: 1.1,
                  colors: [AppColors.acento.withValues(alpha: 0.24), AppColors.acento.withValues(alpha: 0)],
                )
              : null,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Estilos del [MicroBoton].
enum EstiloMicro { claro, oscuro, acento, vidrio }

/// Micro-botón circular para acciones integradas (abrir, editar, más). Siempre con tooltip.
class MicroBoton extends StatefulWidget {
  final IconData icono;
  final String tooltip;
  final VoidCallback? alTocar;
  final EstiloMicro estilo;
  final double tamano;
  const MicroBoton({
    super.key,
    required this.icono,
    required this.tooltip,
    required this.alTocar,
    this.estilo = EstiloMicro.claro,
    this.tamano = 40,
  });

  @override
  State<MicroBoton> createState() => _MicroBotonState();
}

class _MicroBotonState extends State<MicroBoton> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final oscuro = !controlTema.claro;
    Color fondo;
    Color icono;
    Color? borde;
    switch (widget.estilo) {
      case EstiloMicro.acento:
        fondo = AppColors.acento;
        icono = AppColors.sobreAcento;
      case EstiloMicro.oscuro:
        fondo = oscuro ? AppColors.canvas : AppColors.tinta;
        icono = oscuro ? AppColors.tinta : AppColors.superficie;
      case EstiloMicro.vidrio:
        fondo = AppColors.superficie.withValues(alpha: 0.14);
        icono = AppColors.superficie;
        borde = AppColors.superficie.withValues(alpha: 0.18);
      case EstiloMicro.claro:
        fondo = _encima ? sonTarjetaAlta : sonTarjeta;
        icono = sonTexto;
        borde = sonBorde;
    }
    final activo = widget.alTocar != null;
    // Área táctil mínima de 48dp aunque el círculo visible sea más chico.
    final area = widget.tamano < AppSpacing.tactilMinimo ? AppSpacing.tactilMinimo : widget.tamano;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: activo ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _encima = true),
          onExit: (_) => setState(() => _encima = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.alTocar,
            child: SizedBox(
              width: area,
              height: area,
              child: Center(
                child: AnimatedScale(
                  scale: _encima && activo ? 1.06 : 1,
                  duration: AppMotion.rapida,
                  curve: AppMotion.curva,
                  child: AnimatedOpacity(
                    opacity: activo ? 1 : 0.4,
                    duration: AppMotion.rapida,
                    child: Container(
                      width: widget.tamano,
                      height: widget.tamano,
                      decoration: BoxDecoration(
                        color: fondo,
                        shape: BoxShape.circle,
                        border: borde == null ? null : Border.all(color: borde),
                      ),
                      child: Icon(widget.icono, size: widget.tamano * 0.45, color: icono),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Celda de una [GrillaBento]: ocupa [columnas] de la grilla (se recorta al ancho disponible).
class CeldaBento {
  final int columnas;
  final Widget child;
  const CeldaBento({this.columnas = 1, required this.child});
}

/// Grilla tipo Bento: celdas de distinto ancho sobre una grilla de 4, 2 o 1
/// columnas según el espacio, con separación de 16px y aparición escalonada.
class GrillaBento extends StatelessWidget {
  final List<CeldaBento> celdas;
  final double separacion;
  final double anchoColumnaMinimo;
  final int ordenInicial;
  const GrillaBento({super.key, required this.celdas, this.separacion = AppSpacing.s16, this.anchoColumnaMinimo = 200, this.ordenInicial = 0});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, caja) {
      final ancho = caja.maxWidth;
      var columnas = 4;
      while (columnas > 1 && (ancho - separacion * (columnas - 1)) / columnas < anchoColumnaMinimo) {
        columnas = columnas == 4 ? 2 : 1;
      }
      final anchoColumna = (ancho - separacion * (columnas - 1)) / columnas;
      double anchoDe(int n) {
        final c = n.clamp(1, columnas);
        return anchoColumna * c + separacion * (c - 1);
      }

      return Wrap(
        spacing: separacion,
        runSpacing: separacion,
        children: [
          for (var i = 0; i < celdas.length; i++)
            SizedBox(width: anchoDe(celdas[i].columnas), child: Aparecer(orden: ordenInicial + i, child: celdas[i].child)),
        ],
      );
    });
  }
}

/// Tarjeta de indicador para la grilla Bento: micro-ícono circular arriba,
/// número grande y etiqueta corta. Tocable si tiene [alTocar].
class TarjetaKpi extends StatelessWidget {
  final IconData icono;
  final String valor;
  final String etiqueta;
  final Color? colorValor;
  final VoidCallback? alTocar;
  const TarjetaKpi({super.key, required this.icono, required this.valor, required this.etiqueta, this.colorValor, this.alTocar});

  @override
  Widget build(BuildContext context) {
    return TarjetaSon(
      alTocar: alTocar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconoCircular(icono, tamano: 40),
              const Spacer(),
              if (alTocar != null) Icon(Icons.arrow_outward_rounded, size: 18, color: sonTextoTenue),
            ],
          ),
          const SizedBox(height: AppSpacing.s24),
          KpiBloque(valor: valor, etiqueta: etiqueta, colorValor: colorValor, tamano: 34),
        ],
      ),
    );
  }
}

/// Contenido de un botón en píldora con un micro-círculo integrado a la derecha
/// (flecha por defecto). Se usa como `child` de un ElevatedButton/FilledButton.
class EtiquetaConFlecha extends StatelessWidget {
  final String texto;
  final IconData icono;
  final Color? colorCirculo;
  const EtiquetaConFlecha(this.texto, {super.key, this.icono = Icons.arrow_forward_rounded, this.colorCirculo});

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color ?? AppColors.superficie;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: AppSpacing.s8),
        Flexible(child: Text(texto, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: AppSpacing.s12),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: colorCirculo ?? color.withValues(alpha: 0.18), shape: BoxShape.circle),
          child: Icon(icono, size: 18, color: color),
        ),
      ],
    );
  }
}
