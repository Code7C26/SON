import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:son_admin/pantallas/operacion.dart' show abrirAccesoCliente;
import 'package:son_admin/pantallas/piezas.dart';
import 'package:son_admin/services/api.dart';
import 'package:son_admin/theme/tema.dart';
import 'package:son_admin/ui/componentes.dart';

const List<String> provinciasArgentinas = [
  'Buenos Aires',
  'Catamarca',
  'Chaco',
  'Chubut',
  'Ciudad Autónoma de Buenos Aires',
  'Córdoba',
  'Corrientes',
  'Entre Ríos',
  'Formosa',
  'Jujuy',
  'La Pampa',
  'La Rioja',
  'Mendoza',
  'Misiones',
  'Neuquén',
  'Río Negro',
  'Salta',
  'San Juan',
  'San Luis',
  'Santa Cruz',
  'Santa Fe',
  'Santiago del Estero',
  'Tierra del Fuego, Antártida e Islas del Atlántico Sur',
  'Tucumán',
];

/// Actividades que ya usan en su planilla de clientes (se puede escribir cualquier otra).
const List<String> actividadesSugeridas = ['Alimenticia', 'Comercio', 'Estación de Servicio', 'Metalmecánica', 'Minería', 'Transporte'];

/// Riesgo de incendio (Decreto 351/79) y categoría de la empresa.
const List<String> riesgosIncendio = ['R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7'];
const List<String> categoriasEmpresa = ['A', 'B', 'C'];

String _texto(Map<String, dynamic> cliente, String campo) => '${cliente[campo] ?? ''}'.trim();

/// Iguala mayúsculas, tildes y guiones bajos para cruzar una carpeta del disco con su ficha.
String _clave(String nombre) {
  const conTilde = 'ÁÉÍÓÚÜÑáéíóúüñ';
  const sinTilde = 'AEIOUUNaeiouun';
  final limpio = StringBuffer();
  for (final codigo in nombre.runes) {
    final letra = String.fromCharCode(codigo);
    final indice = conTilde.indexOf(letra);
    limpio.write(indice >= 0 ? sinTilde[indice] : letra);
  }
  return limpio.toString().toUpperCase().replaceAll(RegExp(r'[_]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Fichas de los clientes: datos de contacto y de la empresa.
class PantallaClientes extends StatefulWidget {
  const PantallaClientes({super.key});

  @override
  State<PantallaClientes> createState() => _PantallaClientesState();
}

class _PantallaClientesState extends State<PantallaClientes> {
  List<Map<String, dynamic>> _clientes = [];
  bool _cargando = true;
  String? _error;
  final TextEditingController _busqueda = TextEditingController();

  @override
  void initState() {
    super.initState();
    _busqueda.addListener(() => setState(() {}));
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (!_cargando) setState(() => _cargando = true);
    try {
      final respuestas = await Future.wait([apiGet('/api/informes/carpetas'), apiGet('/api/clientes')]);
      if (!mounted) return;
      final disco = respuestas[0];
      if (disco.statusCode != 200) {
        setState(() {
          _error = mensajeError(disco, 'No se pudo leer las carpetas del disco');
          _cargando = false;
        });
        return;
      }
      final fichas = respuestas[1].statusCode == 200
          ? (json.decode(respuestas[1].body) as List).map((c) => Map<String, dynamic>.from(c as Map)).toList()
          : <Map<String, dynamic>>[];
      final porNombre = <String, Map<String, dynamic>>{};
      for (final ficha in fichas) {
        porNombre[_clave(_texto(ficha, 'razon_social'))] = ficha;
        final carpeta = _clave(_texto(ficha, 'carpeta_disco_k'));
        if (carpeta.isNotEmpty) porNombre.putIfAbsent(carpeta, () => ficha);
      }
      final carpetas = (json.decode(disco.body) as List).map((c) => Map<String, dynamic>.from(c as Map)).toList();
      final lista = <Map<String, dynamic>>[];
      final ya = <String>{};
      for (final carpeta in carpetas) {
        final nombre = _texto(carpeta, 'empresa').isNotEmpty ? _texto(carpeta, 'empresa') : _texto(carpeta, 'carpeta');
        if (nombre.isEmpty) continue;
        final ficha = porNombre[_clave(nombre)] ?? porNombre[_clave(_texto(carpeta, 'carpeta'))];
        if (ficha != null) {
          lista.add(ficha);
          final id = ficha['id'];
          if (id != null) ya.add('id:$id');
        } else {
          lista.add({'razon_social': nombre, 'carpeta': carpeta['carpeta'], 'ordenes': 0, 'por_presupuestar': 0});
        }
        ya.add(_clave(nombre));
        ya.add(_clave(_texto(carpeta, 'carpeta')));
      }
      // Clientes cargados en el panel aunque la empresa no tenga una carpeta en un servidor.
      for (final ficha in fichas) {
        final id = ficha['id'];
        if (id != null && ya.contains('id:$id')) continue;
        final nombre = _clave(_texto(ficha, 'razon_social'));
        final carpeta = _clave(_texto(ficha, 'carpeta_disco_k'));
        if (nombre.isEmpty) continue;
        if (ya.contains(nombre) || (carpeta.isNotEmpty && ya.contains(carpeta))) continue;
        lista.add(ficha);
        ya.add(nombre);
      }
      lista.sort((a, b) => _clave(_texto(a, 'razon_social')).compareTo(_clave(_texto(b, 'razon_social'))));
      setState(() {
        _clientes = lista;
        _error = null;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = mensajeSinConexion;
          _cargando = false;
        });
      }
    }
  }

  Future<void> _abrir([Map<String, dynamic>? cliente]) async {
    final guardado = await showDialog<bool>(context: context, builder: (_) => DialogoCliente(cliente: cliente));
    if (guardado != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(cliente == null ? 'Cliente creado' : 'Cliente actualizado')));
    _cargar();
  }

  List<Map<String, dynamic>> get _visibles {
    return _clientes.where((c) {
      final texto = [
        for (final campo in ['razon_social', 'contacto', 'telefono', 'email', 'cuit', 'actividad', 'ciudad', 'departamento', 'provincia']) _texto(c, campo),
      ].join(' ');
      return coincideBusqueda(texto, _busqueda.text);
    }).toList();
  }

  Widget _tarjeta(Map<String, dynamic> cliente) {
    final contacto = _texto(cliente, 'contacto');
    final telefono = _texto(cliente, 'telefono');
    final email = _texto(cliente, 'email');
    final ubicacion = [_texto(cliente, 'ciudad'), _texto(cliente, 'departamento'), _texto(cliente, 'provincia')].where((p) => p.isNotEmpty).join(', ');
    final direccion = _texto(cliente, 'direccion_principal');
    final actividad = _texto(cliente, 'actividad');
    final riesgo = _texto(cliente, 'riesgo');
    final categoria = _texto(cliente, 'categoria');
    final cuit = _texto(cliente, 'cuit');
    final ordenes = (cliente['ordenes'] as num?)?.toInt() ?? 0;
    final pendientes = (cliente['por_presupuestar'] as num?)?.toInt() ?? 0;
    final sinContacto = contacto.isEmpty && telefono.isEmpty && email.isEmpty;

    Widget etiqueta(String texto) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: sonTarjetaAlta, borderRadius: BorderRadius.circular(20), border: Border.all(color: sonBorde)),
          child: Text(texto, style: TextStyle(color: sonTexto, fontSize: 12, fontWeight: FontWeight.w600)),
        );

    return InkWell(
      key: Key('cliente_${cliente['id'] ?? cliente['carpeta'] ?? _texto(cliente, 'razon_social')}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => _abrir(cliente),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
        decoration: decoracionTarjeta(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.business_outlined, color: sonLightGreen, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_texto(cliente, 'razon_social'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sonTexto, fontWeight: FontWeight.bold, fontSize: 17))),
                if (pendientes > 0) Tooltip(message: 'Notas de técnicos sin presupuestar', child: EtiquetaEstado(texto: '$pendientes por presupuestar', color: sonAmbar)),
              ],
            ),
            const SizedBox(height: 10),
            if (sinContacto)
              Text('Sin datos de contacto todavía. Tocá la ficha para completarlos.', style: TextStyle(color: sonTextoSuave, fontSize: 13))
            else ...[
              if (contacto.isNotEmpty) DatoConIcono(icono: Icons.person_outline, texto: contacto, color: sonTexto),
              if (telefono.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: DatoConIcono(icono: Icons.phone_outlined, texto: telefono)),
              if (email.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: DatoConIcono(icono: Icons.mail_outline, texto: email)),
            ],
            if (ubicacion.isNotEmpty || direccion.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: DatoConIcono(icono: Icons.place_outlined, texto: ubicacion.isNotEmpty ? ubicacion : direccion)),
            const Spacer(),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (actividad.isNotEmpty) etiqueta(actividad),
                if (riesgo.isNotEmpty) etiqueta('Riesgo $riesgo'),
                if (categoria.isNotEmpty) etiqueta('Categoría $categoria'),
                if (cuit.isNotEmpty) etiqueta('CUIT $cuit'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(ordenes == 1 ? '1 orden de trabajo' : '$ordenes órdenes de trabajo', style: TextStyle(color: sonTextoSuave, fontSize: 12.5)),
                const Spacer(),
                Icon(Icons.edit_outlined, size: 18, color: sonAzul),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: sonRojo)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _cargar, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (_clientes.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(
            'Todavía no hay clientes. Con Nuevo cliente se carga el primero: nombre, contacto y dirección. Las visitas de ese cliente quedan archivadas en SON.',
            textAlign: TextAlign.center,
            style: TextStyle(color: sonTextoSuave, fontSize: 16, height: 1.45),
          ),
        ),
      );
    }
    final visibles = _visibles;
    if (visibles.isEmpty) return Center(child: Text('No se encontró ningún cliente con esa búsqueda.', style: TextStyle(color: sonTextoSuave)));
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 440, mainAxisExtent: 272, crossAxisSpacing: 18, mainAxisSpacing: 18),
      itemCount: visibles.length,
      itemBuilder: (_, i) => _tarjeta(visibles[i]),
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
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EncabezadoPantalla(eyebrow: 'Comercial', normal: 'Cartera de', destacado: 'clientes'),
                  ],
                ),
              ),
              ElevatedButton.icon(
                key: const Key('nuevo_cliente'),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo cliente'),
                onPressed: () => _abrir(),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              SizedBox(
                width: 340,
                child: TextField(
                  key: const Key('buscar_cliente'),
                  controller: _busqueda,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, contacto, CUIT, ciudad...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    suffixIcon: _busqueda.text.isEmpty
                        ? null
                        : IconButton(tooltip: 'Borrar búsqueda', icon: const Icon(Icons.close, size: 18), onPressed: _busqueda.clear),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              if (!_cargando && _error == null)
                Text(_clientes.length == 1 ? '1 cliente' : '${_clientes.length} clientes', style: TextStyle(color: sonTextoSuave)),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }
}

/// Ventana para crear un cliente nuevo o completar la ficha de uno existente.
/// Devuelve `true` si se guardó.
class DialogoCliente extends StatefulWidget {
  final Map<String, dynamic>? cliente;

  const DialogoCliente({super.key, this.cliente});

  @override
  State<DialogoCliente> createState() => _DialogoClienteState();
}

class _DialogoClienteState extends State<DialogoCliente> {
  late final Map<String, dynamic> _datos = widget.cliente ?? {};
  late final TextEditingController _nombre = TextEditingController(text: _texto(_datos, 'razon_social'));
  late final TextEditingController _cuit = TextEditingController(text: _texto(_datos, 'cuit'));
  late final TextEditingController _contacto = TextEditingController(text: _texto(_datos, 'contacto'));
  late final TextEditingController _telefono = TextEditingController(text: _texto(_datos, 'telefono'));
  late final TextEditingController _email = TextEditingController(text: _texto(_datos, 'email'));
  late final TextEditingController _direccion = TextEditingController(text: _texto(_datos, 'direccion_principal'));
  late final TextEditingController _departamento = TextEditingController(text: _texto(_datos, 'departamento'));
  late final TextEditingController _ciudad = TextEditingController(text: _texto(_datos, 'ciudad'));
  late final TextEditingController _actividad = TextEditingController(text: _texto(_datos, 'actividad'));
  late final TextEditingController _notas = TextEditingController(text: _texto(_datos, 'notas'));
  final FocusNode _focoActividad = FocusNode();
  late String _provincia = _texto(_datos, 'provincia');
  late String _riesgo = _texto(_datos, 'riesgo');
  late String _categoria = _texto(_datos, 'categoria');
  String? _error;
  bool _guardando = false;

  bool get _esNuevo => widget.cliente == null || widget.cliente!['id'] == null;

  @override
  void dispose() {
    for (final controlador in [_nombre, _cuit, _contacto, _telefono, _email, _direccion, _departamento, _ciudad, _actividad, _notas]) {
      controlador.dispose();
    }
    _focoActividad.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() {
      _error = null;
      _guardando = true;
    });
    final cuerpo = json.encode({
      'razon_social': _nombre.text,
      'cuit': _cuit.text,
      'contacto': _contacto.text,
      'telefono': _telefono.text,
      'email': _email.text,
      'direccion_principal': _direccion.text,
      'provincia': _provincia,
      'departamento': _departamento.text,
      'ciudad': _ciudad.text,
      'actividad': _actividad.text,
      'riesgo': _riesgo,
      'categoria': _categoria,
      'notas': _notas.text,
    });
    try {
      final respuesta = _esNuevo ? await apiSend('POST', '/api/clientes', cuerpo) : await apiSend('PUT', '/api/clientes/${_datos['id']}', cuerpo);
      if (!mounted) return;
      if (respuesta.statusCode == 200) {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _error = mensajeError(respuesta, 'No se pudo guardar el cliente');
        _guardando = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = mensajeSinConexion;
          _guardando = false;
        });
      }
    }
  }

  /// Desplegable con "sin definir" al principio. Si el valor guardado no está en la lista, se agrega.
  Widget _desplegable({required String etiqueta, required String valor, required List<String> opciones, required ValueChanged<String> alCambiar, Key? clave}) {
    final todas = [if (valor.isNotEmpty && !opciones.contains(valor)) valor, ...opciones];
    return DropdownButtonFormField<String>(
      key: clave,
      initialValue: valor,
      isExpanded: true,
      decoration: InputDecoration(labelText: etiqueta),
      items: [
        DropdownMenuItem(value: '', child: Text('Sin definir', style: TextStyle(color: sonTextoSuave))),
        for (final opcion in todas) DropdownMenuItem(value: opcion, child: Text(opcion, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (nuevo) => alCambiar(nuevo ?? ''),
    );
  }

  Widget _campoActividad() {
    return LayoutBuilder(
      builder: (context, restricciones) => RawAutocomplete<String>(
        textEditingController: _actividad,
        focusNode: _focoActividad,
        optionsBuilder: (valor) {
          final buscado = sinAcentos(valor.text);
          return actividadesSugeridas.where((a) => buscado.isEmpty || sinAcentos(a).contains(buscado));
        },
        fieldViewBuilder: (context, controlador, foco, alEnviar) => TextField(
          controller: controlador,
          focusNode: foco,
          decoration: const InputDecoration(labelText: 'Actividad', suffixIcon: Icon(Icons.arrow_drop_down)),
        ),
        optionsViewBuilder: (context, alElegir, opciones) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 220, maxWidth: restricciones.maxWidth),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [for (final opcion in opciones) ListTile(dense: true, title: Text(opcion), onTap: () => alElegir(opcion))],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fila(List<Widget> campos) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < campos.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(child: campos[i]),
          ],
        ],
      ),
    );
  }

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(texto.toUpperCase(), style: TextStyle(color: sonLightGreen, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1)),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esNuevo ? 'Nuevo cliente' : 'Ficha del cliente'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titulo('Empresa'),
              _fila([TextField(key: const Key('campo_nombre'), controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre de la empresa *'))]),
              _fila([
                TextField(key: const Key('campo_cuit'), controller: _cuit, decoration: const InputDecoration(labelText: 'CUIT', hintText: '30-12345678-9')),
                _campoActividad(),
              ]),
              _fila([
                _desplegable(etiqueta: 'Riesgo de incendio', valor: _riesgo, opciones: riesgosIncendio, alCambiar: (v) => _riesgo = v, clave: const Key('campo_riesgo')),
                _desplegable(etiqueta: 'Categoría', valor: _categoria, opciones: categoriasEmpresa, alCambiar: (v) => _categoria = v, clave: const Key('campo_categoria')),
              ]),
              _titulo('Contacto'),
              _fila([
                TextField(controller: _contacto, decoration: const InputDecoration(labelText: 'Persona de contacto')),
                TextField(controller: _telefono, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
              ]),
              _fila([TextField(key: const Key('campo_email'), controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo electrónico'))]),
              _titulo('Ubicación'),
              _fila([TextField(controller: _direccion, decoration: const InputDecoration(labelText: 'Dirección'))]),
              _fila([
                _desplegable(etiqueta: 'Provincia', valor: _provincia, opciones: provinciasArgentinas, alCambiar: (v) => _provincia = v, clave: const Key('campo_provincia')),
                TextField(controller: _departamento, decoration: const InputDecoration(labelText: 'Departamento')),
                TextField(controller: _ciudad, decoration: const InputDecoration(labelText: 'Ciudad')),
              ]),
              _titulo('Notas'),
              TextField(controller: _notas, maxLines: 3, maxLength: 2000, decoration: const InputDecoration(hintText: 'Ej: paga a 30 días, avisar antes de ir')),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: sonRojo, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (!_esNuevo)
          TextButton.icon(
            onPressed: () => abrirAccesoCliente(context, (_datos['id'] as num).toInt(), '${_datos['razon_social'] ?? ''}'),
            icon: const Icon(Icons.link),
            label: const Text('Acceso del cliente'),
          ),
        TextButton(onPressed: _guardando ? null : () => Navigator.pop(context, false), child: Text('Cancelar', style: TextStyle(color: sonTextoSuave))),
        ElevatedButton(key: const Key('guardar_cliente'), onPressed: _guardando ? null : _guardar, child: Text(_esNuevo ? 'Crear cliente' : 'Guardar')),
      ],
    );
  }
}
