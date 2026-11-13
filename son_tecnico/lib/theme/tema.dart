import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

export 'app_colors.dart';
export 'app_motion.dart';
export 'app_spacing.dart';
export 'app_typography.dart';

/// Paleta activa de SON. Los valores salen de [AppColors]; esta clase solo
/// agrupa qué token corresponde a cada rol en modo claro u oscuro.
class PaletaSon {
  final Color fondo;
  final Color panel;
  final Color tarjeta;
  final Color tarjetaAlta;
  final Color relleno;
  final Color borde;
  final Color texto;
  final Color textoSuave;
  final Color textoTenue;
  final Color acento;
  final Color sobreAcento;
  final Color tinta;
  final Color oro;
  final Color progreso;
  final Color exito;
  final Color error;
  final List<Color> degradado;

  const PaletaSon({
    required this.fondo,
    required this.panel,
    required this.tarjeta,
    required this.tarjetaAlta,
    required this.relleno,
    required this.borde,
    required this.texto,
    required this.textoSuave,
    required this.textoTenue,
    required this.acento,
    required this.sobreAcento,
    required this.tinta,
    required this.oro,
    required this.progreso,
    required this.exito,
    required this.error,
    required this.degradado,
  });
}

const PaletaSon paletaClara = PaletaSon(
  fondo: AppColors.canvas,
  panel: AppColors.superficie,
  tarjeta: AppColors.superficie,
  tarjetaAlta: AppColors.superficieAlta,
  relleno: AppColors.canvas,
  borde: AppColors.borde,
  texto: AppColors.texto,
  textoSuave: AppColors.textoSecundario,
  textoTenue: AppColors.textoTenue,
  acento: AppColors.acento,
  sobreAcento: AppColors.sobreAcento,
  tinta: AppColors.tinta,
  oro: AppColors.oro,
  progreso: AppColors.progreso,
  exito: AppColors.exito,
  error: AppColors.error,
  degradado: [AppColors.canvas, AppColors.canvas],
);

const PaletaSon paletaOscura = PaletaSon(
  fondo: AppColors.oscuroFondo,
  panel: AppColors.oscuroPanel,
  tarjeta: AppColors.oscuroSuperficie,
  tarjetaAlta: AppColors.oscuroSuperficieAlta,
  relleno: AppColors.oscuroFondo,
  borde: AppColors.oscuroBorde,
  texto: AppColors.oscuroTexto,
  textoSuave: AppColors.oscuroTextoSecundario,
  textoTenue: AppColors.oscuroTextoTenue,
  acento: AppColors.acento,
  sobreAcento: AppColors.sobreAcento,
  tinta: AppColors.tinta,
  oro: AppColors.oro,
  progreso: AppColors.oscuroProgreso,
  exito: AppColors.exito,
  error: AppColors.oscuroError,
  degradado: [AppColors.oscuroFondo, AppColors.oscuroFondo],
);

class ControlTema extends ChangeNotifier {
  /// SON arranca en modo claro; el oscuro queda como opción.
  ThemeMode modo = ThemeMode.light;
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

// Accesos rápidos a la paleta activa. Los nombres viejos se mantienen para no
// romper pantallas; en pantallas nuevas usar los de la derecha.
/// Texto/ícono sobre el acento coral (blanco). Nombre histórico.
Color get sonDarkGreen => controlTema.paleta.sobreAcento;
/// Acento coral. Nombre histórico.
Color get sonLightGreen => controlTema.paleta.acento;
Color get sonAcento => controlTema.paleta.acento;
Color get sonSobreAcento => controlTema.paleta.sobreAcento;
Color get sonTinta => controlTema.paleta.tinta;
Color get sonFondo => controlTema.paleta.fondo;
Color get sonPanel => controlTema.paleta.panel;
Color get sonTarjeta => controlTema.paleta.tarjeta;
Color get sonTarjetaAlta => controlTema.paleta.tarjetaAlta;
Color get sonBorde => controlTema.paleta.borde;
Color get sonTexto => controlTema.paleta.texto;
Color get sonTextoSuave => controlTema.paleta.textoSuave;
Color get sonTextoTenue => controlTema.paleta.textoTenue;
Color get sonAmbar => controlTema.paleta.oro;
/// Color de "en progreso" (naranja tostado). Nombre histórico.
Color get sonAzul => controlTema.paleta.progreso;
Color get sonExito => controlTema.paleta.exito;
Color get sonRojo => controlTema.paleta.error;

ThemeData temaSon() => temaCon(paletaClara, Brightness.light);

ThemeData temaCon(PaletaSon p, Brightness brillo) {
  final oscuro = brillo == Brightness.dark;
  final base = oscuro ? const ColorScheme.dark() : const ColorScheme.light();
  final esquema = base.copyWith(
    primary: p.acento,
    onPrimary: p.sobreAcento,
    primaryContainer: oscuro ? AppColors.eyebrowTexto : AppColors.eyebrowFondo,
    onPrimaryContainer: oscuro ? AppColors.eyebrowFondo : AppColors.eyebrowTexto,
    secondary: p.oro,
    onSecondary: AppColors.sobreOro,
    // Selección (chips, segmentos): bloque oscuro en claro, bloque claro en oscuro.
    secondaryContainer: oscuro ? AppColors.canvas : AppColors.tinta,
    onSecondaryContainer: oscuro ? AppColors.tinta : AppColors.superficie,
    surface: p.tarjeta,
    onSurface: p.texto,
    onSurfaceVariant: p.textoSuave,
    surfaceContainerHighest: p.tarjetaAlta,
    error: p.error,
    onError: AppColors.superficie,
    outline: p.borde,
    outlineVariant: p.borde,
    surfaceTint: Colors.transparent,
  );

  OutlineInputBorder borde(Color color, [double ancho = 1]) =>
      OutlineInputBorder(borderRadius: AppRadius.rInput, borderSide: BorderSide(color: color, width: ancho));

  const pildora = StadiumBorder();
  final textos = AppTypography.textTheme(p.texto, p.textoSuave);
  const ui = AppTypography.ui;
  const display = AppTypography.display;
  // Bloque de alto contraste para snackbars y tooltips.
  final bloque = oscuro ? AppColors.canvas : AppColors.tinta;
  final sobreBloque = oscuro ? AppColors.tinta : AppColors.superficie;

  return ThemeData(
    useMaterial3: true,
    brightness: brillo,
    colorScheme: esquema,
    primaryColor: p.acento,
    scaffoldBackgroundColor: p.fondo,
    canvasColor: p.tarjeta,
    fontFamily: ui,
    textTheme: textos,
    dividerColor: p.borde,
    dividerTheme: DividerThemeData(color: p.borde, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: p.textoSuave),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: p.fondo,
      foregroundColor: p.texto,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      iconTheme: IconThemeData(color: p.texto),
      actionsIconTheme: IconThemeData(color: p.texto),
      titleTextStyle: TextStyle(
        fontFamily: display,
        color: p.texto,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: AppTypography.trackingTitulo,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.tarjeta,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.rTarjeta, side: BorderSide(color: p.borde)),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: p.borde,
      labelColor: p.texto,
      unselectedLabelColor: p.textoSuave,
      indicatorColor: p.acento,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: const TextStyle(fontFamily: ui, fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle: const TextStyle(fontFamily: ui, fontWeight: FontWeight.w500, fontSize: 14),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: p.panel,
      selectedItemColor: oscuro ? p.texto : p.tinta,
      unselectedItemColor: p.textoTenue,
      selectedLabelStyle: const TextStyle(fontFamily: ui, fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelStyle: const TextStyle(fontFamily: ui, fontWeight: FontWeight.w500, fontSize: 12),
      elevation: 0,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.acento,
      foregroundColor: p.sobreAcento,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 2,
      highlightElevation: 0,
      shape: pildora,
      extendedTextStyle: const TextStyle(fontFamily: ui, fontWeight: FontWeight.w600, fontSize: 15),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.acento, linearTrackColor: p.tarjetaAlta),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: oscuro ? p.relleno : p.tarjeta,
      labelStyle: TextStyle(fontFamily: ui, color: p.textoSuave),
      floatingLabelStyle: TextStyle(fontFamily: ui, color: p.texto, fontWeight: FontWeight.w600),
      helperStyle: TextStyle(fontFamily: ui, color: p.textoSuave),
      hintStyle: TextStyle(fontFamily: ui, color: p.textoTenue),
      prefixIconColor: p.textoTenue,
      suffixIconColor: p.textoTenue,
      border: borde(p.borde),
      enabledBorder: borde(p.borde),
      focusedBorder: borde(p.acento, 1.5),
      errorBorder: borde(p.error),
      focusedErrorBorder: borde(p.error, 1.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24, vertical: AppSpacing.s16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: p.acento,
        foregroundColor: p.sobreAcento,
        iconColor: p.sobreAcento,
        disabledBackgroundColor: p.tarjetaAlta,
        disabledForegroundColor: p.textoTenue,
        elevation: 0,
        minimumSize: const Size(AppSpacing.tactilMinimo, AppSpacing.tactilMinimo),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24, vertical: AppSpacing.s12),
        shape: pildora,
        textStyle: const TextStyle(fontFamily: ui, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: oscuro ? AppColors.canvas : AppColors.tinta,
        foregroundColor: oscuro ? AppColors.tinta : AppColors.superficie,
        minimumSize: const Size(AppSpacing.tactilMinimo, AppSpacing.tactilMinimo),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24, vertical: AppSpacing.s12),
        shape: pildora,
        textStyle: const TextStyle(fontFamily: ui, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.acento,
        minimumSize: const Size(AppSpacing.tactilMinimo, AppSpacing.tactilMinimo),
        textStyle: const TextStyle(fontFamily: ui, fontWeight: FontWeight.w600),
        shape: pildora,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.texto,
        side: BorderSide(color: p.borde),
        minimumSize: const Size(AppSpacing.tactilMinimo, AppSpacing.tactilMinimo),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24, vertical: AppSpacing.s12),
        textStyle: const TextStyle(fontFamily: ui, fontWeight: FontWeight.w600),
        shape: pildora,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        textStyle: const TextStyle(fontFamily: ui, fontWeight: FontWeight.w600),
        shape: pildora,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: p.texto)),
    chipTheme: ChipThemeData(
      backgroundColor: p.tarjeta,
      selectedColor: esquema.secondaryContainer,
      secondarySelectedColor: esquema.secondaryContainer,
      checkmarkColor: esquema.onSecondaryContainer,
      side: BorderSide(color: p.borde),
      shape: pildora,
      labelStyle: TextStyle(fontFamily: ui, color: p.texto, fontWeight: FontWeight.w500),
      secondaryLabelStyle: TextStyle(fontFamily: ui, color: esquema.onSecondaryContainer, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.tarjeta,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.rTarjetaGrande),
      titleTextStyle: TextStyle(
        fontFamily: display,
        color: p.texto,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: AppTypography.trackingTitulo,
      ),
      contentTextStyle: TextStyle(fontFamily: ui, color: p.texto, fontSize: 15),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.tarjeta,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.borde,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.tarjetaGrande)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: bloque,
      contentTextStyle: TextStyle(fontFamily: ui, color: sobreBloque, fontSize: 14),
      actionTextColor: p.acento,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const StadiumBorder(),
    ),
    listTileTheme: ListTileThemeData(
      textColor: p.texto,
      iconColor: p.textoSuave,
      titleTextStyle: TextStyle(fontFamily: ui, fontSize: 15, fontWeight: FontWeight.w500, color: p.texto),
      subtitleTextStyle: TextStyle(fontFamily: ui, fontSize: 13, color: p.textoSuave),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.rTarjeta),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? p.sobreAcento : p.textoTenue),
      trackColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? p.acento : p.tarjetaAlta),
      trackOutlineColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? p.acento : p.borde),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? p.acento : p.textoTenue)),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((e) => e.contains(WidgetState.selected) ? p.acento : Colors.transparent),
      checkColor: WidgetStateProperty.all(p.sobreAcento),
      side: BorderSide(color: p.textoTenue, width: 1.5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(p.relleno),
      headingTextStyle: TextStyle(fontFamily: ui, color: p.textoSuave, fontWeight: FontWeight.w600, fontSize: 13),
      dataTextStyle: TextStyle(fontFamily: ui, color: p.texto, fontSize: 14),
      dividerThickness: 1,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.tarjeta,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: const Color(0x14000000),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.rTarjeta, side: BorderSide(color: p.borde)),
      textStyle: TextStyle(fontFamily: ui, color: p.texto),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: bloque, borderRadius: AppRadius.rPildora),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: 6),
      textStyle: TextStyle(fontFamily: ui, color: sobreBloque, fontSize: 12),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: p.tarjeta,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.rTarjetaGrande),
    ),
    scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStateProperty.all(p.borde)),
  );
}

BoxDecoration decoracionTarjeta({Color? color, double radio = AppRadius.tarjeta, Color? borde, bool sombra = false}) => BoxDecoration(
      color: color ?? sonTarjeta,
      borderRadius: BorderRadius.circular(radio),
      border: Border.all(color: borde ?? sonBorde),
      boxShadow: sombra ? AppShadows.suave : null,
    );

BoxDecoration get decoracionIngreso => BoxDecoration(
      gradient: RadialGradient(center: const Alignment(0, -0.6), radius: 1.3, colors: controlTema.paleta.degradado),
    );

TextStyle get estiloTituloPantalla => TextStyle(
      fontFamily: AppTypography.display,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: AppTypography.trackingTitulo,
      color: sonTexto,
    );
TextStyle get estiloSubtitulo => TextStyle(fontFamily: AppTypography.ui, color: sonTextoSuave, fontSize: 15);

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
