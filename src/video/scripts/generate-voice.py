"""
Genera la locución del video con voz femenina mexicana (Microsoft es-MX-DaliaNeural).
Requiere internet y Python 3.

Uso (desde la carpeta del proyecto Remotion):
    pip install edge-tts
    python scripts/generate-voice.py

Crea public/audio/intro.mp3, plan.mp3, field.mp3, ... (uno por escena).
Para cambiar lo que dice la voz, edite los textos de abajo y vuelva a ejecutar.
"""
import asyncio
import pathlib

import edge_tts

VOICE = "es-MX-DaliaNeural"
RATE = "-5%"  # un poco más pausada; use "+0%" para velocidad normal

SCRIPT = {
    "intro": "Conozca SON Operation Platform. La plataforma que simplifica y pone bajo control la gestión de sus operaciones técnicas.",
    "plan": "Todo empieza en la planificación. Desde el panel central, usted asigna visitas, clientes y listas de verificación, y supervisa la agenda de su equipo en tiempo real.",
    "field": "En terreno, cada técnico usa la app móvil. Usted ve su ubicación en vivo en el mapa, el sistema valida su presencia por GPS, y el técnico registra la evidencia fotográfica y la firma digital del cliente, incluso sin conexión.",
    "quality": "Al terminar el servicio, SON genera de inmediato el acta técnica en PDF, con fotografías y firmas, y se la envía al cliente junto con una encuesta de satisfacción.",
    "modules": "Órdenes recurrentes, agenda dinámica, alertas automáticas, informes y analítica de rendimiento. Toda su operación, en un único ecosistema.",
    "demo": "¿Quiere verlo en acción? Agende una demostración técnica personalizada para su equipo.",
    "closing": "SON. Sincronización total entre la administración y el campo.",
}


async def main() -> None:
    out = pathlib.Path("public/audio")
    out.mkdir(parents=True, exist_ok=True)
    for name, text in SCRIPT.items():
        path = out / f"{name}.mp3"
        await edge_tts.Communicate(text, VOICE, rate=RATE).save(str(path))
        print("OK", path)


asyncio.run(main())
