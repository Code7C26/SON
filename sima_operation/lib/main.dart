import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';

// Definición de Colores del Tema SON
const Color simaDarkGreen = Color(0xFF003024);
const Color simaLightGreen = Color(0xFF7AEB67);
const Color simaBackground = Color(0xFFF4F4F4); 

// --- BASE DE DATOS LOCAL SIMULADA (Variable Global) ---
List<Map<String, dynamic>> ordenesGlobales = [
  {
    'id': 1,
    'cliente': 'Clinica del Sol',
    'direccion': 'Av. Siempre Viva 742',
    'hora': 'Hoy, 18:00',
    'tarea': 'Mantenimiento preventivo de equipos médicos y revisión general de sistemas.',
    'estado': 'En progreso',
    'fondoEstado': simaLightGreen,
    'textoEstado': simaDarkGreen,
  },
  {
    'id': 2,
    'cliente': 'Empresa Norte',
    'direccion': 'Ruta 9 Km 123',
    'hora': 'Hoy, 17:00',
    'tarea': 'Reparación de tableros eléctricos.',
    'estado': 'Pendiente',
    'fondoEstado': Colors.orange.shade100,
    'textoEstado': Colors.orange.shade800,
  },
  {
    'id': 3,
    'cliente': 'Hotel Central',
    'direccion': 'San Martín 340',
    'hora': 'Mañana, 09:00',
    'tarea': 'Control de generadores de emergencia.',
    'estado': 'Pendiente',
    'fondoEstado': Colors.orange.shade100,
    'textoEstado': Colors.orange.shade800,
  },
];

void main() {
  runApp(const SonApp());
}

class SonApp extends StatelessWidget {
  const SonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SON',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: simaDarkGreen,
        scaffoldBackgroundColor: simaBackground,
        fontFamily: 'TuFuente',
      ),
      home: const PantallaLogin(),
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: simaBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/LOGO2.png',
                height: 120,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 100, color: simaDarkGreen),
              ),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Iniciar Sesión', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: simaDarkGreen)),
                    const SizedBox(height: 20),
                    const Text('Correo electrónico', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: 'operativo@sima.com',
                        filled: true,
                        fillColor: simaBackground,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Contraseña', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        filled: true,
                        fillColor: simaBackground,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: simaLightGreen,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PantallaPrincipal()));
                        },
                        child: const Text('Ingresar', style: TextStyle(color: simaDarkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
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
// CONTENEDOR PRINCIPAL
// ---------------------------------------------------
class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  int _indiceActual = 0;
  final List<Widget> _pantallas = [const TabDashboard(), const TabOrdenes(), const TabMasPlaceholder()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pantallas[_indiceActual],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _indiceActual,
        onTap: (index) => setState(() => _indiceActual = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: simaDarkGreen,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'Órdenes'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'Más'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------
// 1. TAB DASHBOARD
// ---------------------------------------------------
class TabDashboard extends StatelessWidget {
  const TabDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // Calculamos los contadores dinámicamente
    int total = ordenesGlobales.length;
    int enProgreso = ordenesGlobales.where((o) => o['estado'] == 'En progreso').length;
    int completadas = ordenesGlobales.where((o) => o['estado'] == 'Completada').length;
    int pendientes = ordenesGlobales.where((o) => o['estado'] == 'Pendiente').length;

    // Filtramos las órdenes activas para la vista rápida
    List activas = ordenesGlobales.where((o) => o['estado'] != 'Completada').toList();

    return Scaffold(
      backgroundColor: simaBackground,
      appBar: AppBar(
        title: Image.asset(
          'assets/images/LOGO1.png', 
          height: 40,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: simaDarkGreen),
        ),
        backgroundColor: simaBackground,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hola, Juan 👋', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: simaDarkGreen)),
            const Text('Resumen de tu jornada', style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                _tarjetaContador('Órdenes asignadas', total.toString()),
                _tarjetaContador('En progreso', enProgreso.toString()),
                _tarjetaContador('Completadas', completadas.toString()),
                _tarjetaContador('Pendientes', pendientes.toString()),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Próximas órdenes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: simaDarkGreen)),
            const SizedBox(height: 12),
            ...activas.map((orden) {
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => PantallaDetalle(orden: orden)),
                  );
                },
                child: _tarjetaOrdenMini(orden['cliente'], orden['direccion'], orden['hora'], orden['estado'], orden['fondoEstado'], orden['textoEstado']),
              );
            }),
            if (activas.isEmpty)
              const Text('No tienes órdenes pendientes.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaContador(String titulo, String cantidad) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(titulo, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(cantidad, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: simaDarkGreen)),
        ],
      ),
    );
  }

  Widget _tarjetaOrdenMini(String cliente, String direccion, String hora, String estado, Color fondoEstado, Color textoEstado) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cliente, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: simaDarkGreen), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(direccion, style: const TextStyle(color: Colors.grey, fontSize: 13), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(hora, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: fondoEstado, borderRadius: BorderRadius.circular(20)),
            child: Text(estado, style: TextStyle(color: textoEstado, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------
// 2. TAB ÓRDENES
// ---------------------------------------------------
class TabOrdenes extends StatelessWidget {
  const TabOrdenes({super.key});

  @override
  Widget build(BuildContext context) {
    List asignadas = ordenesGlobales.where((o) => o['estado'] != 'Completada').toList();
    List completadas = ordenesGlobales.where((o) => o['estado'] == 'Completada').toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: simaBackground,
        appBar: AppBar(
          title: const Text('Órdenes', style: TextStyle(color: simaDarkGreen, fontWeight: FontWeight.bold)),
          backgroundColor: simaBackground,
          elevation: 0,
          bottom: const TabBar(
            labelColor: simaDarkGreen,
            unselectedLabelColor: Colors.grey,
            indicatorColor: simaDarkGreen,
            indicatorWeight: 3,
            tabs: [Tab(text: 'Asignadas'), Tab(text: 'Completadas'), Tab(text: 'Todas')],
          ),
        ),
        body: TabBarView(
          children: [
            // Pestaña ASIGNADAS
            asignadas.isEmpty 
              ? const Center(child: Text('No hay órdenes asignadas', style: TextStyle(color: Colors.grey)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: asignadas.map((orden) => _construirTarjetaClicable(context, orden)).toList(),
                ),
            // Pestaña COMPLETADAS
            completadas.isEmpty 
              ? const Center(child: Text('No hay órdenes completadas aún', style: TextStyle(color: Colors.grey)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: completadas.map((orden) => _construirTarjetaClicable(context, orden)).toList(),
                ),
            // Pestaña TODAS
            ListView(
              padding: const EdgeInsets.all(20),
              children: ordenesGlobales.map((orden) => _construirTarjetaClicable(context, orden)).toList(),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: simaLightGreen,
          child: const Icon(Icons.add, color: simaDarkGreen, size: 28),
          onPressed: () {},
        ),
      ),
    );
  }

  Widget _construirTarjetaClicable(BuildContext context, Map orden) {
    return GestureDetector(
      onTap: () {
        if (orden['estado'] != 'Completada') {
          Navigator.push(context, MaterialPageRoute(builder: (context) => PantallaDetalle(orden: orden)));
        }
      },
      child: _tarjetaOrdenMiniDetalle(orden['cliente'], orden['direccion'], orden['hora'], orden['estado'], orden['fondoEstado'], orden['textoEstado']),
    );
  }

  Widget _tarjetaOrdenMiniDetalle(String cliente, String direccion, String hora, String estado, Color fondoEstado, Color textoEstado) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cliente, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: simaDarkGreen), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(direccion, style: const TextStyle(color: Colors.grey, fontSize: 13), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(hora, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: fondoEstado, borderRadius: BorderRadius.circular(20)),
            child: Text(estado, style: TextStyle(color: textoEstado, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------
// PANTALLA 3: DETALLE Y CHECK-IN
// ---------------------------------------------------
class PantallaDetalle extends StatelessWidget {
  final Map orden;

  const PantallaDetalle({super.key, required this.orden});

  Future<void> registrarCheckIn(BuildContext context) async {
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

      Position posicion = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Check-in exitoso.\nLat: ${posicion.latitude} | Lng: ${posicion.longitude}'), backgroundColor: simaDarkGreen),
      );

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => PantallaTrabajoProgreso(orden: orden, posicion: posicion)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: simaBackground,
      appBar: AppBar(
        title: const Text('Detalle de orden', style: TextStyle(color: Colors.white)),
        backgroundColor: simaDarkGreen,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: simaLightGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
              child: Text(orden['estado'], style: const TextStyle(color: simaDarkGreen, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            Text(orden['cliente'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: simaDarkGreen)),
            const SizedBox(height: 8),
            Text(orden['direccion'], style: const TextStyle(fontSize: 16, color: Colors.grey)),
            Text('ID: #${orden['id']}', style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 32),
            const Text('Descripción', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: simaDarkGreen)),
            const SizedBox(height: 8),
            Text(orden['tarea'], style: const TextStyle(fontSize: 16)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: simaLightGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.location_on, color: simaDarkGreen),
                label: const Text('Iniciar trabajo (Check-in)', style: TextStyle(color: simaDarkGreen, fontSize: 18, fontWeight: FontWeight.bold)),
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
  final Map orden;
  final Position posicion;

  const PantallaTrabajoProgreso({super.key, required this.orden, required this.posicion});

  @override
  State<PantallaTrabajoProgreso> createState() => _PantallaTrabajoProgresoState();
}

class _PantallaTrabajoProgresoState extends State<PantallaTrabajoProgreso> {
  List<XFile> evidencias = []; 
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _comentariosController = TextEditingController();

  List<Map<String, dynamic>> microtareas = [
    {'tarea': 'Revisar tablero eléctrico principal', 'hecho': false},
    {'tarea': 'Controlar niveles de presión', 'hecho': false},
    {'tarea': 'Limpiar área de trabajo', 'hecho': false},
  ];

  final SignatureController _firmaTecnicoController = SignatureController(penStrokeWidth: 1.5, penColor: simaDarkGreen, exportBackgroundColor: Colors.white);
  final SignatureController _firmaClienteController = SignatureController(penStrokeWidth: 1.5, penColor: simaDarkGreen, exportBackgroundColor: Colors.white);

  @override
  void dispose() {
    _comentariosController.dispose();
    _firmaTecnicoController.dispose();
    _firmaClienteController.dispose();
    super.dispose();
  }

  Future<void> tomarFoto() async {
    try {
      final XFile? foto = await _picker.pickImage(source: ImageSource.camera);
      if (foto != null) setState(() { evidencias.add(foto); });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al abrir la cámara')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: simaBackground,
      appBar: AppBar(
        title: const Text('Trabajo en progreso', style: TextStyle(color: Colors.white)),
        backgroundColor: simaDarkGreen,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.orden['cliente'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: simaDarkGreen)),
            Text(widget.orden['direccion'], style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 24),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                child: const Column(
                  children: [
                    Text('Tiempo transcurrido', style: TextStyle(color: Colors.grey)),
                    SizedBox(height: 8),
                    Text('00:00:00', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: simaDarkGreen)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text('Ubicación del Check-in', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: simaDarkGreen)),
            const SizedBox(height: 16),
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              clipBehavior: Clip.hardEdge,
              child: FlutterMap(
                options: MapOptions(initialCenter: LatLng(widget.posicion.latitude, widget.posicion.longitude), initialZoom: 16.0),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.sima.operative'),
                  MarkerLayer(markers: [Marker(point: LatLng(widget.posicion.latitude, widget.posicion.longitude), width: 50, height: 50, child: const Icon(Icons.person_pin_circle, color: simaDarkGreen, size: 50))]),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text('Checklist de Tareas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: simaDarkGreen)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: Column(
                children: microtareas.map((tarea) {
                  return CheckboxListTile(
                    activeColor: simaLightGreen,
                    checkColor: simaDarkGreen,
                    title: Text(tarea['tarea'], style: TextStyle(decoration: tarea['hecho'] ? TextDecoration.lineThrough : null, color: tarea['hecho'] ? Colors.grey : Colors.black)),
                    value: tarea['hecho'],
                    onChanged: (bool? valor) { setState(() { tarea['hecho'] = valor!; }); },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Fotos y Videos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: simaDarkGreen)),
                TextButton.icon(onPressed: tomarFoto, icon: const Icon(Icons.add_a_photo, color: simaLightGreen), label: const Text('Agregar', style: TextStyle(color: simaDarkGreen, fontWeight: FontWeight.bold)))
              ],
            ),
            const SizedBox(height: 8),
            evidencias.isEmpty 
              ? const Text('No hay archivos adjuntos.', style: TextStyle(color: Colors.grey))
              : Wrap(spacing: 10, runSpacing: 10, children: evidencias.map((archivo) => Container(height: 80, width: 80, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8)), clipBehavior: Clip.hardEdge, child: Image.network(archivo.path, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, color: Colors.white)))).toList()),
            const SizedBox(height: 32),
            const Text('Comentarios y Cierre', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: simaDarkGreen)),
            const SizedBox(height: 16),
            const Text('Observaciones del técnico', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _comentariosController,
              maxLines: 3, 
              decoration: InputDecoration(
                hintText: 'Describe las tareas...', 
                filled: true, 
                fillColor: Colors.white, 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)), 
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300))
              ),
            ),
            const SizedBox(height: 24),
            const Text('Firma del Técnico', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 150,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              clipBehavior: Clip.hardEdge,
              child: Signature(controller: _firmaTecnicoController, backgroundColor: Colors.white),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _firmaTecnicoController.clear(), child: const Text('Limpiar firma', style: TextStyle(color: Colors.red)))),
            const SizedBox(height: 8),
            const Text('Firma del Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 150,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              clipBehavior: Clip.hardEdge,
              child: Signature(controller: _firmaClienteController, backgroundColor: Colors.white),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _firmaClienteController.clear(), child: const Text('Limpiar firma', style: TextStyle(color: Colors.red)))),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: simaLightGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async { 
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enviando y finalizando orden...'))); 
                  
                  try {
                    List<String> base64Evidencias = [];
                    for (var foto in evidencias) {
                      final bytesFoto = await foto.readAsBytes();
                      base64Evidencias.add('data:image/png;base64,${base64Encode(bytesFoto)}');
                    }

                    final bytesTecnico = await _firmaTecnicoController.toPngBytes();
                    final bytesCliente = await _firmaClienteController.toPngBytes();

                    String? base64Tecnico = bytesTecnico != null ? 'data:image/png;base64,${base64Encode(bytesTecnico)}' : null;
                    String? base64Cliente = bytesCliente != null ? 'data:image/png;base64,${base64Encode(bytesCliente)}' : null;

                    final respuesta = await http.post(
                      Uri.parse('http://localhost:3000/api/generar-informe'),
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode({
                        'cliente': widget.orden['cliente'],
                        'direccion': widget.orden['direccion'],
                        'latitud': widget.posicion.latitude,
                        'longitud': widget.posicion.longitude,
                        'comentarios': _comentariosController.text,
                        'evidencias': base64Evidencias,
                        'firmaTecnico': base64Tecnico,
                        'firmaCliente': base64Cliente,
                      }),
                    );

                    if (respuesta.statusCode == 200) {
                      // 1. Modificar el estado global de la orden a Completada
                      int index = ordenesGlobales.indexWhere((o) => o['id'] == widget.orden['id']);
                      if (index != -1) {
                        ordenesGlobales[index]['estado'] = 'Completada';
                        ordenesGlobales[index]['fondoEstado'] = Colors.blue.shade100; // Color distintivo
                        ordenesGlobales[index]['textoEstado'] = Colors.blue.shade800;
                      }

                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('¡Orden finalizada con éxito!', style: TextStyle(color: Colors.white)), backgroundColor: simaDarkGreen)); 
                      
                      // 2. Regresar a la pantalla principal limpiando el historial
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const PantallaPrincipal()),
                        (route) => false,
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al procesar la orden'), backgroundColor: Colors.red));
                  }
                },
                child: const Text('Finalizar y Generar PDF', style: TextStyle(color: simaDarkGreen, fontSize: 18, fontWeight: FontWeight.bold)),
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
  const TabMasPlaceholder({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: simaBackground,
      appBar: AppBar(
        title: const Text('Más opciones', style: TextStyle(color: simaDarkGreen, fontWeight: FontWeight.bold)),
        backgroundColor: simaBackground,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            leading: const Icon(Icons.person, color: simaDarkGreen),
            title: const Text('Perfil del Técnico'),
            subtitle: const Text('Juan Pérez (juan@sima.com)'),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PantallaLogin()));
            },
          ),
        ],
      ),
    );
  }
}