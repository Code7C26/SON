import 'dart:async';
import 'package:flutter/material.dart';
import 'package:son_admin/config/api_config.dart';
import 'package:son_admin/pantallas/analisis.dart';
import 'package:son_admin/pantallas/clientes.dart';
import 'package:son_admin/pantallas/dashboard.dart';
import 'package:son_admin/pantallas/formularios.dart';
import 'package:son_admin/pantallas/precios.dart';
import 'package:son_admin/pantallas/presupuestos.dart';
import 'package:son_admin/pantallas/operacion.dart';
import 'package:son_admin/services/abrir_informe.dart';
import 'package:son_admin/services/elegir_imagen.dart';
import 'package:son_admin/services/api.dart';
import 'package:son_admin/services/almacen_sesion.dart';
import 'package:son_admin/services/sesion.dart';
import 'package:son_admin/theme/tema.dart';
import 'package:son_admin/ui/componentes.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';

void main() {
  final guardado = leerAlmacen('son_admin_tema');
  if (guardado == 'oscuro') controlTema.establecer(false, avisar: false);
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
    final formulario = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(alignment: Alignment.centerLeft, child: Eyebrow('Panel SON')),
        const SizedBox(height: AppSpacing.s16),
        const TituloContraste(normal: 'Ingresá', destacado: 'a tu panel', tamano: 32),
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
          decoration: InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              tooltip: _verPassword ? 'Ocultar' : 'Mostrar',
              icon: Icon(_verPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _verPassword = !_verPassword),
            ),
          ),
          obscureText: !_verPassword,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _iniciarSesion(),
        ),
        AnimatedSize(
          duration: AppMotion.media,
          curve: AppMotion.curva,
          child: _mensajeError.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: sonRojo.withValues(alpha: 0.10), borderRadius: AppRadius.rTarjeta),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: sonRojo, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_mensajeError, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600, fontSize: 13))),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.s24),
        SizedBox(
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
    );

    return Scaffold(
      body: FondoOrbes(
        child: SafeArea(
        child: LayoutBuilder(builder: (context, caja) {
          final ancho = caja.maxWidth >= 900;
          final columnaForm = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.s24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Aparecer(child: PanelVidrio(padding: const EdgeInsets.all(AppSpacing.s32), child: formulario)),
              ),
            ),
          );
          return Stack(
            children: [
              if (ancho)
                Row(
                  children: [
                    const Expanded(child: Padding(padding: EdgeInsets.all(AppSpacing.s16), child: _BloqueMarcaLogin())),
                    Expanded(child: columnaForm),
                  ],
                )
              else
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s32),
                      child: Container(
                        width: 56,
                        height: 56,
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: AppColors.tinta, shape: BoxShape.circle),
                        child: Image.asset('assets/images/logo_son_icono.png'),
                      ),
                    ),
                    Expanded(child: columnaForm),
                  ],
                ),
              const Positioned(top: AppSpacing.s16, right: AppSpacing.s16, child: BotonTema()),
            ],
          );
        }),
        ),
      ),
    );
  }
}

/// Bloque oscuro de la izquierda en el login: marca, titular y tres datos clave.
class _BloqueMarcaLogin extends StatelessWidget {
  const _BloqueMarcaLogin();

  @override
  Widget build(BuildContext context) {
    const tenue = AppColors.oscuroTextoSecundario;
    return BloqueContraste(
      padding: const EdgeInsets.all(AppSpacing.s48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.oscuroSuperficie, shape: BoxShape.circle, border: Border.all(color: AppColors.oscuroBorde)),
                child: Image.asset('assets/images/logo_son_icono.png'),
              ),
              const SizedBox(width: 12),
              const Text(
                'SON',
                style: TextStyle(fontFamily: AppTypography.display, fontWeight: FontWeight.w700, fontSize: 22, letterSpacing: AppTypography.trackingTitulo, color: AppColors.superficie),
              ),
            ],
          ),
          const Spacer(),
          const Aparecer(
            orden: 1,
            child: TituloContraste(
              normal: 'Toda tu operación,',
              destacado: 'en un solo lugar',
              destacadoEnLineaNueva: true,
              tamano: 44,
              color: AppColors.superficie,
            ),
          ),
          const SizedBox(height: AppSpacing.s48),
          const Wrap(
            spacing: AppSpacing.s48,
            runSpacing: AppSpacing.s24,
            children: [
              Aparecer(orden: 3, child: KpiBloque(valor: '100%', etiqueta: 'Digital, sin papel', colorValor: AppColors.superficie, colorEtiqueta: tenue)),
              Aparecer(orden: 4, child: KpiBloque(valor: 'GPS', etiqueta: 'Presencia validada', colorValor: AppColors.acento, colorEtiqueta: tenue)),
              Aparecer(orden: 5, child: KpiBloque(valor: 'PDF', etiqueta: 'Informe al instante', colorValor: AppColors.superficie, colorEtiqueta: tenue)),
            ],
          ),
        ],
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
    _OpcionMenu('panel', Icons.dashboard_outlined, 'Inicio', 'Operación', _todos),
    _OpcionMenu('ordenes', Icons.assignment_outlined, 'Órdenes', 'Operación', _todos),
    _OpcionMenu('tecnicos', Icons.groups_outlined, 'Técnicos', 'Operación', _todos),
    _OpcionMenu('informes', Icons.folder_outlined, 'Informes', 'Operación', _todos),
    _OpcionMenu('analisis', Icons.bar_chart_rounded, 'Análisis', 'Operación', _todos),
    _OpcionMenu('vencimientos', Icons.event_busy_outlined, 'Vencimientos', 'Operación', _todos),
    _OpcionMenu('gastos', Icons.local_gas_station_outlined, 'Gastos', 'Operación', _todos),
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
        return PantallaDashboard(nombreAdmin: (_adminActual['nombre'] ?? '').toString(), alIrA: _irA);
      case 'ordenes':
        return const PantallaOrdenes();
      case 'tecnicos':
        return const PantallaTecnicos();
      case 'informes':
        return const PantallaInformes();
      case 'analisis':
        return const PantallaAnalisis();
      case 'vencimientos':
        return const PantallaVencimientos();
      case 'gastos':
        return const PantallaGastos();
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

  // --- Menú ocultable y grupos plegables (se recuerdan entre visitas) ---
  static const String _claveMenu = 'son_admin_menu';
  static const String _claveGrupos = 'son_admin_grupos_cerrados';
  bool _menuAbierto = leerAlmacen(_claveMenu) != 'cerrado';
  final Set<String> _gruposCerrados = {
    for (final g in (leerAlmacen(_claveGrupos) ?? '').split(',')) if (g.isNotEmpty) g,
  };

  void _alternarMenu() {
    setState(() => _menuAbierto = !_menuAbierto);
    escribirAlmacen(_claveMenu, _menuAbierto ? 'abierto' : 'cerrado');
  }

  void _alternarGrupo(String grupo) {
    setState(() => _gruposCerrados.contains(grupo) ? _gruposCerrados.remove(grupo) : _gruposCerrados.add(grupo));
    escribirAlmacen(_claveGrupos, _gruposCerrados.join(','));
  }

  void _irA(String id) {
    if (!_visibles.any((o) => o.id == id)) return;
    SesionAdmin.guardarPantalla(id);
    setState(() => _pantallaActual = id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FondoOrbes(
        intensidad: 0.55,
        child: LayoutBuilder(builder: (context, caja) {
        // En pantallas angostas el menú queda siempre en íconos.
        final angosto = caja.maxWidth < 900;
        final compacto = angosto || !_menuAbierto;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s16, 0, AppSpacing.s16),
              child: _menuLateral(compacto, puedeAbrirse: !angosto),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppMotion.media,
                switchInCurve: AppMotion.curva,
                switchOutCurve: Curves.easeInCubic,
                // Solo se ve la pantalla nueva: la anterior no se superpone mientras entra.
                layoutBuilder: (actual, _) => actual ?? const SizedBox.shrink(),
                transitionBuilder: (hijo, animacion) => FadeTransition(
                  opacity: animacion,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.012), end: Offset.zero).animate(animacion),
                    child: hijo,
                  ),
                ),
                child: KeyedSubtree(key: ValueKey(_pantallaActual), child: _pantalla(_pantallaActual)),
              ),
            ),
          ],
        );
      }),
      ),
    );
  }

  /// Las opciones que puede ver este usuario, agrupadas y plegables (Operación / Comercial / Sistema).
  List<Widget> _itemsDelMenu(bool compacto) {
    final grupos = <String, List<_OpcionMenu>>{};
    for (final opcion in _visibles) {
      grupos.putIfAbsent(opcion.grupo, () => []).add(opcion);
    }
    final items = <Widget>[];
    var primero = true;
    grupos.forEach((grupo, opciones) {
      final cerrado = _gruposCerrados.contains(grupo);
      // Con el grupo cerrado igual se ve la pantalla en la que estás.
      final mostradas = cerrado ? opciones.where((o) => o.id == _pantallaActual).toList() : opciones;
      final nuevasEnGrupo = opciones.any((o) => o.id == 'presupuestos') ? _nuevas : 0;
      if (compacto) {
        if (!primero) {
          items.add(const Padding(padding: EdgeInsets.symmetric(vertical: 10, horizontal: 14), child: Divider(height: 1)));
        }
      } else {
        items.add(_CabeceraGrupo(
          texto: grupo,
          cerrado: cerrado,
          primero: primero,
          insignia: cerrado ? nuevasEnGrupo : 0,
          alTocar: () => _alternarGrupo(grupo),
        ));
      }
      final lista = compacto ? opciones : mostradas;
      items.add(
        AnimatedSize(
          duration: AppMotion.media,
          curve: AppMotion.curva,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              for (final opcion in lista)
                _ItemMenu(
                  icono: opcion.icono,
                  texto: opcion.texto,
                  seleccionado: opcion.id == _pantallaActual,
                  compacto: compacto,
                  insignia: opcion.id == 'presupuestos' ? _nuevas : 0,
                  alTocar: () => _irA(opcion.id),
                ),
            ],
          ),
        ),
      );
      primero = false;
    });
    return items;
  }

  Widget _menuLateral(bool compacto, {required bool puedeAbrirse}) {
    final nombre = (_adminActual['nombre'] ?? 'Administrador').toString();
    final email = (_adminActual['email'] ?? '').toString();
    final inicial = nombre.isEmpty ? '?' : nombre[0].toUpperCase();

    final botonPlegar = puedeAbrirse
        ? Tooltip(
            message: compacto ? 'Mostrar menú' : 'Ocultar menú',
            child: InkResponse(
              onTap: _alternarMenu,
              radius: 22,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: sonTarjeta, shape: BoxShape.circle, border: Border.all(color: sonBorde)),
                child: AnimatedRotation(
                  turns: compacto ? 0.5 : 0,
                  duration: AppMotion.media,
                  curve: AppMotion.curva,
                  child: Icon(Icons.chevron_left_rounded, size: 20, color: sonTexto),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    final logo = Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(9),
      decoration: const BoxDecoration(color: AppColors.tinta, shape: BoxShape.circle),
      child: Image.asset('assets/images/logo_son_icono.png'),
    );

    return AnimatedContainer(
      duration: AppMotion.lenta,
      curve: AppMotion.curva,
      width: compacto ? 80 : 256,
      child: PanelVidrio(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: compacto ? 80 : 256,
        maxWidth: compacto ? 80 : 256,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 14, 18),
              child: compacto
                  ? Column(children: [logo, if (puedeAbrirse) ...[const SizedBox(height: 12), botonPlegar]])
                  : Row(
                      children: [
                        logo,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'SON',
                            style: TextStyle(
                              fontFamily: AppTypography.display,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              letterSpacing: AppTypography.trackingTitulo,
                              color: sonTexto,
                            ),
                          ),
                        ),
                        botonPlegar,
                      ],
                    ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: compacto ? 12 : 14, vertical: 4),
                children: _itemsDelMenu(compacto),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(compacto ? 10 : 12),
              child: compacto
                  ? Column(
                      children: [
                        Tooltip(
                          message: 'Mi perfil',
                          child: InkResponse(
                            onTap: _mostrarPerfil,
                            child: CircleAvatar(radius: 18, backgroundColor: sonAcento, child: Text(inicial, style: TextStyle(color: sonSobreAcento, fontWeight: FontWeight.w700))),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const BotonTema(),
                        IconButton(tooltip: 'Cerrar sesión', onPressed: _cerrarSesion, icon: Icon(Icons.logout_rounded, color: sonTextoSuave, size: 20)),
                      ],
                    )
                  : Container(
                      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                      decoration: BoxDecoration(color: sonTarjeta.withValues(alpha: 0.7), borderRadius: AppRadius.rPildora, border: Border.all(color: sonBorde.withValues(alpha: 0.6))),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: AppRadius.rChico,
                              onTap: _mostrarPerfil,
                              child: Row(
                                children: [
                                  CircleAvatar(radius: 17, backgroundColor: sonAcento, child: Text(inicial, style: TextStyle(color: sonSobreAcento, fontWeight: FontWeight.w700))),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTexto, fontWeight: FontWeight.w600, fontSize: 13)),
                                        Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTextoTenue, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const BotonTema(),
                          IconButton(tooltip: 'Cerrar sesión', onPressed: _cerrarSesion, icon: Icon(Icons.logout_rounded, color: sonTextoSuave, size: 20)),
                        ],
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

/// Título de un grupo del menú (OPERACIÓN, COMERCIAL...). Tocándolo se pliega o despliega.
class _CabeceraGrupo extends StatefulWidget {
  final String texto;
  final bool cerrado;
  final bool primero;
  final int insignia;
  final VoidCallback alTocar;
  const _CabeceraGrupo({required this.texto, required this.cerrado, required this.primero, required this.insignia, required this.alTocar});

  @override
  State<_CabeceraGrupo> createState() => _CabeceraGrupoState();
}

class _CabeceraGrupoState extends State<_CabeceraGrupo> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final color = _encima ? sonTexto : sonTextoTenue;
    return Padding(
      padding: EdgeInsets.only(top: widget.primero ? 0 : 14, bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _encima = true),
        onExit: (_) => setState(() => _encima = false),
        child: GestureDetector(
          onTap: widget.alTocar,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.texto.toUpperCase(), style: AppTypography.eyebrow(color).copyWith(fontSize: 11)),
                ),
                if (widget.insignia > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: sonAmbar, shape: BoxShape.circle),
                  ),
                AnimatedRotation(
                  turns: widget.cerrado ? -0.25 : 0,
                  duration: AppMotion.media,
                  curve: AppMotion.curva,
                  child: Icon(Icons.expand_more_rounded, size: 18, color: color),
                ),
              ],
            ),
          ),
        ),
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
    final oscuro = !controlTema.claro;
    // Ítem activo: píldora oscura con texto blanco (en modo oscuro, al revés).
    final fondoActivo = oscuro ? AppColors.canvas : AppColors.tinta;
    final textoActivo = oscuro ? AppColors.tinta : AppColors.superficie;
    final color = activo ? textoActivo : (_encima ? sonTexto : sonTextoSuave);
    final contenido = AnimatedContainer(
      duration: AppMotion.rapida,
      curve: AppMotion.curva,
      margin: const EdgeInsets.symmetric(vertical: 2),
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: widget.compacto ? 0 : 14),
      decoration: BoxDecoration(
        color: activo ? fondoActivo : (_encima ? sonTarjeta.withValues(alpha: 0.8) : Colors.transparent),
        borderRadius: AppRadius.rPildora,
      ),
      child: Row(
        mainAxisAlignment: widget.compacto ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          // Con el menú angosto el número va como una chapita sobre el ícono.
          widget.compacto && widget.insignia > 0
              ? Badge(label: Text(widget.insignia > 99 ? '99+' : '${widget.insignia}'), backgroundColor: sonAmbar, textColor: AppColors.sobreOro, child: Icon(widget.icono, color: color, size: 20))
              : Icon(widget.icono, color: color, size: 20),
          if (!widget.compacto) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.texto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: activo ? FontWeight.w600 : FontWeight.w500, fontSize: 14),
              ),
            ),
            if (widget.insignia > 0)
              Container(
                key: const Key('insignia_menu'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: sonAmbar, borderRadius: AppRadius.rPildora),
                child: Text(widget.insignia > 99 ? '99+' : '${widget.insignia}', style: const TextStyle(color: AppColors.sobreOro, fontWeight: FontWeight.bold, fontSize: 12)),
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
        child: widget.compacto ? Tooltip(message: widget.texto, waitDuration: const Duration(milliseconds: 300), child: contenido) : contenido,
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

/// "08:00 a 12:00" (rango horario) o "08:00" si la orden no tiene hora de fin.
String _rangoHorario(dynamic orden) {
  String corta(dynamic valor) {
    final texto = '${valor ?? ''}'.trim();
    return texto.length > 5 ? texto.substring(0, 5) : texto;
  }
  final desde = corta(orden['hora_ejecucion']);
  final hasta = corta(orden['hora_hasta']);
  if (desde.isEmpty) return '';
  return hasta.isEmpty ? desde : '$desde a $hasta';
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
  String? _error;
  String _busqueda = '';

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
  // Las visitas son en un rango horario: el técnico maneja su horario dentro de la franja.
  final TextEditingController _horaCtrl = TextEditingController(text: '08:00');
  final TextEditingController _horaHastaCtrl = TextEditingController(text: '17:00');
  // "Guardar como tareas fijas": el checklist pasa a cargarse solo en cada orden nueva de esa empresa.
  bool _guardarTareasFijas = false;
  // Formularios de control de la orden (los fijos de la empresa se cargan solos al elegirla).
  List<Map<String, dynamic>> _formulariosDisponibles = [];
  List<int> _formulariosElegidos = [];
  StateSetter? _redibujarOrden;
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
      _actualizarFormularios();
      if (!mounted) return;

      if (resOrdenes.statusCode == 200 && resTecnicos.statusCode == 200) {
        setState(() {
          _ordenes = json.decode(resOrdenes.body);
          _tecnicos = json.decode(resTecnicos.body);
          _cargando = false;
          _error = null;
        });
        _cargarClientes();
      } else {
        setState(() {
          _cargando = false;
          _error = mensajeError(resOrdenes.statusCode == 200 ? resTecnicos : resOrdenes, 'No se pudieron cargar las órdenes.');
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = mensajeSinConexion;
      });
    }
  }

  void _reintentar() {
    setState(() {
      _cargando = true;
      _error = null;
    });
    _obtenerDatos();
  }

  String _nombreTecnicoDe(dynamic orden) {
    for (final t in _tecnicos) {
      if (t['id'] == orden['tecnico_id']) return '${t['nombre']}';
    }
    return '';
  }

  /// Coincide con la búsqueda por cliente, dirección, tarea, técnico o número.
  bool _coincide(dynamic orden) {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;
    final texto = [
      orden['id'],
      orden['cliente'],
      orden['direccion_trabajo'],
      orden['descripcion_tarea'],
      _nombreTecnicoDe(orden),
    ].map((v) => (v ?? '').toString().toLowerCase()).join(' ');
    return texto.contains(q);
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
        onSelected: (nombre) {
          FocusScope.of(context).nextFocus();
          _cargarDatosDeEmpresa(nombre);
        },
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

  /// Al elegir el cliente: si el checklist está vacío se cargan sus tareas fijas, y si falta la
  /// dirección o el correo se completan con los de la empresa.
  Future<void> _cargarDatosDeEmpresa(String nombre, {bool forzarTareas = false}) async {
    try {
      final respuesta = await apiGet('/api/clientes/tareas?nombre=${Uri.encodeQueryComponent(nombre)}');
      if (respuesta.statusCode != 200) return;
      final datos = json.decode(respuesta.body) as Map;
      final tareas = (datos['tareas'] as List? ?? []).map((t) => '$t').toList();
      if (tareas.isNotEmpty && (forzarTareas || _puntosCtrl.text.trim().isEmpty)) _puntosCtrl.text = tareas.join('\n');
      final fijos = (datos['formularios'] as List? ?? []).map((id) => (id as num).toInt()).toList();
      if (fijos.isNotEmpty && (forzarTareas || _formulariosElegidos.isEmpty)) {
        _formulariosElegidos = fijos;
        _redibujarOrden?.call(() {});
      }
      if (_direccionController.text.trim().isEmpty && '${datos['direccion'] ?? ''}'.isNotEmpty) _direccionController.text = '${datos['direccion']}';
      if (_emailClienteCtrl.text.trim().isEmpty && '${datos['email'] ?? ''}'.isNotEmpty) _emailClienteCtrl.text = '${datos['email']}';
      if (forzarTareas && tareas.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Esta empresa todavía no tiene tareas fijas.')));
      }
    } catch (_) {}
  }

  Future<void> _guardarOrden({int? idAEditar}) async {
    if (_tecnicoSeleccionado == null || _clienteController.text.isEmpty || _direccionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completá técnico, cliente y dirección')));
      return;
    }

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
          'hora_hasta': _horaHastaCtrl.text.trim(),
          'guardar_tareas_fijas': _guardarTareasFijas,
          'formularios': _formulariosElegidos,
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
        if (!mounted) return;
        Navigator.of(context).pop();
        setState(() => _cargando = true);
        _obtenerDatos();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(respuesta, 'No se pudo guardar la orden'))));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(mensajeSinConexion)));
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
      var hora = '${ordenAEditar['hora_ejecucion'] ?? '08:00'}';
      if (hora.length > 5) hora = hora.substring(0, 5);
      _horaCtrl.text = hora;
      var hasta = '${ordenAEditar['hora_hasta'] ?? ''}';
      if (hasta.length > 5) hasta = hasta.substring(0, 5);
      _horaHastaCtrl.text = hasta;
      _guardarTareasFijas = false;
      _fechaOrden = _fechaDeOrden(ordenAEditar) ?? DateTime.now();
      final puntos = ordenAEditar['puntos'];
      _puntosCtrl.text = puntos is List ? puntos.map((punto) => '$punto').join('\n') : '';
      final formularios = ordenAEditar['formularios'];
      _formulariosElegidos = formularios is List ? formularios.map((f) => ((f as Map)['id'] as num).toInt()).toList() : [];
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
      _formulariosElegidos = [];
      _emailClienteCtrl.clear();
      _whatsappCtrl.clear();
      _horaCtrl.text = '08:00';
      _horaHastaCtrl.text = '17:00';
      _guardarTareasFijas = false;
    }

    // La lista de formularios se pide de nuevo (pudo cambiar) y el diálogo se redibuja cuando llega.
    _actualizarFormularios();
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            _redibujarOrden = setStateModal;
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
                          SizedBox(width: 90, child: TextField(controller: _horaCtrl, decoration: const InputDecoration(labelText: 'Desde'))),
                          const SizedBox(width: 8),
                          SizedBox(width: 90, child: TextField(controller: _horaHastaCtrl, decoration: const InputDecoration(labelText: 'Hasta', hintText: 'sin límite'))),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Franja horaria: el técnico va cuando le queda mejor dentro del rango.', style: TextStyle(color: sonTextoSuave, fontSize: 12)),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _puntosCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Checklist de la visita (una tarea por renglón)',
                          helperText: 'Al elegir el cliente se cargan solas sus tareas fijas. Se pueden cambiar.',
                        ),
                        maxLines: 5,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _guardarTareasFijas,
                              onChanged: (valor) => setStateModal(() => _guardarTareasFijas = valor ?? false),
                              title: const Text('Guardar checklist y formularios como fijos de la empresa (todos los meses)'),
                            ),
                          ),
                          TextButton(
                            onPressed: _clienteController.text.trim().isEmpty ? null : () => _cargarDatosDeEmpresa(_clienteController.text.trim(), forzarTareas: true),
                            child: const Text('Cargar los fijos'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectorFormularios(
                        disponibles: _formulariosDisponibles,
                        elegidos: _formulariosElegidos,
                        alCambiar: (lista) => setStateModal(() => _formulariosElegidos = lista),
                        alCambiarDisponibles: (lista) {
                          setState(() => _formulariosDisponibles = lista);
                          setStateModal(() {});
                        },
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
                  onPressed: () => _guardarOrden(idAEditar: ordenAEditar?['id']),
                  child: Text(ordenAEditar == null ? 'Asignar Trabajo' : 'Guardar Cambios', style: TextStyle(color: sonDarkGreen, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    ).then((_) => _redibujarOrden = null); // cerrado el diálogo, ya no hay nada que redibujar
  }

  /// Pide los formularios guardados y redibuja el diálogo de la orden si está abierto.
  Future<void> _actualizarFormularios() async {
    final lista = await listaDeFormularios();
    if (!mounted) return;
    setState(() => _formulariosDisponibles = lista);
    _redibujarOrden?.call(() {});
  }

  String _filtroEstado = 'Todas';

  /// Píldoras para filtrar las órdenes por estado, con la cantidad de cada uno.
  Widget _barraFiltros() {
    const opciones = ['Todas', 'Por asignar', 'Pendiente', 'En progreso', 'Completada'];
    final base = _ordenes.where(_coincide).toList();
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: opciones.map((op) {
        final cantidad = op == 'Todas' ? base.length : base.where((o) => o['estado'] == op).length;
        return PildoraContador(
          texto: op,
          cantidad: cantidad,
          activa: _filtroEstado == op,
          punto: op == 'Todas' ? null : _colorEstado(op),
          alTocar: () => setState(() => _filtroEstado = op),
        );
      }).toList(),
    );
  }

  Widget _cuerpoOrdenes() {
    if (_ordenes.isEmpty) {
      return EstadoVacio(icono: Icons.assignment_outlined, mensaje: 'Todavía no hay órdenes.', accion: 'Nueva orden', alAccionar: () => _mostrarDialogoOrden());
    }
    final visibles = _visibles;
    if (visibles.isEmpty) {
      return EstadoVacio(icono: Icons.search_off_rounded, mensaje: _busqueda.isNotEmpty ? 'Sin resultados para "$_busqueda".' : 'No hay órdenes "$_filtroEstado".');
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8, top: 4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 440,
        mainAxisExtent: 240,
        crossAxisSpacing: AppSpacing.s16,
        mainAxisSpacing: AppSpacing.s16,
      ),
      itemCount: visibles.length,
      itemBuilder: (_, i) => Aparecer(orden: i < 12 ? i : 12, child: _tarjetaOrden(visibles[i])),
    );
  }

  /// Carga: siluetas con la forma de las tarjetas.
  Widget _esqueletoOrdenes() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 440,
        mainAxisExtent: 240,
        crossAxisSpacing: AppSpacing.s16,
        mainAxisSpacing: AppSpacing.s16,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => const Skeleton(alto: 240, radio: AppRadius.rTarjetaGrande),
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
    final hora = _rangoHorario(orden);
    final recurrente = orden['es_recurrente'] == true;
    final direccion = (orden['direccion_trabajo'] ?? '').toString().trim();
    final tarea = (orden['descripcion_tarea'] ?? '').toString().trim();

    return Container(
      decoration: decoracionTarjeta(radio: AppRadius.tarjetaGrande, sombra: true),
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
                          padding: const EdgeInsets.only(left: 8),
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

  List<dynamic> get _visibles => _ordenes.where((o) => _coincide(o) && (_filtroEstado == 'Todas' || o['estado'] == _filtroEstado)).toList();

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
    final hora = _rangoHorario(orden);
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
    final Widget cuerpo;
    if (_cargando) {
      cuerpo = _esqueletoOrdenes();
    } else if (_error != null && _ordenes.isEmpty) {
      cuerpo = EstadoError(mensaje: _error!, alReintentar: _reintentar);
    } else {
      cuerpo = _vista == 'semana' ? _semana() : _cuerpoOrdenes();
    }
    return Padding(
      padding: AppSpacing.pagina,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Aparecer(
            child: EncabezadoPantalla(
              eyebrow: 'Operación',
              normal: 'Órdenes de',
              destacado: 'trabajo',
              accion: ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nueva orden'),
                onPressed: () => _mostrarDialogoOrden(),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s24),
          Wrap(
            spacing: AppSpacing.s16,
            runSpacing: AppSpacing.s12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Buscador(pista: 'Buscar cliente, dirección, técnico...', alCambiar: (v) => setState(() => _busqueda = v), ancho: 320),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'semana', icon: Icon(Icons.calendar_view_week_rounded, size: 18), label: Text('Semana')),
                  ButtonSegment(value: 'lista', icon: Icon(Icons.grid_view_rounded, size: 18), label: Text('Tarjetas')),
                ],
                selected: {_vista},
                onSelectionChanged: (v) => setState(() => _vista = v.first),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          _barraFiltros(),
          const SizedBox(height: AppSpacing.s16),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.media,
              switchInCurve: AppMotion.curva,
              layoutBuilder: (actual, _) => actual ?? const SizedBox.shrink(),
              child: KeyedSubtree(key: ValueKey('$_vista-$_cargando-${_error != null}'), child: cuerpo),
            ),
          ),
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
  // Perfil: desde dónde sale (ordena su recorrido), matrícula y firma con sello (va sola en cada informe).
  final TextEditingController _salidaController = TextEditingController();
  final TextEditingController _matriculaController = TextEditingController();
  String? _firma; // data URL de la imagen que se ve en el diálogo
  bool _firmaCambiada = false;

  @override
  void initState() {
    super.initState();
    _obtenerTecnicos();
  }

  /// Lo que se manda del perfil: la firma solo si se cambió (si no, el servidor la deja como está).
  Map<String, dynamic> _datosDePerfil() => {
        'salida_direccion': _salidaController.text.trim(),
        'matricula': _matriculaController.text.trim(),
        if (_firmaCambiada) 'firma_sello': _firma,
      };

  Future<void> _elegirFirma() async {
    final imagen = await elegirImagen();
    if (imagen == null) return;
    if (!RegExp(r'^data:image/(png|jpeg);base64,').hasMatch(imagen)) {
      _mostrarErrorDialogo('La firma tiene que ser una imagen PNG o JPG');
      return;
    }
    if (imagen.length > 2000000) {
      _mostrarErrorDialogo('La imagen es muy pesada (máximo 1,5 MB). Achicala o recortala.');
      return;
    }
    _redibujarDialogo?.call(() {
      _firma = imagen;
      _firmaCambiada = true;
      _errorDialogo = null;
    });
  }

  Future<void> _leerFirma(int id) async {
    try {
      final respuesta = await apiGet('/api/tecnicos/$id/firma');
      if (respuesta.statusCode != 200) return;
      final firma = (json.decode(respuesta.body) as Map)['firma_sello'];
      if (firma is String && !_firmaCambiada) _redibujarDialogo?.call(() => _firma = firma);
    } catch (_) {}
  }

  Widget _vistaFirma() {
    Widget contenido;
    final firma = _firma;
    if (firma == null) {
      contenido = Text('Sin firma cargada: el técnico firma en el celular en cada visita.', textAlign: TextAlign.center, style: TextStyle(color: sonTextoSuave));
    } else {
      try {
        contenido = Image.memory(base64Decode(firma.substring(firma.indexOf(',') + 1)), fit: BoxFit.contain);
      } catch (_) {
        contenido = Text('No se puede mostrar la imagen', style: TextStyle(color: sonRojo));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Firma y sello (va sola en cada informe)', style: TextStyle(color: sonTextoSuave, fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          height: 110,
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: sonBorde)),
          child: Center(child: contenido),
        ),
        Row(
          children: [
            TextButton.icon(onPressed: _elegirFirma, icon: const Icon(Icons.upload_file), label: Text(firma == null ? 'Subir imagen' : 'Cambiar imagen')),
            if (firma != null)
              TextButton.icon(
                onPressed: () => _redibujarDialogo?.call(() {
                  _firma = null;
                  _firmaCambiada = true;
                }),
                icon: Icon(Icons.delete_outline, color: sonRojo),
                label: Text('Quitar', style: TextStyle(color: sonRojo)),
              ),
          ],
        ),
      ],
    );
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
          ..._datosDePerfil(),
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
    _salidaController.text = '${tecnico?['salida_direccion'] ?? ''}';
    _matriculaController.text = '${tecnico?['matricula'] ?? ''}';
    _firma = null;
    _firmaCambiada = false;
    _errorDialogo = null;
    if (tecnico != null && tecnico['tiene_firma'] == true) {
      // Se pide después de abrir el diálogo, para poder mostrarla.
      Future.microtask(() => _leerFirma((tecnico['id'] as num).toInt()));
    }
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialogo) {
          _redibujarDialogo = setStateDialogo;
          return AlertDialog(
            title: Text(tecnico == null ? 'Registrar Nuevo Técnico' : 'Editar Técnico', style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: _salidaController,
                    decoration: const InputDecoration(
                      labelText: 'Sale desde (dirección o localidad)',
                      helperText: 'Ordena sus visitas desde ahí. Ej: Villa María, Córdoba',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _matriculaController, decoration: const InputDecoration(labelText: 'Matrícula profesional')),
                  const SizedBox(height: 16),
                  _vistaFirma(),
                  if (_errorDialogo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(_errorDialogo!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancelar', style: TextStyle(color: sonTextoSuave))
              ),
              ElevatedButton(
                onPressed: () => tecnico == null ? _registrarTecnico() : _guardarTecnico(tecnico['id']),
                child: const Text('Guardar'),
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
          ..._datosDePerfil(),
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
      padding: AppSpacing.pagina,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EncabezadoPantalla(eyebrow: 'Operación', normal: 'Equipo', destacado: 'técnico'),
                ],
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.person_add),
                label: const Text('Nuevo técnico'),
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
                      ? EstadoVacio(icono: Icons.groups_outlined, mensaje: 'Todavía no hay técnicos.', accion: 'Nuevo técnico', alAccionar: _mostrarDialogoNuevoTecnico)
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: _tecnicos.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final tecnico = _tecnicos[index];
                            return ListTile(
                              leading: CircleAvatar(backgroundColor: sonTarjetaAlta, child: Icon(Icons.person, color: sonLightGreen)),
                              title: Text(tecnico['nombre'] ?? 'Sin Nombre', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text([
                                '${tecnico['email'] ?? 'Sin correo'}',
                                if ('${tecnico['salida_direccion'] ?? ''}'.isNotEmpty) 'Sale desde ${tecnico['salida_direccion']}',
                                if ('${tecnico['matricula'] ?? ''}'.isNotEmpty) 'Mat. ${tecnico['matricula']}',
                                tecnico['tiene_firma'] == true ? 'Firma cargada' : 'Sin firma cargada',
                              ].join(' · ')),
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
                child: const Text('Crear'),
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
      padding: AppSpacing.pagina,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EncabezadoPantalla(eyebrow: 'Sistema', normal: 'Usuarios', destacado: 'del panel'),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              ElevatedButton.icon(
                key: const Key('nuevo_usuario'),
                icon: const Icon(Icons.person_add),
                label: const Text('Nuevo usuario'),
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

  /// El enlace con el que el cliente ve sus informes. Lo maneja también Administración desde acá.
  Future<void> _accesoDelCliente(Map carpeta) async {
    final nombre = '${carpeta['empresa'] ?? carpeta['carpeta'] ?? ''}';
    try {
      final respuesta = await apiGet('/api/clientes/portal-por-nombre?nombre=${Uri.encodeQueryComponent(nombre)}');
      if (!mounted) return;
      if (respuesta.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensajeError(respuesta, 'No se encontró el cliente'))));
        return;
      }
      final datos = json.decode(respuesta.body) as Map;
      await abrirAccesoCliente(context, (datos['id'] as num).toInt(), '${datos['empresa'] ?? nombre}');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(mensajeSinConexion)));
    }
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
            TextButton.icon(
              onPressed: () => _accesoDelCliente(carpeta),
              icon: const Icon(Icons.link),
              label: const Text('Acceso del cliente'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.pagina,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const EncabezadoPantalla(eyebrow: 'Operación', normal: 'Informes de', destacado: 'clientes'),
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
                    ? EstadoError(mensaje: _error!, alReintentar: _obtenerCarpetasDiscoK)
                    : _carpetas.isEmpty
                    ? Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Text(
                            'Todavía no hay carpetas de clientes. Cuando se cierre la primera visita, el informe queda guardado acá.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: sonTextoSuave, fontSize: 18, height: 1.4),
                          ),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                        ),
                        itemCount: _carpetas.length,
                        itemBuilder: (context, index) {
                          final carpeta = _carpetas[index];
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: InkWell(
                                  onTap: () => _abrirCarpeta(carpeta),
                                  child: _carpetaEmpresa(carpeta['empresa'], '${carpeta['cantidad']} informes'),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  tooltip: 'Acceso del cliente (enlace para ver sus informes)',
                                  icon: Icon(Icons.link, color: sonTextoSuave, size: 20),
                                  onPressed: () => _accesoDelCliente(carpeta),
                                ),
                              ),
                            ],
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
  final TextEditingController _carpeta = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _carpeta.dispose();
    super.dispose();
  }

  /// Instalación como servicio en el servidor de archivos: arranca con la máquina y no hay que
  /// volver a descargar nada (el agente se actualiza solo desde este servidor).
  String get _comandoServidor {
    final carpeta = _carpeta.text.trim();
    return 'SON-Agente.exe --instalar-servidor --codigo=$_codigoDeConexion${carpeta.isEmpty ? '' : ' --carpeta="$carpeta"'}';
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
          CircleAvatar(radius: 11, backgroundColor: sonTarjetaAlta, child: Text(numero, style: TextStyle(color: sonTexto, fontSize: 12))),
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
                      'El agente es un programa que conecta el disco K (la carpeta de clientes) con este servidor. '
                      'Se instala UNA sola vez en la máquina que tiene el disco y queda prendido siempre: '
                      'arranca solo con Windows (aunque nadie inicie sesión) y se actualiza solo. '
                      'Desde ese momento nadie más tiene que descargar nada para usar el panel.',
                      style: TextStyle(color: sonTextoSuave),
                    ),
                    const SizedBox(height: 16),
                    _paso('1', 'En el servidor de archivos (la máquina del disco K), descargá el programa.'),
                    _paso('2', 'Tocá "Generar código", escribí la carpeta de clientes tal como se ve EN ESE servidor y copiá el comando.'),
                    _paso('3', 'Abrí una consola "como administrador" en la carpeta donde quedó el programa, pegá el comando y Enter. Listo para siempre.'),
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
                      const SizedBox(height: 14),
                      TextField(
                        controller: _carpeta,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Carpeta de clientes vista desde el servidor',
                          hintText: r'Ej: D:\HIGIENE Y SEGURIDAD\00. CLIENTES',
                          helperText: 'En el servidor conviene la ruta local (D:\\...), no la K: ni \\\\sa-server: el agente corre como servicio.',
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('Comando para instalarlo en el servidor (una sola vez):', style: TextStyle(fontWeight: FontWeight.w600, color: sonTexto)),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: sonTarjetaAlta, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            Expanded(child: SelectableText(_comandoServidor, style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: sonTexto))),
                            IconButton(
                              tooltip: 'Copiar comando',
                              icon: Icon(Icons.copy, color: sonTexto),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _comandoServidor));
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comando copiado')));
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Si preferís instalarlo en una PC común, abrí el programa con doble clic y pegá el código: '
                        'funciona igual, pero solo mientras esa PC esté prendida.',
                        style: TextStyle(color: sonTextoSuave, fontSize: 12),
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
                        padding: const EdgeInsets.only(top: 8),
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
