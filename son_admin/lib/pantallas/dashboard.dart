import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:son_admin/services/api.dart';
import 'package:son_admin/theme/tema.dart';
import 'package:son_admin/ui/componentes.dart';

const LatLng _centroPorDefecto = LatLng(-31.6643, -64.4282); // Alta Gracia, la base

const List<String> _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const List<String> _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String _dos(int n) => n.toString().padLeft(2, '0');

/// Panel de Control: resumen del día, mapa y actividad de los técnicos.
class PantallaDashboard extends StatefulWidget {
  final String nombreAdmin;

  /// Abre otra pantalla del panel (por ejemplo, 'ordenes' al tocar un indicador).
  final void Function(String id)? alIrA;
  const PantallaDashboard({super.key, this.nombreAdmin = '', this.alIrA});

  @override
  State<PantallaDashboard> createState() => _PantallaDashboardState();
}

class _PantallaDashboardState extends State<PantallaDashboard> {
  List<Map<String, dynamic>> _ordenes = [];
  List<Map<String, dynamic>> _tecnicos = [];
  bool _cargando = true;
  bool _sinConexion = false;
  Timer? _timer;
  final MapController _mapa = MapController();

  @override
  void initState() {
    super.initState();
    _cargar();
    // Posiciones de los técnicos y contadores de órdenes, cada 5 segundos.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _cargar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final resultados = await Future.wait([apiGet('/api/ordenes'), apiGet('/api/tecnicos')]);
      if (!mounted) return;
      if (resultados[0].statusCode == 200 && resultados[1].statusCode == 200) {
        setState(() {
          _ordenes = (json.decode(resultados[0].body) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _tecnicos = (json.decode(resultados[1].body) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _cargando = false;
          _sinConexion = false;
        });
      } else if (_cargando) {
        setState(() { _cargando = false; _sinConexion = true; });
      }
    } catch (_) {
      if (mounted) setState(() { _cargando = false; _sinConexion = true; });
    }
  }

  // --- Cálculos ---
  int _contar(String estado) => _ordenes.where((o) => o['estado'] == estado).length;

  String _fechaDe(Map<String, dynamic> orden) {
    final texto = (orden['fecha_ocurrencia'] ?? orden['fecha_asignada'] ?? '').toString();
    return texto.length >= 10 ? texto.substring(0, 10) : '';
  }

  String _hoy() {
    final ahora = DateTime.now();
    return '${ahora.year}-${_dos(ahora.month)}-${_dos(ahora.day)}';
  }

  LatLng? _posicion(Map<String, dynamic> tecnico) {
    final lat = double.tryParse('${tecnico['lat'] ?? ''}');
    final lng = double.tryParse('${tecnico['lng'] ?? ''}');
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  /// Minutos desde la última ubicación que mandó el técnico (null si nunca mandó).
  int? _minutosSinSenal(Map<String, dynamic> tecnico) {
    final texto = tecnico['ubicacion_en'];
    if (texto == null) return null;
    final fecha = DateTime.tryParse(texto.toString());
    if (fecha == null) return null;
    final minutos = DateTime.now().difference(fecha).inMinutes;
    return minutos < 0 ? 0 : minutos;
  }

  bool _enLinea(Map<String, dynamic> tecnico) {
    final minutos = _minutosSinSenal(tecnico);
    return minutos != null && minutos < 10;
  }

  String _textoSenal(Map<String, dynamic> tecnico) {
    final minutos = _minutosSinSenal(tecnico);
    if (_posicion(tecnico) == null || minutos == null) return 'Sin ubicación';
    if (minutos < 10) return 'En línea';
    if (minutos < 60) return 'Hace $minutos min';
    if (minutos < 60 * 24) return 'Hace ${minutos ~/ 60} h';
    return 'Hace ${minutos ~/ (60 * 24)} d';
  }

  int _ordenesActivasDe(Map<String, dynamic> tecnico) =>
      _ordenes.where((o) => o['tecnico_id'] == tecnico['id'] && o['estado'] != 'Completada').length;

  String _nombreTecnico(dynamic id) {
    for (final tecnico in _tecnicos) {
      if (tecnico['id'] == id) return (tecnico['nombre'] ?? 'Técnico').toString();
    }
    return 'Sin asignar';
  }

  Color _colorEstado(String? estado) {
    switch (estado) {
      case 'Pendiente': return sonAmbar;
      case 'En progreso': return sonAzul;
      case 'Completada': return sonLightGreen;
      default: return sonTextoSuave;
    }
  }

  // --- Pantalla ---
  @override
  Widget build(BuildContext context) {
    if (_cargando) return _esqueleto();
    if (_sinConexion && _ordenes.isEmpty && _tecnicos.isEmpty) {
      return EstadoError(
        mensaje: 'No se pudo conectar con el servidor.',
        alReintentar: () {
          setState(() => _cargando = true);
          _cargar();
        },
      );
    }

    return SingleChildScrollView(
      padding: AppSpacing.pagina,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Aparecer(child: _encabezado()),
          const SizedBox(height: AppSpacing.s24),
          Aparecer(orden: 2, child: _indicadores()),
          const SizedBox(height: AppSpacing.s24),
          LayoutBuilder(builder: (context, caja) {
            final ancho = caja.maxWidth;
            final izquierda = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_tarjetaMapa(), const SizedBox(height: 20), _tarjetaEstados()],
            );
            final derecha = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_tarjetaTecnicos(), const SizedBox(height: 20), _tarjetaOrdenesActivas()],
            );
            if (ancho >= 1060) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: izquierda),
                  const SizedBox(width: 20),
                  SizedBox(width: 380, child: derecha),
                ],
              );
            }
            return Column(children: [izquierda, const SizedBox(height: 20), derecha]);
          }),
        ],
      ),
    );
  }
  Widget _encabezado() {
    final ahora = DateTime.now();
    final fecha = '${_dias[ahora.weekday - 1]} ${ahora.day} de ${_meses[ahora.month - 1]}';
    final primerNombre = widget.nombreAdmin.trim().split(' ').first;

    final estado = _sinConexion ? _pildora('Sin conexión', sonAmbar, apagado: true) : _pildora('En vivo', sonExito);

    return LayoutBuilder(builder: (context, caja) {
      final textos = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(fecha, icono: Icons.calendar_today_rounded),
          const SizedBox(height: AppSpacing.s16),
          TituloContraste(
            normal: primerNombre.isEmpty ? 'Tu operación,' : 'Hola, $primerNombre.',
            destacado: primerNombre.isEmpty ? 'de un vistazo' : 'Así va tu operación',
            destacadoEnLineaNueva: true,
            tamano: caja.maxWidth < 640 ? 30 : 40,
          ),
        ],
      );
      if (caja.maxWidth < 640) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [textos, const SizedBox(height: 12), estado]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: textos), estado]);
    });
  }

  /// Carga: siluetas grises con la forma de la pantalla.
  Widget _esqueleto() {
    return const SingleChildScrollView(
      padding: AppSpacing.pagina,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(alto: 26, ancho: 160, radio: AppRadius.rPildora),
          SizedBox(height: AppSpacing.s16),
          Skeleton(alto: 40, ancho: 320),
          SizedBox(height: 10),
          Skeleton(alto: 40, ancho: 420),
          SizedBox(height: AppSpacing.s24),
          Skeleton(alto: 190, radio: AppRadius.rTarjetaGrande),
          SizedBox(height: AppSpacing.s24),
          Skeleton(alto: 420, radio: AppRadius.rTarjetaGrande),
        ],
      ),
    );
  }

  Widget _pildora(String texto, Color color, {bool apagado = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: apagado ? null : [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 8),
          Text(texto, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // --- Indicadores ---
  /// Bloque oscuro de alto contraste con los números grandes del día y el avance general.
  Widget _indicadores() {
    final pendientes = _contar('Pendiente');
    final enProgreso = _contar('En progreso');
    final completadas = _contar('Completada');
    final hoy = _hoy();
    final paraHoy = _ordenes.where((o) => _fechaDe(o) == hoy).toList();
    final hoyCompletadas = paraHoy.where((o) => o['estado'] == 'Completada').length;
    final enLinea = _tecnicos.where((t) => _posicion(t) != null && _enLinea(t)).length;
    final total = _ordenes.length;
    final avance = total == 0 ? 0.0 : completadas / total;
    final irOrdenes = widget.alIrA == null ? null : () => widget.alIrA!('ordenes');
    final irTecnicos = widget.alIrA == null ? null : () => widget.alIrA!('tecnicos');

    const blanco = AppColors.superficie;
    const tenue = AppColors.oscuroTextoSecundario;
    const linea = AppColors.oscuroBorde;
    final kpis = <Widget>[
      KpiBloque(valor: '${pendientes + enProgreso}', etiqueta: 'Órdenes activas', colorValor: blanco, colorEtiqueta: tenue, tamano: 40, alTocar: irOrdenes),
      KpiBloque(valor: '$enProgreso', etiqueta: 'En curso ahora', colorValor: AppColors.acento, colorEtiqueta: tenue, tamano: 40, alTocar: irOrdenes),
      KpiBloque(valor: '$hoyCompletadas/${paraHoy.length}', etiqueta: 'Visitas de hoy', colorValor: blanco, colorEtiqueta: tenue, tamano: 40, alTocar: irOrdenes),
      KpiBloque(valor: '$enLinea/${_tecnicos.length}', etiqueta: 'Técnicos en línea', colorValor: blanco, colorEtiqueta: tenue, tamano: 40, alTocar: irTecnicos),
    ];

    return BloqueContraste(
      child: LayoutBuilder(builder: (context, caja) {
        final ancho = caja.maxWidth;
        final Widget fila = ancho >= 760
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < kpis.length; i++) ...[
                    if (i > 0) Container(width: 1, height: 64, margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s24), color: linea),
                    Expanded(child: Aparecer(orden: 3 + i, child: kpis[i])),
                  ],
                ],
              )
            : Wrap(
                spacing: AppSpacing.s32,
                runSpacing: AppSpacing.s24,
                children: [
                  for (var i = 0; i < kpis.length; i++)
                    SizedBox(width: (ancho - AppSpacing.s32) / 2, child: Aparecer(orden: 3 + i, child: kpis[i])),
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            fila,
            const SizedBox(height: AppSpacing.s32),
            Row(
              children: [
                Text('Completadas', style: AppTypography.kpiEtiqueta(tenue)),
                const Spacer(),
                Text('$completadas de $total · ${(avance * 100).round()}%',
                    style: AppTypography.kpiEtiqueta(blanco).copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: AppRadius.rPildora,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: avance),
                duration: const Duration(milliseconds: 900),
                curve: AppMotion.curva,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  backgroundColor: linea,
                  color: AppColors.oro,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  // --- Mapa ---
  Widget _tarjetaMapa() {
    final conPosicion = _tecnicos.where((t) => _posicion(t) != null).toList();
    // Si hay varios técnicos, el mapa arranca encuadrando a todos; con uno solo, centrado en él.
    final puntos = [for (final t in conPosicion) _posicion(t)!];
    final centro = puntos.length == 1 ? puntos.first : _centroPorDefecto;
    final encuadre = puntos.length >= 2
        ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(puntos), padding: const EdgeInsets.all(70), maxZoom: 15)
        : null;

    return Container(
      height: 520,
      decoration: decoracionTarjeta(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Row(
              children: [
                Icon(Icons.map_outlined, color: sonLightGreen, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Mapa', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: sonTexto)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapa,
                  options: MapOptions(
                    initialCenter: centro,
                    initialZoom: puntos.isEmpty ? 13 : (puntos.length == 1 ? 15 : 12),
                    initialCameraFit: encuadre,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.son.admin',
                    ),
                    MarkerLayer(
                      markers: [
                        for (final tecnico in conPosicion)
                          Marker(point: _posicion(tecnico)!, width: 140, height: 90, child: _marcador(tecnico)),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  right: 8,
                  bottom: 6,
                  child: Text('© OpenStreetMap', style: TextStyle(color: sonTextoSuave, fontSize: 10)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _marcador(Map<String, dynamic> tecnico) {
    final enLinea = _enLinea(tecnico);
    final color = enLinea ? sonLightGreen : sonTextoSuave;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          bottom: 90 - 30, // el cartel queda justo arriba del punto (que está en el centro del marcador)
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            constraints: const BoxConstraints(maxWidth: 140),
            decoration: BoxDecoration(
              color: sonFondo.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.7)),
            ),
            child: Text(
              (tecnico['nombre'] ?? 'Técnico').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: sonTexto, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Positioned(
          top: 36,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: sonFondo, width: 3),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: enLinea ? 14 : 4, spreadRadius: enLinea ? 2 : 0)],
            ),
          ),
        ),
      ],
    );
  }

  // --- Columna lateral ---
  Widget _tituloTarjeta(String texto, {Widget? derecha}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(child: Text(texto, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: sonTexto))),
          if (derecha != null) derecha,
        ],
      ),
    );
  }

  Widget _tarjetaEstados() {
    final datos = [
      ('Pendientes', _contar('Pendiente'), sonAmbar),
      ('En progreso', _contar('En progreso'), sonAzul),
      ('Completadas', _contar('Completada'), sonLightGreen),
    ];
    final total = datos.fold<int>(0, (suma, d) => suma + d.$2);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: decoracionTarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloTarjeta('Estado de las órdenes', derecha: Text('$total en total', style: TextStyle(color: sonTextoSuave, fontSize: 12))),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 12,
              child: total == 0
                  ? Container(color: sonTarjetaAlta)
                  : Row(
                      children: [
                        for (final d in datos)
                          if (d.$2 > 0) Expanded(flex: d.$2, child: Container(margin: const EdgeInsets.only(right: 2), color: d.$3)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          for (final d in datos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: d.$3, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(d.$1, style: TextStyle(color: sonTexto, fontSize: 14))),
                  Text('${d.$2}', style: TextStyle(color: sonTexto, fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tarjetaTecnicos() {
    final lista = [..._tecnicos]
      ..sort((a, b) {
        final ea = _enLinea(a) ? 0 : 1;
        final eb = _enLinea(b) ? 0 : 1;
        return ea != eb ? ea - eb : '${a['nombre']}'.compareTo('${b['nombre']}');
      });

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: decoracionTarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloTarjeta('Técnicos en campo', derecha: Text('${_tecnicos.length}', style: TextStyle(color: sonTextoSuave, fontSize: 12))),
          if (lista.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Todavía no hay técnicos registrados.', style: TextStyle(color: sonTextoSuave, fontSize: 13)),
            ),
          for (final tecnico in lista.take(6)) _filaTecnico(tecnico),
          if (lista.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('y ${lista.length - 6} más en la sección Técnicos', style: TextStyle(color: sonTextoSuave, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _filaTecnico(Map<String, dynamic> tecnico) {
    final nombre = (tecnico['nombre'] ?? 'Sin nombre').toString();
    final enLinea = _enLinea(tecnico);
    final posicion = _posicion(tecnico);
    final activas = _ordenesActivasDe(tecnico);
    final detalle = '${_textoSenal(tecnico)}${activas > 0 ? ' · $activas orden${activas == 1 ? '' : 'es'} activa${activas == 1 ? '' : 's'}' : ''}';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: posicion == null ? null : () => _mapa.move(posicion, 15),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: sonTarjetaAlta,
                  child: Text(nombre.isEmpty ? '?' : nombre[0].toUpperCase(), style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold)),
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: enLinea ? sonLightGreen : sonTextoSuave,
                      shape: BoxShape.circle,
                      border: Border.all(color: sonTarjeta, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(detalle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: enLinea ? sonLightGreen : sonTextoSuave, fontSize: 12)),
                ],
              ),
            ),
            if (posicion != null) Icon(Icons.my_location, size: 16, color: sonTextoSuave),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaOrdenesActivas() {
    final activas = _ordenes.where((o) => o['estado'] != 'Completada').toList();
    activas.sort((a, b) {
      // Primero las que están en curso.
      final ea = a['estado'] == 'En progreso' ? 0 : 1;
      final eb = b['estado'] == 'En progreso' ? 0 : 1;
      return ea != eb ? ea - eb : (b['id'] as num).compareTo(a['id'] as num);
    });

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: decoracionTarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloTarjeta('Órdenes activas', derecha: Text('${activas.length}', style: TextStyle(color: sonTextoSuave, fontSize: 12))),
          if (activas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No hay órdenes pendientes ni en curso.', style: TextStyle(color: sonTextoSuave, fontSize: 13)),
            ),
          for (final orden in activas.take(5)) _filaOrden(orden),
          if (activas.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('y ${activas.length - 5} más en Órdenes de Trabajo', style: TextStyle(color: sonTextoSuave, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _filaOrden(Map<String, dynamic> orden) {
    final estado = (orden['estado'] ?? '').toString();
    final color = _colorEstado(estado);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Row(
        children: [
          Container(width: 4, height: 34, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (orden['cliente'] ?? 'Cliente sin nombre').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  _nombreTecnico(orden['tecnico_id']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: sonTextoSuave, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Text(estado, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
