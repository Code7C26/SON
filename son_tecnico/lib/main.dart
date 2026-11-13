import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:son_tecnico/config/api_config.dart';
import 'package:son_tecnico/pantallas/formularios.dart';
import 'package:son_tecnico/pantallas/operacion.dart';
import 'package:son_tecnico/pantallas/para_presupuestar.dart';
import 'package:son_tecnico/services/api.dart';
import 'package:son_tecnico/services/almacen.dart';
import 'package:son_tecnico/services/sesion.dart';
import 'package:son_tecnico/services/sincronizacion.dart';
import 'package:son_tecnico/theme/colores.dart';
import 'package:son_tecnico/ui/componentes.dart';

export 'package:son_tecnico/theme/colores.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Si el técnico ya había ingresado antes, entra directo (aunque no haya internet)
  // y, si dejó un trabajo a medias, lo retoma donde estaba.
  final tema = await Almacen.leer('tema.json');
  if (tema == 'oscuro') controlTema.establecer(false, avisar: false);
  controlTema.alGuardar = (claro) => Almacen.escribir('tema.json', claro ? 'claro' : 'oscuro');

  Widget inicio = const PantallaLogin();
  if (await Sesion.restaurar()) {
    final id = Sesion.tecnicoId!;
    final borrador = await Borrador.leer(id);
    if (borrador != null && borrador['orden'] is Map) {
      inicio = PantallaTrabajoProgreso(
        orden: Map<String, dynamic>.from(borrador['orden'] as Map),
        latitud: (borrador['latitud'] as num).toDouble(),
        longitud: (borrador['longitud'] as num).toDouble(),
        tecnicoId: id,
        nombreTecnico: Sesion.nombre,
        emailTecnico: Sesion.email,
        borrador: borrador,
      );
    } else {
      inicio = PantallaPrincipal(tecnicoId: id, nombre: Sesion.nombre, email: Sesion.email);
    }
  }
  runApp(SonApp(inicio: inicio));
}

class SonApp extends StatelessWidget {
  final Widget inicio;
  const SonApp({super.key, this.inicio = const PantallaLogin()});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controlTema,
      builder: (context, _) => MaterialApp(
        title: 'SON',
        debugShowCheckedModeBanner: false,
        theme: temaCon(paletaClara, Brightness.light),
        darkTheme: temaCon(paletaOscura, Brightness.dark),
        themeMode: controlTema.modo,
        builder: (context, child) => RepintadoTema(child: child ?? const SizedBox.shrink()),
        home: inicio,
      ),
    );
  }
}

// ---------------------------------------------------
// PANTALLA 1: LOGIN 
// ---------------------------------------------------
class PantallaLogin extends StatefulWidget {
  const PantallaLogin({super.key});

  @override
  State<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends State<PantallaLogin> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _cargando = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    setState(() => _cargando = true);

    try {
      final respuesta = await apiPost(
        '/api/tecnicos/login',
        json.encode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
        }),
      );

      if (respuesta.statusCode == 200) {
        final datosTecnico = json.decode(respuesta.body);
        if (!mounted) return;
        Sesion.iniciar(
          nuevoToken: datosTecnico['token'],
          id: (datosTecnico['id'] as num).toInt(),
          nuevoNombre: datosTecnico['nombre'] ?? 'Técnico',
          nuevoEmail: datosTecnico['email'] ?? '',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('¡Bienvenido, ${datosTecnico['nombre']}!'), backgroundColor: sonTarjetaAlta)
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PantallaPrincipal(
              tecnicoId: (datosTecnico['id'] as num).toInt(),
              nombre: datosTecnico['nombre'] ?? 'Técnico',
              email: datosTecnico['email'] ?? '',
            ),
          ),
        );
      } else {
        final cuerpo = json.decode(respuesta.body);
        final texto = cuerpo is Map && cuerpo['error'] is String ? '${cuerpo['error']}' : 'Credenciales incorrectas';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(texto), backgroundColor: sonRojo)
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sin conexión. La primera vez necesitás internet.'), backgroundColor: sonRojo)
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FondoOrbes(
        child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: AppSpacing.paginaMovil,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Aparecer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          padding: const EdgeInsets.all(14),
                          decoration: const BoxDecoration(color: AppColors.tinta, shape: BoxShape.circle),
                          child: Image.asset('assets/images/logo_son_icono.png', errorBuilder: (c, e, st) => const Icon(Icons.hourglass_bottom, color: AppColors.acento)),
                        ),
                        const SizedBox(height: AppSpacing.s32),
                        const Eyebrow('App de campo'),
                        const SizedBox(height: AppSpacing.s16),
                        const TituloContraste(normal: 'Ingresá a', destacado: 'tu jornada', tamano: 34),
                        const SizedBox(height: AppSpacing.s32),
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline_rounded)),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'Contraseña', prefixIcon: Icon(Icons.lock_outline_rounded)),
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _cargando ? null : _iniciarSesion(),
                        ),
                        const SizedBox(height: AppSpacing.s24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.only(left: AppSpacing.s24, right: AppSpacing.s12)),
                            onPressed: _cargando ? null : _iniciarSesion,
                            child: _cargando
                                ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: sonSobreAcento))
                                : const EtiquetaConFlecha('Ingresar'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(top: AppSpacing.s8, right: AppSpacing.s8, child: BotonTema()),
          ],
        ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------
// CONTENEDOR PRINCIPAL
// ---------------------------------------------------
class PantallaPrincipal extends StatefulWidget {
  final int tecnicoId;
  final String nombre;
  final String email;

  const PantallaPrincipal({
    super.key,
    required this.tecnicoId,
    required this.nombre,
    required this.email,
  });

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  int _indiceActual = 0;

  @override
  void initState() {
    super.initState();
    Sincronizador.iniciar();
    Sincronizador.estado.addListener(_siVencioLaSesion);
  }

  @override
  void dispose() {
    Sincronizador.estado.removeListener(_siVencioLaSesion);
    super.dispose();
  }

  void _siVencioLaSesion() {
    if (!Sincronizador.estado.value.sinSesion || !mounted) return;
    Sincronizador.estado.removeListener(_siVencioLaSesion);
    Sincronizador.detener();
    Sesion.cerrar();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PantallaLogin()));
  }

  @override
  Widget build(BuildContext context) {
    final pantallas = [
      TabDashboard(
        tecnicoId: widget.tecnicoId,
        nombreTecnico: widget.nombre,
        emailTecnico: widget.email,
        alIrAOrdenes: () => setState(() => _indiceActual = 1),
      ),
      TabOrdenes(
        tecnicoId: widget.tecnicoId,
        nombreTecnico: widget.nombre,
        emailTecnico: widget.email,
      ),
      TabMasPlaceholder(nombre: widget.nombre, email: widget.email),
    ];

    return Scaffold(
      extendBody: true,
      body: FondoOrbes(
        intensidad: 0.6,
        child: AnimatedSwitcher(
        duration: AppMotion.media,
        switchInCurve: AppMotion.curva,
        layoutBuilder: (actual, _) => actual ?? const SizedBox.shrink(),
        transitionBuilder: (hijo, animacion) => FadeTransition(
          opacity: animacion,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(animacion), child: hijo),
        ),
        child: KeyedSubtree(key: ValueKey(_indiceActual), child: pantallas[_indiceActual]),
      ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.s16, 0, AppSpacing.s16, AppSpacing.s12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BannerSincronizacion(),
              BarraPildora(
                indice: _indiceActual,
                alElegir: (index) => setState(() => _indiceActual = index),
                destinos: const [
                  (Icons.home_rounded, 'Inicio'),
                  (Icons.assignment_rounded, 'Órdenes'),
                  (Icons.more_horiz_rounded, 'Más'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra inferior flotante en forma de píldora. El destino activo se marca con un bloque
/// oscuro que muestra su nombre; los demás quedan como ícono (áreas táctiles de 56dp).
class BarraPildora extends StatelessWidget {
  final int indice;
  final ValueChanged<int> alElegir;
  final List<(IconData, String)> destinos;
  const BarraPildora({super.key, required this.indice, required this.alElegir, required this.destinos});

  @override
  Widget build(BuildContext context) {
    final oscuro = !controlTema.claro;
    final fondoActivo = oscuro ? AppColors.canvas : AppColors.tinta;
    final textoActivo = oscuro ? AppColors.tinta : AppColors.superficie;
    return PanelVidrio(
      radio: AppRadius.rPildora,
      child: Container(
      height: 68,
      padding: const EdgeInsets.all(6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < destinos.length; i++)
            Expanded(
              flex: i == indice ? 3 : 2,
              child: Semantics(
                button: true,
                selected: i == indice,
                label: destinos[i].$2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => alElegir(i),
                  child: AnimatedContainer(
                    duration: AppMotion.media,
                    curve: AppMotion.curva,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i == indice ? fondoActivo : Colors.transparent,
                      borderRadius: AppRadius.rPildora,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(destinos[i].$1, size: 22, color: i == indice ? textoActivo : sonTextoSuave),
                        AnimatedSize(
                          duration: AppMotion.media,
                          curve: AppMotion.curva,
                          child: i == indice
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(destinos[i].$2, maxLines: 1, style: TextStyle(color: textoActivo, fontWeight: FontWeight.w600, fontSize: 14)),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

/// Aviso flotante sobre la barra inferior: envíos guardados en el celular o rechazados.
/// Píldora oscura con un punto de color según el estado; tocándola se reintenta.
class BannerSincronizacion extends StatelessWidget {
  const BannerSincronizacion({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EstadoSync>(
      valueListenable: Sincronizador.estado,
      builder: (context, estado, _) {
        Widget contenido = const SizedBox(width: double.infinity);
        if (estado.pendientes > 0 || estado.fallidos > 0 || estado.sinSesion) {
          String texto;
          Color punto = sonAmbar;
          if (estado.sinSesion) {
            texto = 'Sesión vencida · ingresá de nuevo con internet';
            punto = sonRojo;
          } else if (estado.pendientes > 0) {
            final cantidad = estado.pendientes == 1 ? '1 envío' : '${estado.pendientes} envíos';
            texto = estado.sincronizando
                ? 'Enviando $cantidad...'
                : '$cantidad en el celular${estado.sinConexion ? ' · sin señal' : ''}';
          } else {
            texto = '${estado.fallidos} envío(s) rechazados · avisá a la oficina';
            punto = sonRojo;
          }
          contenido = Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: Material(
              color: AppColors.tinta,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: Sincronizador.sincronizar,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        estado.sincronizando
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.superficie))
                            : Container(width: 10, height: 10, decoration: BoxDecoration(color: punto, shape: BoxShape.circle)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(texto, style: const TextStyle(color: AppColors.superficie, fontSize: 14, fontWeight: FontWeight.w500))),
                        if (estado.pendientes > 0 && !estado.sincronizando)
                          const Icon(Icons.refresh_rounded, color: AppColors.superficie, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return AnimatedSize(duration: AppMotion.media, curve: AppMotion.curva, child: contenido);
      },
    );
  }
}

// ---------------------------------------------------
// 1. TAB DASHBOARD
// ---------------------------------------------------
class TabDashboard extends StatefulWidget {
  final int tecnicoId;
  final String nombreTecnico;
  final String emailTecnico;

  /// Abre la pestaña Órdenes (al tocar un indicador).
  final VoidCallback? alIrAOrdenes;

  const TabDashboard({
    super.key,
    required this.tecnicoId,
    required this.nombreTecnico,
    required this.emailTecnico,
    this.alIrAOrdenes,
  });

  @override
  State<TabDashboard> createState() => _TabDashboardState();
}

class _TabDashboardState extends State<TabDashboard> {
  List<Map<String, dynamic>> _ordenes = [];
  bool _cargando = true;
  bool _sinConexion = false;
  Timer? _ubicacion;
  Timer? _reintento;

  @override
  void initState() {
    super.initState();
    _mostrarGuardadas();
    _cargar();
    Sincronizador.version.addListener(_cargar);
    _ubicacion = Timer.periodic(const Duration(seconds: 20), (_) => enviarUbicacion());
    // Mientras se muestran datos guardados, se vuelve a intentar sola: apenas hay internet
    // se actualiza la lista y desaparece el aviso de "Sin conexión".
    _reintento = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_sinConexion) _cargar();
    });
  }

  Future<void> _mostrarGuardadas() async {
    final guardadas = await ordenesGuardadas(widget.tecnicoId);
    if (!mounted || guardadas == null || !_cargando) return;
    setState(() {
      _ordenes = guardadas;
      _cargando = false;
    });
  }

  @override
  void dispose() {
    Sincronizador.version.removeListener(_cargar);
    _ubicacion?.cancel();
    _reintento?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    final resultado = await cargarOrdenes(widget.tecnicoId);
    if (!mounted) return;
    setState(() {
      _ordenes = resultado.ordenes;
      _sinConexion = resultado.sinConexion;
      _cargando = false;
    });
  }

  void _abrirOrden(Map<String, dynamic> orden) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PantallaDetalle(
          orden: orden,
          tecnicoId: widget.tecnicoId,
          nombreTecnico: widget.nombreTecnico,
          emailTecnico: widget.emailTecnico,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const SafeArea(
        child: Padding(
          padding: AppSpacing.paginaMovil,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(alto: 24, ancho: 140, radio: AppRadius.rPildora),
              SizedBox(height: AppSpacing.s16),
              Skeleton(alto: 34, ancho: 220),
              SizedBox(height: 8),
              Skeleton(alto: 34, ancho: 260),
              SizedBox(height: AppSpacing.s24),
              Skeleton(alto: 210, radio: AppRadius.rTarjetaGrande),
              SizedBox(height: AppSpacing.s24),
              Skeleton(alto: 88, radio: AppRadius.rTarjeta),
              SizedBox(height: AppSpacing.s12),
              Skeleton(alto: 88, radio: AppRadius.rTarjeta),
            ],
          ),
        ),
      );
    }

    final total = _ordenes.length;
    final enProgreso = _ordenes.where((o) => o['estado'] == 'En progreso').length;
    final completadas = _ordenes.where((o) => o['estado'] == 'Completada').length;
    final pendientes = _ordenes.where((o) => o['estado'] == 'Pendiente').length;
    final activas = _ordenes.where((o) => o['estado'] != 'Completada').toList();
    final primerNombre = widget.nombreTecnico.trim().split(' ').first;
    const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    final ahora = DateTime.now();
    final fecha = '${dias[ahora.weekday - 1]} ${ahora.day} de ${meses[ahora.month - 1]}';
    const tenue = AppColors.oscuroTextoSecundario;
    const blanco = AppColors.superficie;

    Widget kpi(int orden, String valor, String etiqueta, Color color) => Aparecer(
          orden: orden,
          child: KpiBloque(valor: valor, etiqueta: etiqueta, colorValor: color, colorEtiqueta: tenue, tamano: 36, alTocar: widget.alIrAOrdenes),
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          color: sonLightGreen,
          onRefresh: _cargar,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.paginaMovil,
            children: [
              Aparecer(
                child: Row(
                  children: [
                    _sinConexion ? const Eyebrow('Sin señal', icono: Icons.cloud_off_rounded) : Eyebrow(fecha, icono: Icons.calendar_today_rounded),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              Aparecer(
                orden: 1,
                child: TituloContraste(
                  normal: primerNombre.isEmpty ? 'Hola.' : 'Hola, $primerNombre.',
                  destacado: 'Tu jornada de hoy',
                  destacadoEnLineaNueva: true,
                  tamano: 30,
                ),
              ),
              const SizedBox(height: AppSpacing.s24),
              Aparecer(
                orden: 2,
                child: BloqueContraste(
                  padding: const EdgeInsets.all(AppSpacing.s24),
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(child: kpi(3, '$total', 'Asignadas', blanco)),
                        Expanded(child: kpi(4, '$enProgreso', 'En curso', AppColors.acento)),
                      ]),
                      const SizedBox(height: AppSpacing.s24),
                      Row(children: [
                        Expanded(child: kpi(5, '$pendientes', 'Pendientes', AppColors.oro)),
                        Expanded(child: kpi(6, '$completadas', 'Completadas', blanco)),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s32),
              Text('Próximas', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.s12),
              if (activas.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.s16),
                  child: EstadoVacio(icono: Icons.task_alt_rounded, mensaje: 'No tenés órdenes pendientes.'),
                )
              else
                for (var i = 0; i < activas.length; i++)
                  Aparecer(orden: 3 + (i < 6 ? i : 6), child: _tarjetaOrdenMini(activas[i])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaOrdenMini(Map<String, dynamic> orden) {
    final hora = [orden['fecha'], rangoHorario(orden)].where((parte) => parte != null && '$parte'.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: TarjetaOrdenSon(
        cliente: '${orden['cliente'] ?? ''}',
        direccion: '${orden['direccion'] ?? ''}',
        hora: hora,
        estado: '${orden['estado'] ?? ''}',
        alTocar: () => _abrirOrden(orden),
      ),
    );
  }
}

/// Tarjeta de orden para la app: cliente, dirección, horario y estado; toda la tarjeta es tocable.
/// [accion] es un botón redondo opcional (por ejemplo "Ir con Google Maps").
class TarjetaOrdenSon extends StatelessWidget {
  final String cliente;
  final String direccion;
  final String hora;
  final String estado;
  final int? parada;
  final VoidCallback alTocar;
  final Widget? accion;
  const TarjetaOrdenSon({
    super.key,
    required this.cliente,
    required this.direccion,
    required this.hora,
    required this.estado,
    required this.alTocar,
    this.parada,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    final colores = coloresEstado(estado);
    return Material(
      color: sonTarjeta,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.rTarjeta, side: BorderSide(color: sonBorde)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: alTocar,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s16, AppSpacing.s12, AppSpacing.s16),
            child: Row(
              children: [
                if (parada != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.tinta, shape: BoxShape.circle),
                    child: Text('$parada', style: const TextStyle(color: AppColors.superficie, fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: colores.$1, borderRadius: AppRadius.rPildora),
                            child: Text(estado, style: TextStyle(color: colores.$2, fontWeight: FontWeight.w600, fontSize: 12)),
                          ),
                          if (hora.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(child: Text(hora, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTextoSuave, fontSize: 13))),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(cliente, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: AppTypography.display, fontWeight: FontWeight.w700, fontSize: 17, color: sonTexto, letterSpacing: -0.3)),
                      if (direccion.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(direccion, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTextoSuave, fontSize: 14)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Micro-círculo integrado: indica que toda la tarjeta abre la orden.
                accion ?? const ExcludeSemantics(child: IconoCircular(Icons.arrow_forward_rounded, tamano: 40)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------
// 2. TAB ÓRDENES
// ---------------------------------------------------
/// Dónde está el técnico ahora (null si no hay GPS o no dio permiso).
Future<Position?> posicionActual() async {
  try {
    final servicio = await Geolocator.isLocationServiceEnabled();
    if (!servicio) return null;
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) return null;
    try {
      return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
    } on TimeoutException {
      return await Geolocator.getLastKnownPosition();
    }
  } catch (_) {
    return null;
  }
}

Future<void> enviarUbicacion() async {
  try {
    final posicion = await posicionActual();
    if (posicion == null) return;
    await apiPost('/api/tecnicos/ubicacion', json.encode({'lat': posicion.latitude, 'lng': posicion.longitude}));
  } catch (_) {}
}

/// Ordena las visitas de hoy por cercanía desde donde está parado el técnico (no desde la oficina:
/// cada uno sale de un lugar distinto). Devuelve true si el servidor las reordenó.
Future<bool> ordenarDesdeDondeEstoy() async {
  final posicion = await posicionActual();
  if (posicion == null) return false;
  try {
    final respuesta = await apiPost(
      '/api/ordenes/recorrido',
      json.encode({'lat': posicion.latitude, 'lng': posicion.longitude}),
      espera: const Duration(minutes: 1),
    );
    return respuesta.statusCode == 200;
  } catch (_) {
    return false;
  }
}

class TabOrdenes extends StatefulWidget {
  final int tecnicoId;
  final String nombreTecnico;
  final String emailTecnico;

  const TabOrdenes({
    super.key,
    required this.tecnicoId,
    required this.nombreTecnico,
    required this.emailTecnico,
  });

  @override
  State<TabOrdenes> createState() => _TabOrdenesState();
}

class _TabOrdenesState extends State<TabOrdenes> {
  List<Map<String, dynamic>> _ordenes = [];
  bool _cargando = true;
  bool _sinConexion = false;
  bool _ordenando = false;
  Timer? _reintento;

  // Se reordena desde la ubicación como mucho cada 10 minutos (cada vez se consulta el mapa).
  static DateTime? _ultimoOrden;

  @override
  void initState() {
    super.initState();
    _mostrarGuardadas();
    _cargar();
    final ultimo = _ultimoOrden;
    if (ultimo == null || DateTime.now().difference(ultimo) > const Duration(minutes: 10)) {
      _ordenarYRecargar();
    }
    Sincronizador.version.addListener(_cargar);
    _reintento = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_sinConexion) _cargar();
    });
  }

  @override
  void dispose() {
    Sincronizador.version.removeListener(_cargar);
    _reintento?.cancel();
    super.dispose();
  }

  Future<void> _mostrarGuardadas() async {
    final guardadas = await ordenesGuardadas(widget.tecnicoId);
    if (!mounted || guardadas == null || !_cargando) return;
    setState(() {
      _ordenes = guardadas;
      _cargando = false;
    });
  }

  Future<void> _cargar() async {
    final resultado = await cargarOrdenes(widget.tecnicoId);
    if (!mounted) return;
    setState(() {
      _ordenes = resultado.ordenes;
      _sinConexion = resultado.sinConexion;
      _cargando = false;
    });
  }

  Future<bool> _ordenarYRecargar() async {
    if (_ordenando) return false;
    if (mounted) setState(() => _ordenando = true);
    final ok = await ordenarDesdeDondeEstoy();
    if (ok) {
      _ultimoOrden = DateTime.now();
      await _cargar();
    }
    if (mounted) setState(() => _ordenando = false);
    return ok;
  }

  /// Ordena desde donde está y abre Google Maps con las paradas de hoy en ese orden.
  Future<void> _recorridoDeHoy() async {
    final ok = await _ordenarYRecargar();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin GPS o sin señal: se usa el orden que había.')));
    }
    final deHoy = _ordenes
        .where((orden) => orden['fecha_iso'] == _hoyIso() && orden['estado'] != 'Completada' && orden['estado'] != 'Por asignar' && '${orden['direccion'] ?? ''}'.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => ((a['orden_ruta'] as num?)?.toInt() ?? 999).compareTo((b['orden_ruta'] as num?)?.toInt() ?? 999));
    await abrirRecorrida(deHoy);
  }

  Widget _lista(List<Map<String, dynamic>> ordenes, String vacio, BuildContext context, {bool recorrida = false}) {
    final deHoy = ordenes.where((orden) => orden['fecha_iso'] == _hoyIso() && orden['estado'] != 'Por asignar' && '${orden['direccion'] ?? ''}'.trim().isNotEmpty).toList();
    return RefreshIndicator(
      color: sonLightGreen,
      onRefresh: _cargar,
      child: ordenes.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: 320, child: EstadoVacio(icono: Icons.assignment_outlined, mensaje: vacio)),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s16, AppSpacing.s16, 96),
              children: [
                if (recorrida && deHoy.length >= 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _ordenando ? null : _recorridoDeHoy,
                        icon: _ordenando
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.superficie))
                            : const Icon(Icons.route_rounded),
                        label: Text(_ordenando ? 'Ordenando...' : 'Recorrido de hoy'),
                      ),
                    ),
                  ),
                ...ordenes.map((orden) => _construirTarjetaClicable(context, orden)),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asignadas = _ordenes.where((o) => o['estado'] != 'Completada').toList()
      ..sort((a, b) {
        final porDia = '${a['fecha_iso'] ?? ''}'.compareTo('${b['fecha_iso'] ?? ''}');
        if (porDia != 0) return porDia;
        final pa = (a['orden_ruta'] as num?)?.toInt() ?? 999;
        final pb = (b['orden_ruta'] as num?)?.toInt() ?? 999;
        return pa.compareTo(pb);
      });
    final completadas = _ordenes.where((o) => o['estado'] == 'Completada').toList();

    if (_cargando) {
      return const SafeArea(
        child: Padding(
          padding: AppSpacing.paginaMovil,
          child: Column(children: [
            Skeleton(alto: 34, ancho: 200),
            SizedBox(height: AppSpacing.s24),
            Skeleton(alto: 88, radio: AppRadius.rTarjetaGrande),
            SizedBox(height: AppSpacing.s12),
            Skeleton(alto: 88, radio: AppRadius.rTarjetaGrande),
            SizedBox(height: AppSpacing.s12),
            Skeleton(alto: 88, radio: AppRadius.rTarjetaGrande),
          ]),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          toolbarHeight: 72,
          title: const TituloContraste(normal: 'Mis', destacado: 'órdenes', tamano: 28),
          bottom: const TabBar(
            indicatorWeight: 3,
            tabs: [Tab(text: 'Asignadas'), Tab(text: 'Completadas'), Tab(text: 'Todas')],
          ),
        ),
        body: TabBarView(
          children: [
            _lista(asignadas, 'No hay órdenes asignadas', context, recorrida: true),
            _lista(completadas, 'No hay órdenes completadas aún', context),
            _lista(_ordenes, 'No hay órdenes', context),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add_rounded),
          label: const Text('Pedir visita'),
          onPressed: _pedirVisita,
        ),
      ),
    );
  }

  Future<void> _pedirVisita() async {
    final cliente = TextEditingController();
    final direccion = TextEditingController();
    final descripcion = TextEditingController();
    DateTime fecha = DateTime.now();
    final enviada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, actualizar) => Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.s24, 0, AppSpacing.s24, AppSpacing.s24 + MediaQuery.of(contexto).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TituloContraste(normal: 'Pedir', destacado: 'visita', tamano: 26),
                const SizedBox(height: AppSpacing.s24),
                TextField(controller: cliente, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Cliente')),
                const SizedBox(height: AppSpacing.s12),
                TextField(controller: direccion, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Dirección')),
                const SizedBox(height: AppSpacing.s12),
                TextField(controller: descripcion, maxLines: 3, decoration: const InputDecoration(labelText: 'Qué hay que hacer')),
                const SizedBox(height: AppSpacing.s12),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final elegida = await showDatePicker(context: contexto, initialDate: fecha, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 400)));
                      if (elegida != null) actualizar(() => fecha = elegida);
                    },
                    icon: const Icon(Icons.event_outlined),
                    label: Text('${fecha.day}/${fecha.month}/${fecha.year}'),
                  ),
                ),
                const SizedBox(height: AppSpacing.s24),
                SizedBox(height: 56, child: ElevatedButton(onPressed: () => Navigator.pop(contexto, true), child: const Text('Pedir'))),
              ],
            ),
          ),
        ),
      ),
    );
    if (enviada == true) {
      try {
        final marca = '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';
        final respuesta = await apiPost('/api/ordenes/pedir', json.encode({
          'nombre_cliente': cliente.text,
          'direccion': direccion.text,
          'descripcion': descripcion.text,
          'fecha': marca,
        }));
        if (!mounted) return;
        if (respuesta.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pedido enviado. Lo van a asignar desde el panel.')));
          _cargar();
        } else {
          final cuerpo = json.decode(respuesta.body);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${cuerpo is Map ? cuerpo['error'] ?? 'No se pudo pedir' : 'No se pudo pedir'}')));
        }
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin conexión. Probá de nuevo cuando haya señal.')));
      }
    }
    cliente.dispose();
    direccion.dispose();
    descripcion.dispose();
  }

  Widget _construirTarjetaClicable(BuildContext context, Map orden) {
    final hora = [orden['fecha'], rangoHorario(orden)].where((parte) => parte != null && '$parte'.isNotEmpty).join(' · ');
    final puedeIr = orden['estado'] != 'Completada' && orden['estado'] != 'Por asignar' && '${orden['direccion'] ?? ''}'.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: TarjetaOrdenSon(
        cliente: '${orden['cliente'] ?? ''}',
        direccion: '${orden['direccion'] ?? ''}',
        hora: hora,
        estado: '${orden['estado'] ?? ''}',
        parada: (orden['orden_ruta'] as num?)?.toInt(),
        alTocar: () {
          if (orden['estado'] == 'Completada') {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Orden completada · el informe ya se generó')));
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PantallaDetalle(
                orden: orden,
                tecnicoId: widget.tecnicoId,
                nombreTecnico: widget.nombreTecnico,
                emailTecnico: widget.emailTecnico,
              ),
            ),
          );
        },
        accion: puedeIr
            ? IconButton.filled(
                tooltip: 'Ir con Google Maps',
                constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                style: IconButton.styleFrom(backgroundColor: AppColors.acento, foregroundColor: AppColors.sobreAcento),
                onPressed: () => irConGoogleMaps(orden),
                icon: const Icon(Icons.navigation_rounded, size: 22),
              )
            : null,
      ),
    );
  }
}

Future<void> irConGoogleMaps(Map orden) async {
  // Si la orden tiene rango horario, el aviso "está en camino" al cliente sale ahora.
  if (orden['id'] != null) {
    unawaited(apiPost('/api/ordenes/${orden['id']}/en-camino', '{}').then((_) {}, onError: (_) {}));
  }
  final lat = orden['lat'];
  final lng = orden['lng'];
  final destino = lat is num && lng is num ? '$lat,$lng' : '${orden['direccion'] ?? ''}'.trim();
  if (destino.isEmpty) return;
  final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destino)}&travelmode=driving');
  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
    await launchUrl(url);
  }
}

Future<void> abrirRecorrida(List<Map> paradas) async {
  String punto(Map parada) {
    final lat = parada['lat'];
    final lng = parada['lng'];
    if (lat is num && lng is num) return '$lat,$lng';
    return '${parada['direccion'] ?? ''}'.trim();
  }

  final utiles = paradas.where((parada) => punto(parada).isNotEmpty).take(10).toList();
  if (utiles.isEmpty) return;
  final destino = punto(utiles.last);
  final medios = utiles.length == 1 ? '' : utiles.sublist(0, utiles.length - 1).map(punto).join('|');
  final url = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destino)}'
    '${medios.isEmpty ? '' : '&waypoints=${Uri.encodeComponent(medios)}'}&travelmode=driving',
  );
  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
    await launchUrl(url);
  }
}

String _hoyIso() {
  final hoy = DateTime.now();
  return '${hoy.year.toString().padLeft(4, '0')}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------
// PANTALLA 3: DETALLE Y CHECK-IN
// ---------------------------------------------------
class PantallaDetalle extends StatelessWidget {
  final Map orden;
  final int tecnicoId;
  final String nombreTecnico;
  final String emailTecnico;

  const PantallaDetalle({
    super.key,
    required this.orden,
    required this.tecnicoId,
    required this.nombreTecnico,
    required this.emailTecnico,
  });

  Future<void> registrarCheckIn(BuildContext context) async {
    // Si ya había empezado esta orden y la app se cerró, se retoma sin perder nada.
    final guardado = await Borrador.leer(tecnicoId);
    if (guardado != null && guardado['orden'] is Map && (guardado['orden'] as Map)['id'] == orden['id']) {
      if (!context.mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PantallaTrabajoProgreso(
            orden: Map<String, dynamic>.from(guardado['orden'] as Map),
            latitud: (guardado['latitud'] as num).toDouble(),
            longitud: (guardado['longitud'] as num).toDouble(),
            tecnicoId: tecnicoId,
            nombreTecnico: nombreTecnico,
            emailTecnico: emailTecnico,
            borrador: guardado,
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    try {
      bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
      if (!servicioHabilitado) throw Exception('Activá el GPS del celular.');

      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
        if (permiso == LocationPermission.denied) throw Exception('Hace falta permiso de ubicación.');
      }
      if (permiso == LocationPermission.deniedForever) throw Exception('Habilitá la ubicación para SON en los ajustes del celular.');

      // El GPS funciona sin internet. Si tarda mucho (por ejemplo, adentro de un edificio),
      // se usa la última posición conocida.
      Position? posicion;
      try {
        posicion = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)),
        );
      } on TimeoutException {
        posicion = await Geolocator.getLastKnownPosition();
      }
      if (posicion == null) throw Exception('Sin señal de GPS. Probá en un lugar abierto.');
      final latitud = posicion.latitude;
      final longitud = posicion.longitude;

      // La hora y el estado se guardan en el celular; se envían ahora si hay internet o más tarde si no.
      final ordenLocal = Map<String, dynamic>.from(orden);
      ordenLocal['estado'] = 'En progreso';
      await Sincronizador.encolarEstado((orden['id'] as num).toInt(), 'En progreso');
      unawaited(enviarUbicacion());
      unawaited(Sincronizador.sincronizar());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check-in registrado')));

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PantallaTrabajoProgreso(
            orden: ordenLocal,
            latitud: latitud,
            longitud: longitud,
            tecnicoId: tecnicoId,
            nombreTecnico: nombreTecnico,
            emailTecnico: emailTecnico,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      final mensaje = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: sonRojo,
          action: SnackBarAction(label: 'Reintentar', textColor: AppColors.superficie, onPressed: () => registrarCheckIn(context)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = coloresEstado('${orden['estado'] ?? ''}');
    final horario = rangoHorario(orden);
    final tieneDireccion = '${orden['direccion'] ?? ''}'.trim().isNotEmpty;

    Widget dato(IconData icono, String texto) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s12),
          child: Row(
            children: [
              IconoCircular(icono, tamano: 40),
              const SizedBox(width: AppSpacing.s12),
              Expanded(child: Text(texto, style: TextStyle(fontSize: 15, color: sonTexto))),
            ],
          ),
        );

    return Scaffold(
      backgroundColor: sonFondo,
      appBar: AppBar(title: Text('Orden #${orden['id']}')),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: AppSpacing.paginaMovil,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Aparecer(
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: colores.$1, borderRadius: AppRadius.rPildora),
                          child: Text('${orden['estado'] ?? ''}', style: TextStyle(color: colores.$2, fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    Aparecer(
                      orden: 1,
                      child: Text(
                        '${orden['cliente'] ?? ''}',
                        style: const TextStyle(fontFamily: AppTypography.display, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: AppTypography.trackingTitulo, height: 1.15),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s24),
                    Aparecer(
                      orden: 2,
                      child: Column(children: [
                        if (tieneDireccion) dato(Icons.place_rounded, '${orden['direccion']}'),
                        if (horario.isNotEmpty) dato(Icons.schedule_rounded, '${orden['fecha'] ?? ''} · $horario'),
                      ]),
                    ),
                    if (tieneDireccion && orden['estado'] != 'Por asignar') ...[
                      const SizedBox(height: AppSpacing.s8),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: () => irConGoogleMaps(orden),
                          icon: const Icon(Icons.navigation_rounded),
                          label: const Text('Ir con Google Maps'),
                        ),
                      ),
                    ],
                    if ('${orden['tarea'] ?? ''}'.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s24),
                      TarjetaSon(
                        padding: const EdgeInsets.all(AppSpacing.s16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Eyebrow('Tarea'),
                            const SizedBox(height: AppSpacing.s12),
                            Text('${orden['tarea']}', style: const TextStyle(fontSize: 16, height: 1.45)),
                          ],
                        ),
                      ),
                    ],
                    ResumenDelCliente(orden: orden),
                    const SizedBox(height: AppSpacing.s16),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              if (orden['estado'] == 'Por asignar')
                const Center(child: Eyebrow('Sin asignar'))
              else
                BotonOcupado(
                  icono: Icons.location_on_rounded,
                  texto: 'Iniciar trabajo',
                  textoOcupado: 'Ubicando...',
                  alPresionar: () => registrarCheckIn(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón principal grande (56dp) que se deshabilita y muestra un indicador mientras
/// corre la acción, para que no se pueda tocar dos veces.
class BotonOcupado extends StatefulWidget {
  final IconData icono;
  final String texto;
  final String textoOcupado;
  final Future<void> Function() alPresionar;
  const BotonOcupado({super.key, required this.icono, required this.texto, required this.textoOcupado, required this.alPresionar});

  @override
  State<BotonOcupado> createState() => _BotonOcupadoState();
}

class _BotonOcupadoState extends State<BotonOcupado> {
  bool _ocupado = false;

  Future<void> _tocar() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await widget.alPresionar();
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _ocupado ? null : _tocar,
        icon: _ocupado
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: sonTextoSuave))
            : Icon(widget.icono),
        label: Text(_ocupado ? widget.textoOcupado : widget.texto, style: const TextStyle(fontSize: 17)),
      ),
    );
  }
}

// ---------------------------------------------------
// PANTALLA 4: TRABAJO EN PROGRESO
// ---------------------------------------------------
class PantallaTrabajoProgreso extends StatefulWidget {
  final Map<String, dynamic> orden;
  final double latitud;
  final double longitud;
  final int tecnicoId;
  final String nombreTecnico;
  final String emailTecnico;

  /// Datos guardados de un trabajo que quedó a medias (null si recién empieza).
  final Map<String, dynamic>? borrador;

  const PantallaTrabajoProgreso({
    super.key,
    required this.orden,
    required this.latitud,
    required this.longitud,
    required this.tecnicoId,
    required this.nombreTecnico,
    required this.emailTecnico,
    this.borrador,
  });

  @override
  State<PantallaTrabajoProgreso> createState() => _PantallaTrabajoProgresoState();
}

class _PantallaTrabajoProgresoState extends State<PantallaTrabajoProgreso> {
  final List<Uint8List> evidencias = [];
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _comentariosController = TextEditingController();

  // Lo que el técnico anotó para presupuestar en esta visita (se guarda con el borrador).
  final List<Map<String, dynamic>> solicitudes = [];
  final Map<String, Uint8List> _fotosSolicitudes = {};
  Set<String> _solicitudesPendientes = {};
  Set<String> _solicitudesFallidas = {};
  late final List<Map<String, dynamic>> microtareas;
  late final DateTime _inicio;
  Timer? _reloj;
  Timer? _ubicacion;
  Timer? _guardado;
  bool _finalizando = false;
  String _tiempo = '00:00:00';
  // Paso del flujo: 0 Tareas, 1 Evidencia, 2 Notas, 3 Firmas.
  int _paso = 0;
  static const List<String> _pasos = ['Tareas', 'Evidencia', 'Notas', 'Firmas'];

  // Si el técnico tiene su firma con sello cargada en el perfil, el informe la lleva sola.
  bool _tieneFirma = false;
  // Lo que se anotó en esta visita (se guarda con el borrador para mostrarlo si se reabre la app).
  final List<Map<String, dynamic>> vencimientosAnotados = [];
  // Gastos cargados en esta visita (solo el resumen; van a Administración, no al informe).
  final List<Map<String, dynamic>> _gastos = [];
  // Formularios de control de la orden y lo que se fue completando (por id de formulario).
  late final List<Map<String, dynamic>> _formularios = (widget.orden['formularios'] as List? ?? [])
      .whereType<Map>()
      .map((f) => Map<String, dynamic>.from(f))
      .toList();
  final Map<String, Map<String, dynamic>> _respuestasFormularios = {};

  final SignatureController _firmaTecnicoController = SignatureController(penStrokeWidth: 1.5, penColor: AppColors.tinta, exportBackgroundColor: Colors.white);
  final SignatureController _firmaClienteController = SignatureController(penStrokeWidth: 1.5, penColor: AppColors.tinta, exportBackgroundColor: Colors.white);

  @override
  void initState() {
    super.initState();
    final guardado = widget.borrador;
    if (guardado != null) {
      // Se retoma un trabajo que quedó a medias: se recupera todo lo que ya se había cargado.
      _inicio = DateTime.tryParse('${guardado['inicio']}')?.toLocal() ?? DateTime.now();
      microtareas = (guardado['checklist'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      _comentariosController.text = '${guardado['comentarios'] ?? ''}';
      for (final foto in (guardado['evidencias'] as List? ?? [])) {
        evidencias.add(base64Decode('$foto'));
      }
      for (final nota in (guardado['solicitudes'] as List? ?? [])) {
        solicitudes.add(Map<String, dynamic>.from(nota as Map));
      }
      for (final vencimiento in (guardado['vencimientos'] as List? ?? [])) {
        vencimientosAnotados.add(Map<String, dynamic>.from(vencimiento as Map));
      }
      for (final gasto in (guardado['gastos'] is List ? guardado['gastos'] as List : const [])) {
        if (gasto is Map) _gastos.add(Map<String, dynamic>.from(gasto));
      }
      final formularios = guardado['formularios'];
      if (formularios is Map) {
        formularios.forEach((id, respuestas) {
          if (respuestas is Map) _respuestasFormularios['$id'] = Map<String, dynamic>.from(respuestas);
        });
      }
    } else {
      _inicio = DateTime.now();
      final puntos = widget.orden['puntos'];
      final delFormulario = puntos is List ? puntos.map((punto) => '$punto'.trim()).where((punto) => punto.isNotEmpty).toList() : <String>[];
      final lineas = delFormulario.isNotEmpty
          ? delFormulario
          : '${widget.orden['tarea'] ?? ''}'.split('\n').map((linea) => linea.trim()).where((linea) => linea.isNotEmpty).toList();
      microtareas = (lineas.isEmpty ? ['Revisar el trabajo indicado', 'Registrar evidencias', 'Confirmar con el cliente'] : lineas)
          .map((tarea) => {'tarea': tarea, 'hecho': false})
          .toList();
      _guardarAvance();
    }
    _comentariosController.addListener(_guardarAvanceConDemora);
    _actualizarReloj();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_actualizarReloj);
    });
    _ubicacion = Timer.periodic(const Duration(seconds: 20), (_) => enviarUbicacion());
    // Cada vez que cambia la cola de envíos, se actualiza si las notas ya llegaron.
    Sincronizador.estado.addListener(_refrescarSolicitudes);
    _refrescarSolicitudes();
    _leerPerfil();
  }

  Future<void> _leerPerfil() async {
    final guardado = await PerfilTecnico.guardado(widget.tecnicoId);
    if (mounted && guardado != null) setState(() => _tieneFirma = guardado['tiene_firma'] == true);
    final actual = await PerfilTecnico.actualizar(widget.tecnicoId);
    if (mounted && actual != null) setState(() => _tieneFirma = actual['tiene_firma'] == true);
  }

  Future<void> _anotarVencimiento() async {
    final vencimiento = await anotarVencimiento(context, orden: widget.orden);
    if (vencimiento == null || !mounted) return;
    setState(() => vencimientosAnotados.add(vencimiento));
    unawaited(_guardarAvance());
  }

  Future<void> _completarFormulario(Map<String, dynamic> formulario) async {
    final clave = '${formulario['id']}';
    final respuestas = await completarFormulario(context, formulario, _respuestasFormularios[clave], cliente: '${widget.orden['cliente'] ?? ''}');
    if (respuestas == null || !mounted) return;
    setState(() => _respuestasFormularios[clave] = respuestas);
    unawaited(_guardarAvance());
  }

  Widget _seccionFormularios() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSeccion('Formularios'),
        for (final formulario in _formularios)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: decoracionTarjeta(),
            child: ListTile(
              onTap: () => _completarFormulario(formulario),
              leading: Icon(
                formularioEmpezado(formulario, _respuestasFormularios['${formulario['id']}']) ? Icons.task_alt : Icons.fact_check_outlined,
                color: formularioEmpezado(formulario, _respuestasFormularios['${formulario['id']}']) ? sonLightGreen : sonTextoSuave,
              ),
              title: Text('${formulario['nombre']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(avanceDeFormulario(formulario, _respuestasFormularios['${formulario['id']}'])),
              minVerticalPadding: 14,
              trailing: Icon(Icons.chevron_right_rounded, color: sonTextoTenue),
            ),
          ),
      ],
    );
  }

  Future<void> _cargarGasto() async {
    final cargado = await cargarGasto(context, orden: widget.orden);
    if (cargado.isEmpty || !mounted) return;
    setState(() => _gastos.addAll(cargado));
    unawaited(_guardarAvance());
  }

  /// Mira en la cola del celular qué notas para presupuestar siguen sin enviarse.
  Future<void> _refrescarSolicitudes() async {
    if (solicitudes.isEmpty) return;
    final pendientes = await Sincronizador.solicitudesPendientes();
    final fallidas = await Sincronizador.solicitudesFallidas();
    if (!mounted) return;
    setState(() {
      _solicitudesPendientes = pendientes;
      _solicitudesFallidas = fallidas;
    });
  }

  /// Anota algo que falta presupuestar. Se guarda en el celular y se manda apenas haya señal.
  Future<void> _anotarParaPresupuestar() async {
    final nota = await pedirNotaParaPresupuestar(context);
    if (nota == null || !mounted) return;
    final id = nuevoIdDeNota();
    try {
      await Sincronizador.encolarSolicitud({
        'idCliente': id,
        'ordenId': widget.orden['id'],
        'cliente': widget.orden['cliente'],
        'descripcion': nota.descripcion,
        'cantidad': nota.cantidad,
        'foto': nota.foto == null ? null : 'data:image/jpeg;base64,${base64Encode(nota.foto!)}',
        'creadaEn': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la nota en el celular: $e'), backgroundColor: sonRojo),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      solicitudes.add({'id': id, 'descripcion': nota.descripcion, 'cantidad': nota.cantidad, 'conFoto': nota.foto != null});
      if (nota.foto != null) _fotosSolicitudes[id] = nota.foto!;
    });
    unawaited(_guardarAvance());
    unawaited(Sincronizador.sincronizar());
    await _refrescarSolicitudes();
    if (!mounted) return;
    final enCola = _solicitudesPendientes.contains(id) || _solicitudesFallidas.contains(id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(enCola ? 'Guardada en el celular · se envía con señal' : 'Nota enviada'), duration: const Duration(seconds: 3)),
    );
  }

  void _actualizarReloj() {
    final transcurrido = DateTime.now().difference(_inicio);
    String dos(int valor) => valor.toString().padLeft(2, '0');
    _tiempo = '${dos(transcurrido.inHours)}:${dos(transcurrido.inMinutes.remainder(60))}:${dos(transcurrido.inSeconds.remainder(60))}';
  }

  /// Guarda en el celular lo que el técnico lleva cargado, para no perderlo si se cierra la app.
  Future<void> _guardarAvance() {
    return Borrador.guardar(widget.tecnicoId, {
      'orden': widget.orden,
      'latitud': widget.latitud,
      'longitud': widget.longitud,
      'inicio': _inicio.toUtc().toIso8601String(),
      'checklist': microtareas,
      'comentarios': _comentariosController.text,
      'evidencias': evidencias.map(base64Encode).toList(),
      'solicitudes': solicitudes,
      'vencimientos': vencimientosAnotados,
      'gastos': _gastos,
      'formularios': _respuestasFormularios,
    });
  }

  void _guardarAvanceConDemora() {
    _guardado?.cancel();
    _guardado = Timer(const Duration(seconds: 1), _guardarAvance);
  }

  @override
  void dispose() {
    Sincronizador.estado.removeListener(_refrescarSolicitudes);
    _reloj?.cancel();
    _ubicacion?.cancel();
    _guardado?.cancel();
    _comentariosController.dispose();
    _firmaTecnicoController.dispose();
    _firmaClienteController.dispose();
    super.dispose();
  }

  Future<void> tomarFoto() async {
    try {
      final XFile? foto = await _picker.pickImage(source: ImageSource.camera, imageQuality: 60);
      if (foto != null) {
        final bytes = await foto.readAsBytes();
        if (mounted) setState(() => evidencias.add(bytes));
        await _guardarAvance();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al abrir la cámara')));
    }
  }

  /// Guarda el informe completo en el celular y lo deja en la cola de envío.
  /// No depende de internet: si hay señal se manda enseguida, si no, apenas vuelva.
  Future<void> _finalizar() async {
    // Aviso si quedó algún formulario sin tocar (puede ser a propósito: no se frena).
    final sinCompletar = _formularios.where((f) => !formularioEmpezado(f, _respuestasFormularios['${f['id']}'])).map((f) => '${f['nombre']}').toList();
    if (sinCompletar.isNotEmpty) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (dialogo) => AlertDialog(
          title: const Text('Hay formularios sin completar'),
          content: Text('${sinCompletar.join(', ')}.\n\n¿Finalizar igual? En el informe van a figurar sin completar.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Volver')),
            TextButton(onPressed: () => Navigator.pop(dialogo, true), child: const Text('Finalizar igual')),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
    }
    setState(() => _finalizando = true);
    try {
      // Con la firma con sello cargada en el perfil, el servidor la pone sola en el informe.
      final bytesTecnico = _tieneFirma ? null : await _firmaTecnicoController.toPngBytes();
      final bytesCliente = await _firmaClienteController.toPngBytes();

      await Sincronizador.encolarInforme({
        'ordenId': widget.orden['id'],
        'cliente': widget.orden['cliente'],
        'direccion': widget.orden['direccion'],
        'latitud': widget.latitud,
        'longitud': widget.longitud,
        'comentarios': _comentariosController.text,
        'checklist': microtareas,
        'formularios': _formularios.map((f) => {'id': f['id'], ...?_respuestasFormularios['${f['id']}']}).toList(),
        'evidencias': evidencias.map((bytes) => 'data:image/jpeg;base64,${base64Encode(bytes)}').toList(),
        'firmaTecnico': bytesTecnico != null ? 'data:image/png;base64,${base64Encode(bytesTecnico)}' : null,
        'firmaCliente': bytesCliente != null ? 'data:image/png;base64,${base64Encode(bytesCliente)}' : null,
        'inicio': _inicio.toUtc().toIso8601String(),
        'fin': DateTime.now().toUtc().toIso8601String(),
      });
      await Borrador.borrar(widget.tecnicoId);
      unawaited(Sincronizador.sincronizar());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe guardado · se envía automáticamente'),
          duration: Duration(seconds: 5),
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => PantallaPrincipal(
            tecnicoId: widget.tecnicoId,
            nombre: widget.nombreTecnico,
            email: widget.emailTecnico,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _finalizando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el informe en el celular: $e'), backgroundColor: sonRojo),
      );
    }
  }

  // ---------- Piezas visuales del flujo ----------
  Widget _tituloSeccion(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
        child: Text(texto, style: Theme.of(context).textTheme.titleLarge),
      );

  Widget _botonSeccion(IconData icono, String texto, VoidCallback alTocar) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.s12),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(onPressed: alTocar, icon: Icon(icono), label: Text(texto)),
        ),
      );

  Widget _tarjetaLista(List<Widget> filas) => Container(
        decoration: decoracionTarjeta(radio: AppRadius.tarjetaGrande),
        clipBehavior: Clip.antiAlias,
        child: Column(children: filas),
      );

  void _irAPaso(int paso) {
    if (paso < 0 || paso >= _pasos.length) return;
    setState(() => _paso = paso);
  }

  Widget _indicadorPasos() {
    return Row(
      children: [
        for (var i = 0; i < _pasos.length; i++)
          Expanded(
            child: InkWell(
              borderRadius: AppRadius.rChico,
              onTap: () => _irAPaso(i),
              child: Container(
                constraints: const BoxConstraints(minHeight: AppSpacing.tactilMinimo),
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: AppMotion.media,
                      curve: AppMotion.curva,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i < _paso ? sonTexto : (i == _paso ? sonAcento : sonBorde),
                        borderRadius: AppRadius.rPildora,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _pasos[i],
                      style: TextStyle(fontSize: 12, fontWeight: i == _paso ? FontWeight.w700 : FontWeight.w500, color: i == _paso ? sonTexto : sonTextoSuave),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------- Paso 1: tareas ----------
  Widget _pasoTareas() {
    final hechas = microtareas.where((t) => t['hecho'] == true).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _tituloSeccion('Checklist')),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: Text('$hechas de ${microtareas.length}', style: TextStyle(color: sonTextoSuave, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        _tarjetaLista([
          for (final tarea in microtareas)
            CheckboxListTile(
              minVerticalPadding: 14,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '${tarea['tarea']}',
                style: TextStyle(fontSize: 15, decoration: tarea['hecho'] == true ? TextDecoration.lineThrough : null, color: tarea['hecho'] == true ? sonTextoSuave : sonTexto),
              ),
              value: tarea['hecho'] == true,
              onChanged: (bool? valor) {
                setState(() => tarea['hecho'] = valor ?? false);
                _guardarAvance();
              },
            ),
        ]),
        if (_formularios.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s32),
          _seccionFormularios(),
        ],
        const SizedBox(height: AppSpacing.s32),
        _tituloSeccion('Check-in'),
        Container(
          height: 150,
          decoration: decoracionTarjeta(radio: AppRadius.tarjetaGrande),
          clipBehavior: Clip.antiAlias,
          child: FlutterMap(
            options: MapOptions(initialCenter: LatLng(widget.latitud, widget.longitud), initialZoom: 16.0),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.son.tecnico'),
              MarkerLayer(markers: [Marker(point: LatLng(widget.latitud, widget.longitud), width: 44, height: 44, child: Icon(Icons.location_on_rounded, color: sonAcento, size: 44))]),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Paso 2: evidencia ----------
  Future<void> _verFoto(int indice) async {
    final borrar = await showDialog<bool>(
      context: context,
      builder: (dialogo) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: InteractiveViewer(child: Image.memory(evidencias[indice], fit: BoxFit.contain))),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(dialogo, true),
                        icon: Icon(Icons.delete_outline_rounded, color: sonRojo),
                        label: Text('Borrar', style: TextStyle(color: sonRojo)),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(child: SizedBox(height: 48, child: ElevatedButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Listo')))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (borrar == true && mounted) {
      setState(() => evidencias.removeAt(indice));
      unawaited(_guardarAvance());
    }
  }

  Widget _pasoEvidencia() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSeccion('Fotos'),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.s8,
          crossAxisSpacing: AppSpacing.s8,
          children: [
            Material(
              color: AppColors.tinta,
              borderRadius: AppRadius.rTarjeta,
              child: InkWell(
                borderRadius: AppRadius.rTarjeta,
                onTap: tomarFoto,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_rounded, color: AppColors.superficie, size: 28),
                    SizedBox(height: 6),
                    Text('Agregar', style: TextStyle(color: AppColors.superficie, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            for (var i = 0; i < evidencias.length; i++)
              GestureDetector(
                onTap: () => _verFoto(i),
                child: ClipRRect(borderRadius: AppRadius.rTarjeta, child: Image.memory(evidencias[i], fit: BoxFit.cover)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s32),
        SeccionParaPresupuestar(
          notas: solicitudes,
          fotos: _fotosSolicitudes,
          pendientes: _solicitudesPendientes,
          fallidas: _solicitudesFallidas,
          onAnotar: _anotarParaPresupuestar,
        ),
      ],
    );
  }

  // ---------- Paso 3: notas ----------
  Widget _pasoNotas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSeccion('Observaciones'),
        TextField(
          controller: _comentariosController,
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(hintText: 'Qué se hizo en la visita'),
        ),
        const SizedBox(height: AppSpacing.s32),
        _tituloSeccion('Vencimientos'),
        if (vencimientosAnotados.isNotEmpty)
          _tarjetaLista([
            for (final v in vencimientosAnotados)
              ListTile(
                leading: IconoCircular(Icons.event_rounded, tamano: 40),
                title: Text('${v['descripcion']}${((v['cantidad'] as num?) ?? 1) > 1 ? ' (x${v['cantidad']})' : ''}'),
                subtitle: Text('Vence el ${fechaCorta('${v['vence']}')}'),
              ),
          ]),
        _botonSeccion(Icons.event_available_rounded, 'Anotar vencimiento', _anotarVencimiento),
        const SizedBox(height: AppSpacing.s32),
        _tituloSeccion('Vehículo y gastos'),
        if (_gastos.isNotEmpty)
          _tarjetaLista([
            for (final gasto in _gastos)
              ListTile(
                leading: IconoCircular(gasto['tipo'] == 'Combustible' ? Icons.local_gas_station_rounded : Icons.receipt_long_rounded, tamano: 40),
                title: Text(resumenDeGasto(gasto)),
                subtitle: Text([
                  if ('${gasto['vehiculo'] ?? ''}'.isNotEmpty) '${gasto['vehiculo']}',
                  if (gasto['conFoto'] == true) 'con ticket',
                ].join(' · ')),
              ),
          ]),
        _botonSeccion(Icons.add_rounded, _gastos.isEmpty ? 'Cargar gasto' : 'Agregar otro', _cargarGasto),
      ],
    );
  }

  // ---------- Paso 4: firmas ----------
  Future<void> _firmarPantallaCompleta(SignatureController controlador, String titulo) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (pantalla) => Scaffold(
          appBar: AppBar(
            title: Text(titulo),
            actions: [
              TextButton(onPressed: controlador.clear, child: Text('Borrar', style: TextStyle(color: sonRojo))),
              const SizedBox(width: AppSpacing.s8),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: AppColors.superficie, borderRadius: AppRadius.rTarjetaGrande, border: Border.all(color: sonBorde)),
                      clipBehavior: Clip.antiAlias,
                      child: Signature(controller: controlador, backgroundColor: AppColors.superficie),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(onPressed: () => Navigator.pop(pantalla), child: const Text('Listo')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _tarjetaFirma(String titulo, SignatureController controlador) {
    final vacia = controlador.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSeccion(titulo),
        GestureDetector(
          onTap: () => _firmarPantallaCompleta(controlador, titulo),
          child: Container(
            height: 160,
            decoration: BoxDecoration(
              color: AppColors.superficie,
              borderRadius: AppRadius.rTarjetaGrande,
              border: Border.all(color: vacia ? sonBorde : sonAcento, width: vacia ? 1 : 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: vacia
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.draw_rounded, size: 32, color: AppColors.textoTenue),
                        const SizedBox(height: 6),
                        const Text('Tocar para firmar', style: TextStyle(color: AppColors.textoSecundario, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )
                : IgnorePointer(child: Signature(controller: controlador, backgroundColor: AppColors.superficie)),
          ),
        ),
      ],
    );
  }

  Widget _pasoFirmas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_tieneFirma)
          Container(
            padding: const EdgeInsets.all(AppSpacing.s16),
            decoration: decoracionTarjeta(radio: AppRadius.tarjetaGrande),
            child: Row(
              children: [
                const IconoCircular(Icons.verified_rounded, tamano: 40),
                const SizedBox(width: AppSpacing.s12),
                Expanded(child: Text('Tu firma y sello van solos', style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600))),
              ],
            ),
          )
        else
          _tarjetaFirma('Firma del técnico', _firmaTecnicoController),
        const SizedBox(height: AppSpacing.s32),
        _tarjetaFirma('Firma y sello del cliente', _firmaClienteController),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pasos = [_pasoTareas, _pasoEvidencia, _pasoNotas, _pasoFirmas];
    final ultimo = _paso == _pasos.length - 1;
    return Scaffold(
      backgroundColor: sonFondo,
      appBar: AppBar(
        title: Text('${widget.orden['cliente'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: AppSpacing.s16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(color: AppColors.tinta, borderRadius: AppRadius.rPildora),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 16, color: AppColors.acento),
                const SizedBox(width: 6),
                Text(_tiempo, style: const TextStyle(color: AppColors.superficie, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(padding: const EdgeInsets.fromLTRB(13, 0, 13, 4), child: _indicadorPasos()),
        ),
      ),
      body: AnimatedSwitcher(
        duration: AppMotion.media,
        switchInCurve: AppMotion.curva,
        layoutBuilder: (actual, _) => actual ?? const SizedBox.shrink(),
        transitionBuilder: (hijo, animacion) => FadeTransition(
          opacity: animacion,
          child: SlideTransition(position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(animacion), child: hijo),
        ),
        child: ListView(
          key: ValueKey(_paso),
          padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s24, AppSpacing.s16, AppSpacing.s32),
          children: [pasos[_paso]()],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s12, AppSpacing.s16, AppSpacing.s12),
          decoration: BoxDecoration(color: sonPanel, border: Border(top: BorderSide(color: sonBorde))),
          child: Row(
            children: [
              if (_paso > 0) ...[
                SizedBox(
                  width: 56,
                  height: 56,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => _irAPaso(_paso - 1),
                    child: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
              ],
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ultimo
                      ? ElevatedButton.icon(
                          onPressed: _finalizando ? null : _finalizar,
                          icon: _finalizando
                              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: sonTextoSuave))
                              : const Icon(Icons.check_rounded),
                          label: Text(_finalizando ? 'Guardando...' : 'Finalizar', style: const TextStyle(fontSize: 17)),
                        )
                      : FilledButton.icon(
                          onPressed: () => _irAPaso(_paso + 1),
                          iconAlignment: IconAlignment.end,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(_pasos[_paso + 1], style: const TextStyle(fontSize: 17)),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------
// 5. TAB MÁS
// ---------------------------------------------------
class TabMasPlaceholder extends StatelessWidget {
  final String nombre;
  final String email;

  const TabMasPlaceholder({super.key, required this.nombre, required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Más opciones', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            leading: Icon(Icons.person, color: sonTexto),
            title: const Text('Perfil del Técnico'),
            subtitle: FutureBuilder<Map<String, dynamic>?>(
              future: Sesion.tecnicoId == null ? Future.value(null) : PerfilTecnico.actualizar(Sesion.tecnicoId!),
              builder: (context, perfil) {
                final datos = perfil.data;
                final lineas = [
                  '$nombre ($email)',
                  if (datos != null && '${datos['matricula'] ?? ''}'.isNotEmpty) 'Matrícula: ${datos['matricula']}',
                  if (datos != null) datos['tiene_firma'] == true ? 'Firma y sello cargados: el informe los lleva solos' : 'Sin firma cargada: pedile a la oficina que la suba',
                ];
                return Text(lineas.join('\n'));
              },
            ),
          ),
          ListTile(
            leading: Icon(Icons.request_quote_outlined, color: sonTexto),
            title: const Text('Mis pedidos de presupuesto'),
            subtitle: const Text('Pedido, presupuestado, enviado o aprobado'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaMisPresupuestos())),
          ),
          ListTile(
            leading: Icon(Icons.event_busy_outlined, color: sonTexto),
            title: const Text('Vencimientos de mis clientes'),
            subtitle: const Text('Extintores, mediciones y habilitaciones por vencer'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaVencimientos())),
          ),
          ListTile(
            leading: Icon(Icons.local_gas_station_outlined, color: sonTexto),
            title: const Text('Cargar gasto o kilometraje'),
            subtitle: const Text('Fuera de una visita (por ejemplo, carga de combustible)'),
            onTap: () => cargarGasto(context),
          ),
          ListTile(
            leading: Icon(controlTema.claro ? Icons.dark_mode_outlined : Icons.light_mode_outlined, color: sonTexto),
            title: Text(controlTema.claro ? 'Usar tema oscuro' : 'Usar tema claro'),
            subtitle: Text(controlTema.claro ? 'Fondo claro' : 'Fondo oscuro'),
            onTap: controlTema.alternar,
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: sonRojo),
            title: Text('Cerrar Sesión', style: TextStyle(color: sonRojo)),
            onTap: () async {
              final pendientes = Sincronizador.estado.value.pendientes;
              if (pendientes > 0) {
                final confirmar = await showDialog<bool>(
                  context: context,
                  builder: (dialogo) => AlertDialog(
                    title: const Text('Tenés envíos pendientes'),
                    content: Text(
                      'Hay $pendientes envío(s) guardados en el celular que todavía no llegaron al servidor. '
                      'No se pierden, pero se enviarán cuando vuelvas a ingresar con internet.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
                      TextButton(onPressed: () => Navigator.pop(dialogo, true), child: Text('Cerrar sesión', style: TextStyle(color: sonRojo))),
                    ],
                  ),
                );
                if (confirmar != true) return;
              }
              Sincronizador.detener();
              Sesion.cerrar();
              if (!context.mounted) return;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PantallaLogin()));
            },
          ),
        ],
      ),
    );
  }
}
