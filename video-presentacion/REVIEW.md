# Revisión: «Una visita, de punta a punta» (v1)

Video: `renders/SON-presentacion.mp4`, 55.7 s, 1920 × 1080, 30 fps.
Voz: Fernanda (ElevenLabs), `assets/voz-nueva/fernanda-v2.mp3`, normalizada a −17.5 LUFS (`fernanda-v2-norm.mp3`) y recortada por frase con `data-media-start`;
cada frase se ubicó para que su palabra ancla caiga en su animación (tiempos por palabra en `assets/voz-nueva/palabras.json`, hechos con `scripts/transcribir.py`).
Música: paulyudin «minimal» (Pixabay), `assets/musica/minimal.mp3`, desde 4.8 s del tema para que su entrada fuerte coincida con SON (12 s);
baja durante el desorden (0.35), 0.6 bajo la voz, 0.9 en el cierre de marca, con fundido final.
Mezcla medida: −15.2 LUFS integrados, pico −1.2 dBFS. La voz anterior (Elena) quedó en `assets/voz` sin usar.

## Decisiones creativas
- Se armó la idea A de `STORYLINES.md`. Quedaron sin armar la B («El reloj de arena») y la C («Varios días contra un momento»).
- Las pantallas de SON se rearmaron a partir del código: textos y pasos reales de `son_tecnico/lib/main.dart`
  (Tu jornada de hoy, Iniciar trabajo / Ubicando..., Check-in registrado, Tareas · Evidencia · Notas · Firmas,
  Tu firma y sello van solos, Tocar para firmar, Finalizar), el formulario «Nueva orden» y el botón «Asignar Trabajo» del panel,
  y las secciones del PDF (`backend/src/pdf.js`: Informe de visita, Tareas, Evidencias, Firmas).
- **Datos de ejemplo inventados:** Orden #1042, Metalúrgica Andina S.A., Martín Ruiz, Lucía Pérez, Av. Colón 1250, horarios, las otras filas de la tabla
  y las tres fotos de evidencia (ilustraciones, no fotos reales).
- «En el acto» sale de `Perfil del Cliente y Validación de la Idea.pdf` («tener el acta firmada en el acto»).
- El CTA «Pedir demo» y `sonoperation.com` salen de la landing (`backend/presentacion/index.html`) y de `despliegue/.env`.
- Efectos de Pixabay (licencia libre) en cada acción visible.
- Final rehecho (v2): bloque oscuro con el reloj de arena dibujado y llenado, logo, frase de marca, CTA con clic y cinta de módulos del README.

## Qué se midió y qué no
- `hyperframes check`: sin errores. Se revisaron cuadros fijos de cada escena y de cada corte.
- **El audio se midió, pero nadie lo escuchó**.

## Advertencias que se dejaron a propósito
- Textos de UI dentro del celular y del panel por debajo de 28 px: son la interfaz real; lo que hay que leer va en las palabras grandes y la voz.
- `line_unread` en burbujas, «Tocar para firmar», «Tu firma y sello van solos» y el correo: son estados de la UI que pasan mientras la voz explica.

## La toma más floja y qué cambiaría
- El panel (16.6–19.6 s) dura 3 s y es rápido: con más tiempo, una toma más larga mostrando el mapa con técnicos.
- Las pantallas son reconstrucciones: con capturas o una grabación real con datos de ejemplo, la parte central ganaría credibilidad.

## Para cambiar
- Texto de la voz: `scripts/voz.py` (después hay que volver a ubicar los tiempos en `index.html` y en cada escena).
- Escenas: `compositions/*.html`. Plan de tomas: `SPEC.md`.
