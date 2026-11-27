"""VICEFOLD : compose les captures de l'App Store (titre + vraie capture du simulateur), en anglais et en français.

Usage : python3 compose.py <brutes> <sortie> [--sheet apercu.jpg]
Brutes : <appareil>-<lang>/NN-<écran>.png  (appareil : duo, iphone, ipad ; voir collect.py)
Sorties : duo-<lang>-N.png (2007×2853), <lang>-N.png (1290×2796), ipad-<lang>-N.png (2064×2752).
--sheet : écrit aussi une planche-contact (JPEG) de toutes les images composées, pour les relire d'un coup d'œil.

Même identité que l'app : la nuit de Leonida, des lueurs de néon, un horizon quadrillé, les titres en Anton (la
deuxième ligne dans le dégradé du coucher de soleil). Tout est dessiné ici avec Pillow : pas de navigateur.
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

SRC, OUT = sys.argv[1], sys.argv[2]
SHEET = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
os.makedirs(OUT, exist_ok=True)
ROUTES = ["home", "mappins", "mission", "thread", "collectibles", "eggs", "widgets", "guide", "characters"]
C = {
    "en": {"home": ("Your Leonida,", "at 100%"), "mappins": ("A detailed map,", "600 places and your pins"), "mission": ("All 91 missions,", "spoiler-free"),
           "collectibles": ("Every 100% category,", "with a counter"), "eggs": ("Every easter egg,", "spoiler-free"), "guide": ("Guides for", "every part of the game"), "characters": ("Who's who,", "with your notes"), "widgets": ("Progress widgets,", "synced with iCloud"), "thread": ("Stuck on a mission?", "Ask the community")},
    "fr": {"home": ("Ton Leonida,", "à 100 %"), "mappins": ("Une carte détaillée,", "600 lieux et tes épingles"), "mission": ("Les 91 missions,", "sans spoiler"),
           "collectibles": ("Tout le 100 %,", "avec un compteur"), "eggs": ("Tous les easter eggs,", "sans spoiler"), "guide": ("Des guides pour", "tout le jeu"), "characters": ("Qui est qui,", "avec tes notes"), "widgets": ("Widgets de progression,", "synchro iCloud"), "thread": ("Bloqué sur une mission ?", "Demande à la communauté")},
}
SIZES = {"duo": (2007, 2853, "duo-"), "iphone": (1290, 2796, ""), "ipad": (2064, 2752, "ipad-")}
ANTON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Fonts", "Anton-Regular.ttf")

# Les couleurs de l'app (Shared/Tokens.swift).
ABYSS = (4, 5, 14)
FLAMINGO = (255, 66, 153)
SUNSET = (255, 138, 61)
CYAN = (61, 230, 242)
VIOLET = (122, 77, 242)
TEXT = (245, 247, 255)


def glow(size, center, radius, color, strength):
    """Une lueur ronde (dégradé radial), dessinée en petit puis agrandie."""
    w, h = size
    k = 8
    small = Image.new("L", (w // k, h // k), 0)
    d = ImageDraw.Draw(small)
    cx, cy, r = center[0] / k, center[1] / k, radius / k
    steps = 40
    for i in range(steps, 0, -1):
        t = i / steps
        d.ellipse([cx - r * t, cy - r * t, cx + r * t, cy + r * t], fill=int(255 * strength * (1 - t) ** 1.6))
    mask = small.resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(k * 2))
    return Image.merge("RGBA", [Image.new("L", size, c) for c in color] + [mask])


def background(w, h):
    bg = Image.new("RGBA", (w, h), ABYSS + (255,))
    for center, radius, color, s in [((w * 1.0, h * 0.02), w * 1.1, FLAMINGO, 0.42), ((w * 0.0, h * 0.22), w * 0.9, VIOLET, 0.40),
                                     ((w * 0.1, h * 1.0), w * 1.0, CYAN, 0.20), ((w * 1.0, h * 0.86), w * 0.9, SUNSET, 0.22)]:
        bg = Image.alpha_composite(bg, glow((w, h), center, radius, color, s))
    # L'horizon quadrillé, en bas.
    grid = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(grid)
    hy = int(h * 0.80)
    lw = max(2, w // 700)
    for i in range(-16, 17):
        d.line([(w / 2, hy), (w / 2 + i * w / 5, h)], fill=FLAMINGO + (120,), width=lw)
    for k in range(1, 12):
        y = hy + (h - hy) * (k / 11) ** 2.2
        d.line([(0, y), (w, y)], fill=FLAMINGO + (int(40 + 120 * k / 11),), width=lw)
    fade = Image.new("L", (1, h), 0)
    for y in range(hy, h):
        fade.putpixel((0, y), int(150 * (y - hy) / max(1, h - hy)))
    grid.putalpha(ImageChops.multiply(grid.getchannel("A"), fade.resize((w, h))))
    bg = Image.alpha_composite(bg, grid.filter(ImageFilter.GaussianBlur(lw * 3)))
    return Image.alpha_composite(bg, grid)


def text_layer(size, lines, font, top, gap):
    """Deux lignes centrées : la première en clair, la seconde dans le dégradé magenta → orange, avec un halo."""
    w, h = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    y = top
    for n, line in enumerate(lines):
        box = font.getbbox(line)
        tw, th = box[2] - box[0], font.size
        x = (w - tw) / 2 - box[0]
        mask = Image.new("L", size, 0)
        ImageDraw.Draw(mask).text((x, y), line, font=font, fill=255)
        if n == 0:
            fill = Image.new("RGBA", size, TEXT + (255,))
            halo_color = (255, 255, 255)
            halo_strength = 0.18
        else:
            ramp = Image.new("RGB", (256, 1))
            for i in range(256):
                t = i / 255
                ramp.putpixel((i, 0), tuple(int(a + (b - a) * t) for a, b in zip(FLAMINGO, SUNSET)))
            fill = Image.new("RGBA", size, (0, 0, 0, 0))
            fill.paste(ramp.resize((max(1, int(tw)), h)), (int((w - tw) / 2), 0))
            halo_color = FLAMINGO
            halo_strength = 0.75
        halo = mask.filter(ImageFilter.GaussianBlur(font.size * 0.16)).point(lambda v: int(v * halo_strength))
        layer = Image.alpha_composite(layer, Image.merge("RGBA", [Image.new("L", size, c) for c in halo_color] + [halo]))
        fill.putalpha(mask)
        layer = Image.alpha_composite(layer, fill)
        y += th * gap
    return layer


def render(w, h, shot, l1, l2, out):
    img = Image.open(shot).convert("RGB")
    iw, ih = img.size
    sy = int(h * 0.19)
    sw = int(min(w * 0.88, (h - sy - h * 0.035) * iw / ih))
    sh = int(sw * ih / iw)
    top = int(sy + max(0, (h - sy - sh) / 2 - h * 0.015))
    fs = int(min(w * 0.092, h * 0.044))
    font = ImageFont.truetype(ANTON, fs)
    # Le texte rétrécit s'il est plus large que l'image.
    widest = max(font.getbbox(t)[2] for t in (l1, l2))
    if widest > w * 0.92:
        fs = int(fs * w * 0.92 / widest)
        font = ImageFont.truetype(ANTON, fs)
    ty = int(max(h * 0.035, (top - fs * 2.5) / 2))
    page = background(w, h)
    page = Image.alpha_composite(page, text_layer((w, h), (l1, l2), font, ty, 1.22))
    # La capture : coins arrondis, lueur derrière, filet lumineux.
    r = int(sw * 0.06)
    x = (w - sw) // 2
    shape = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shape).rounded_rectangle([x, top, x + sw, top + sh], r, fill=255)
    for color, blur, strength in [(FLAMINGO, w * 0.05, 0.55), (CYAN, w * 0.02, 0.30)]:
        halo = shape.filter(ImageFilter.GaussianBlur(blur)).point(lambda v, s=strength: int(v * s))
        page = Image.alpha_composite(page, Image.merge("RGBA", [Image.new("L", (w, h), c) for c in color] + [halo]))
    page.paste(img.resize((sw, sh), Image.LANCZOS), (x, top), shape.crop((x, top, x + sw, top + sh)))
    edge = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bw = max(3, int(w * 0.003))
    ImageDraw.Draw(edge).rounded_rectangle([x, top, x + sw, top + sh], r, outline=(255, 255, 255, 110), width=bw)
    page = Image.alpha_composite(page, edge)
    page.convert("RGB").save(out, optimize=True)


made = []
for dev, (w, h, prefix) in SIZES.items():
    for lang in C:
        d = os.path.join(SRC, f"{dev}-{lang}")
        if not os.path.isdir(d):
            continue
        files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
        n = 0
        for route in ROUTES:
            f = next((x for x in files if x.split("-", 1)[1] == f"{route}.png"), None)
            if not f:
                continue
            n += 1
            l1, l2 = C[lang][route]
            out = os.path.join(OUT, f"{prefix}{lang}-{n}.png")
            render(w, h, os.path.join(d, f), l1, l2, out)
            made.append(out)
            print("ok", dev, lang, n, route)

if SHEET and made:
    th = 620
    thumbs = [Image.open(p).convert("RGB") for p in made]
    thumbs = [t.resize((int(t.width * th / t.height), th), Image.LANCZOS) for t in thumbs]
    cols = math.ceil(math.sqrt(len(thumbs) * 1.6))
    rows = [thumbs[i:i + cols] for i in range(0, len(thumbs), cols)]
    sheet = Image.new("RGB", (max(sum(t.width for t in r) for r in rows), th * len(rows)), ABYSS)
    for j, r in enumerate(rows):
        x = 0
        for t in r:
            sheet.paste(t, (x, j * th))
            x += t.width
    sheet.save(SHEET, quality=82)
    print("planche", SHEET, sheet.size)
