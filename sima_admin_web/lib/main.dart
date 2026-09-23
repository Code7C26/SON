import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const Color simaDarkGreen = Color(0xFF003024);
const Color simaLightGreen = Color(0xFF7AEB67);
const Color simaBackground = Color(0xFFF4F4F4);

void main() {
  runApp(const SimaAdminWeb());
}

class SimaAdminWeb extends StatelessWidget {
  const SimaAdminWeb({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SON Admin',
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

// --- PANTALLA DE LOGIN ---
class PantallaLogin extends StatefulWidget {
  const PantallaLogin({super.key});

  @override
  State<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends State<PantallaLogin> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _cargando = false;
  String _mensajeError = '';

  Future<void> _iniciarSesion() async {
    setState(() { _cargando = true; _mensajeError = ''; });

    try {
      final respuesta = await http.post(
        Uri.parse('http://127.0.0.1:3000/api/admin/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
        }),
      );

      if (respuesta.statusCode == 200) {
        final datosAdmin = json.decode(respuesta.body);
        if (mounted) {
          Navigator.pushReplacement(
            context, 
            MaterialPageRoute(
              builder: (context) => LayoutAdministrador(adminData: datosAdmin),
            ),
          );
        }
      } else {
        setState(() => _mensajeError = 'Credenciales incorrectas. Intenta nuevamente.');
      }
    } catch (e) {
      setState(() => _mensajeError = 'Error de conexión con el servidor.');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/COLOR4.png', height: 100, errorBuilder: (c, e, s) => const Icon(Icons.security, size: 80, color: simaDarkGreen)),
              const SizedBox(height: 32),
              const Text('Acceso Administrativo', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: simaDarkGreen)),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Correo Electrónico', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder()),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              if (_mensajeError.isNotEmpty) 
                Text(_mensajeError, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: simaLightGreen),
                  onPressed: _cargando ? null : _iniciarSesion,
                  child: _cargando 
                      ? const CircularProgressIndicator(color: simaDarkGreen) 
                      : const Text('Ingresar al Sistema', style: TextStyle(color: simaDarkGreen, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// --- LAYOUT DEL DASHBOARD ---
class LayoutAdministrador extends StatefulWidget {
  final Map<String, dynamic> adminData;
  const LayoutAdministrador({super.key, required this.adminData});

  @override
  State<LayoutAdministrador> createState() => _LayoutAdministradorState();
}

class _LayoutAdministradorState extends State<LayoutAdministrador> {
  int _indiceActual = 0;
  late Map<String, dynamic> _adminActual;

  @override
  void initState() {
    super.initState();
    _adminActual = widget.adminData;
  }

  void _mostrarPerfil() {
    final TextEditingController nombreController = TextEditingController(text: _adminActual['nombre']);
    final TextEditingController emailController = TextEditingController(text: _adminActual['email']);
    final TextEditingController passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Mi Perfil de Administrador', style: TextStyle(color: simaDarkGreen, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreController,
                  decoration: const InputDecoration(labelText: 'Nombre Completo'),
                ),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Correo Electrónico'),
                ),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: 'Nueva Contraseña (dejar en blanco para no cambiar)'),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: simaLightGreen),
              onPressed: () async {
                try {
                  final res = await http.put(
                    Uri.parse('http://127.0.0.1:3000/api/admin/actualizar/${_adminActual['id']}'),
                    headers: {'Content-Type': 'application/json'},
                    body: json.encode({
                      'nombre': nombreController.text,
                      'email': emailController.text,
                      'password': passwordController.text.isNotEmpty ? passwordController.text : '123456',
                    }),
                  );

                  if (res.statusCode == 200) {
                    setState(() {
                      _adminActual = json.decode(res.body);
                    });
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Perfil actualizado con éxito')),
                    );
                  }
                } catch (e) {
                  print('Error al actualizar: $e');
                }
              },
              child: const Text('Guardar Cambios', style: TextStyle(color: simaDarkGreen, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pantallas = [
      const PantallaDashboard(),
      const PantallaOrdenes(),
      const PantallaTecnicos(),
      const PantallaInformes(),
      const PantallaAnalisis(),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _indiceActual,
            onDestinationSelected: (int index) => setState(() => _indiceActual = index),
            backgroundColor: simaDarkGreen,
            unselectedIconTheme: const IconThemeData(color: Colors.white54),
            selectedIconTheme: const IconThemeData(color: simaLightGreen),
            unselectedLabelTextStyle: const TextStyle(color: Colors.white54),
            selectedLabelTextStyle: const TextStyle(color: simaLightGreen, fontWeight: FontWeight.bold),
            extended: true,
            minExtendedWidth: 250,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32.0),
              child: Image.asset(
                'assets/images/3.png', 
                height: 60,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white, size: 50),
              ),
            ),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.dashboard), label: Text('Panel de Control')),
              NavigationRailDestination(icon: Icon(Icons.assignment), label: Text('Órdenes de Trabajo')),
              NavigationRailDestination(icon: Icon(Icons.people), label: Text('Técnicos')),
              NavigationRailDestination(icon: Icon(Icons.folder), label: Text('Informes')),
              NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('Análisis')),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.account_circle, color: simaLightGreen, size: 28),
                        onPressed: _mostrarPerfil,
                        tooltip: 'Ver Perfil',
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white54, size: 28),
                        onPressed: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PantallaLogin()));
                        },
                        tooltip: 'Cerrar Sesión',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: pantallas[_indiceActual]),
        ],
      ),
    );
  }
}

// --- 1. DASHBOARD DINÁMICO CON MAPA EN TIEMPO REAL ---
class PantallaDashboard extends StatefulWidget {
  const PantallaDashboard({super.key});

  @override
  State<PantallaDashboard> createState() => _PantallaDashboardState();
}

class _PantallaDashboardState extends State<PantallaDashboard> {
  int _ordenesActivas = 0;
  int _tecnicosTotal = 0;
  List<dynamic> _tecnicosUbicaciones = [];
  bool _cargando = true;
  Timer? _timerUbicaciones;

  @override
  void initState() {
    super.initState();
    _cargarMetricasYMapa();
    // Temporizador para refrescar las posiciones GPS de los técnicos cada 5 segundos en tiempo real
    _timerUbicaciones = Timer.periodic(const Duration(seconds: 5), (timer) {
      _actualizarUbicacionesTecnicos();
    });
  }

  @override
  void dispose() {
    _timerUbicaciones?.cancel();
    super.dispose();
  }

  Future<void> _cargarMetricasYMapa() async {
    try {
      final resOrd = await http.get(Uri.parse('http://127.0.0.1:3000/api/ordenes'));
      final resTec = await http.get(Uri.parse('http://127.0.0.1:3000/api/tecnicos'));
      
      if (resOrd.statusCode == 200 && resTec.statusCode == 200) {
        final ordenes = json.decode(resOrd.body) as List;
        final tecnicos = json.decode(resTec.body) as List;
        setState(() {
          _ordenesActivas = ordenes.where((o) => o['estado'] == 'Pendiente').length;
          _tecnicosTotal = tecnicos.length;
          _tecnicosUbicaciones = tecnicos;
          _cargando = false;
        });
      }
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  Future<void> _actualizarUbicacionesTecnicos() async {
    try {
      final resTec = await http.get(Uri.parse('http://127.0.0.1:3000/api/tecnicos'));
      if (resTec.statusCode == 200 && mounted) {
        setState(() {
          _tecnicosUbicaciones = json.decode(resTec.body) as List;
        });
      }
    } catch (e) {
      // Silenciar errores de sondeo en segundo plano
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator(color: simaDarkGreen));
    
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Panel de Control', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: simaDarkGreen)),
          const SizedBox(height: 8),
          const Text('Resumen en tiempo real de operaciones y geolocalización de operarios.', style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 24),
          Row(
            children: [
              _tarjetaMetrica('Órdenes Activas', _ordenesActivas.toString(), Colors.orange),
              const SizedBox(width: 24),
              _tarjetaMetrica('Técnicos Registrados', _tecnicosTotal.toString(), simaLightGreen),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Mapa en Vivo - Técnicos en Campo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: simaDarkGreen)),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(-31.4201, -64.1888), // Coordenadas centrales por defecto (ej. Córdoba)
                    initialZoom: 13.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.sima.admin',
                    ),
                    MarkerLayer(
                      markers: _tecnicosUbicaciones.map((tecnico) {
                        // Lee lat y lng provistos por la base de datos (si no existen, usa centro por defecto o simulación)
                        double lat = tecnico['lat'] != null ? double.parse(tecnico['lat'].toString()) : -31.4201;
                        double lng = tecnico['lng'] != null ? double.parse(tecnico['lng'].toString()) : -64.1888;

                        return Marker(
                          point: LatLng(lat, lng),
                          width: 80,
                          height: 80,
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: simaDarkGreen, borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  tecnico['nombre'] ?? 'Técnico', 
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.location_on, color: Colors.red, size: 36),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaMetrica(String titulo, String valor, Color colorAcento) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 12),
            Text(valor, style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: colorAcento)),
          ],
        ),
      ),
    );
  }
}

// --- PANTALLA ÓRDENES DE TRABAJO ---
class PantallaOrdenes extends StatefulWidget {
  const PantallaOrdenes({super.key});

  @override
  State<PantallaOrdenes> createState() => _PantallaOrdenesState();
}

class _PantallaOrdenesState extends State<PantallaOrdenes> {
  List<dynamic> _ordenes = [];
  List<dynamic> _tecnicos = [];
  bool _cargando = true;

  // Controladores principales
  final TextEditingController _clienteController = TextEditingController();
  final TextEditingController _direccionController = TextEditingController();
  final TextEditingController _tareaController = TextEditingController();
  int? _tecnicoSeleccionado;

  // Controladores de Recurrencia (Estilo Google Calendar)
  bool _esRecurrente = false;
  final TextEditingController _recurrenciaValorCtrl = TextEditingController(text: '1');
  String _recurrenciaTipo = 'día'; // día, semana, mes
  final TextEditingController _horaCtrl = TextEditingController(text: '12:30');
  String _terminaCondicion = 'Nunca'; // Nunca, Fecha, Repeticiones
  DateTime? _terminaFecha;
  final TextEditingController _terminaRepeticionesCtrl = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    _obtenerDatos();
  }

  Future<void> _obtenerDatos() async {
    try {
      final resOrdenes = await http.get(Uri.parse('http://127.0.0.1:3000/api/ordenes'));
      final resTecnicos = await http.get(Uri.parse('http://127.0.0.1:3000/api/tecnicos'));

      if (resOrdenes.statusCode == 200 && resTecnicos.statusCode == 200) {
        setState(() {
          _ordenes = json.decode(resOrdenes.body);
          _tecnicos = json.decode(resTecnicos.body);
          _cargando = false;
        });
      }
    } catch (e) {
      print('Error al cargar: $e');
      setState(() => _cargando = false);
    }
  }

  Future<void> _guardarOrden({int? idAEditar}) async {
    if (_tecnicoSeleccionado == null || _clienteController.text.isEmpty || _direccionController.text.isEmpty) return;

    try {
      final url = idAEditar == null 
          ? 'http://127.0.0.1:3000/api/ordenes' 
          : 'http://127.0.0.1:3000/api/ordenes/$idAEditar';
          
      final metodo = idAEditar == null ? http.post : http.put;

      final respuesta = await metodo(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'tecnico_id': _tecnicoSeleccionado,
          'nombre_cliente': _clienteController.text,
          'direccion_trabajo': _direccionController.text,
          'descripcion_tarea': _tareaController.text,
          // Datos de recurrencia
          'es_recurrente': _esRecurrente,
          'recurrencia_valor': int.tryParse(_recurrenciaValorCtrl.text) ?? 1,
          'recurrencia_tipo': _recurrenciaTipo,
          'hora_ejecucion': _horaCtrl.text,
          'termina_condicion': _terminaCondicion,
          'termina_fecha': _terminaFecha?.toIso8601String().split('T')[0],
          'termina_repeticiones': int.tryParse(_terminaRepeticionesCtrl.text) ?? 30,
        }),
      );

      if (respuesta.statusCode == 200) {
        Navigator.of(context).pop();
        setState(() => _cargando = true);
        _obtenerDatos();
      }
    } catch (e) {
      print('Error al guardar: $e');
    }
  }

  Future<void> _eliminarOrden(int id) async {
    bool confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Orden'),
        content: const Text('¿Estás seguro de eliminar esta orden de trabajo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmar) {
      await http.delete(Uri.parse('http://127.0.0.1:3000/api/ordenes/$id'));
      _obtenerDatos();
    }
  }

  void _mostrarDialogoOrden({Map<String, dynamic>? ordenAEditar}) {
    // Si estamos editando, rellenamos los campos
    if (ordenAEditar != null) {
      _clienteController.text = ordenAEditar['cliente'] ?? '';
      _direccionController.text = ordenAEditar['direccion_trabajo'] ?? '';
      _tareaController.text = ordenAEditar['descripcion_tarea'] ?? '';
      _tecnicoSeleccionado = ordenAEditar['tecnico_id'];
    } else {
      _clienteController.clear();
      _direccionController.clear();
      _tareaController.clear();
      _tecnicoSeleccionado = null;
      _esRecurrente = false;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: Text(ordenAEditar == null ? 'Crear Nueva Orden' : 'Editar Orden', style: const TextStyle(color: simaDarkGreen, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(labelText: 'Técnico asignado'),
                        value: _tecnicoSeleccionado,
                        items: _tecnicos.map<DropdownMenuItem<int>>((t) => DropdownMenuItem(value: t['id'], child: Text(t['nombre']))).toList(),
                        onChanged: ordenAEditar == null ? (valor) => setStateModal(() => _tecnicoSeleccionado = valor) : null,
                      ),
                      TextField(controller: _clienteController, decoration: const InputDecoration(labelText: 'Empresa / Cliente'), enabled: ordenAEditar == null),
                      TextField(controller: _direccionController, decoration: const InputDecoration(labelText: 'Dirección exacta del trabajo')),
                      TextField(controller: _tareaController, decoration: const InputDecoration(labelText: 'Checklist / Descripción'), maxLines: 3),
                      const SizedBox(height: 20),
                      
                      // --- SECCIÓN GOOGLE CALENDAR ---
                      if (ordenAEditar == null) ...[
                        SwitchListTile(
                          title: const Text('Se repite', style: TextStyle(fontWeight: FontWeight.bold)),
                          activeColor: simaLightGreen,
                          value: _esRecurrente,
                          onChanged: (val) => setStateModal(() => _esRecurrente = val),
                        ),
                        if (_esRecurrente) Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Se repite cada', style: TextStyle(color: Colors.grey)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 60,
                                    child: TextField(controller: _recurrenciaValorCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center)
                                  ),
                                  const SizedBox(width: 16),
                                  DropdownButton<String>(
                                    value: _recurrenciaTipo,
                                    items: ['día', 'semana', 'mes', 'año'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                    onChanged: (v) => setStateModal(() => _recurrenciaTipo = v!),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextField(controller: _horaCtrl, decoration: const InputDecoration(labelText: 'Hora (Ej: 12:30)')),
                              const SizedBox(height: 16),
                              const Text('Termina', style: TextStyle(color: Colors.grey)),
                              RadioListTile(
                                title: const Text('Nunca'), value: 'Nunca', groupValue: _terminaCondicion,
                                onChanged: (v) => setStateModal(() => _terminaCondicion = v.toString()),
                              ),
                              RadioListTile(
                                title: Row(
                                  children: [
                                    const Text('El '),
                                    TextButton(
                                      onPressed: () async {
                                        DateTime? fecha = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2030));
                                        if (fecha != null) setStateModal(() { _terminaFecha = fecha; _terminaCondicion = 'Fecha'; });
                                      },
                                      child: Text(_terminaFecha == null ? 'Seleccionar fecha' : _terminaFecha.toString().split(' ')[0])
                                    )
                                  ],
                                ),
                                value: 'Fecha', groupValue: _terminaCondicion,
                                onChanged: (v) => setStateModal(() => _terminaCondicion = v.toString()),
                              ),
                              RadioListTile(
                                title: Row(
                                  children: [
                                    const Text('Después de '),
                                    SizedBox(width: 50, child: TextField(controller: _terminaRepeticionesCtrl, textAlign: TextAlign.center)),
                                    const Text(' repeticiones'),
                                  ],
                                ),
                                value: 'Repeticiones', groupValue: _terminaCondicion,
                                onChanged: (v) => setStateModal(() => _terminaCondicion = v.toString()),
                              ),
                            ],
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: simaLightGreen),
                  onPressed: () => _guardarOrden(idAEditar: ordenAEditar?['id']),
                  child: Text(ordenAEditar == null ? 'Asignar Trabajo' : 'Guardar Cambios', style: const TextStyle(color: simaDarkGreen, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Órdenes de Trabajo', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: simaDarkGreen)),
                  SizedBox(height: 4),
                  Text('Listado oficial con funciones de edición.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: simaLightGreen, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18)),
                icon: const Icon(Icons.add, color: simaDarkGreen),
                label: const Text('Crear Nueva Orden', style: TextStyle(color: simaDarkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: () => _mostrarDialogoOrden(),
              )
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(color: simaDarkGreen))
                  : _ordenes.isEmpty
                      ? const Center(child: Text('No hay órdenes registradas.'))
                      : SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: DataTable(
                            headingRowColor: MaterialStateProperty.all(simaBackground),
                            columns: const [
                              DataColumn(label: Text('ID', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Cliente', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Dirección', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Tarea', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Estado', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))), // NUEVA COLUMNA
                            ],
                            rows: _ordenes.map((orden) {
                              return DataRow(cells: [
                                DataCell(Text('#${orden['id']}')),
                                DataCell(Text(orden['cliente'] ?? 'Desconocido', style: const TextStyle(fontWeight: FontWeight.bold, color: simaDarkGreen))),
                                DataCell(Text(orden['direccion_trabajo'] ?? '')),
                                DataCell(Text(orden['descripcion_tarea'] ?? '')),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(color: orden['estado'] == 'Pendiente' ? Colors.orange.shade100 : simaLightGreen.withOpacity(0.3), borderRadius: BorderRadius.circular(20)),
                                    child: Text(orden['estado'], style: TextStyle(color: orden['estado'] == 'Pendiente' ? Colors.orange.shade900 : simaDarkGreen, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    children: [
                                      IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _mostrarDialogoOrden(ordenAEditar: orden)),
                                      IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _eliminarOrden(orden['id'])),
                                    ],
                                  )
                                ),
                              ]);
                            }).toList(),
                          ),
                        ),
            ),
          )
        ],
      ),
    );
  }
}

// --- 3. TÉCNICOS ---
class PantallaTecnicos extends StatefulWidget {
  const PantallaTecnicos({super.key});

  @override
  State<PantallaTecnicos> createState() => _PantallaTecnicosState();
}

class _PantallaTecnicosState extends State<PantallaTecnicos> {
  List<dynamic> _tecnicos = [];
  bool _cargando = true;

  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _obtenerTecnicos();
  }

  Future<void> _obtenerTecnicos() async {
    try {
      final respuesta = await http.get(Uri.parse('http://127.0.0.1:3000/api/tecnicos'));
      if (respuesta.statusCode == 200) {
        setState(() {
          _tecnicos = json.decode(respuesta.body);
          _cargando = false;
        });
      }
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  Future<void> _registrarTecnico() async {
    if (_nombreController.text.isEmpty || _emailController.text.isEmpty || _passwordController.text.isEmpty) return; 

    try {
      final respuesta = await http.post(
        Uri.parse('http://127.0.0.1:3000/api/tecnicos'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'nombre': _nombreController.text,
          'email': _emailController.text,
          'password': _passwordController.text,
        }),
      );

      if (respuesta.statusCode == 200) {
        _nombreController.clear();
        _emailController.clear();
        _passwordController.clear();
        Navigator.of(context).pop(); 
        setState(() => _cargando = true);
        _obtenerTecnicos(); 
      }
    } catch (e) {
      print('Error al registrar: $e');
    }
  }

  void _mostrarDialogoNuevoTecnico() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Registrar Nuevo Técnico', style: TextStyle(color: simaDarkGreen, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _nombreController, decoration: const InputDecoration(labelText: 'Nombre completo')),
              TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Correo electrónico')),
              TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Contraseña'), obscureText: true),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: simaLightGreen),
              onPressed: _registrarTecnico,
              child: const Text('Guardar', style: TextStyle(color: simaDarkGreen, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gestión de Técnicos', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: simaDarkGreen)),
                  SizedBox(height: 4),
                  Text('Administración de cuentas, correos y credenciales de la app.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: simaLightGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.person_add, color: simaDarkGreen),
                label: const Text('Registrar Técnico', style: TextStyle(color: simaDarkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: _mostrarDialogoNuevoTecnico, 
              )
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: _cargando
                  ? const Center(child: CircularProgressIndicator(color: simaDarkGreen))
                  : _tecnicos.isEmpty
                      ? const Center(child: Text('No hay técnicos registrados.', style: TextStyle(color: Colors.grey)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: _tecnicos.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final tecnico = _tecnicos[index];
                            return ListTile(
                              leading: const CircleAvatar(backgroundColor: simaDarkGreen, child: Icon(Icons.person, color: simaLightGreen)),
                              title: Text(tecnico['nombre'] ?? 'Sin Nombre', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(tecnico['email'] ?? 'Sin correo'),
                              trailing: OutlinedButton(
                                onPressed: () {},
                                child: const Text('Editar', style: TextStyle(color: simaDarkGreen)),
                              ),
                            );
                          },
                        ),
            ),
          )
        ],
      ),
    );
  }
}

// --- 5. INFORMES (DINÁMICO DESDE DISCO K) ---
class PantallaInformes extends StatefulWidget {
  const PantallaInformes({super.key});

  @override
  State<PantallaInformes> createState() => _PantallaInformesState();
}

class _PantallaInformesState extends State<PantallaInformes> {
  List<dynamic> _carpetas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _obtenerCarpetasDiscoK();
  }

  Future<void> _obtenerCarpetasDiscoK() async {
    try {
      final respuesta = await http.get(Uri.parse('http://127.0.0.1:3000/api/informes/carpetas'));
      if (respuesta.statusCode == 200) {
        setState(() {
          _carpetas = json.decode(respuesta.body);
          _cargando = false;
        });
      }
    } catch (e) {
      print('Error al leer carpetas: $e');
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Informes (Disco K)', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: simaDarkGreen)),
          const SizedBox(height: 8),
          const Text('Lectura en vivo de las carpetas alojadas en el servidor.', style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 32),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: simaDarkGreen))
                : _carpetas.isEmpty
                    ? const Center(child: Text('No se detectaron carpetas en el Disco K de la empresa.', style: TextStyle(color: Colors.grey, fontSize: 18)))
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                        ),
                        itemCount: _carpetas.length,
                        itemBuilder: (context, index) {
                          final carpeta = _carpetas[index];
                          return _carpetaEmpresa(carpeta['empresa'], '${carpeta['cantidad']} informes');
                        },
                      ),
          )
        ],
      ),
    );
  }

  Widget _carpetaEmpresa(String empresa, String subtitulo) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder, size: 60, color: Colors.amber),
          const SizedBox(height: 12),
          Text(empresa, style: const TextStyle(fontWeight: FontWeight.bold, color: simaDarkGreen), textAlign: TextAlign.center),
          Text(subtitulo, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

// --- 5. ANÁLISIS ---
class PantallaAnalisis extends StatelessWidget {
  const PantallaAnalisis({super.key});

  @override
  Widget build(BuildContext context) {
    // ...
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Análisis y Estadísticas', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: simaDarkGreen)),
          const SizedBox(height: 8),
          const Text('Módulo en construcción para gráficos y promedios de rendimiento.', style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 32),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.insert_chart, size: 100, color: simaLightGreen),
                    SizedBox(height: 16),
                    Text('Espacio reservado para KPI', style: TextStyle(color: Colors.grey, fontSize: 18)),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}