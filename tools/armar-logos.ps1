Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class LogosSon {
    public static Bitmap QuitarNegro(string ruta) {
        using (var origen = new Bitmap(ruta)) {
            var bmp = new Bitmap(origen.Width, origen.Height, PixelFormat.Format32bppArgb);
            var rect = new Rectangle(0, 0, origen.Width, origen.Height);
            var src = origen.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var dst = bmp.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            int bytes = Math.Abs(src.Stride) * src.Height;
            byte[] buffer = new byte[bytes];
            Marshal.Copy(src.Scan0, buffer, 0, bytes);
            origen.UnlockBits(src);
            for (int i = 0; i < bytes; i += 4) {
                int b = buffer[i];
                int g = buffer[i + 1];
                int r = buffer[i + 2];
                int m = Math.Max(r, Math.Max(g, b));
                if (m < 16) {
                    buffer[i] = buffer[i + 1] = buffer[i + 2] = buffer[i + 3] = 0;
                    continue;
                }
                int alpha = Math.Min(255, m * 255 / 210);
                if (alpha < 24) {
                    buffer[i] = buffer[i + 1] = buffer[i + 2] = buffer[i + 3] = 0;
                    continue;
                }
                if (alpha >= 250) {
                    buffer[i + 3] = 255;
                    continue;
                }
                buffer[i] = (byte)Math.Min(255, b * 255 / alpha);
                buffer[i + 1] = (byte)Math.Min(255, g * 255 / alpha);
                buffer[i + 2] = (byte)Math.Min(255, r * 255 / alpha);
                buffer[i + 3] = (byte)alpha;
            }
            Marshal.Copy(buffer, 0, dst.Scan0, bytes);
            bmp.UnlockBits(dst);
            return bmp;
        }
    }

    public static Bitmap Recortar(Bitmap im, double margen) {
        int minX = im.Width, minY = im.Height, maxX = 0, maxY = 0;
        for (int y = 0; y < im.Height; y++) {
            for (int x = 0; x < im.Width; x++) {
                if (im.GetPixel(x, y).A > 12) {
                    if (x < minX) minX = x;
                    if (y < minY) minY = y;
                    if (x > maxX) maxX = x;
                    if (y > maxY) maxY = y;
                }
            }
        }
        if (maxX < minX) return im;
        int ancho = maxX - minX + 1;
        int alto = maxY - minY + 1;
        int mx = (int)(ancho * margen);
        int my = (int)(alto * margen);
        minX = Math.Max(0, minX - mx);
        minY = Math.Max(0, minY - my);
        maxX = Math.Min(im.Width - 1, maxX + mx);
        maxY = Math.Min(im.Height - 1, maxY + my);
        var recorte = new Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1);
        return im.Clone(recorte, PixelFormat.Format32bppArgb);
    }

    public static Bitmap Cuadrado(Bitmap marca, int lado, Color fondo, double escala) {
        var lienzo = new Bitmap(lado, lado, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(lienzo)) {
            g.Clear(fondo);
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            int tope = (int)(lado * escala);
            float proporcion = Math.Min((float)tope / marca.Width, (float)tope / marca.Height);
            int w = Math.Max(1, (int)(marca.Width * proporcion));
            int h = Math.Max(1, (int)(marca.Height * proporcion));
            g.DrawImage(marca, (lado - w) / 2, (lado - h) / 2, w, h);
        }
        return lienzo;
    }
}
"@

$raiz = "C:\Users\franc\SIMAOPERATION"
$icono = [LogosSon]::Recortar([LogosSon]::QuitarNegro("$raiz\DESINGS\5SINCOLOR.png"), 0.08)
$marca = [LogosSon]::Recortar([LogosSon]::QuitarNegro("$raiz\DESINGS\1SINCOLOR.png"), 0.04)

function Guardar($im, $ruta) {
    $dir = Split-Path $ruta
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $im.Save($ruta, [System.Drawing.Imaging.ImageFormat]::Png)
}

foreach ($app in @("son_admin", "son_tecnico")) {
    Guardar $icono "$raiz\$app\assets\images\logo_son_icono.png"
    Guardar $marca "$raiz\$app\assets\images\logo_son_claro.png"
    $web = "$raiz\$app\web"
    Guardar ([LogosSon]::Cuadrado($icono, 64, [System.Drawing.Color]::FromArgb(0, 0, 0, 0), 0.82)) "$web\favicon.png"
    foreach ($par in @(
        @{ lado = 192; nombre = "Icon-192.png"; fondo = $true; escala = 0.78 },
        @{ lado = 512; nombre = "Icon-512.png"; fondo = $true; escala = 0.78 },
        @{ lado = 192; nombre = "Icon-maskable-192.png"; fondo = $false; escala = 0.62 },
        @{ lado = 512; nombre = "Icon-maskable-512.png"; fondo = $false; escala = 0.62 }
    )) {
        $color = if ($par.fondo) { [System.Drawing.Color]::FromArgb(0, 0, 0, 0) } else { [System.Drawing.Color]::FromArgb(255, 0x2E, 0x2E, 0x2E) }
        Guardar ([LogosSon]::Cuadrado($icono, $par.lado, $color, $par.escala)) "$web\icons\$($par.nombre)"
    }
}

$android = "$raiz\son_tecnico\android\app\src\main\res"
foreach ($par in @(
    @{ carpeta = "mipmap-mdpi"; lado = 48 },
    @{ carpeta = "mipmap-hdpi"; lado = 72 },
    @{ carpeta = "mipmap-xhdpi"; lado = 96 },
    @{ carpeta = "mipmap-xxhdpi"; lado = 144 },
    @{ carpeta = "mipmap-xxxhdpi"; lado = 192 }
)) {
    $oscuro = [System.Drawing.Color]::FromArgb(255, 0x2E, 0x2E, 0x2E)
    $vacio = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)
    Guardar ([LogosSon]::Cuadrado($icono, $par.lado, $oscuro, 0.68)) "$android\$($par.carpeta)\ic_launcher.png"
    Guardar ([LogosSon]::Cuadrado($icono, $par.lado, $vacio, 0.68)) "$android\$($par.carpeta)\ic_launcher_foreground.png"
}

"icono $($icono.Width)x$($icono.Height) marca $($marca.Width)x$($marca.Height)"
