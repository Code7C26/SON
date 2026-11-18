"""
Transcribe la voz en off con tiempos por palabra (faster-whisper, modelo small, español).
Uso (desde video-presentacion/):
    python scripts/transcribir.py assets/voz-nueva/fernanda.mp3
Escribe assets/voz-nueva/palabras.json: [{"palabra", "inicio", "fin"}, ...]
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys

import numpy as np
from faster_whisper import WhisperModel

ruta = pathlib.Path(sys.argv[1])
# El audio se decodifica con ffmpeg (16 kHz, mono) para no depender de la versión de PyAV
ffmpeg = shutil.which("ffmpeg") or os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Links", "ffmpeg.exe")
crudo = subprocess.run([ffmpeg, "-v", "error", "-i", str(ruta), "-f", "s16le", "-ac", "1", "-ar", "16000", "-"], capture_output=True, check=True).stdout
audio = np.frombuffer(crudo, np.int16).astype(np.float32) / 32768.0
modelo = WhisperModel("small", device="cpu", compute_type="int8")
segmentos, _ = modelo.transcribe(
    audio,
    language="es",
    word_timestamps=True,
    initial_prompt="SON, checklist, GPS, PDF, remito, ecosistema.",
)
palabras = []
for seg in segmentos:
    for w in seg.words:
        palabras.append({"palabra": w.word.strip(), "inicio": round(w.start, 3), "fin": round(w.end, 3)})
(ruta.parent / "palabras.json").write_text(json.dumps(palabras, ensure_ascii=False, indent=1), encoding="utf-8")
print(" ".join(f'{p["palabra"]}@{p["inicio"]}' for p in palabras))
