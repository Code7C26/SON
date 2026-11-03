import 'dart:async';
import 'package:flutter/material.dart';
import 'package:son_admin/config/api_config.dart';
import 'package:son_admin/pantallas/analisis.dart';
import 'package:son_admin/pantallas/clientes.dart';
import 'package:son_admin/pantallas/dashboard.dart';
import 'package:son_admin/pantallas/precios.dart';
import 'package:son_admin/pantallas/presupuestos.dart';
import 'package:son_admin/services/abrir_informe.dart';
import 'package:son_admin/services/api.dart';
import 'package:son_admin/services/almacen_sesion.dart';
import 'package:son_admin/services/sesion.dart';
import 'package:son_admin/theme/tema.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';

void main() {
  final guardado = leerAlmacen('son_admin_tema');
  if (guardado == 'claro') controlTema.establecer(true, avisar: false);
  controlTema.alGuardar = (claro) => escribirAlmacen('son_admin_tema', claro ? 'claro' : 'oscuro');
  runApp(const SonAdmin());
}

class SonAdmin extends StatelessWidget {
  const SonAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controlTema,
      builder: (context, _) => MaterialApp(
        title: 'SON Admin',
        debugShowCheckedModeBanner: false,
        theme: temaCon(paletaClara, Brightness.light),
        darkTheme: temaCon(paletaOscura, Brightness.dark),
        themeMode: controlTema.modo,
        builder: (context, child) => RepintadoTema(child: child ?? const SizedBox.shrink()),
        home: const PantallaInicio(),
      ),
    );
  }
}

// --- PANTALLA DE INICIO: si ya había una sesión guardada (por ejemplo al refrescar la página), entra directo ---
class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key});

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  @override
  void initState() {
    super.initState();
    _decidir();
  }

  Future<void> _decidir() async {
    await Future<void>.delayed(Duration.zero); // no navegar mientras se está armando la pantalla
    final admin = SesionAdmin.restaurar();
    Widget destino = const PantallaLogin();
    if (admin != null) {
      try {
        // Se confirma con el servidor que la sesión siga vigente (vence a las 12 horas).
        // Sirve para cualquier usuario del panel (administración o comercial) y trae sus datos al día.
        final respuesta = await apiGet('/api/admin/yo').timeout(const Duration(seconds: 10));
        if (respuesta.statusCode == 401 || respuesta.statusCode == 403) {
          SesionAdmin.cerrar();
        } else if (respuesta.statusCode == 200) {
          final actual = Map<String, dynamic>.from(json.decode(respuesta.body) as Map);
          SesionAdmin.guardarAdmin(actual);
          destino = LayoutAdministrador(adminData: actual);
        } else {
          destino = LayoutAdministrador(adminData: admin);
        }
      } catch (_) {
        // Sin conexión por un momento: se entra igual y las pantallas avisan si no pueden cargar.
        destino = LayoutAdministrador(adminData: admin);
      }
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => destino));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo_son_icono.png', height: 70),
            const SizedBox(height: 28),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          ],
        ),
      ),
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
  bool _verPassword = false;
  String _mensajeError = '';

  Future<void> _iniciarSesion() async {
    if (_cargando) return;
    setState(() { _cargando = true; _mensajeError = ''; });

    try {
      final respuesta = await http.post(
        Uri.parse('$apiBaseUrl/api/admin/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
        }),
      );

      if (respuesta.statusCode == 200) {
        final datosAdmin = json.decode(respuesta.body);
        SesionAdmin.guardar(datosAdmin['token'], Map<String, dynamic>.from(datosAdmin));
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
            padding: const EdgeInsets.all(24),
            child: Container(
              width: 420,
              padding: const EdgeInsets.fromLTRB(36, 36, 36, 32),
              decoration: BoxDecoration(
                color: sonTarjeta.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sonBorde),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 40, offset: const Offset(0, 18))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Image.asset('assets/images/logo_son_icono.png', height: 62)),
                  const SizedBox(height: 28),
                  Text('Acceso administrativo', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: sonTexto)),
                  const SizedBox(height: 26),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline)),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _verPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                        icon: Icon(_verPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _verPassword = !_verPassword),
                      ),
                    ),
                    obscureText: !_verPassword,
                    onSubmitted: (_) => _iniciarSesion(),
                  ),
                  if (_mensajeError.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: sonRojo.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: sonRojo.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: sonRojo, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_mensajeError, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600, fontSize: 13))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _cargando ? null : _iniciarSesion,
                      child: _cargando
                          ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: sonDarkGreen))
                          : const Text('Ingresar al sistema', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text('Seguridad, higiene y medio ambiente', textAlign: TextAlign.center, style: TextStyle(color: sonTextoSuave, fontSize: 12)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: controlTema.alternar,
                    icon: Icon(controlTema.claro ? Icons.dark_mode_outlined : Icons.light_mode_outlined, color: sonTextoSuave),
                    label: Text(controlTema.claro ? 'Tema oscuro' : 'Tema claro', style: TextStyle(color: sonTextoSuave)),
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

// --- LAYOUT: menú lateral + pantalla elegida ---
class LayoutAdministrador extends StatefulWidget {
  final Map<String, dynamic> adminData;
  const LayoutAdministrador({super.key, required this.adminData});

  @override
  State<LayoutAdministrador> createState() => _LayoutAdministradorState();
}

/// Una opción del menú lateral: qué pantalla abre, en qué grupo va y quién la puede ver.
class _OpcionMenu {
  final String id;
  final IconData icono;
  final String texto;
  final String grupo;
  final Set<String> roles;
  const _OpcionMenu(this.id, this.icono, this.texto, this.grupo, this.roles);
}

class _LayoutAdministradorState extends State<LayoutAdministrador> {
  // El área técnica la usan los dos tipos de usuario; el área comercial y los usuarios, solo Comercial
  // (la dueña de la empresa). El servidor aplica las mismas reglas: esconder el botón no es la protección.
  static const Set<String> _todos = {'admin', 'comercial'};
  static const Set<String> _soloComercial = {'comercial'};

  static const List<_OpcionMenu> _opciones = [
    _OpcionMenu('panel', Icons.dashboard_outlined, 'Panel de Control', 'Operación', _todos),
    _OpcionMenu('ordenes', Icons.assignment_outlined, 'Órdenes de Trabajo', 'Operación', _todos),
    _OpcionMenu('tecnicos', Icons.groups_outlined, 'Técnicos', 'Operación', _todos),
    _OpcionMenu('informes', Icons.folder_outlined, 'Informes', 'Operación', _todos),
    _OpcionMenu('analisis', Icons.bar_chart_rounded, 'Análisis', 'Operación', _todos),
    _OpcionMenu('presupuestos', Icons.receipt_long_outlined, 'Presupuestos', 'Comercial', _soloComercial),
    _OpcionMenu('precios', Icons.sell_outlined, 'Precios', 'Comercial', _soloComercial),
    _OpcionMenu('clientes', Icons.business_center_outlined, 'Clientes', 'Comercial', _soloComercial),
    _OpcionMenu('usuarios', Icons.admin_panel_settings_outlined, 'Usuarios', 'Sistema', _soloComercial),
  ];

  late Map<String, dynamic> _adminActual;
  late String _pantallaActual;
  int _nuevas = 0;
  Timer? _reloj;

  /// Tipo de usuario: 'comercial' (la dueña: ve todo) o 'admin' (Administración: solo el área técnica).
  /// Si no se sabe cuál es, se asume el de menor acceso.
  String get _rol => (_adminActual['rol'] ?? 'admin').toString();

  bool get _esComercial => _rol == 'comercial';

  List<_OpcionMenu> get _visibles => _opciones.where((o) => o.roles.contains(_rol)).toList();

  @override
  void initState() {
    super.initState();
    _adminActual = widget.adminData;
    var guardada = SesionAdmin.pantallaGuardada();
    // Las notas de los técnicos ahora viven adentro de Presupuestos.
    if (guardada == 'por_presupuestar') guardada = 'presupuestos';
    final visibles = _visibles;
    _pantallaActual = visibles.firstWhere((o) => o.id == guardada, orElse: () => visibles.first).id;
    // El número de notas nuevas del menú es solo para Comercial (Administración no ve esas notas).
    if (_esComercial) {
      _cargarResumen();
      _reloj = Timer.periodic(const Duration(seconds: 60), (_) => _cargarResumen());
    }
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  /// Cuántas notas de técnicos están sin atender (el menú muestra el número).
  Future<void> _cargarResumen() async {
    if (!_esComercial) return;
    try {
      final respuesta = await apiGet('/api/solicitudes-presupuesto/resumen');
      if (!mounted || respuesta.statusCode != 200) return;
      final nuevas = ((json.decode(respuesta.body) as Map)['nuevas'] as num?)?.toInt() ?? 0;
      if (nuevas != _nuevas) setState(() => _nuevas = nuevas);
    } catch (_) {}
  }

  void _mostrarPerfil() {
    final TextEditingController nombreController = TextEditingController(text: _adminActual['nombre']);
    final TextEditingController emailController = TextEditingController(text: _adminActual['email']);
    final TextEditingController passwordController = TextEditingController();

    String? error;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialogo) {
          return AlertDialog(
            title: const Text('Mi perfil'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nombreController,
                    decoration: const InputDecoration(labelText: 'Nombre completo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo electrónico (con este ingresás al panel)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    decoration: const InputDecoration(labelText: 'Nueva contraseña (dejar en blanco para no cambiar)'),
                    obscureText: true,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancelar', style: TextStyle(color: sonTextoSuave)),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final res = await apiSend(
                      'PUT',
                      '/api/admin/actualizar/${_adminActual['id']}',
                      json.encode({
                        'nombre': nombreController.text,
                        'email': emailController.text,
                        if (passwordController.text.isNotEmpty) 'password': passwordController.text,
                      }),
                    );

                    if (res.statusCode == 200) {
                      setState(() {
                        _adminActual = json.decode(res.body);
                      });
                      SesionAdmin.guardarAdmin(_adminActual);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Perfil actualizado con éxito')),
                      );
                    } else {
                      setStateDialogo(() => error = mensajeError(res, 'No se pudo actualizar el perfil'));
                    }
                  } catch (e) {
                    setStateDialogo(() => error = mensajeSinConexion);
                  }
                },
                child: const Text('Guardar cambios'),
              ),
            ],
          );
        });
      },
    );
  }

  void _cerrarSesion() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) {
      SesionAdmin.cerrar();
      return const PantallaLogin();
    }));
  }

  Widget _pantalla(String id) {
    switch (id) {
      case 'panel':
        return PantallaDashboard(nombreAdmin: (_adminActual['nombre'] ?? '').toString());
      case 'ordenes':
        return const PantallaOrdenes();
      case 'tecnicos':
        return const PantallaTecnicos();
      case 'informes':
        return const PantallaInformes();
      case 'analisis':
        return const PantallaAnalisis();
      case 'presupuestos':
        return PantallaPresupuestos(onCambioNotas: _cargarResumen);
      case 'precios':
        return const PantallaPrecios();
      case 'clientes':
        return const PantallaClientes();
      case 'usuarios':
        return PantallaAdministradores(adminActualId: (_adminActual['id'] as num).toInt());
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, caja) {
        final compacto = caja.maxWidth < 900; // en pantallas angostas el menú muestra solo los íconos
        return Row(
          children: [
            _menuLateral(compacto),
            Expanded(child: _pantalla(_pantallaActual)),
          ],
        );
      }),
    );
  }

  /// Las opciones que puede ver este usuario, agrupadas (Operación / Comercial / Sistema).
  List<Widget> _itemsDelMenu(bool compacto) {
    final items = <Widget>[];
    String? grupoAnterior;
    for (final opcion in _visibles) {
      if (opcion.grupo != grupoAnterior) {
        final primero = grupoAnterior == null;
        items.add(
          compacto
              ? Padding(padding: EdgeInsets.symmetric(vertical: primero ? 2 : 8), child: primero ? null : const Divider(height: 1))
              : Padding(
                  padding: EdgeInsets.fromLTRB(14, primero ? 2 : 20, 14, 6),
                  child: Text(
                    opcion.grupo.toUpperCase(),
                    style: TextStyle(color: sonTextoSuave, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                ),
        );
        grupoAnterior = opcion.grupo;
      }
      items.add(
        _ItemMenu(
          icono: opcion.icono,
          texto: opcion.texto,
          seleccionado: opcion.id == _pantallaActual,
          compacto: compacto,
          insignia: opcion.id == 'presupuestos' ? _nuevas : 0,
          alTocar: () {
            SesionAdmin.guardarPantalla(opcion.id);
            setState(() => _pantallaActual = opcion.id);
          },
        ),
      );
    }
    return items;
  }

  Widget _menuLateral(bool compacto) {
    final nombre = (_adminActual['nombre'] ?? 'Administrador').toString();
    final email = (_adminActual['email'] ?? '').toString();

    return Container(
      width: compacto ? 78 : 262,
      decoration: BoxDecoration(color: sonPanel, border: Border(right: BorderSide(color: sonBorde))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 28, 12, 26),
            child: Center(child: Image.asset('assets/images/logo_son_icono.png', height: compacto ? 42 : 50)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: compacto ? 10 : 14),
              children: _itemsDelMenu(compacto),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(compacto ? 10 : 14),
            child: compacto
                ? Column(
                    children: [
                      const BotonTema(),
                      IconButton(tooltip: 'Ver perfil', onPressed: _mostrarPerfil, icon: Icon(Icons.account_circle_outlined, color: sonLightGreen)),
                      IconButton(tooltip: 'Cerrar sesión', onPressed: _cerrarSesion, icon: Icon(Icons.logout, color: sonTextoSuave)),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _mostrarPerfil,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: sonTarjetaAlta,
                                  child: Text(nombre.isEmpty ? '?' : nombre[0].toUpperCase(), style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600, fontSize: 13)),
                                      Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTextoSuave, fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const BotonTema(),
                      IconButton(tooltip: 'Cerrar sesión', onPressed: _cerrarSesion, icon: Icon(Icons.logout, color: sonTextoSuave, size: 22)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ItemMenu extends StatefulWidget {
  final IconData icono;
  final String texto;
  final bool seleccionado;
  final bool compacto;
  final VoidCallback alTocar;

  /// Número que se muestra al lado (por ejemplo, notas nuevas sin atender). Con 0 no se muestra nada.
  final int insignia;
  const _ItemMenu({required this.icono, required this.texto, required this.seleccionado, required this.compacto, required this.alTocar, this.insignia = 0});

  @override
  State<_ItemMenu> createState() => _ItemMenuState();
}

class _ItemMenuState extends State<_ItemMenu> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final activo = widget.seleccionado;
    final color = activo ? sonLightGreen : sonTextoSuave;
    final contenido = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: EdgeInsets.symmetric(horizontal: widget.compacto ? 0 : 14, vertical: 13),
      decoration: BoxDecoration(
        color: activo ? sonLightGreen.withValues(alpha: 0.12) : (_encima ? sonTarjeta : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: activo ? sonLightGreen.withValues(alpha: 0.25) : Colors.transparent),
      ),
      child: Row(
        mainAxisAlignment: widget.compacto ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          // Con el menú angosto el número va como una chapita sobre el ícono.
          widget.compacto && widget.insignia > 0
              ? Badge(label: Text(widget.insignia > 99 ? '99+' : '${widget.insignia}'), backgroundColor: sonAmbar, textColor: sonDarkGreen, child: Icon(widget.icono, color: color, size: 22))
              : Icon(widget.icono, color: color, size: 22),
          if (!widget.compacto) ...[
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                widget.texto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: activo ? sonTexto : sonTextoSuave, fontWeight: activo ? FontWeight.bold : FontWeight.w500, fontSize: 14),
              ),
            ),
            if (widget.insignia > 0)
              Container(
                key: const Key('insignia_menu'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: sonAmbar, borderRadius: BorderRadius.circular(20)),
                child: Text(widget.insignia > 99 ? '99+' : '${widget.insignia}', style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
          ],
        ],
      ),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        onTap: widget.alTocar,
        behavior: HitTestBehavior.opaque,
        child: widget.compacto ? Tooltip(message: widget.texto, child: contenido) : contenido,
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

Color _colorEstado(dynamic estado) {
  switch (estado) {
    case 'Pendiente': return sonAmbar;
    case 'En progreso': return sonAzul;
    case 'Completada': return sonLightGreen;
    case 'Por asignar': return sonTexto;
    default: return sonTextoSuave;
  }
}

DateTime _lunesDe(DateTime fecha) {
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  return dia.subtract(Duration(days: dia.weekday - 1));
}

DateTime? _fechaDeOrden(dynamic orden) {
  final texto = '${orden['fecha_dia'] ?? orden['fecha_asignada'] ?? ''}';
  final match = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(texto);
  if (match == null) return null;
  return DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!));
}

class _PantallaOrdenesState extends State<PantallaOrdenes> {
  List<dynamic> _ordenes = [];
  List<dynamic> _tecnicos = [];
  bool _cargando = true;

  // Controladores principales
  final TextEditingController _clienteController = TextEditingController();
  final FocusNode _clienteFocus = FocusNode();
  List<String> _clientesConocidos = []; // carpetas del disco de la empresa + clientes de órdenes anteriores
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
  DateTime _fechaOrden = DateTime.now();
  final TextEditingController _puntosCtrl = TextEditingController();
  final TextEditingController _emailClienteCtrl = TextEditingController();
  final TextEditingController _whatsappCtrl = TextEditingController();
  String _vista = 'semana';
  DateTime _lunes = DateTime.now();

  @override
  void initState() {
    super.initState();
    _lunes = _lunesDe(DateTime.now());
    _obtenerDatos();
  }

  Future<void> _obtenerDatos() async {
    try {
      final resOrdenes = await apiGet('/api/ordenes');
      final resTecnicos = await apiGet('/api/tecnicos');

      if (resOrdenes.statusCode == 200 && resTecnicos.statusCode == 200) {
        setState(() {
          _ordenes = json.decode(resOrdenes.body);
          _tecnicos = json.decode(resTecnicos.body);
          _cargando = false;
        });
        _cargarClientes();
      }
    } catch (e) {
      print('Error al cargar: $e');
      setState(() => _cargando = false);
    }
  }

  /// Arma la lista de clientes para sugerir: las carpetas que ya existen en el disco de la empresa
  /// y los clientes de órdenes anteriores. Si el disco no responde, se usan solo las órdenes.
  Future<void> _cargarClientes() async {
    final nombres = <String>[];
    for (final orden in _ordenes) {
      final cliente = (orden['cliente'] ?? '').toString().trim();
      if (cliente.isNotEmpty) nombres.add(cliente);
    }
    // Los clientes que cargó el área comercial también se pueden elegir al crear una orden.
    // Se piden solo los nombres: Administración no ve los datos de contacto de las fichas.
    try {
      final respuesta = await apiGet('/api/clientes/nombres');
      if (respuesta.statusCode == 200) {
        for (final cliente in json.decode(respuesta.body)) {
          final nombre = (cliente['razon_social'] ?? '').toString().trim();
          if (nombre.isNotEmpty) nombres.add(nombre);
        }
      }
    } catch (_) {}
    try {
      final respuesta = await apiGet('/api/informes/carpetas');
      if (respuesta.statusCode == 200) {
        for (final carpeta in json.decode(respuesta.body)) {
          final empresa = (carpeta['empresa'] ?? '').toString().trim();
          if (empresa.isNotEmpty) nombres.add(empresa);
        }
      }
    } catch (_) {}
    final vistos = <String>{};
    final unicos = <String>[];
    for (final nombre in nombres) {
      if (vistos.add(_sinAcentos(nombre))) unicos.add(nombre);
    }
    unicos.sort((a, b) => _sinAcentos(a).compareTo(_sinAcentos(b)));
    if (mounted) setState(() => _clientesConocidos = unicos);
  }

  String _sinAcentos(String texto) {
    const con = 'áàäâéèëêíìïîóòöôúùüûñÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑ';
    const sin = 'aaaaeeeeiiiioooouuuunAAAAEEEEIIIIOOOOUUUUN';
    var resultado = texto.toLowerCase().replaceAll('_', ' ').trim();
    for (var i = 0; i < con.length; i++) {
      resultado = resultado.replaceAll(con[i].toLowerCase(), sin[i].toLowerCase());
    }
    return resultado;
  }

  /// Campo "Empresa / Cliente": sugiere los clientes conocidos mientras se escribe,
  /// pero deja escribir cualquier nombre nuevo.
  Widget _campoCliente() {
    return LayoutBuilder(
      builder: (context, restricciones) => RawAutocomplete<String>(
        textEditingController: _clienteController,
        focusNode: _clienteFocus,
        optionsBuilder: (valor) {
          final buscado = _sinAcentos(valor.text);
          if (buscado.isEmpty) return _clientesConocidos;
          return _clientesConocidos.where((nombre) => _sinAcentos(nombre).contains(buscado));
        },
        onSelected: (_) => FocusScope.of(context).nextFocus(),
        fieldViewBuilder: (context, controlador, foco, alEnviar) => TextField(
          controller: controlador,
          focusNode: foco,
          decoration: InputDecoration(
            labelText: 'Empresa / Cliente',
            suffixIcon: _clientesConocidos.isEmpty ? null : const Icon(Icons.arrow_drop_down),
          ),
        ),
        optionsViewBuilder: (context, alElegir, opciones) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 240, maxWidth: restricciones.maxWidth),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opciones.length,
                itemBuilder: (context, indice) {
                  final opcion = opciones.elementAt(indice);
                  return ListTile(dense: true, title: Text(opcion), onTap: () => alElegir(opcion));
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _guardarOrden({int? idAEditar}) async {
    if (_tecnicoSeleccionado == null || _clienteController.text.isEmpty || _direccionController.text.isEmpty) return;

    try {
      final respuesta = await apiSend(
        idAEditar == null ? 'POST' : 'PUT',
        idAEditar == null ? '/api/ordenes' : '/api/ordenes/$idAEditar',
        json.encode({
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
          'fecha_asignada': '${_fechaOrden.year.toString().padLeft(4, '0')}-${_fechaOrden.month.toString().padLeft(2, '0')}-${_fechaOrden.day.toString().padLeft(2, '0')}',
          'puntos': _puntosCtrl.text.split('\n').map((linea) => linea.trim()).where((linea) => linea.isNotEmpty).toList(),
          'email_cliente': _emailClienteCtrl.text.trim(),
          'whatsapp_cliente': _whatsappCtrl.text.trim(),
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
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Eliminar', style: TextStyle(color: sonRojo))),
        ],
      ),
    );

    if (confirmar) {
      await apiSend('DELETE', '/api/ordenes/$id');
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
      _esRecurrente = ordenAEditar['es_recurrente'] == true;
      _recurrenciaValorCtrl.text = '${ordenAEditar['recurrencia_valor'] ?? 1}';
      _recurrenciaTipo = ordenAEditar['recurrencia_tipo'] ?? 'día';
      _horaCtrl.text = ordenAEditar['hora_ejecucion'] ?? '12:30';
      _terminaCondicion = ordenAEditar['termina_condicion'] ?? 'Nunca';
      _terminaRepeticionesCtrl.text = '${ordenAEditar['termina_repeticiones'] ?? 30}';
      var hora = '${ordenAEditar['hora_ejecucion'] ?? '12:30'}';
      if (hora.length > 5) hora = hora.substring(0, 5);
      _horaCtrl.text = hora;
      _fechaOrden = _fechaDeOrden(ordenAEditar) ?? DateTime.now();
      final puntos = ordenAEditar['puntos'];
      _puntosCtrl.text = puntos is List ? puntos.map((punto) => '$punto').join('\n') : '';
      _emailClienteCtrl.text = '${ordenAEditar['email_cliente'] ?? ''}';
      _whatsappCtrl.text = '${ordenAEditar['whatsapp_cliente'] ?? ''}';
    } else {
      _clienteController.clear();
      _direccionController.clear();
      _tareaController.clear();
      _tecnicoSeleccionado = null;
      _esRecurrente = false;
      _fechaOrden = DateTime.now();
      _puntosCtrl.clear();
      _emailClienteCtrl.clear();
      _whatsappCtrl.clear();
      _horaCtrl.text = '12:30';
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: Text(ordenAEditar == null ? 'Crear Nueva Orden' : 'Editar Orden', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
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
                        onChanged: (valor) => setStateModal(() => _tecnicoSeleccionado = valor),
                      ),
                      const SizedBox(height: 12),
                      _campoCliente(),
                      const SizedBox(height: 12),
                      TextField(controller: _direccionController, decoration: const InputDecoration(labelText: 'Dirección exacta del trabajo')),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _emailClienteCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo del cliente'))),
                          const SizedBox(width: 12),
                          Expanded(child: TextField(controller: _whatsappCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'WhatsApp'))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final elegida = await showDatePicker(
                                  context: context,
                                  initialDate: _fechaOrden,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (elegida != null) setStateModal(() => _fechaOrden = elegida);
                              },
                              icon: const Icon(Icons.event_outlined),
                              label: Text('${_fechaOrden.day}/${_fechaOrden.month}/${_fechaOrden.year}'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(width: 110, child: TextField(controller: _horaCtrl, decoration: const InputDecoration(labelText: 'Hora'))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _puntosCtrl,
                        decoration: const InputDecoration(labelText: 'Checklist de la visita'),
                        maxLines: 5,
                      ),
                      const SizedBox(height: 12),
                      TextField(controller: _tareaController, decoration: const InputDecoration(labelText: 'Notas de la visita'), maxLines: 3),
                      const SizedBox(height: 20),
                      
                      // --- SECCIÓN GOOGLE CALENDAR ---
                      if (true) ...[
                        SwitchListTile(
                          title: const Text('Se repite', style: TextStyle(fontWeight: FontWeight.bold)),
                          activeColor: sonLightGreen,
                          value: _esRecurrente,
                          onChanged: (val) => setStateModal(() => _esRecurrente = val),
                        ),
                        if (_esRecurrente) Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: sonTarjetaAlta, borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Se repite cada', style: TextStyle(color: sonTextoSuave)),
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
                              Text('Termina', style: TextStyle(color: sonTextoSuave)),
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
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar', style: TextStyle(color: sonTextoSuave))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: sonLightGreen),
                  onPressed: () => _guardarOrden(idAEditar: ordenAEditar?['id']),
                  child: Text(ordenAEditar == null ? 'Asignar Trabajo' : 'Guardar Cambios', style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  String _filtroEstado = 'Todas';

  /// Botones para filtrar las órdenes por estado, con la cantidad de cada uno.
  Widget _barraFiltros() {
    const opciones = ['Todas', 'Por asignar', 'Pendiente', 'En progreso', 'Completada'];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: opciones.map((op) {
        final cantidad = op == 'Todas' ? _ordenes.length : _ordenes.where((o) => o['estado'] == op).length;
        final activo = _filtroEstado == op;
        final color = op == 'Todas' ? sonLightGreen : _colorEstado(op);
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _filtroEstado = op),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: activo ? color.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: activo ? color : sonBorde),
            ),
            child: Text('$op · $cantidad', style: TextStyle(color: activo ? color : sonTextoSuave, fontWeight: FontWeight.w600)),
          ),
        );
      }).toList(),
    );
  }

  Widget _cuerpoOrdenes() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_ordenes.isEmpty) return Center(child: Text('No hay órdenes registradas.', style: TextStyle(color: sonTextoSuave)));
    final visibles = _filtroEstado == 'Todas' ? _ordenes : _ordenes.where((o) => o['estado'] == _filtroEstado).toList();
    if (visibles.isEmpty) return Center(child: Text('No hay órdenes en estado "$_filtroEstado".', style: TextStyle(color: sonTextoSuave)));
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 440,
        mainAxisExtent: 240,
        crossAxisSpacing: 18,
        mainAxisSpacing: 18,
      ),
      itemCount: visibles.length,
      itemBuilder: (_, i) => _tarjetaOrden(visibles[i]),
    );
  }

  Widget _datoOrden(IconData icono, String texto, {int lineas = 1, Color? color}) {
    final tinta = color ?? sonTextoSuave;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 16, color: sonTextoSuave),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, maxLines: lineas, overflow: TextOverflow.ellipsis, style: TextStyle(color: tinta, fontSize: 13.5, height: 1.3))),
      ],
    );
  }

  /// Una orden como tarjeta: lo importante a la vista y las acciones abajo.
  Widget _tarjetaOrden(dynamic orden) {
    final estado = (orden['estado'] ?? '').toString();
    final color = _colorEstado(estado);
    var tecnico = 'Sin técnico asignado';
    for (final t in _tecnicos) {
      if (t['id'] == orden['tecnico_id']) tecnico = '${t['nombre']}';
    }
    var hora = (orden['hora_ejecucion'] ?? '').toString();
    if (hora.length > 5) hora = hora.substring(0, 5);
    final recurrente = orden['es_recurrente'] == true;
    final direccion = (orden['direccion_trabajo'] ?? '').toString().trim();
    final tarea = (orden['descripcion_tarea'] ?? '').toString().trim();

    return Container(
      decoration: decoracionTarjeta(),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(width: 5, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('#${orden['id']}', style: TextStyle(color: sonTextoSuave, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                        child: Text(estado, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12.5)),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    (orden['cliente'] ?? 'Desconocido').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  if (direccion.isNotEmpty) _datoOrden(Icons.place_outlined, direccion),
                  if (direccion.isNotEmpty) const SizedBox(height: 6),
                  Expanded(
                    child: tarea.isEmpty
                        ? const SizedBox.shrink()
                        : _datoOrden(Icons.assignment_outlined, tarea, lineas: 3, color: sonTexto),
                  ),
                  Divider(height: 1, color: sonBorde),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 17, color: sonLightGreen),
                      const SizedBox(width: 6),
                      Expanded(child: Text(tecnico, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTexto, fontSize: 13.5, fontWeight: FontWeight.w600))),
                      if (hora.isNotEmpty) ...[
                        Icon(Icons.schedule, size: 15, color: sonTextoSuave),
                        const SizedBox(width: 4),
                        Text(hora, style: TextStyle(color: sonTextoSuave, fontSize: 12.5)),
                      ],
                      if (recurrente)
                        Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Tooltip(message: 'Orden recurrente', child: Icon(Icons.repeat, size: 16, color: sonTextoSuave)),
                        ),
                      if (estado == 'Pendiente' || estado == 'En progreso')
                        IconButton(
                          tooltip: 'Avisar al cliente',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.outgoing_mail, size: 20, color: sonLightGreen),
                          onPressed: () => _avisar(orden),
                        ),
                      IconButton(
                        tooltip: 'Editar',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.edit, size: 20, color: sonAzul),
                        onPressed: () => _mostrarDialogoOrden(ordenAEditar: orden),
                      ),
                      IconButton(
                        tooltip: 'Eliminar',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.delete, size: 20, color: sonRojo),
                        onPressed: () => _eliminarOrden(orden['id']),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _avisar(dynamic orden) async {
    try {
      final respuesta = await apiSend('POST', '/api/ordenes/${orden['id']}/avisar', '{}');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aviso enviado por correo')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(respuesta, 'No se pudo avisar al cliente'))));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(mensajeSinConexion)));
    }
  }

  List<dynamic> get _visibles => _filtroEstado == 'Todas' ? _ordenes : _ordenes.where((o) => o['estado'] == _filtroEstado).toList();

  Widget _semana() {
    const nombres = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final dias = List.generate(7, (i) => _lunes.add(Duration(days: i)));
    final rango = '${dias.first.day}/${dias.first.month} – ${dias.last.day}/${dias.last.month}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(tooltip: 'Semana anterior', onPressed: () => setState(() => _lunes = _lunes.subtract(const Duration(days: 7))), icon: const Icon(Icons.chevron_left)),
            Text(rango, style: const TextStyle(fontWeight: FontWeight.bold)),
            IconButton(tooltip: 'Semana siguiente', onPressed: () => setState(() => _lunes = _lunes.add(const Duration(days: 7))), icon: const Icon(Icons.chevron_right)),
            TextButton(onPressed: () => setState(() => _lunes = _lunesDe(DateTime.now())), child: const Text('Esta semana')),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < dias.length; i++) _columnaDia(nombres[i], dias[i]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _columnaDia(String nombre, DateTime dia) {
    final hoy = DateTime.now();
    final esHoy = dia.year == hoy.year && dia.month == hoy.month && dia.day == hoy.day;
    final ordenes = _visibles.where((orden) {
      final fecha = _fechaDeOrden(orden);
      return fecha != null && fecha.year == dia.year && fecha.month == dia.month && fecha.day == dia.day;
    }).toList();
    return Container(
      width: 210,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: sonTarjeta.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: esHoy ? sonLightGreen : sonBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$nombre ${dia.day}', style: TextStyle(fontWeight: FontWeight.bold, color: esHoy ? sonLightGreen : sonTexto)),
          const SizedBox(height: 8),
          Expanded(
            child: ordenes.isEmpty
                ? Text('—', style: TextStyle(color: sonTextoSuave))
                : ListView.separated(
                    itemCount: ordenes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _tarjetaDia(ordenes[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaDia(dynamic orden) {
    final estado = '${orden['estado']}';
    var hora = '${orden['hora_ejecucion'] ?? ''}';
    if (hora.length > 5) hora = hora.substring(0, 5);
    var tecnico = 'Sin técnico';
    for (final t in _tecnicos) {
      if (t['id'] == orden['tecnico_id']) tecnico = '${t['nombre']}';
    }
    return InkWell(
      onTap: () => _mostrarDialogoOrden(ordenAEditar: Map<String, dynamic>.from(orden as Map)),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: sonTarjetaAlta, borderRadius: BorderRadius.circular(10), border: Border.all(color: _colorEstado(estado).withValues(alpha: 0.7))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${orden['cliente'] ?? 'Sin cliente'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Text('$hora · $tecnico', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTextoSuave, fontSize: 12)),
            Text(orden['orden_ruta'] == null ? estado : 'Parada ${orden['orden_ruta']} · $estado', style: TextStyle(color: _colorEstado(estado), fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Órdenes de Trabajo', style: estiloTituloPantalla),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: sonLightGreen, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18)),
                icon: Icon(Icons.add, color: sonDarkGreen),
                label: Text('Crear Nueva Orden', style: TextStyle(color: sonDarkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: () => _mostrarDialogoOrden(),
              )
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              ChoiceChip(
                label: const Text('Semana'),
                selected: _vista == 'semana',
                onSelected: (_) => setState(() => _vista = 'semana'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Lista'),
                selected: _vista == 'lista',
                onSelected: (_) => setState(() => _vista = 'lista'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _barraFiltros(),
          const SizedBox(height: 16),
          Expanded(child: _vista == 'semana' ? _semana() : _cuerpoOrdenes()),
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
      final respuesta = await apiGet('/api/tecnicos');
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

  // Error que se muestra dentro del cuadro de diálogo abierto (por ejemplo "Ese correo ya está registrado").
  String? _errorDialogo;
  StateSetter? _redibujarDialogo;

  void _mostrarErrorDialogo(String mensaje) {
    _redibujarDialogo?.call(() => _errorDialogo = mensaje);
  }

  Future<void> _registrarTecnico() async {
    if (_nombreController.text.trim().isEmpty || _emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      _mostrarErrorDialogo('Completá nombre, correo y contraseña');
      return;
    }

    try {
      final respuesta = await apiSend(
        'POST',
        '/api/tecnicos',
        json.encode({
          'nombre': _nombreController.text,
          'email': _emailController.text,
          'password': _passwordController.text,
        }),
      );

      if (respuesta.statusCode == 200) {
        _nombreController.clear();
        _emailController.clear();
        _passwordController.clear();
        if (mounted) Navigator.of(context).pop();
        setState(() => _cargando = true);
        _obtenerTecnicos();
      } else {
        _mostrarErrorDialogo(mensajeError(respuesta, 'No se pudo registrar el técnico'));
      }
    } catch (e) {
      _mostrarErrorDialogo(mensajeSinConexion);
    }
  }

  void _mostrarDialogoNuevoTecnico() => _mostrarDialogoTecnico(null);

  void _mostrarDialogoTecnico(Map<String, dynamic>? tecnico) {
    _nombreController.text = tecnico?['nombre'] ?? '';
    _emailController.text = tecnico?['email'] ?? '';
    _passwordController.clear();
    _errorDialogo = null;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialogo) {
          _redibujarDialogo = setStateDialogo;
          return AlertDialog(
            title: Text(tecnico == null ? 'Registrar Nuevo Técnico' : 'Editar Técnico', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: _nombreController, decoration: const InputDecoration(labelText: 'Nombre completo')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo electrónico'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    decoration: InputDecoration(labelText: tecnico == null ? 'Contraseña (mínimo 6 caracteres)' : 'Nueva contraseña (vacío = no cambiar)'),
                    obscureText: true,
                  ),
                  if (_errorDialogo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(_errorDialogo!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancelar', style: TextStyle(color: sonTextoSuave))
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: sonLightGreen),
                onPressed: () => tecnico == null ? _registrarTecnico() : _guardarTecnico(tecnico['id']),
                child: Text('Guardar', style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _guardarTecnico(int id) async {
    try {
      final respuesta = await apiSend(
        'PUT',
        '/api/tecnicos/$id',
        json.encode({
          'nombre': _nombreController.text,
          'email': _emailController.text,
          if (_passwordController.text.isNotEmpty) 'password': _passwordController.text,
        }),
      );
      if (respuesta.statusCode == 200) {
        _nombreController.clear();
        _emailController.clear();
        _passwordController.clear();
        if (mounted) Navigator.of(context).pop();
        setState(() => _cargando = true);
        _obtenerTecnicos();
      } else {
        _mostrarErrorDialogo(mensajeError(respuesta, 'No se pudo guardar el técnico'));
      }
    } catch (e) {
      _mostrarErrorDialogo(mensajeSinConexion);
    }
  }

  Future<void> _eliminarTecnico(Map<String, dynamic> tecnico) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text('Eliminar técnico', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
        content: Text(
          '¿Eliminar a ${tecnico['nombre']} (${tecnico['email']})?\n\n'
          'Ya no va a poder ingresar a la app. Sus órdenes no se borran: quedan sin técnico para que las reasignes. '
          'Los informes ya generados se conservan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo, false), child: Text('Cancelar', style: TextStyle(color: sonTextoSuave))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: sonRojo),
            onPressed: () => Navigator.pop(dialogo, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    String mensaje;
    try {
      final respuesta = await apiSend('DELETE', '/api/tecnicos/${tecnico['id']}');
      if (respuesta.statusCode == 200) {
        final sinAsignar = (json.decode(respuesta.body)['ordenesSinAsignar'] ?? 0) as int;
        mensaje = sinAsignar > 0
            ? 'Técnico eliminado. $sinAsignar orden(es) quedaron sin técnico: reasignalas en Órdenes de Trabajo.'
            : 'Técnico eliminado.';
        setState(() => _cargando = true);
        _obtenerTecnicos();
      } else {
        mensaje = mensajeError(respuesta, 'No se pudo eliminar el técnico');
      }
    } catch (e) {
      mensaje = mensajeSinConexion;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
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
                children: [
                  Text('Gestión de Técnicos', style: estiloTituloPantalla),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: sonLightGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(Icons.person_add, color: sonDarkGreen),
                label: Text('Registrar Técnico', style: TextStyle(color: sonDarkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: _mostrarDialogoNuevoTecnico, 
              )
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: decoracionTarjeta(),
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _tecnicos.isEmpty
                      ? Center(child: Text('No hay técnicos registrados.', style: TextStyle(color: sonTextoSuave)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: _tecnicos.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final tecnico = _tecnicos[index];
                            return ListTile(
                              leading: CircleAvatar(backgroundColor: sonTarjetaAlta, child: Icon(Icons.person, color: sonLightGreen)),
                              title: Text(tecnico['nombre'] ?? 'Sin Nombre', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(tecnico['email'] ?? 'Sin correo'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _mostrarDialogoTecnico(tecnico),
                                    child: Text('Editar', style: TextStyle(color: sonTexto)),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Eliminar técnico',
                                    icon: Icon(Icons.delete_outline, color: sonRojo),
                                    onPressed: () => _eliminarTecnico(Map<String, dynamic>.from(tecnico as Map)),
                                  ),
                                ],
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

// --- ADMINISTRADORES: cuentas con acceso a este panel ---
class PantallaAdministradores extends StatefulWidget {
  final int adminActualId;
  const PantallaAdministradores({super.key, required this.adminActualId});

  @override
  State<PantallaAdministradores> createState() => _PantallaAdministradoresState();
}

class _PantallaAdministradoresState extends State<PantallaAdministradores> {
  List<dynamic> _admins = [];
  bool _cargando = true;
  String? _errorLista;

  @override
  void initState() {
    super.initState();
    _obtener();
  }

  Future<void> _obtener() async {
    try {
      final respuesta = await apiGet('/api/admin/admins');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        setState(() {
          _admins = json.decode(respuesta.body);
          _errorLista = null;
          _cargando = false;
        });
      } else {
        setState(() {
          _errorLista = mensajeError(respuesta, 'No se pudo leer la lista');
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorLista = mensajeSinConexion;
          _cargando = false;
        });
      }
    }
  }

  void _dialogoNuevoAdmin() {
    final nombre = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    String rol = 'admin';
    String? error;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialogo) {
          return AlertDialog(
            title: const Text('Nuevo usuario'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre completo')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo electrónico'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña (mínimo 6 caracteres)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('tipo_usuario'),
                    initialValue: rol,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tipo de usuario'),
                    items: const [
                      DropdownMenuItem(value: 'admin', child: Text('Administración (solo el área técnica)')),
                      DropdownMenuItem(value: 'comercial', child: Text('Comercial (acceso total)')),
                    ],
                    onChanged: (nuevo) => rol = nuevo ?? 'admin',
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancelar', style: TextStyle(color: sonTextoSuave))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: sonLightGreen),
                onPressed: () async {
                  try {
                    final respuesta = await apiSend(
                      'POST',
                      '/api/admin/admins',
                      json.encode({'nombre': nombre.text, 'email': email.text, 'password': password.text, 'rol': rol}),
                    );
                    if (respuesta.statusCode == 200) {
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      _obtener();
                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Usuario creado')));
                    } else {
                      setStateDialogo(() => error = mensajeError(respuesta, 'No se pudo crear el usuario'));
                    }
                  } catch (e) {
                    setStateDialogo(() => error = mensajeSinConexion);
                  }
                },
                child: Text('Crear', style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        });
      },
    );
  }

  /// Cambia a una persona de Administración a Comercial (o al revés). El servidor lo aplica enseguida;
  /// el menú de esa persona se actualiza la próxima vez que abra o recargue el panel.
  Future<void> _cambiarRol(Map admin, String rol) async {
    String mensaje;
    try {
      final respuesta = await apiSend('PUT', '/api/admin/admins/${admin['id']}/rol', json.encode({'rol': rol}));
      if (respuesta.statusCode == 200) {
        mensaje = '${admin['nombre']} ahora es usuario ${rol == 'comercial' ? 'Comercial (acceso total)' : 'de Administración (solo el área técnica)'}.';
        _obtener();
      } else {
        mensaje = mensajeError(respuesta, 'No se pudo cambiar el tipo de usuario');
      }
    } catch (e) {
      mensaje = mensajeSinConexion;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _eliminar(Map admin) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text('Eliminar usuario', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
        content: Text('¿Eliminar a ${admin['nombre']} (${admin['email']})? Ya no va a poder ingresar al panel.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo, false), child: Text('Cancelar', style: TextStyle(color: sonTextoSuave))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: sonRojo),
            onPressed: () => Navigator.pop(dialogo, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    String mensaje;
    try {
      final respuesta = await apiSend('DELETE', '/api/admin/admins/${admin['id']}');
      if (respuesta.statusCode == 200) {
        mensaje = 'Usuario eliminado';
        _obtener();
      } else {
        mensaje = mensajeError(respuesta, 'No se pudo eliminar');
      }
    } catch (e) {
      mensaje = mensajeSinConexion;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Usuarios', style: estiloTituloPantalla),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              ElevatedButton.icon(
                key: const Key('nuevo_usuario'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: sonLightGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(Icons.person_add, color: sonDarkGreen),
                label: Text('Nuevo usuario', style: TextStyle(color: sonDarkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: _dialogoNuevoAdmin,
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: decoracionTarjeta(),
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _errorLista != null
                      ? Center(child: Text(_errorLista!, style: TextStyle(color: sonRojo)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: _admins.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final admin = _admins[index] as Map;
                            final esYo = admin['id'] == widget.adminActualId;
                            final comercial = admin['rol'] == 'comercial';
                            final colorRol = comercial ? sonAzul : sonLightGreen;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: sonTarjetaAlta,
                                child: Icon(comercial ? Icons.storefront_outlined : Icons.admin_panel_settings, color: colorRol),
                              ),
                              title: Text('${admin['nombre']}${esYo ? '  (vos)' : ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${admin['email']}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    key: Key('rol_${admin['id']}'),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(color: colorRol.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                                    child: Text(comercial ? 'Comercial' : 'Administración', style: TextStyle(color: colorRol, fontWeight: FontWeight.bold, fontSize: 12.5)),
                                  ),
                                  if (!esYo) ...[
                                    PopupMenuButton<String>(
                                      key: Key('cambiar_rol_${admin['id']}'),
                                      tooltip: 'Cambiar tipo de usuario',
                                      icon: Icon(Icons.swap_horiz, color: sonTextoSuave),
                                      onSelected: (rol) => _cambiarRol(admin, rol),
                                      itemBuilder: (_) => [
                                        if (comercial) const PopupMenuItem(value: 'admin', child: Text('Pasar a Administración (solo el área técnica)')),
                                        if (!comercial) const PopupMenuItem(value: 'comercial', child: Text('Pasar a Comercial (acceso total)')),
                                      ],
                                    ),
                                    IconButton(
                                      tooltip: 'Eliminar usuario',
                                      icon: Icon(Icons.delete_outline, color: sonRojo),
                                      onPressed: () => _eliminar(admin),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ),
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
  List<dynamic> _pendientes = [];
  bool _modoAgente = false;
  bool _agenteConectado = false;
  DateTime? _catalogoEn;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _obtenerCarpetasDiscoK();
  }

  Future<void> _obtenerCarpetasDiscoK() async {
    setState(() => _cargando = true);
    // Informes que todavía esperan copiarse a la carpeta de clientes.
    try {
      final estado = await apiGet('/api/informes/estado');
      if (estado.statusCode == 200 && mounted) {
        final datos = json.decode(estado.body);
        _pendientes = (datos['pendientes'] as List?) ?? [];
        _modoAgente = datos['modo'] == 'agente';
        _agenteConectado = datos['servidorDisponible'] == true;
        _catalogoEn = datos['catalogoEn'] == null ? null : DateTime.tryParse('${datos['catalogoEn']}')?.toLocal();
      }
    } catch (_) {}

    try {
      final respuesta = await apiGet('/api/informes/carpetas');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        setState(() {
          _carpetas = json.decode(respuesta.body);
          _error = null;
          _cargando = false;
        });
      } else {
        setState(() {
          _carpetas = [];
          _error = mensajeError(respuesta, 'No se pudieron leer las carpetas');
          _cargando = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carpetas = [];
        _error = mensajeSinConexion;
        _cargando = false;
      });
    }
  }

  String _textoEstadoCarpetas() {
    if (!_modoAgente) return '';
    if (!_agenteConectado) {
      return _catalogoEn == null
          ? 'El agente de la oficina no está conectado: solo se ven los informes guardados en el servidor.'
          : 'El agente de la oficina no está conectado ahora. Se muestra la última lista que envió${_haceCuanto(_catalogoEn!)}.';
    }
    if (_catalogoEn == null) return 'Agente conectado. Está leyendo las carpetas de la empresa, volvé a actualizar en un minuto.';
    return 'Carpetas del disco de la empresa (actualizado${_haceCuanto(_catalogoEn!)}).';
  }

  String _haceCuanto(DateTime fecha) {
    final minutos = DateTime.now().difference(fecha).inMinutes;
    if (minutos < 1) return ' recién';
    if (minutos < 60) return ' hace $minutos min';
    if (minutos < 60 * 24) return ' hace ${minutos ~/ 60} h';
    return ' hace ${minutos ~/ (60 * 24)} días';
  }

  void _verPendientes() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Informes esperando copiarse', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ya están generados y guardados en el servidor. Se copian solos a la carpeta de cada cliente apenas esté disponible. Mientras tanto se pueden abrir desde acá.',
                  style: TextStyle(color: sonTextoSuave),
                ),
                const SizedBox(height: 12),
                ..._pendientes.map((p) {
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.picture_as_pdf, color: sonRojo),
                    title: Text('${p['carpeta']}'),
                    subtitle: Text('${p['archivo']}'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () {
                      final url = '$apiBaseUrl/api/informes/pendientes/${Uri.encodeComponent('${p['carpeta']}')}/${Uri.encodeComponent('${p['archivo']}')}?token=${SesionAdmin.token}';
                      abrirInforme(url);
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
        );
      },
    );
  }

  Future<void> _abrirCarpeta(Map carpeta) async {
    final respuesta = await apiGet('/api/informes/carpetas/${Uri.encodeComponent('${carpeta['carpeta']}')}');
    if (!mounted) return;
    if (respuesta.statusCode != 200) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(respuesta, 'No se pudo abrir la carpeta'))));
      return;
    }
    final archivos = json.decode(respuesta.body) as List;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(carpeta['empresa'] ?? 'Informes', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 420,
            child: archivos.isEmpty
                ? const Text('Esta carpeta no tiene PDFs.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: archivos.map((archivo) {
                      final nombre = '${archivo['nombre']}';
                      return ListTile(
                        leading: Icon(Icons.picture_as_pdf, color: sonRojo),
                        title: Text(nombre),
                        subtitle: archivo['entregado'] == false
                            ? Text('En espera de llegar a la carpeta del cliente', style: TextStyle(color: sonAmbar, fontSize: 12))
                            : null,
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () {
                          final url = '$apiBaseUrl/api/informes/archivo/${Uri.encodeComponent('${carpeta['carpeta']}')}/${Uri.encodeComponent(nombre)}?token=${SesionAdmin.token}';
                          if (_modoAgente && archivo['entregado'] != false) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Buscando el informe en el disco de la empresa… puede tardar unos segundos.'),
                            ));
                          }
                          abrirInforme(url);
                        },
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
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
              Text('Informes de clientes', style: estiloTituloPantalla),
              Row(
                children: [
                  if (_modoAgente)
                    OutlinedButton.icon(
                      onPressed: () => showDialog(context: context, builder: (_) => const _DialogoAgente()),
                      icon: Icon(Icons.computer, color: sonTexto),
                      label: Text('Conectar agente', style: TextStyle(color: sonTexto)),
                    ),
                  IconButton(
                    tooltip: 'Actualizar',
                    icon: Icon(Icons.refresh, color: sonTexto),
                    onPressed: _obtenerCarpetasDiscoK,
                  ),
                ],
              ),
            ],
          ),
          if (_textoEstadoCarpetas().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_textoEstadoCarpetas(), style: TextStyle(color: _modoAgente && !_agenteConectado ? sonAmbar : sonTextoSuave, fontSize: 16)),
          ],
          if (_pendientes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: sonAmbar.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8), border: Border.all(color: sonAmbar.withValues(alpha: 0.45))),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: sonAmbar),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _modoAgente
                          ? '${_pendientes.length} informe(s) generado(s) esperando que el agente de la oficina los copie a la carpeta de clientes. No se pierden: se entregan solos cuando la PC del agente esté prendida y conectada al disco.'
                          : '${_pendientes.length} informe(s) generado(s) esperando copiarse a la carpeta de clientes. No se pierden: se copian solos cuando el servidor de archivos esté disponible.',
                      style: TextStyle(color: sonAmbar),
                    ),
                  ),
                  TextButton(onPressed: _verPendientes, child: const Text('Ver')),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: sonRojo, fontSize: 16)),
                        ),
                      )
                    : _carpetas.isEmpty
                    ? Center(child: Text('No se detectaron carpetas de clientes.', style: TextStyle(color: sonTextoSuave, fontSize: 18)))
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                        ),
                        itemCount: _carpetas.length,
                        itemBuilder: (context, index) {
                          final carpeta = _carpetas[index];
                          return InkWell(
                            onTap: () => _abrirCarpeta(carpeta),
                            child: _carpetaEmpresa(carpeta['empresa'], '${carpeta['cantidad']} informes'),
                          );
                        },
                      ),
          )
        ],
      ),
    );
  }

  Widget _carpetaEmpresa(String empresa, String subtitulo) {
    return Container(
      decoration: decoracionTarjeta(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder, size: 60, color: sonAmbar),
          const SizedBox(height: 12),
          Text(empresa, style: TextStyle(fontWeight: FontWeight.bold, color: sonTexto), textAlign: TextAlign.center),
          Text(subtitulo, style: TextStyle(color: sonTextoSuave, fontSize: 12)),
        ],
      ),
    );
  }
}

// --- Conectar el agente de la oficina (el programa que guarda los informes en la carpeta de clientes) ---
class _DialogoAgente extends StatefulWidget {
  const _DialogoAgente();

  @override
  State<_DialogoAgente> createState() => _DialogoAgenteState();
}

class _DialogoAgenteState extends State<_DialogoAgente> {
  List<dynamic> _agentes = [];
  bool _descargaDisponible = false;
  bool _cargando = true;
  String? _error;
  String? _codigo;
  int _venceEnMinutos = 15;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Lo que se pega en el programa: el código y la dirección de este servidor.
  String get _codigoDeConexion {
    final uri = Uri.parse(apiBaseUrl);
    final direccion = uri.scheme == 'https' ? uri.host + (uri.hasPort && uri.port != 443 ? ':${uri.port}' : '') : apiBaseUrl;
    return '$_codigo@$direccion';
  }

  Future<void> _cargar() async {
    try {
      final respuesta = await apiGet('/api/agentes');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        final datos = json.decode(respuesta.body);
        setState(() {
          _agentes = (datos['agentes'] as List?) ?? [];
          _descargaDisponible = datos['descargaDisponible'] == true;
          _error = null;
          _cargando = false;
        });
      } else {
        setState(() {
          _error = mensajeError(respuesta, 'No se pudo leer la lista de agentes');
          _cargando = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = mensajeSinConexion;
        _cargando = false;
      });
    }
  }

  Future<void> _generarCodigo() async {
    try {
      final respuesta = await apiSend('POST', '/api/agentes/codigo');
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        final datos = json.decode(respuesta.body);
        setState(() {
          _codigo = '${datos['codigo']}';
          _venceEnMinutos = (datos['venceEnMinutos'] as num?)?.toInt() ?? 15;
          _error = null;
        });
      } else {
        setState(() => _error = mensajeError(respuesta, 'No se pudo generar el código'));
      }
    } catch (_) {
      if (mounted) setState(() => _error = mensajeSinConexion);
    }
  }

  Future<void> _desvincular(Map agente) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Desvincular este agente?'),
        content: Text('"${agente['nombre']}" va a dejar de recibir informes. Los informes pendientes quedan guardados en el servidor.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Desvincular', style: TextStyle(color: sonRojo))),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final respuesta = await apiSend('DELETE', '/api/agentes/${agente['id']}');
      if (respuesta.statusCode != 200 && mounted) {
        setState(() => _error = mensajeError(respuesta, 'No se pudo desvincular'));
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _error = mensajeSinConexion);
      return;
    }
    _cargar();
  }

  String _visto(dynamic iso) {
    if (iso == null) return 'todavía no se conectó';
    final fecha = DateTime.tryParse('$iso')?.toLocal();
    if (fecha == null) return '';
    final minutos = DateTime.now().difference(fecha).inMinutes;
    if (minutos < 1) return 'conectado ahora';
    if (minutos < 60) return 'visto hace $minutos min';
    if (minutos < 60 * 24) return 'visto hace ${minutos ~/ 60} h';
    return 'visto hace ${minutos ~/ (60 * 24)} días';
  }

  Widget _paso(String numero, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 11, backgroundColor: sonTarjetaAlta, child: Text(numero, style: const TextStyle(color: Colors.white, fontSize: 12))),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Conectar agente de la oficina', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 520,
        child: _cargando
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'El agente es un programa que corre en una PC de la oficina con acceso al disco de clientes. Baja los informes de este servidor y los guarda en la carpeta de cada cliente.',
                      style: TextStyle(color: sonTextoSuave),
                    ),
                    const SizedBox(height: 16),
                    _paso('1', 'Descargá el programa e instalalo en la PC de la oficina (doble clic).'),
                    _paso('2', 'Tocá "Generar código" y pegalo cuando el programa lo pida.'),
                    _paso('3', 'Elegí la carpeta de clientes. Listo: arranca solo con Windows.'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _descargaDisponible ? () => abrirInforme('$apiBaseUrl/api/agentes/descargar?token=${SesionAdmin.token}') : null,
                          icon: const Icon(Icons.download),
                          label: Text(_descargaDisponible ? 'Descargar agente' : 'Programa no disponible en este servidor'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _generarCodigo,
                          icon: Icon(Icons.vpn_key, color: sonTexto),
                          label: Text('Generar código', style: TextStyle(color: sonTexto)),
                        ),
                      ],
                    ),
                    if (_codigo != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: sonLightGreen.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8), border: Border.all(color: sonLightGreen.withValues(alpha: 0.4))),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(_codigoDeConexion, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: sonTexto)),
                                  const SizedBox(height: 4),
                                  Text('Sirve una sola vez y vence en $_venceEnMinutos minutos.', style: TextStyle(color: sonTextoSuave, fontSize: 12)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copiar',
                              icon: Icon(Icons.copy, color: sonTexto),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _codigoDeConexion));
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código copiado')));
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: sonRojo)),
                    ],
                    const SizedBox(height: 20),
                    Text('Agentes conectados', style: TextStyle(fontWeight: FontWeight.bold, color: sonTexto)),
                    if (_agentes.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Todavía no hay ningún agente vinculado.', style: TextStyle(color: sonTextoSuave)),
                      ),
                    ..._agentes.map((agente) {
                      final activo = agente['activo'] == true;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.circle, size: 14, color: activo ? sonLightGreen : sonAmbar),
                        title: Text('${agente['nombre']}'),
                        subtitle: Text(_visto(agente['vistoEn'])),
                        trailing: IconButton(
                          tooltip: 'Desvincular',
                          icon: Icon(Icons.link_off, color: sonRojo),
                          onPressed: () => _desvincular(agente as Map),
                        ),
                      );
                    }),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _cargar, child: const Text('Actualizar')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
    );
  }
}
