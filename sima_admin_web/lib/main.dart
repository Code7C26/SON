import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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
        fontFamily: 'TuFuente', // Tipografía unificada
      ),
      home: const LayoutAdministrador(),
    );
  }
}

class LayoutAdministrador extends StatefulWidget {
  const LayoutAdministrador({super.key});

  @override
  State<LayoutAdministrador> createState() => _LayoutAdministradorState();
}

class _LayoutAdministradorState extends State<LayoutAdministrador> {
  int _indiceActual = 0;

  final List<Widget> _pantallas = [
    const PantallaDashboard(),
    const PantallaMapa(),
    const PantallaOrdenes(),
    const PantallaTecnicos(),
    const PantallaInformes(),
    const PantallaAnalisis(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _indiceActual,
            onDestinationSelected: (int index) {
              setState(() {
                _indiceActual = index;
              });
            },
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
                'assets/images/LOGO2.png',
                height: 80,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white, size: 50),
              ),
            ),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.dashboard), label: Text('Panel de Control')),
              NavigationRailDestination(icon: Icon(Icons.map), label: Text('Mapa en vivo')),
              NavigationRailDestination(icon: Icon(Icons.assignment), label: Text('Órdenes de Trabajo')),
              NavigationRailDestination(icon: Icon(Icons.people), label: Text('Técnicos')),
              NavigationRailDestination(icon: Icon(Icons.folder), label: Text('Informes')),
              NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('Análisis')),
            ],
          ),
          Expanded(child: _pantallas[_indiceActual]),
        ],
      ),
    );
  }
}

// --- 1. DASHBOARD ---
class PantallaDashboard extends StatelessWidget {
  const PantallaDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Panel de Control', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: simaDarkGreen)),
          const SizedBox(height: 8),
          const Text('Resumen en tiempo real de operaciones.', style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 32),
          Row(
            children: [
              _tarjetaMetricaWeb('Órdenes Activas', '12', Colors.orange),
              const SizedBox(width: 24),
              _tarjetaMetricaWeb('Completadas Hoy', '4', Colors.blue),
              const SizedBox(width: 24),
              _tarjetaMetricaWeb('Técnicos en Calle', '3', simaLightGreen),
            ],
          ),
          const SizedBox(height: 32),
          const Text('Últimas Órdenes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: simaDarkGreen)),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: const Center(child: Text('Tabla de órdenes recientes', style: TextStyle(color: Colors.grey))),
            ),
          )
        ],
      ),
    );
  }

  Widget _tarjetaMetricaWeb(String titulo, String valor, Color colorAcento) {
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

// --- 2. MAPA ---
class PantallaMapa extends StatelessWidget {
  const PantallaMapa({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mapa de Técnicos', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: simaDarkGreen)),
          const SizedBox(height: 8),
          const Text('Seguimiento GPS en tiempo real.', style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(12)),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Aquí se integrará Google Maps o Flutter Map', style: TextStyle(color: Colors.grey, fontSize: 18)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

// --- 3. ÓRDENES DE TRABAJO (CONECTADA A BASE DE DATOS) ---
class PantallaOrdenes extends StatefulWidget {
  const PantallaOrdenes({super.key});

  @override
  State<PantallaOrdenes> createState() => _PantallaOrdenesState();
}

class _PantallaOrdenesState extends State<PantallaOrdenes> {
  List<dynamic> _ordenes = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _obtenerOrdenes();
  }

  Future<void> _obtenerOrdenes() async {
    try {
      final respuesta = await http.get(Uri.parse('http://localhost:3000/api/ordenes'));
      if (respuesta.statusCode == 200) {
        setState(() {
          _ordenes = json.decode(respuesta.body);
          _cargando = false;
        });
      }
    } catch (e) {
      print('Error de conexión: $e');
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Órdenes de Trabajo', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: simaDarkGreen)),
                  SizedBox(height: 4),
                  Text('Listado oficial desde PostgreSQL.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: simaLightGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add, color: simaDarkGreen),
                label: const Text('Crear Nueva Orden', style: TextStyle(color: simaDarkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: () {
                  // Futuro formulario
                },
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
                      ? const Center(child: Text('No hay órdenes registradas.', style: TextStyle(color: Colors.grey)))
                      : SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(simaBackground),
                            columns: const [
                              DataColumn(label: Text('ID', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Cliente', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Dirección', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Tarea', style: TextStyle(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Estado', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                            rows: _ordenes.map((orden) {
                              return DataRow(cells: [
                                DataCell(Text('#${orden['id']}')),
                                DataCell(Text(orden['cliente'], style: const TextStyle(fontWeight: FontWeight.bold, color: simaDarkGreen))),
                                DataCell(Text(orden['direccion'])),
                                DataCell(Text(orden['tarea'])),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: orden['estado'] == 'Pendiente' ? Colors.orange.shade100 : simaLightGreen.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(orden['estado'], style: TextStyle(color: orden['estado'] == 'Pendiente' ? Colors.orange.shade900 : simaDarkGreen, fontWeight: FontWeight.bold)),
                                  ),
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

// --- 4. TÉCNICOS (CONECTADA A BASE DE DATOS) ---
class PantallaTecnicos extends StatefulWidget {
  const PantallaTecnicos({super.key});

  @override
  State<PantallaTecnicos> createState() => _PantallaTecnicosState();
}

class _PantallaTecnicosState extends State<PantallaTecnicos> {
  List<dynamic> _tecnicos = [];
  bool _cargando = true;

  // Controladores para leer lo que el administrador escribe
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _obtenerTecnicos();
  }

  // Leer técnicos desde Node.js
  Future<void> _obtenerTecnicos() async {
    try {
      final respuesta = await http.get(Uri.parse('http://localhost:3000/api/tecnicos'));
      if (respuesta.statusCode == 200) {
        setState(() {
          _tecnicos = json.decode(respuesta.body);
          _cargando = false;
        });
      }
    } catch (e) {
      print('Error de conexión: $e');
      setState(() => _cargando = false);
    }
  }

  // Enviar nuevo técnico a Node.js
  Future<void> _registrarTecnico() async {
    if (_nombreController.text.isEmpty || _emailController.text.isEmpty || _passwordController.text.isEmpty) {
      return; // Validación simple para no enviar campos vacíos
    }

    try {
      final respuesta = await http.post(
        Uri.parse('http://localhost:3000/api/tecnicos'),
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
        Navigator.of(context).pop(); // Cerrar el cuadro de diálogo
        _obtenerTecnicos(); // Refrescar la lista automáticamente
      }
    } catch (e) {
      print('Error al registrar: $e');
    }
  }

  // Dibujar el cuadro de diálogo emergente
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
              TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Correo electrónico (para la app)')),
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
                  Text('Administración de cuentas, correos y contraseñas de la app.', style: TextStyle(color: Colors.grey, fontSize: 16)),
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
                onPressed: _mostrarDialogoNuevoTecnico, // Abre el modal
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
                              title: Text(tecnico['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(tecnico['email']),
                              trailing: OutlinedButton(
                                onPressed: () {
                                  // Próximamente: Editar o cambiar clave
                                },
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
// --- 5. INFORMES ---
class PantallaInformes extends StatelessWidget {
  const PantallaInformes({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Informes', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: simaDarkGreen)),
          const SizedBox(height: 8),
          const Text('PDFs organizados por empresa cliente.', style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.count(
              crossAxisCount: 5,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              children: [
                _carpetaEmpresa('Clínica del Sol', '12 informes'),
                _carpetaEmpresa('Empresa Norte', '8 informes'),
                _carpetaEmpresa('Hotel Central', '25 informes'),
                _carpetaEmpresa('Supermercados Plus', '3 informes'),
              ],
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

// --- 6. ANÁLISIS ---
class PantallaAnalisis extends StatelessWidget {
  const PantallaAnalisis({super.key});

  @override
  Widget build(BuildContext context) {
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