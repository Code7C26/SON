"""
Genera la voz en off del video de SON con Elena (Microsoft es-AR-ElenaNeural, vía edge-tts).
Requiere internet y:  python -m pip install --user edge-tts

Uso (desde video-presentacion/):
    python scripts/voz.py

Crea assets/voz/<id>.mp3 (una frase por momento del video) y assets/voz/tiempos.json
con la duración de cada frase y el momento en que Elena dice cada palabra.
Para cambiar lo que dice la voz, editá GUION y volvé a correrlo.
"""
import asyncio
import json
import pathlib

import edge_tts

VOZ = "es-AR-ElenaNeural"
VELOCIDAD = "+0%"

GUION = [
    ("desorden", "Planillas en papel. Mensajes sueltos. Y un informe que tarda días en salir."),
    ("dudas", "¿El técnico fue a la planta? ¿Dónde quedó el remito firmado?"),
    ("son", "Con SON, toda su operación queda sincronizada en un único ecosistema."),
    ("panel", "Desde el panel, usted asigna la visita."),
    ("celular", "Y la orden llega al celular del técnico."),
    ("checkin", "Al llegar, el GPS registra que está en el sitio."),
    ("checklist", "Completa el checklist, saca las fotos,"),
    ("firma", "y el cliente firma en la pantalla."),
    ("informe", "Al finalizar, SON arma el informe en PDF, con fotos y firmas, y se lo envía al cliente junto con una encuesta."),
    ("cierre", "Sin papeles. Sin pasar en limpio. Sin esperar días."),
    ("marca", "SON. Agende una demostración."),
]


async def generar(clave: str, texto: str, carpeta: pathlib.Path) -> dict:
    comunicar = edge_tts.Communicate(texto, VOZ, rate=VELOCIDAD, boundary="WordBoundary")
    palabras = []
    with open(carpeta / f"{clave}.mp3", "wb") as archivo:
        async for parte in comunicar.stream():
            if parte["type"] == "audio":
                archivo.write(parte["data"])
            elif parte["type"] == "WordBoundary":
                palabras.append({
                    "palabra": parte["text"],
                    "inicio": round(parte["offset"] / 1e7, 3),
                    "fin": round((parte["offset"] + parte["duration"]) / 1e7, 3),
                })
    return {"id": clave, "texto": texto, "palabras": palabras}


async def main() -> None:
    carpeta = pathlib.Path("assets/voz")
    carpeta.mkdir(parents=True, exist_ok=True)
    tiempos = [await generar(clave, texto, carpeta) for clave, texto in GUION]
    (carpeta / "tiempos.json").write_text(json.dumps(tiempos, ensure_ascii=False, indent=2), encoding="utf-8")
    for t in tiempos:
        fin = t["palabras"][-1]["fin"] if t["palabras"] else 0
        print(f'{t["id"]:10s} habla hasta {fin:5.2f}s  {t["texto"]}')


asyncio.run(main())
