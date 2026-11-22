# Revisión: tutorial «Cómo funciona SON» (v1)

Video final: `assets/SON-tutorial-en.mp4` (carpeta `assets/` de la raíz del repositorio), 115 s (1:55), 1920 × 1080, 30 fps. Guion de voz: `GUION-EN.md`.

## Cómo se hicieron las imágenes
- **Todas las pantallas son capturas reales** del panel (`son_admin`) y de la app del técnico (`son_tecnico`), compiladas
  para web y servidas por el backend en un puerto aparte (3020) con una base aislada `son_tutorial`
  (sin correo saliente). No se tocó `sima_db`.
- El recorrido se hizo de verdad: se creó la orden de Metalúrgica Andina desde «Nueva orden», Martín la abrió en la app,
  hizo el check-in por GPS (ubicación simulada en Av. Colón 1250), tildó el checklist, subió dos fotos, escribió la nota,
  firmaron los dos y tocó Finalizar. El backend generó el PDF y la encuesta; la encuesta se respondió con 5.
- Panel capturado a 1920 × 1080; app y encuesta a 390 × 844 con densidad 2.5 (975 × 2110).
- **Datos de ejemplo inventados**: clientes, técnicos (Martín Ruiz, Sofía Gómez, Diego Ferreyra, Valentina Torres),
  administradora (Lucía Pérez), visitas anteriores y encuestas. Las fotos de evidencia son `backend/temp_foto_0.png`.

## Retoques sobre datos (no sobre imágenes)
- El PDF se regeneró con el mismo generador (`backend/src/pdf.js`) y horario 09:41–10:38 h, porque la grabación
  se hizo de noche y el informe original decía 21:22 h y 3 minutos de visita.
- Las encuestas de ejemplo figuran como enviadas (en esta base el correo está apagado, así que el envío no quedó registrado).
- El encabezado y el pie del PDF (logo y contacto de la consultora) quedan fuera del recorte: se muestra solo el cuerpo del informe.

## Qué se midió
- `hyperframes check`: sin errores. Avisos que quedan a propósito: la etiqueta coral sobre coral al 12 % (regla de
  marca del CLAUDE.md, 2.39:1) y la dirección de la barra del navegador a 14 px (decorado).
- Se revisaron cuadros de cada escena y de cada corte.
- **Voz (v2)**: locución de ElevenLabs (`assets/voz/locucion.mp3`, 89 s, −17.4 LUFS), transcrita con
  `scripts/transcribir.py` (tiempos por palabra en `assets/voz/palabras.json`) y cortada en 15 frases; cada una
  se ubicó para que su palabra clave caiga en la acción («Nueva orden», «Asignar», «abre», «iniciar», «check-in»,
  «tildando», «fotos», «Notas», «firman», «finalizar», «tareas/fotos/firmas», «envía», «califica», «completada»,
  «Análisis», «satisfacción»). Para eso se adelantaron algunos toques de la app y de Resultados, y la escena del
  informe pasó de 12 a 9 s: el video quedó en **1:55**.
- **Música (v2)**: «educational presentation tutorial» de Monume (Pixabay), 60.5 s, duplicada con un fundido de 2 s
  en 59.4 s (`assets/musica/tutorial-loop.mp3`); a 0.2 bajo la voz y 0.38 en el cierre.

## Detalle encontrado en la app (no se corrigió)
- En la pantalla de Firmas, la vista previa muestra solo los primeros 160 px del lienzo de firma: si el técnico firma
  en el medio de la pantalla completa, la tarjeta queda en blanco aunque la firma esté guardada.
  (`son_tecnico/lib/main.dart`, `_tarjetaFirma`: reusa `Signature` en un contenedor de 160 px de alto en vez de escalar la firma.)

## Voz clonada (v3, 22/11/2026)
- La autora clonó su voz en ElevenLabs (Instant Voice Clone) y generó la locución en español y en inglés.
  Archivos normalizados a −17.5 LUFS: `assets/voz/locucion-clon-es.mp3` (87.9 s) y `locucion-clon-en.mp3` (82.4 s).
- `scripts/armar_index.py <es|en>` arma `index.html`: corta cada frase en sus silencios y la ubica para que su palabra
  clave caiga en la acción. En español dos frases se corren menos de 0.6 s para no pisarse; en inglés ninguna.
- Versión en inglés: carpeta hermana `video-tutorial-en/` (mismas escenas y capturas, con los textos agregados
  traducidos; las pantallas del sistema siguen en español porque son capturas reales).
