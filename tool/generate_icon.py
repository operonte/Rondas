"""Genera el icono de Control de Rondas.

Escudo (seguridad) con un reloj adentro (las rondas son por horario), sobre el
azul oscuro de la app. Se dibuja a 4x y se reduce, para que los bordes queden
suaves sin depender de antialiasing del rasterizador.
"""
import math
import os
from PIL import Image, ImageDraw

BG_DARK = (15, 23, 42)      # AppColors.background
BG_DEEP = (8, 14, 29)
ACCENT = (56, 189, 248)     # AppColors.accent
ACCENT_DK = (14, 165, 233)  # AppColors.accentStrong
WHITE = (255, 255, 255)

SS = 4  # supersampling


def shield_points(cx, cy, w, h):
    """Contorno de escudo: hombros rectos arriba, punta abajo."""
    half = w / 2
    top = cy - h / 2
    bot = cy + h / 2
    pts = [(cx - half, top), (cx + half, top)]
    # Lado derecho: recto y luego curva hacia la punta
    for i in range(1, 41):
        t = i / 40
        y = top + h * (0.42 + 0.58 * t)
        x = cx + half * (1 - t ** 2.1)
        pts.append((x, y))
    pts.append((cx, bot))
    # Lado izquierdo, espejado
    for i in range(40, 0, -1):
        t = i / 40
        y = top + h * (0.42 + 0.58 * t)
        x = cx - half * (1 - t ** 2.1)
        pts.append((x, y))
    return pts


def draw_icon(size, with_bg=True, shield_scale=0.62):
    S = size * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if with_bg:
        # Fondo con degradado vertical sutil
        for y in range(S):
            t = y / S
            c = tuple(int(BG_DARK[i] + (BG_DEEP[i] - BG_DARK[i]) * t) for i in range(3))
            d.line([(0, y), (S, y)], fill=c + (255,))

    cx, cy = S / 2, S / 2
    sw = S * shield_scale
    sh = sw * 1.16

    # Escudo relleno con degradado: se pinta sobre una máscara
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(shield_points(cx, cy, sw, sh), fill=255)

    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        t = y / S
        c = tuple(int(ACCENT[i] + (ACCENT_DK[i] - ACCENT[i]) * t) for i in range(3))
        gd.line([(0, y), (S, y)], fill=c + (255,))
    img.paste(grad, (0, 0), mask)

    # Reloj: círculo hueco y agujas, calados sobre el escudo
    r = sw * 0.30
    ring = max(2, int(S * 0.016))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=BG_DARK + (255,), width=ring)

    hand = max(2, int(S * 0.020))
    # Horaria hacia las 10, minutero hacia las 2: lectura clara a tamaño chico
    for ang_deg, length in ((-150, 0.58), (-30, 0.78)):
        a = math.radians(ang_deg)
        d.line(
            [(cx, cy), (cx + math.cos(a) * r * length, cy + math.sin(a) * r * length)],
            fill=BG_DARK + (255,), width=hand,
        )
    d.ellipse([cx - hand, cy - hand, cx + hand, cy + hand], fill=BG_DARK + (255,))

    return img.resize((size, size), Image.LANCZOS)


def rounded(img, radius_ratio=0.22):
    """Recorta esquinas redondeadas para el icono heredado."""
    size = img.size[0]
    mask = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size * SS, size * SS], radius=int(size * SS * radius_ratio), fill=255
    )
    mask = mask.resize((size, size), Image.LANCZOS)
    out = img.copy()
    out.putalpha(mask)
    return out


ROOT = "/home/cristian/X/Github/Rondas"
DENSITIES = {
    "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
}

for name, px in DENSITIES.items():
    outdir = os.path.join(ROOT, "android/app/src/main/res", f"mipmap-{name}")
    os.makedirs(outdir, exist_ok=True)
    rounded(draw_icon(px)).save(os.path.join(outdir, "ic_launcher.png"))
    # Adaptativo: el sistema recorta el 33% exterior, así que el escudo va
    # más chico y el fondo va aparte.
    draw_icon(int(px * 1.5), with_bg=False, shield_scale=0.40).save(
        os.path.join(outdir, "ic_launcher_foreground.png"))

# Web y tienda
web = os.path.join(ROOT, "web/icons")
os.makedirs(web, exist_ok=True)
for px, fname in ((192, "Icon-192.png"), (512, "Icon-512.png")):
    draw_icon(px).save(os.path.join(web, fname))
    rounded(draw_icon(px), 0.0).save(os.path.join(web, fname.replace("Icon-", "Icon-maskable-")))
draw_icon(32).save(os.path.join(ROOT, "web/favicon.png"))
draw_icon(512).save("/tmp/claude-1000/-home-cristian-X-Github-Rondas/6ef203db-e2f4-48d3-be9d-e871314ba918/scratchpad/icon_preview.png")
print("iconos generados")
