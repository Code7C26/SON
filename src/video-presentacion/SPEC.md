# SPEC: «Una visita, de punta a punta»

GOAL:    el dueño de una consultora de HyS ve su propio desorden ordenarse y quiere «Pedir demo».
OUTPUT:  HyperFrames, 1920 × 1080, 30 fps.
TIME:    52.5 s × 30 = 1575 cuadros. Sin música: la voz de Elena marca el reloj (cada evento cae en su palabra).
LOOK:    canvas #F4F4F4 plano; tarjetas #FFFFFF, borde 1 px #D5D5D5, sombra 0 8px 20px rgba(46,46,46,.04-.10);
         tinta #2E2E2E; texto 2.º #6E6E6E; tenue #9A9A9A; relleno #E7E7E7.
         Coral #FF6147 solo en: el isologo, el botón principal de cada pantalla, el pin del GPS, la palabra clave del cierre y el CTA.
         Dorado #D99C13 solo en «Pendiente» y las estrellas de la encuesta. Panel web en su modo oscuro real
         (#2E2E2E / #262626 / #353535, bordes #4C4C4C).
         Display: Plus Jakarta Sans 400 + 700 en el mismo titular, 64–120 px, tracking −0.5 px (−1 a −2 px en tamaños grandes).
         Texto UI: Inter 400/600/700, nunca menos de 28 px en lo que hay que leer (texto de UI dentro del celular a escala 1.6× o más).
         Medio: UI real de SON reconstruida desde el código (son_tecnico/lib/main.dart, son_admin), papel y burbujas planas.
         Radios 16–24 px tarjetas, 999 px píldoras. Sin grano, sin viñeta, sin brillos.
OBJECTS: planilla de papel (hoja blanca rayada con renglones a mano en trazo #6E6E6E, levemente girada); burbujas de chat genéricas
         (blancas, sin marca de WhatsApp); planilla de cálculo genérica (grilla #D5D5D5); reloj de arena = isotipo real (assets/img/isotipo.png);
         panel web (sidebar real: Panel de Control, Órdenes de Trabajo, Técnicos, Informes, Análisis…);
         celular (marco #2E2E2E radio 64, pantalla 440 × 950 con la app en tema claro: «Tu jornada de hoy», «Iniciar trabajo»,
         «Check-in registrado», pasos Tareas · Evidencia · Notas · Firmas, «Tocar para firmar», «Finalizar»);
         informe PDF A4 («Informe de visita»: Tareas, Evidencias, Firmas); correo al cliente con adjunto PDF y encuesta de 5 estrellas.
         Datos de ejemplo: Orden #1042, «Metalúrgica Andina S.A.», técnico «Martín Ruiz»: inventados, ilustrativos.
MOTION:  llegada expo.out / power4.out 0.5–0.7 s; cámara power2.inOut 0.6 s; salida y zoom-through power3.in 0.35–0.45 s.
         Escalonado: palabras 0.07 s, ítems de lista 0.06 s. Títulos quietos una vez que llegan.
SHOTS:
  0.0–11.6  caos      Hoja de papel ya en cuadro (cuadro 0 = miniatura). Burbujas caen en «Mensajes» (2.5 s), grilla en «informe» (4.9 s),
                      etiqueta «Informe pendiente» con el día rodando (lunes→jueves) en «días» (5.8 s). En «planta» (8.2) y «remito» (10.3)
                      llegan dos burbujas más y el montón tapa la hoja. 11.1–11.6: todo es succionado al centro (power3.in, blur 10 px). Sonido: pop por burbuja.
  11.6–16.6 reveal    El isotipo aparece en el punto de succión, gira 180° (el reloj se da vuelta) en «SON» (12.25). Titular a la derecha:
                      «Oficina y campo, / **en la misma página**» palabra por palabra en «sincronizada» (14.2). 16.1–16.6: el isotipo
                      vuela arriba a la izquierda (carry across) y la escena se va. Sonido: whoosh al girar.
  16.6–19.6 panel     El panel real en modo oscuro llena el cuadro; el isotipo ya está en su sidebar. La fila de la Orden #1042 «Por asignar»
                      se destaca; cámara empuja 1.6× a la fila; cursor clic «Asignar Trabajo» en «asigna» (18.3); la píldora pasa a «Pendiente»
                      y aparece «Martín Ruiz». 19.2–19.6: la tarjeta de la fila sale a la derecha con blur (power3.in). Sonido: click.
  19.6–31.6 campo     Celular grande a la derecha (x≈1290), palabra-paso grande a la izquierda (blur swap). La tarjeta entra desde la izquierda
                      a la lista «Tu jornada de hoy» (match de dirección) en «orden» (20.3) → toque → detalle con «Iniciar trabajo» →
                      toque en «GPS» (23.7) «Ubicando…» → mapa con pin coral + «Check-in registrado» en «sitio» (25.4) →
                      Checklist 3 ítems tildados (27.1) → fotos en grilla (28.5) → «Firma y sello del cliente» se dibuja en «firma» (30.0) →
                      dedo sobre «Finalizar» 31.3. Palabras-paso: «Asignada», «En el sitio», «Checklist», «Firmada». Sonido: click en cada toque, pop por tilde.
  31.6–39.6 informe   La pantalla del celular se convierte en la hoja A4 (morph) en «finalizar». La hoja se arma por secciones en «informe/PDF» (33.7),
                      fotos y firma vuelan a su lugar en «fotos»/«firmas» (35.4/35.9) — el momento grande. En «envía» (37.1) la hoja se pliega
                      en un correo al cliente; en «encuesta» (38.5) 5 estrellas doradas se llenan. Sonido: whoosh al plegar, notificación al llegar.
  39.6–46.0 cierre    Inundación de color a #2E2E2E. Tres renglones del caos, uno a la vez, tachados en su palabra: «Planillas en papel» (40.4),
                      «Pasar en limpio» (42.7), «Varios días» (44.9) que rueda a «En el acto» en coral. Sonido: ninguno extra.
  46.0–52.5 marca     Canvas claro. Las dos medias lunas del isotipo entran de arriba y abajo y se tocan en el centro en «SON» (46.7);
                      la palabra SON (logo real) se descubre a la derecha; en «Agende» (48.0) aparece el botón «Pedir demo» y sonoperation.com.
                      Quieto 2.5 s.
BANNED:  vacío oscuro con cosas chicas flotando; brillos, partículas, degradés azules/violetas; papel crema + serif; todo centrado;
         todo entrando con fade + subida; tres tarjetas en fila; logo en una esquina; verdes, azules o grises azulados;
         texto blanco sobre coral; marcas reales de terceros (WhatsApp, Excel); repetir en pantalla la frase exacta de la voz.
QA:      0.0 (miniatura no vacía) · 9.5 (montón) · 12.6 (reloj girado) · 18.6 (asignación) · 25.6 (check-in) · 28.8 (fotos) ·
         30.8 (firma) · 36.0 (informe completo) · 38.9 (correo + estrellas) · 45.3 («En el acto») · 50.5 (cierre de marca).
