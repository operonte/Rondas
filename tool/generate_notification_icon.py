"""Genera el icono de notificacion (status bar) de Control de Rondas.

Android tine estos iconos a blanco solido e ignora el color/RGB: solo importa
el canal alfa (forma). Por eso NO se puede usar el ic_launcher a color como
notification icon (Android 5+ lo renderiza como un bloque blanco sin forma
reconocible) -- hace falta una silueta separada. Reusa el contorno de escudo
de generate_icon.py para mantener el mismo lenguaje visual.
"""
import os
from PIL import Image, ImageDraw

SS = 4  # supersampling

ROOT = "/home/cristian/X/Github/Rondas"
# Tamanios de notification icon (status bar), distintos de los de ic_launcher.
DENSITIES = {
    "mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96,
}


def shield_points(cx, cy, w, h):
    half = w / 2
    top = cy - h / 2
    bot = cy + h / 2
    pts = [(cx - half, top), (cx + half, top)]
    for i in range(1, 41):
        t = i / 40
        y = top + h * (0.42 + 0.58 * t)
        x = cx + half * (1 - t ** 2.1)
        pts.append((x, y))
    pts.append((cx, bot))
    for i in range(40, 0, -1):
        t = i / 40
        y = top + h * (0.42 + 0.58 * t)
        x = cx - half * (1 - t ** 2.1)
        pts.append((x, y))
    return pts


def draw_notification_icon(size):
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    cx, cy = S / 2, S / 2
    sw = S * 0.72
    sh = sw * 1.16
    d.polygon(shield_points(cx, cy, sw, sh), fill=(255, 255, 255, 255))

    return img.resize((size, size), Image.LANCZOS)


for name, px in DENSITIES.items():
    outdir = os.path.join(ROOT, "android/app/src/main/res", f"drawable-{name}")
    os.makedirs(outdir, exist_ok=True)
    draw_notification_icon(px).save(os.path.join(outdir, "ic_stat_rondas.png"))

print("icono de notificacion generado")
