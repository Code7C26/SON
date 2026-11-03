"""Arma los PNG transparentes del logo nuevo a partir de DESINGS."""
from pathlib import Path
from PIL import Image

raiz = Path(r"C:\Users\franc\SIMAOPERATION")
disenos = raiz / "DESINGS"


def quitar_negro(origen: Path) -> Image.Image:
    im = Image.open(origen).convert("RGBA")
    pix = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, _a = pix[x, y]
            m = max(r, g, b)
            if m < 16:
                pix[x, y] = (0, 0, 0, 0)
                continue
            alpha = min(255, int(m * 255 / 210))
            if alpha < 24:
                pix[x, y] = (0, 0, 0, 0)
                continue
            if alpha >= 250:
                pix[x, y] = (r, g, b, 255)
            else:
                pix[x, y] = (
                    min(255, int(r * 255 / alpha)),
                    min(255, int(g * 255 / alpha)),
                    min(255, int(b * 255 / alpha)),
                    alpha,
                )
    return im


def recortar(im: Image.Image, margen=0.06) -> Image.Image:
    caja = im.getbbox()
    if not caja:
        return im
    x0, y0, x1, y1 = caja
    ancho, alto = x1 - x0, y1 - y0
    mx, my = int(ancho * margen), int(alto * margen)
    x0, y0 = max(0, x0 - mx), max(0, y0 - my)
    x1, y1 = min(im.width, x1 + mx), min(im.height, y1 + my)
    return im.crop((x0, y0, x1, y1))


def cuadrado(im: Image.Image, lado: int, fondo, escala=0.72) -> Image.Image:
    lienzo = Image.new("RGBA", (lado, lado), fondo)
    marca = im.copy()
    tope = int(lado * escala)
    marca.thumbnail((tope, tope), Image.Resampling.LANCZOS)
    x = (lado - marca.width) // 2
    y = (lado - marca.height) // 2
    lienzo.alpha_composite(marca, (x, y))
    return lienzo


def guardar(im: Image.Image, destino: Path):
    destino.parent.mkdir(parents=True, exist_ok=True)
    im.save(destino, "PNG")


icono = recortar(quitar_negro(disenos / "5SINCOLOR.png"))
marca = recortar(quitar_negro(disenos / "1SINCOLOR.png"))

for app in ("son_admin", "son_tecnico"):
    imagenes = raiz / app / "assets" / "images"
    guardar(icono, imagenes / "logo_son_icono.png")
    guardar(marca, imagenes / "logo_son_claro.png")
    web = raiz / app / "web"
    guardar(cuadrado(icono, 64, (0, 0, 0, 0), 0.82), web / "favicon.png")
    for lado, nombre in (
        (192, "Icon-192.png"),
        (512, "Icon-512.png"),
        (192, "Icon-maskable-192.png"),
        (512, "Icon-maskable-512.png"),
    ):
        fondo = (0, 0, 0, 0) if "maskable" not in nombre else (0x2E, 0x2E, 0x2E, 255)
        escala = 0.78 if "maskable" not in nombre else 0.62
        guardar(cuadrado(icono, lado, fondo, escala), web / "icons" / nombre)

android = raiz / "son_tecnico" / "android" / "app" / "src" / "main" / "res"
for carpeta, lado in (
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192),
):
    guardar(cuadrado(icono, lado, (0x2E, 0x2E, 0x2E, 255), 0.68), android / carpeta / "ic_launcher.png")
    guardar(cuadrado(icono, lado, (0, 0, 0, 0), 0.68), android / carpeta / "ic_launcher_foreground.png")

print("icono", icono.size, "marca", marca.size)
