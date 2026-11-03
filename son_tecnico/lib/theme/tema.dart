import 'package:flutter/material.dart';

/// Paleta de SON: coral, dorado y los dos fondos de la marca.
class PaletaSon {
  final Color fondo;
  final Color panel;
  final Color tarjeta;
  final Color tarjetaAlta;
  final Color borde;
  final Color texto;
  final Color textoSuave;
  final Color acento;
  final Color tinta;
  final Color oro;
  final Color progreso;
  final Color error;
  final List<Color> degradado;

  const PaletaSon({
    required this.fondo,
    required this.panel,
    required this.tarjeta,
    required this.tarjetaAlta,
    required this.borde,
    required this.texto,
    required this.textoSuave,
    required this.acento,
    required this.tinta,
    required this.oro,
    required this.progreso,
    required this.error,
    required this.degradado,
  });
}

const Color _coral = Color(0xFFFF6147);
const Color _oro = Color(0xFFD99C13);
const Color _tinta = Color(0xFF2E2E2E);
const Color _claro = Color(0xFFF4F4F4);

const PaletaSon paletaClara = PaletaSon(
  fondo: _claro,
  panel: Color(0xFFFFFFFF),
  tarjeta: Color(0xFFFFFFFF),
  tarjetaAlta: Color(0xFFE7E7E7),
  borde: Color(0xFFD5D5D5),
  texto: _tinta,
  textoSuave: Color(0xFF6E6E6E),
  acento: _coral,
  tinta: _tinta,
  oro: _oro,
  progreso: Color(0xFFC46A3A),
  error: Color(0xFFC62828),
  degradado: [_claro, _claro],
);

const PaletaSon paletaOscura = PaletaSon(
  fondo: _tinta,
  panel: Color(0xFF262626),
  tarjeta: Color(0xFF353535),
  tarjetaAlta: Color(0xFF3F3F3F),
  borde: Color(0xFF4C4C4C),
  texto: _claro,
  textoSuave: Color(0xFFB3B3B3),
  acento: _coral,
  tinta: _tinta,
  oro: _oro,
  progreso: Color(0xFFE08A55),
  error: Color(0xFFFF8A80),
  degradado: [_tinta, _tinta],
);

class ControlTema extends ChangeNotifier {
  ThemeMode modo = ThemeMode.dark;
  void Function(bool claro)? alGuardar;

  bool get claro => modo == ThemeMode.light;
  PaletaSon get paleta => claro ? paletaClara : paletaOscura;

  void establecer(bool claro, {bool avisar = true, bool guardar = false}) {
    final nuevo = claro ? ThemeMode.light : ThemeMode.dark;
    if (nuevo == modo) return;
    modo = nuevo;
    if (avisar) notifyListeners();
    if (guardar) alGuardar?.call(claro);
  }

  void alternar() => establecer(!claro, guardar: true);
}

final controlTema = ControlTema();

Color get sonDarkGreen => controlTema.paleta.tinta;
Color get sonLightGreen => controlTema.paleta.acento;
Color get sonFondo => controlTema.paleta.fondo;
Color get sonPanel => controlTema.paleta.panel;
Color get sonTarjeta => controlTema.paleta.tarjeta;
Color get sonTarjetaAlta => controlTema.paleta.tarjetaAlta;
Color get sonBorde => controlTema.paleta.borde;
Color get sonTexto => controlTema.paleta.texto;
Color get sonTextoSuave => controlTema.paleta.textoSuave;
Color get sonAmbar => controlTema.paleta.oro;
Color get sonAzul => controlTema.paleta.progreso;
Color get sonRojo => controlTema.paleta.error;

ThemeData temaSon() => temaCon(paletaOscura, Brightness.dark);

ThemeData temaCon(PaletaSon p, Brightness brillo) {
  final base = brillo == Brightness.dark ? const ColorScheme.dark() : const ColorScheme.light();
  final esquema = base.copyWith(
    primary: p.acento,
    onPrimary: p.tinta,
    secondary: p.oro,
    onSecondary: _tinta,
    surface: p.tarjeta,
    onSurface: p.texto,
    error: p.error,
    onError: _claro,
    outline: p.borde,
    surfaceTint: Colors.transparent,
  );

  OutlineInputBorder borde(Color color, [double ancho = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color, width: ancho));

  final textoBase = (brillo == Brightness.dark ? ThemeData.dark() : ThemeData.light()).textTheme;

  return ThemeData(
    useMaterial3: true,
    brightness: brillo,
    colorScheme: esquema,
    primaryColor: p.acento,
    scaffoldBackgroundColor: p.fondo,
    canvasColor: p.tarjeta,
    fontFamily: 'TuFuente',
    dividerColor: p.borde,
    dividerTheme: DividerThemeData(color: p.borde, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: p.textoSuave),
    textTheme: textoBase.apply(fontFamily: 'TuFuente', bodyColor: p.texto, displayColor: p.texto),
    appBarTheme: AppBarTheme(
      backgroundColor: p.fondo,
      foregroundColor: p.texto,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: p.texto),
      titleTextStyle: TextStyle(fontFamily: 'TuFuente', color: p.texto, fontSize: 20, fontWeight: FontWeight.bold),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: p.borde,
      labelColor: p.acento,
      unselectedLabelColor: p.textoSuave,
      indicatorColor: p.acento,
      labelStyle: const TextStyle(fontFamily: 'TuFuente', fontWeight: FontWeight.bold),
      unselectedLabelStyle: const TextStyle(fontFamily: 'TuFuente'),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: p.panel,
      selectedItemColor: p.acento,
      unselectedItemColor: p.textoSuave,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.acento,
      foregroundColor: p.tinta,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.acento, linearTrackColor: p.tarjetaAlta),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.tarjetaAlta.withValues(alpha: brillo == Brightness.dark ? 0.55 : 0.85),
      labelStyle: TextStyle(color: p.textoSuave),
      floatingLabelStyle: TextStyle(color: p.acento),
      helperStyle: TextStyle(color: p.textoSuave),
      hintStyle: TextStyle(color: p.textoSuave),
      border: borde(p.borde),
      enabledBorder: borde(p.borde),
      focusedBorder: borde(p.acento, 1.5),
      errorBorder: borde(p.error),
      focusedErrorBorder: borde(p.error, 1.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: p.acento,
        foregroundColor: p.tinta,
        disabledBackgroundColor: p.tarjetaAlta,
        disabledForegroundColor: p.textoSuave,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontFamily: 'TuFuente', fontWeight: FontWeight.bold),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.acento,
        textStyle: const TextStyle(fontFamily: 'TuFuente', fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.texto,
        side: BorderSide(color: p.borde),
        textStyle: const TextStyle(fontFamily: 'TuFuente', fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: p.texto)),
    dialogTheme: DialogThemeData(
      backgroundColor: p.tarjeta,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.borde)),
      titleTextStyle: TextStyle(fontFamily: 'TuFuente', color: p.texto, fontSize: 20, fontWeight: FontWeight.bold),
      contentTextStyle: TextStyle(fontFamily: 'TuFuente', color: p.texto, fontSize: 15),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.tarjetaAlta,
      contentTextStyle: TextStyle(fontFamily: 'TuFuente', color: p.texto),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: p.borde)),
    ),
    listTileTheme: ListTileThemeData(
      textColor: p.texto,
      iconColor: p.textoSuave,
      subtitleTextStyle: TextStyle(fontFamily: 'TuFuente', fontSize: 14, color: p.textoSuave),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? p.tinta : p.textoSuave),
      trackColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? p.acento : p.tarjetaAlta),
      trackOutlineColor: WidgetStateProperty.all(p.borde),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? p.acento : p.textoSuave)),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? p.acento : Colors.transparent),
      checkColor: WidgetStateProperty.all(p.tinta),
      side: BorderSide(color: p.textoSuave),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(p.tarjetaAlta),
      headingTextStyle: TextStyle(fontFamily: 'TuFuente', color: p.textoSuave, fontWeight: FontWeight.bold, fontSize: 13),
      dataTextStyle: TextStyle(fontFamily: 'TuFuente', color: p.texto, fontSize: 14),
      dividerThickness: 1,
    ),
    popupMenuTheme: PopupMenuThemeData(color: p.tarjetaAlta, textStyle: TextStyle(fontFamily: 'TuFuente', color: p.texto)),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.tarjetaAlta, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.borde)),
      textStyle: TextStyle(fontFamily: 'TuFuente', color: p.texto, fontSize: 12),
    ),
    datePickerTheme: DatePickerThemeData(backgroundColor: p.tarjeta, surfaceTintColor: Colors.transparent),
    scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStateProperty.all(p.borde)),
  );
}

BoxDecoration decoracionTarjeta({Color? color, double radio = 14, Color? borde}) => BoxDecoration(
      color: color ?? sonTarjeta,
      borderRadius: BorderRadius.circular(radio),
      border: Border.all(color: borde ?? sonBorde),
    );

BoxDecoration get decoracionIngreso => BoxDecoration(
      gradient: RadialGradient(center: const Alignment(0, -0.6), radius: 1.3, colors: controlTema.paleta.degradado),
    );

TextStyle get estiloTituloPantalla => TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: sonTexto);
TextStyle get estiloSubtitulo => TextStyle(color: sonTextoSuave, fontSize: 15);

class BotonTema extends StatelessWidget {
  const BotonTema({super.key});

  @override
  Widget build(BuildContext context) {
    final claro = controlTema.claro;
    return IconButton(
      tooltip: claro ? 'Tema oscuro' : 'Tema claro',
      onPressed: controlTema.alternar,
      icon: Icon(claro ? Icons.dark_mode_outlined : Icons.light_mode_outlined, color: sonTexto),
    );
  }
}

/// Vuelve a pintar lo que está en pantalla cuando se cambia el tema.
/// Los colores se leen al armar cada pantalla; si no se reconstruyen,
/// el fondo y los textos se quedan con el tema anterior.
class RepintadoTema extends StatefulWidget {
  final Widget child;
  const RepintadoTema({super.key, required this.child});

  @override
  State<RepintadoTema> createState() => _RepintadoTemaState();
}

class _RepintadoTemaState extends State<RepintadoTema> {
  @override
  void initState() {
    super.initState();
    controlTema.addListener(_repintar);
  }

  @override
  void dispose() {
    controlTema.removeListener(_repintar);
    super.dispose();
  }

  void _repintar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void marcar(Element elemento) {
        elemento.markNeedsBuild();
        elemento.visitChildren(marcar);
      }
      (context as Element).visitChildren(marcar);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
