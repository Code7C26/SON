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
import 'package:son_tecnico/pantallas/para_presupuestar.dart';
import 'package:son_tecnico/services/api.dart';
import 'package:son_tecnico/services/almacen.dart';
import 'package:son_tecnico/services/sesion.dart';
import 'package:son_tecnico/services/sincronizacion.dart';
import 'package:son_tecnico/theme/colores.dart';

export 'package:son_tecnico/theme/colores.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Si el técnico ya había ingresado antes, entra directo (aunque no haya internet)
  // y, si dejó un trabajo a medias, lo retoma donde estaba.
  final tema = await Almacen.leer('tema.json');
  if (tema == 'claro') controlTema.establecer(true, avisar: false);
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
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: decoracionIngreso,
        child: Stack(
          children: [
            Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo_son_icono.png', height: 84, errorBuilder: (c, e, s) => Icon(Icons.broken_image, size: 80, color: sonTexto)),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: sonTarjeta,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: sonBorde),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 5))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Iniciar Sesión', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: sonTexto)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(hintText: 'Correo del técnico', prefixIcon: Icon(Icons.mail_outline)),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(hintText: 'Contraseña', prefixIcon: Icon(Icons.lock_outline)),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _cargando ? null : _iniciarSesion,
                        child: _cargando 
                          ? CircularProgressIndicator(color: sonDarkGreen)
                          : Text('Ingresar', style: TextStyle(color: sonDarkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton.icon(
                        onPressed: controlTema.alternar,
                        icon: Icon(controlTema.claro ? Icons.dark_mode_outlined : Icons.light_mode_outlined, color: sonTextoSuave),
                        label: Text(controlTema.claro ? 'Tema oscuro' : 'Tema claro', style: TextStyle(color: sonTextoSuave)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            ),
          ),
        ),
            ),
            const Positioned(top: 4, right: 4, child: SafeArea(child: BotonTema())),
          ],
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
      ),
      TabOrdenes(
        tecnicoId: widget.tecnicoId,
        nombreTecnico: widget.nombre,
        emailTecnico: widget.email,
      ),
      TabMasPlaceholder(nombre: widget.nombre, email: widget.email),
    ];

    return Scaffold(
      body: pantallas[_indiceActual],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BannerSincronizacion(),
          BottomNavigationBar(
            currentIndex: _indiceActual,
            onTap: (index) => setState(() => _indiceActual = index),
            type: BottomNavigationBarType.fixed,
            backgroundColor: sonPanel,
            selectedItemColor: sonLightGreen,
            unselectedItemColor: sonTextoSuave,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Dashboard'),
              BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'Órdenes'),
              BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'Más'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aviso sobre la barra inferior: cuántos envíos están guardados en el celular esperando internet.
class BannerSincronizacion extends StatelessWidget {
  const BannerSincronizacion({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EstadoSync>(
      valueListenable: Sincronizador.estado,
      builder: (context, estado, _) {
        if (estado.pendientes == 0 && estado.fallidos == 0 && !estado.sinSesion) return const SizedBox.shrink();

        String texto;
        Color fondo = const Color(0xFFD97B00);
        if (estado.sinSesion) {
          texto = 'Tu sesión venció. Cerrá sesión e ingresá de nuevo con internet para enviar lo pendiente (no se pierde).';
          fondo = const Color(0xFFC62828);
        } else if (estado.pendientes > 0) {
          final cantidad = estado.pendientes == 1 ? '1 envío guardado' : '${estado.pendientes} envíos guardados';
          texto = estado.sincronizando
              ? 'Enviando $cantidad...'
              : '$cantidad en el celular${estado.sinConexion ? ' · sin conexión, se envía solo cuando haya internet' : ''}';
        } else {
          texto = '${estado.fallidos} envío(s) fueron rechazados por el servidor. Avisá al administrador.';
          fondo = const Color(0xFFC62828);
        }

        return Material(
          color: fondo,
          child: InkWell(
            onTap: Sincronizador.sincronizar,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(estado.sincronizando ? Icons.sync : Icons.cloud_off, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(texto, style: const TextStyle(color: Colors.white, fontSize: 12.5))),
                  if (estado.pendientes > 0 && !estado.sincronizando)
                    const Text('Reintentar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                ],
              ),
            ),
          ),
        );
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

  const TabDashboard({
    super.key,
    required this.tecnicoId,
    required this.nombreTecnico,
    required this.emailTecnico,
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

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    final total = _ordenes.length;
    final enProgreso = _ordenes.where((o) => o['estado'] == 'En progreso').length;
    final completadas = _ordenes.where((o) => o['estado'] == 'Completada').length;
    final pendientes = _ordenes.where((o) => o['estado'] == 'Pendiente').length;
    final activas = _ordenes.where((o) => o['estado'] != 'Completada').toList();

    return Scaffold(
      backgroundColor: sonFondo,
      body: RefreshIndicator(
        color: sonLightGreen,
        onRefresh: _cargar,
        child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hola, ${widget.nombreTecnico} 👋', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: sonTexto)),
            Text(
              _sinConexion ? 'Sin conexión · mostrando lo último guardado' : 'Resumen de tu jornada',
              style: TextStyle(color: _sinConexion ? sonAmbar : sonTextoSuave, fontSize: 14, fontWeight: _sinConexion ? FontWeight.w600 : FontWeight.normal),
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                _tarjetaContador('Órdenes asignadas', total.toString(), Icons.assignment_outlined, sonLightGreen),
                _tarjetaContador('En progreso', enProgreso.toString(), Icons.directions_run, sonLightGreen),
                _tarjetaContador('Completadas', completadas.toString(), Icons.task_alt, sonLightGreen),
                _tarjetaContador('Pendientes', pendientes.toString(), Icons.schedule, sonLightGreen),
              ],
            ),
            const SizedBox(height: 24),
            Text('Próximas órdenes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: sonTexto)),
            const SizedBox(height: 12),
            ...activas.map((orden) {
              return GestureDetector(
                onTap: () {
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
                child: _tarjetaOrdenMini(orden),
              );
            }),
            if (activas.isEmpty)
              Text('No tienes órdenes pendientes.', style: TextStyle(color: sonTextoSuave)),
          ],
        ),
        ),
      ),
    );
  }

  Widget _tarjetaContador(String titulo, String cantidad, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: decoracionTarjeta(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                child: Icon(icono, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(titulo.toUpperCase(), style: TextStyle(color: sonTextoSuave, fontSize: 10.5, letterSpacing: 0.7, fontWeight: FontWeight.w600, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          Text(cantidad, style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: sonTexto, height: 1)),
        ],
      ),
    );
  }

  Widget _tarjetaOrdenMini(Map orden) {
    final colores = coloresEstado('${orden['estado']}');
    final hora = [orden['fecha'], orden['hora']].where((parte) => parte != null && '$parte'.isNotEmpty).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: decoracionTarjeta(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${orden['cliente'] ?? ''}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: sonTexto), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('${orden['direccion'] ?? ''}', style: TextStyle(color: sonTextoSuave, fontSize: 13), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(hora, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: colores.$1, borderRadius: BorderRadius.circular(20)),
            child: Text('${orden['estado']}', style: TextStyle(color: colores.$2, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------
// 2. TAB ÓRDENES
// ---------------------------------------------------
Future<void> enviarUbicacion() async {
  try {
    final servicio = await Geolocator.isLocationServiceEnabled();
    if (!servicio) return;
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) return;
    final posicion = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
    await apiPost('/api/tecnicos/ubicacion', json.encode({'lat': posicion.latitude, 'lng': posicion.longitude}));
  } catch (_) {}
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
  Timer? _reintento;

  @override
  void initState() {
    super.initState();
    _mostrarGuardadas();
    _cargar();
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

  Widget _lista(List<Map<String, dynamic>> ordenes, String vacio, BuildContext context, {bool recorrida = false}) {
    final deHoy = ordenes.where((orden) => orden['fecha_iso'] == _hoyIso() && orden['estado'] != 'Por asignar' && '${orden['direccion'] ?? ''}'.trim().isNotEmpty).toList();
    return RefreshIndicator(
      color: sonLightGreen,
      onRefresh: _cargar,
      child: ordenes.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: 200, child: Center(child: Text(vacio, style: TextStyle(color: sonTextoSuave)))),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (recorrida && deHoy.length >= 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: sonLightGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () => abrirRecorrida(deHoy),
                        icon: Icon(Icons.route, color: sonDarkGreen),
                        label: Text('Recorrido de hoy', style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold)),
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

    if (_cargando) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: sonFondo,
        appBar: AppBar(
          title: Text('Órdenes', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
          backgroundColor: sonFondo,
          elevation: 0,
          bottom: TabBar(
            labelColor: sonLightGreen,
            unselectedLabelColor: sonTextoSuave,
            indicatorColor: sonLightGreen,
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
          backgroundColor: sonLightGreen,
          icon: Icon(Icons.add, color: sonDarkGreen),
          label: Text('Pedir visita', style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold)),
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
    final enviada = await showDialog<bool>(
      context: context,
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, actualizar) => AlertDialog(
          title: const Text('Pedir una visita'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: cliente, decoration: const InputDecoration(labelText: 'Cliente')),
                const SizedBox(height: 8),
                TextField(controller: direccion, decoration: const InputDecoration(labelText: 'Dirección')),
                const SizedBox(height: 8),
                TextField(controller: descripcion, maxLines: 3, decoration: const InputDecoration(labelText: 'Qué hay que hacer')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final elegida = await showDatePicker(context: contexto, initialDate: fecha, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 400)));
                    if (elegida != null) actualizar(() => fecha = elegida);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text('${fecha.day}/${fecha.month}/${fecha.year}'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(contexto, true), child: const Text('Pedir')),
          ],
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
    return GestureDetector(
      onTap: () {
        if (orden['estado'] != 'Completada') {
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
      },
      child: _tarjetaOrden(orden),
    );
  }

  Widget _tarjetaOrden(Map orden) {
    final colores = coloresEstado('${orden['estado']}');
    final hora = [orden['fecha'], orden['hora']].where((parte) => parte != null && '$parte'.isNotEmpty).join(' · ');
    final parada = (orden['orden_ruta'] as num?)?.toInt();
    final puedeIr = orden['estado'] != 'Completada' && orden['estado'] != 'Por asignar' && '${orden['direccion'] ?? ''}'.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: decoracionTarjeta(),
      child: Row(
        children: [
          if (parada != null) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: sonLightGreen,
              child: Text('$parada', style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${orden['cliente'] ?? ''}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: sonTexto), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('${orden['direccion'] ?? ''}', style: TextStyle(color: sonTextoSuave, fontSize: 13), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(hora, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: colores.$1, borderRadius: BorderRadius.circular(20)),
                child: Text('${orden['estado']}', style: TextStyle(color: colores.$2, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              if (puedeIr)
                TextButton.icon(
                  onPressed: () => irConGoogleMaps(orden),
                  icon: const Icon(Icons.navigation, size: 18),
                  label: const Text('Ir'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> irConGoogleMaps(Map orden) async {
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Obteniendo ubicación GPS...')));
    try {
      bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
      if (!servicioHabilitado) throw Exception('El GPS está desactivado.');

      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
        if (permiso == LocationPermission.denied) throw Exception('Permisos denegados.');
      }
      if (permiso == LocationPermission.deniedForever) throw Exception('Permisos denegados permanentemente.');

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
      if (posicion == null) throw Exception('No se pudo obtener la ubicación. Salí a un lugar abierto y probá de nuevo.');
      final latitud = posicion.latitude;
      final longitud = posicion.longitude;

      // La hora y el estado se guardan en el celular; se envían ahora si hay internet o más tarde si no.
      final ordenLocal = Map<String, dynamic>.from(orden);
      ordenLocal['estado'] = 'En progreso';
      await Sincronizador.encolarEstado((orden['id'] as num).toInt(), 'En progreso');
      unawaited(enviarUbicacion());
      unawaited(Sincronizador.sincronizar());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Check-in registrado'), backgroundColor: sonTarjetaAlta),
      );

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: sonRojo));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: sonFondo,
      appBar: AppBar(
        title: Text('Detalle de orden', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
        backgroundColor: sonPanel,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: sonLightGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
              child: Text(orden['estado'], style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            Text(orden['cliente'], style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: sonTexto)),
            const SizedBox(height: 8),
            Text(orden['direccion'], style: TextStyle(fontSize: 16, color: sonTextoSuave)),
            Text('ID: #${orden['id']}', style: TextStyle(fontSize: 14, color: sonTextoSuave)),
            if ('${orden['direccion'] ?? ''}'.trim().isNotEmpty && orden['estado'] != 'Por asignar') ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: sonLightGreen),
                  onPressed: () => irConGoogleMaps(orden),
                  icon: Icon(Icons.navigation, color: sonDarkGreen),
                  label: Text('Ir con Google Maps', style: TextStyle(color: sonDarkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            const SizedBox(height: 32),
            Text('Descripción', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: sonTexto)),
            const SizedBox(height: 8),
            Text(orden['tarea'], style: const TextStyle(fontSize: 16)),
            const Spacer(),
            if (orden['estado'] == 'Por asignar')
              Text('Esta visita todavía no está asignada.', style: TextStyle(color: sonTextoSuave))
            else
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: sonLightGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(Icons.location_on, color: sonDarkGreen),
                label: Text('Iniciar trabajo (Check-in)', style: TextStyle(color: sonDarkGreen, fontSize: 18, fontWeight: FontWeight.bold)),
                onPressed: () => registrarCheckIn(context),
              ),
            ),
          ],
        ),
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

  final SignatureController _firmaTecnicoController = SignatureController(penStrokeWidth: 1.5, penColor: sonDarkGreen, exportBackgroundColor: Colors.white);
  final SignatureController _firmaClienteController = SignatureController(penStrokeWidth: 1.5, penColor: sonDarkGreen, exportBackgroundColor: Colors.white);

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nota enviada'), duration: Duration(seconds: 3)),
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
    setState(() => _finalizando = true);
    try {
      final bytesTecnico = await _firmaTecnicoController.toPngBytes();
      final bytesCliente = await _firmaClienteController.toPngBytes();

      await Sincronizador.encolarInforme({
        'ordenId': widget.orden['id'],
        'cliente': widget.orden['cliente'],
        'direccion': widget.orden['direccion'],
        'latitud': widget.latitud,
        'longitud': widget.longitud,
        'comentarios': _comentariosController.text,
        'checklist': microtareas,
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
        SnackBar(
          content: Text('Informe guardado'),
          backgroundColor: sonTarjetaAlta,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: sonFondo,
      appBar: AppBar(
        title: Text('Trabajo en progreso', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
        backgroundColor: sonPanel,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.orden['cliente'], style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: sonTexto)),
            Text(widget.orden['direccion'], style: TextStyle(fontSize: 16, color: sonTextoSuave)),
            const SizedBox(height: 24),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                decoration: decoracionTarjeta(),
                child: Column(
                  children: [
                    Text('Tiempo transcurrido', style: TextStyle(color: sonTextoSuave)),
                    const SizedBox(height: 8),
                    Text(_tiempo, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: sonTexto)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text('Ubicación del Check-in', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: sonTexto)),
            const SizedBox(height: 16),
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: sonBorde)),
              clipBehavior: Clip.hardEdge,
              child: FlutterMap(
                options: MapOptions(initialCenter: LatLng(widget.latitud, widget.longitud), initialZoom: 16.0),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.son.tecnico'),
                  MarkerLayer(markers: [Marker(point: LatLng(widget.latitud, widget.longitud), width: 50, height: 50, child: Icon(Icons.person_pin_circle, color: sonLightGreen, size: 50))]),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text('Coordenadas: ${widget.latitud.toStringAsFixed(5)}, ${widget.longitud.toStringAsFixed(5)}', style: TextStyle(color: sonTextoSuave, fontSize: 12)),
            const SizedBox(height: 32),
            Text('Checklist de Tareas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: sonTexto)),
            const SizedBox(height: 16),
            Container(
              decoration: decoracionTarjeta(),
              child: Column(
                children: microtareas.map((tarea) {
                  return CheckboxListTile(
                    activeColor: sonLightGreen,
                    checkColor: sonDarkGreen,
                    title: Text(tarea['tarea'], style: TextStyle(decoration: tarea['hecho'] ? TextDecoration.lineThrough : null, color: tarea['hecho'] ? sonTextoSuave : sonTexto)),
                    value: tarea['hecho'],
                    onChanged: (bool? valor) {
                      setState(() { tarea['hecho'] = valor ?? false; });
                      _guardarAvance();
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Fotos y Videos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: sonTexto)),
                TextButton.icon(onPressed: tomarFoto, icon: Icon(Icons.add_a_photo, color: sonLightGreen), label: Text('Agregar', style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold)))
              ],
            ),
            const SizedBox(height: 8),
            evidencias.isEmpty 
              ? Text('No hay archivos adjuntos.', style: TextStyle(color: sonTextoSuave))
              : Wrap(spacing: 10, runSpacing: 10, children: evidencias.map((bytes) => Container(height: 80, width: 80, decoration: BoxDecoration(color: sonBorde, borderRadius: BorderRadius.circular(8)), clipBehavior: Clip.hardEdge, child: Image.memory(bytes, fit: BoxFit.cover))).toList()),
            const SizedBox(height: 32),
            SeccionParaPresupuestar(
              notas: solicitudes,
              fotos: _fotosSolicitudes,
              pendientes: _solicitudesPendientes,
              fallidas: _solicitudesFallidas,
              onAnotar: _anotarParaPresupuestar,
            ),
            const SizedBox(height: 32),
            Text('Comentarios y Cierre', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: sonTexto)),
            const SizedBox(height: 16),
            const Text('Observaciones del técnico', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _comentariosController,
              maxLines: 3, 
              decoration: InputDecoration(
                hintText: 'Describe las tareas...', 
                filled: true, 
                fillColor: sonTarjetaAlta, 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: sonBorde)), 
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: sonBorde))
              ),
            ),
            const SizedBox(height: 24),
            const Text('Firma del Técnico', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 150,
              decoration: decoracionTarjeta(),
              clipBehavior: Clip.hardEdge,
              child: Signature(controller: _firmaTecnicoController, backgroundColor: Colors.white),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _firmaTecnicoController.clear(), child: Text('Limpiar firma', style: TextStyle(color: sonRojo)))),
            const SizedBox(height: 8),
            const Text('Firma del Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 150,
              decoration: decoracionTarjeta(),
              clipBehavior: Clip.hardEdge,
              child: Signature(controller: _firmaClienteController, backgroundColor: Colors.white),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _firmaClienteController.clear(), child: Text('Limpiar firma', style: TextStyle(color: sonRojo)))),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: sonLightGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _finalizando ? null : _finalizar,
                child: _finalizando
                    ? SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: sonDarkGreen, strokeWidth: 3))
                    : Text('Finalizar y Generar PDF', style: TextStyle(color: sonDarkGreen, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
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
      backgroundColor: sonFondo,
      appBar: AppBar(
        title: Text('Más opciones', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
        backgroundColor: sonFondo,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            leading: Icon(Icons.person, color: sonTexto),
            title: const Text('Perfil del Técnico'),
            subtitle: Text('$nombre ($email)'),
            onTap: () {},
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
