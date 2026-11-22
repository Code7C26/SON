"""
Arma index.html: escenas, voz (cortada en frases y ubicada en su acción), música y efectos.
Uso (desde la carpeta del proyecto):
    python scripts/armar_index.py es    -> voz assets/voz/locucion-clon-es.mp3
    python scripts/armar_index.py en    -> voz assets/voz/locucion-clon-en.mp3
Cada frase se corta en los silencios (tiempos por palabra en <voz>-palabras.json, de scripts/transcribir.py)
y se coloca para que su palabra clave caiga en el clic o toque que nombra. Si una frase pisaría a la anterior,
se corre y se avisa.
"""
import json
import subprocess
import sys
import unicodedata

import numpy as np

LANG = sys.argv[1] if len(sys.argv) > 1 else "es"
TOTAL = 115
VOZ = f"assets/voz/locucion-clon-{LANG}.mp3"

# (id, primeras palabras de la frase, palabra clave, segundo del video en que cae la palabra clave)
FRASES = {
    "es": [
        ("apertura", ("son", "paso"), "son", 0.6),
        ("inicio", ("todo", "empieza"), "todo", 6.4),
        ("ordenes", ("en", "ordenes"), "en", 16.3),
        ("nueva", ("para", "programar"), "nueva", 22.2),
        ("asignar", ("con", "asignar"), "asignar", 34.75),
        ("jornada", ("martin",), "abre", 41.7),
        ("gps", ("son", "registra"), "check", 46.4),
        ("checklist", ("primero",), "primero", 53.75),
        ("fotos", ("despues",), "fotos", 60.6),
        ("notas", ("en", "notas"), "notas", 64.9),
        ("firmas", ("al", "final"), "finalizar", 74.7),
        ("informe", ("en", "ese"), "tareas", 81.2),
        ("encuesta", ("el", "cliente", "lo"), "califica", 89.8),
        ("resultados", ("de", "vuelta"), "completada", 96.6),
        ("cierre", ("son", "toda"), "son", 108.4),
    ],
    "en": [
        ("apertura", ("son", "step"), "son", 0.6),
        ("inicio", ("it", "all"), "it", 6.4),
        ("ordenes", ("in", "work"), "in", 16.3),
        ("nueva", ("to", "schedule"), "new", 22.2),
        ("asignar", ("with",), "a", 34.75),
        ("jornada", ("martin",), "opens", 41.7),
        ("gps", ("son", "records"), "check", 46.4),
        ("checklist", ("first",), "first", 53.75),
        ("fotos", ("then", "he"), "photo", 60.6),
        ("notas", ("in", "notes"), "notes", 64.9),
        ("firmas", ("finally",), "finish", 74.7),
        ("informe", ("at", "that"), "tasks", 81.2),
        ("encuesta", ("the", "client", "receives"), "rates", 89.8),
        ("resultados", ("back", "in"), "completed", 96.6),
        ("cierre", ("sun",), "sun", 108.4),
    ],
}[LANG]


def norm(p):
    p = unicodedata.normalize("NFD", p.lower())
    return "".join(c for c in p if c.isalnum())


palabras = json.load(open(VOZ.replace(".mp3", "-palabras.json"), encoding="utf-8"))
tokens = [norm(w["palabra"]) for w in palabras]
dur_archivo = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", VOZ],
                                   capture_output=True, text=True).stdout)

# Dónde empieza cada frase en el archivo
inicios, desde = [], 0
for _, pref, _, _ in FRASES:
    i = next(k for k in range(desde, len(tokens)) if tuple(tokens[k:k + len(pref)]) == pref)
    inicios.append(i)
    desde = i + 1

# Energía del audio cada 10 ms: los cortes van en el silencio real, no en los tiempos de la transcripción
# (whisper marca el inicio de una palabra antes de que termine la anterior, y eso partía palabras).
crudo = subprocess.run(["ffmpeg", "-v", "error", "-i", VOZ, "-f", "s16le", "-ac", "1", "-ar", "16000", "-"],
                       capture_output=True, check=True).stdout
muestras = np.frombuffer(crudo, np.int16).astype(np.float32) / 32768.0
PASO = 160  # 10 ms
db = 20 * np.log10(np.sqrt(np.convolve(muestras[: len(muestras) // PASO * PASO].reshape(-1, PASO).__pow__(2).mean(1),
                                        np.ones(6) / 6, mode="same")) + 1e-9)


def corte(j):
    """Punto más silencioso entre el final de la frase anterior y el arranque de la palabra j."""
    a = int((palabras[j - 1]["inicio"] + 0.15) * 100)
    b = int((palabras[j]["inicio"] + 0.8) * 100)
    k = a + int(np.argmin(db[a:b]))
    return k / 100, float(db[k])


cortes = {}
for n in range(1, len(FRASES)):
    cortes[n] = corte(inicios[n])
    print(f"  corte antes de {FRASES[n][0]:11s} en {cortes[n][0]:6.2f} s ({cortes[n][1]:.0f} dB)")
    if cortes[n][1] > -45:
        print(f"  aviso: el corte antes de «{FRASES[n][0]}» no cae en silencio ({cortes[n][1]:.0f} dB)")

clips, fin_anterior = [], -1.0
for n, (nombre, _, clave, objetivo) in enumerate(FRASES):
    i = inicios[n]
    j = inicios[n + 1] if n + 1 < len(FRASES) else len(palabras)
    m_ini = cortes[n][0] if n in cortes else 0.0
    m_fin = cortes[n + 1][0] if n + 1 in cortes else dur_archivo
    k = next(x for x in range(i, j) if tokens[x] == clave)
    inicio = round(objetivo - (palabras[k]["inicio"] - m_ini), 2)
    if inicio < fin_anterior + 0.1:
        print(f"  aviso: {nombre} se corre {fin_anterior + 0.1 - inicio:.2f} s para no pisar la frase anterior")
        inicio = round(fin_anterior + 0.1, 2)
    dur = round(m_fin - m_ini, 2)
    clips.append((f"voz-{nombre}", inicio, round(m_ini, 2), dur))
    fin_anterior = inicio + dur
    print(f"  {nombre:11s} {inicio:7.2f} -> {inicio + dur:7.2f}  («{palabras[k]['palabra']}» en {objetivo})")
assert fin_anterior <= TOTAL - 0.5, "la voz se pasa del final"

vtags = "\n".join(
    f'      <audio id="{i}" class="clip" src="{VOZ}" data-start="{s}" data-media-start="{m}" data-duration="{d}" data-track-index="{3 + k % 2}" data-volume="1"></audio>'
    for k, (i, s, m, d) in enumerate(clips))

clicks = [7.15, 8.2, 16.2, 22.1, 24.0, 26.9, 29.45, 32.0, 34.9,
          41.7, 43.0, 55.6, 56.9, 59.5, 61.0, 62.6, 64.9, 65.9, 68.5, 69.5, 71.7, 72.6, 73.7, 74.8,
          90.0, 98.1, 99.25, 100.9]
pops = [55.8, 57.1, 90.35, 90.55, 90.75]
whoosh = [5.45, 37.55, 77.55, 86.4, 93.55, 107.55]
sfx = []
for n, t in enumerate(clicks, 1):
    sfx.append(f'      <audio id="sfx-clic-{n}" class="clip" src="assets/sfx/click-soft.mp3" data-start="{t}" data-duration="0.36" data-track-index="{5 + n % 2}" data-volume="0.4"></audio>')
for n, t in enumerate(pops, 1):
    sfx.append(f'      <audio id="sfx-pop-{n}" class="clip" src="assets/sfx/pop.mp3" data-start="{t}" data-duration="0.2" data-track-index="{7 + n % 2}" data-volume="0.22"></audio>')
for n, t in enumerate(whoosh, 1):
    sfx.append(f'      <audio id="sfx-whoosh-{n}" class="clip" src="assets/sfx/whoosh-short.mp3" data-start="{t}" data-duration="0.57" data-track-index="9" data-volume="0.25"></audio>')
sfx.append('      <audio id="sfx-correo" class="clip" src="assets/sfx/notification.mp3" data-start="83.8" data-duration="2.45" data-track-index="10" data-volume="0.22"></audio>')
sfx.append('      <audio id="sfx-reloj" class="clip" src="assets/sfx/click-soft.mp3" data-start="1.3" data-duration="0.36" data-track-index="10" data-volume="0.4"></audio>')
sfx.append('      <audio id="sfx-reloj-2" class="clip" src="assets/sfx/click-soft.mp3" data-start="109.75" data-duration="0.36" data-track-index="10" data-volume="0.4"></audio>')

sube = round(fin_anterior + 0.1, 2)
auto = {"version": 1, "lanes": [{"target": "volume", "points": [
    {"t": 0, "v": 0}, {"t": 0.6, "v": 0.2}, {"t": sube, "v": 0.2}, {"t": round(sube + 0.6, 2), "v": 0.38},
    {"t": 113.6, "v": 0.38}, {"t": 114.95, "v": 0}]}]}
auto_s = json.dumps(auto).replace('"', "&quot;")

escenas = [("apertura", 0, 6, 0, 3), ("panel", 6, 32, 1, 1), ("app", 38, 40, 1, 1), ("informe", 78, 9, 1, 1),
           ("encuesta", 87, 7, 1, 1), ("resultados", 94, 14, 1, 1), ("cierre", 108, 7, 1, 1), ("guia", 6, 102, 2, 5)]
hosts = "\n".join(
    f'      <div id="{i}" class="clip" data-composition-id="{i}" data-composition-src="compositions/{i}.html" data-start="{s}" data-duration="{d}" data-track-index="{tr}" data-track-kind="graphics" data-width="1920" data-height="1080" style="z-index: {z}"></div>'
    for i, s, d, tr, z in escenas)

html = f'''<!doctype html>
<html lang="{LANG}">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=1920, height=1080" />
    <script src="https://cdn.jsdelivr.net/npm/gsap@3.15.0/dist/gsap.min.js"></script>
    <style>
      * {{ margin: 0; padding: 0; box-sizing: border-box; }}
      html, body {{ margin: 0; width: 1920px; height: 1080px; overflow: hidden; background: #f4f4f4; }}
      #root {{ width: 100%; height: 100%; position: relative; }}
    </style>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="{TOTAL}" data-width="1920" data-height="1080">
      <!-- Escenas: capturas reales del panel web y de la app del técnico (assets/capturas) -->
{hosts}

      <!-- Voz en off: voz clonada de la autora (ElevenLabs), normalizada a -17.5 LUFS, una frase por pantalla.
           Generado con scripts/armar_index.py {LANG}: cada frase cae en su acción. -->
{vtags}

      <!-- Música: «educational presentation tutorial» (Monume, Pixabay), duplicada con fundido de 2 s en 59.4 s
           (assets/musica/tutorial-loop.mp3). Baja bajo la voz y sube en el cierre. -->
      <audio id="musica" class="clip" src="assets/musica/tutorial-loop.mp3" data-start="0" data-media-start="0" data-duration="{TOTAL}" data-track-index="11" data-volume="1" data-timeline-role="music" data-automation="{auto_s}"></audio>

      <!-- Efectos: cada uno con su causa en pantalla (clic, toque, tilde, cambio de escena, correo) -->
{chr(10).join(sfx)}
    </div>
    <script>
      window.__timelines = window.__timelines || {{}};
      window.__timelines["main"] = gsap.timeline({{ paused: true }});
    </script>
  </body>
</html>
'''
open("index.html", "w", encoding="utf-8").write(html)
print("index.html listo")
