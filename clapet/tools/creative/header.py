"""Les « creative assets » iOS 27 de Foldly : la vidéo d'en-tête de la fiche App Store (21:9, 3840 × 1646)
et celle des résultats de recherche (3:2, 2400 × 1600). Boucle muette de 12 s, sans saut.

python3 header.py en|fr [header|search] [--preview t1,t2]
Le titre reste visible à chaque image (n'importe laquelle peut servir d'affiche) ; seuls les plantes,
les médailles et les feuilles s'animent, et reviennent à leur état de départ à la fin de la boucle.
"""
import math, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
LANG = sys.argv[1] if len(sys.argv) > 1 else "en"
KIND = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else "header"
W, H = (3840, 1646) if KIND == "header" else (2400, 1600)
FPS, DUR = 30, 12.0

FD = "/usr/share/fonts/opentype/inter/"
BLACK, XBOLD = FD + "InterDisplay-Black.otf", FD + "InterDisplay-ExtraBold.otf"
MINT = (94, 227, 199)
GOLD = (255, 205, 96)

TEXT = {
    "en": {"l1": "Close your phone.", "l2": "Grow a garden.", "medals": [("7", "DAYS"), ("100", "PLANTS")]},
    "fr": {"l1": "Ferme ton téléphone.", "l2": "Fais pousser un jardin.", "medals": [("7", "JOURS"), ("100", "PLANTES")]},
}[LANG]


def font(p, s):
    return ImageFont.truetype(p, s)


def clamp(x):
    return max(0.0, min(1.0, x))


def back_out(x, s=1.6):
    x = clamp(x) - 1
    return x * x * ((s + 1) * x + s) + 1


def ease(x):
    x = clamp(x)
    return x * x * (3 - 2 * x)


# ---------------------------------------------------------------- les écrans de l'app

def still(name):
    return Image.open(os.path.join(HERE, f"still-{LANG}-{name}.png")).convert("RGB")


def rounded(img, r):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.width - 1, img.height - 1), r, fill=255)
    out = img.convert("RGBA")
    out.putalpha(m)
    return out


def phone(screen, height, angle):
    """L'écran à plat dans un cadre noir fin, tourné de quelques degrés, avec son ombre."""
    sh = int(height)
    sw = int(round(sh * screen.width / screen.height))
    scr = screen.resize((sw, sh), Image.LANCZOS)
    b = int(sh * 0.016)
    R = int(sh * 0.06)
    fw, fh = sw + 2 * b, sh + 2 * b
    body = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle((0, 0, fw - 1, fh - 1), R, fill=(12, 12, 14, 255), outline=(78, 80, 86, 255), width=max(2, b // 4))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), R - b, fill=255)
    body.paste(scr, (b, b), mask)
    pad = int(sh * 0.12)
    shadow = Image.new("RGBA", (fw + 2 * pad, fh + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((pad, pad + pad // 3, fw + pad, fh + pad), R, fill=(0, 0, 0, 160))
    shadow = shadow.filter(ImageFilter.GaussianBlur(pad // 3))
    shadow.alpha_composite(body, (pad, pad))
    return shadow.rotate(angle, resample=Image.BICUBIC, expand=True)


def widget(box, scale):
    """Un widget découpé dans l'écran d'accueil filmé (coins arrondis), avec son ombre."""
    w = still("widgets").crop(box)
    w = w.resize((int(w.width * scale), int(w.height * scale)), Image.LANCZOS)
    w = rounded(w, int(46 * scale))
    pad = int(60 * scale)
    out = Image.new("RGBA", (w.width + 2 * pad, w.height + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(out).rounded_rectangle((pad, pad + pad // 3, pad + w.width, pad + w.height + pad // 3), int(46 * scale), fill=(0, 0, 0, 150))
    out = out.filter(ImageFilter.GaussianBlur(pad // 3))
    out.alpha_composite(w, (pad, pad))
    return out


FOLDS_SMALL = (570, 620, 944, 994)
DOWN_SMALL = (140, 620, 514, 994)
FOLDS_MEDIUM = (140, 190, 944, 564)


# ---------------------------------------------------------------- décor

def background():
    y = np.linspace(0, 1, H)[:, None, None]
    top, bottom = np.array([8, 17, 15]), np.array([14, 44, 36])
    arr = top * (1 - y) + bottom * y
    arr = np.repeat(arr, W, axis=1)
    # une lueur menthe derrière le titre
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt(((xx - W / 2) / (W * 0.32)) ** 2 + ((yy - H * 0.5) / (H * 0.55)) ** 2)
    glow = np.clip(1 - d, 0, 1)[..., None] ** 2
    arr = arr + glow * np.array([30, 80, 68]) * 0.55
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def leaf_poly(cx, cy, size, angle):
    pts = []
    for k in range(21):
        u = k / 20
        pts.append(((u - 0.5) * size, -math.sin(u * math.pi) * size * 0.32))
    for k in range(21):
        u = 1 - k / 20
        pts.append(((u - 0.5) * size, math.sin(u * math.pi) * size * 0.32))
    ca, sa = math.cos(angle), math.sin(angle)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]


def plant(d, kind, cx, base, h, col):
    """Feuille, tulipe ou arbre, dessinés à plat (comme dans l'app)."""
    a = (*col, 255)
    if kind == 0:  # deux feuilles
        d.line((cx, base, cx, base - h * 0.55), fill=a, width=max(3, int(h * 0.07)))
        d.polygon(leaf_poly(cx - h * 0.2, base - h * 0.55, h * 0.55, math.radians(-35)), fill=a)
        d.polygon(leaf_poly(cx + h * 0.2, base - h * 0.75, h * 0.55, math.radians(215)), fill=a)
    elif kind == 1:  # tulipe
        d.line((cx, base, cx, base - h * 0.55), fill=a, width=max(3, int(h * 0.07)))
        r = h * 0.24
        top = base - h * 0.62
        d.pieslice((cx - r, top - r, cx + r, top + r), 0, 180, fill=a)
        for k in (-1, 0, 1):
            d.polygon([(cx + k * r * 0.7 - r * 0.32, top), (cx + k * r * 0.7, top - r * 1.05), (cx + k * r * 0.7 + r * 0.32, top)], fill=a)
        d.polygon(leaf_poly(cx + h * 0.16, base - h * 0.22, h * 0.42, math.radians(205)), fill=a)
    else:  # arbre
        d.rectangle((cx - h * 0.05, base - h * 0.4, cx + h * 0.05, base), fill=a)
        for (dx, dy, r) in ((0, -0.68, 0.3), (-0.22, -0.52, 0.22), (0.22, -0.52, 0.22)):
            rr = h * r
            d.ellipse((cx + dx * h - rr, base + dy * h - rr, cx + dx * h + rr, base + dy * h + rr), fill=a)


def medal(canvas, cx, cy, r, label, unit, p, color):
    if p <= 0.01:
        return
    rr = r * p
    over = Image.new("RGBA", (int(r * 3), int(r * 3)), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    c = r * 1.5
    d.ellipse((c - rr * 1.22, c - rr * 1.22, c + rr * 1.22, c + rr * 1.22), fill=(*color, 60))
    d.ellipse((c - rr, c - rr, c + rr, c + rr), fill=(*color, 255))
    d.ellipse((c - rr * 0.82, c - rr * 0.82, c + rr * 0.82, c + rr * 0.82), outline=(255, 255, 255, 150), width=max(2, int(r * 0.04)))
    if p > 0.6:
        d.text((c, c - rr * 0.1), label, font=font(BLACK, max(8, int(r * (0.62 if len(label) < 3 else 0.5) * p))), fill=(40, 26, 4, 255), anchor="mm")
        d.text((c, c + rr * 0.47), unit, font=font(XBOLD, max(6, int(r * 0.25 * p))), fill=(40, 26, 4, 235), anchor="mm")
    canvas.alpha_composite(over, (int(cx - c), int(cy - c)))


# ---------------------------------------------------------------- mise en page

S = W / 3840 if KIND == "header" else W / 2400
BG = background()
if KIND == "header":
    LEFT = phone(still("phonedown"), 1500, 7)
    RIGHT = phone(still("garden"), 1500, -7)
    W_LEFT = widget(FOLDS_SMALL, 1.05)
    W_RIGHT = widget(DOWN_SMALL, 1.05)
    # Zone sûre du modèle d'Apple : 1646 × 661 au centre. Le titre et les plantes y tiennent.
    TITLE_Y, TITLE_SIZE, TITLE_W = 520, 132, 1580
    STRIP_Y, STRIP_W, PLANT_H = 905, 1440, 110
else:
    LEFT = phone(still("phonedown"), 1180, 6)
    RIGHT = phone(still("garden"), 1180, -6)
    W_LEFT = widget(FOLDS_SMALL, 0.8)
    W_RIGHT = widget(DOWN_SMALL, 0.8)
    TITLE_Y, TITLE_SIZE, TITLE_W = 120, 116, 2100
    STRIP_Y, STRIP_W, PLANT_H = 470, 1500, 96


def title_layer():
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    size = TITLE_SIZE
    while True:
        f = font(BLACK, size)
        w1, w2 = d.textlength(TEXT["l1"], font=f), d.textlength(TEXT["l2"], font=f)
        if max(w1, w2) <= TITLE_W or size < 60:
            break
        size -= 4
    lh = int(size * 1.12)
    d.text((W / 2, TITLE_Y), TEXT["l1"], font=f, fill=(255, 255, 255, 255), anchor="mt")
    d.text((W / 2, TITLE_Y + lh), TEXT["l2"], font=f, fill=(*MINT, 255), anchor="mt")
    uy = TITLE_Y + lh + size * 1.08
    d.rounded_rectangle((W / 2 - w2 / 2, uy, W / 2 + w2 / 2, uy + size * 0.09), int(size * 0.045), fill=(*MINT, 210))
    return over


TITLE = title_layer()
N_PLANTS = 13 if KIND == "header" else 12


# La vidéo commence jardin plein (la première image sert d'affiche), puis la boucle repart sans saut.
SHIFT = 8.6


def render(t):
    t = (t + SHIFT) % DUR
    c = BG.copy()
    # Les feuilles qui flottent (période de 12 s : la boucle est parfaite)
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    rng = np.random.default_rng(7)
    for k in range(22 if KIND == "header" else 14):
        x0 = rng.uniform(0, W)
        phase = rng.uniform(0, 1)
        size = rng.uniform(40, 90) * S * (1.4 if KIND == "header" else 1.1)
        u = (t / DUR + phase) % 1
        y = H + 120 - u * (H + 240)
        x = x0 + math.sin(2 * math.pi * (u * 2 + phase)) * 60 * S
        d.polygon(leaf_poly(x, y, size, 2 * math.pi * (u + phase)), fill=(*MINT, int(rng.uniform(26, 60))))
    c.alpha_composite(over)

    # Les deux écrans, qui flottent doucement
    f1 = math.sin(2 * math.pi * t / 6) * 14 * S
    f2 = math.sin(2 * math.pi * t / 6 + 2) * 14 * S
    if KIND == "header":
        c.alpha_composite(LEFT, (int(560 - LEFT.width / 2), int(170 + f1 - 120)))
        c.alpha_composite(RIGHT, (int(3280 - RIGHT.width / 2), int(170 + f2 - 120)))
        c.alpha_composite(W_LEFT, (int(985 - W_LEFT.width / 2), int(150 + f2 * 1.4)))
        c.alpha_composite(W_RIGHT, (int(2790 - W_RIGHT.width / 2), int(1110 + f1 * 1.4)))
    else:
        c.alpha_composite(LEFT, (int(700 - LEFT.width / 2), int(640 + f1)))
        c.alpha_composite(RIGHT, (int(1700 - RIGHT.width / 2), int(660 + f2)))
        c.alpha_composite(W_LEFT, (int(250 - W_LEFT.width / 2), int(470 + f2 * 1.4)))
        c.alpha_composite(W_RIGHT, (int(2150 - W_RIGHT.width / 2), int(560 + f1 * 1.4)))

    # Les médailles, près de l'écran du jardin
    out = 1 - ease((t - 10.6) / 0.7)
    for j, (label, unit) in enumerate(TEXT["medals"]):
        p = back_out((t - 2.0 - j * 1.2) / 0.5) * out
        if KIND == "header":
            medal(c, 2330 + j * 235, 255 + j * 45, 100, label, unit, p, GOLD if j == 0 else MINT)
        else:
            medal(c, 1180 + j * 1080, 1460 - j * 60, 92, label, unit, p, GOLD if j == 0 else MINT)

    # Le titre (toujours là), puis le jardin qui pousse sous le titre
    c.alpha_composite(TITLE)
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    step = STRIP_W / N_PLANTS
    x0 = W / 2 - STRIP_W / 2 + step / 2
    base = STRIP_Y + PLANT_H
    d.rounded_rectangle((W / 2 - STRIP_W / 2, base + 8 * S, W / 2 + STRIP_W / 2, base + 22 * S), int(7 * S), fill=(*MINT, 70))
    gone = ease((t - 10.6) / 0.8)
    for i in range(N_PLANTS):
        p = back_out((t - 0.6 - i * 0.6) / 0.45, 1.8) * (1 - gone)
        if p <= 0.02:
            continue
        shade = 0.6 + 0.4 * ((i * 7) % 5) / 4
        col = tuple(int(v * shade + 14 * (1 - shade)) for v in MINT)
        plant(d, i % 3, x0 + i * step, base, PLANT_H * p, col)
    c.alpha_composite(over)
    return c.convert("RGB")


if __name__ == "__main__":
    if "--preview" in sys.argv:
        for t in [float(x) for x in sys.argv[sys.argv.index("--preview") + 1].split(",")]:
            render(t).save(os.path.join(HERE, f"{KIND}-{LANG}-{t:04.1f}.jpg"), quality=85)
        sys.exit(0)
    out = os.path.join(HERE, f"foldly-{KIND}-{LANG}.mp4")
    ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                           "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "17",
                           "-profile:v", "high", "-level:v", "5.1", "-pix_fmt", "yuv420p", "-tag:v", "avc1",
                           "-movflags", "+faststart", "-an", out], stdin=subprocess.PIPE)
    n = int(DUR * FPS)
    for k in range(n):
        ff.stdin.write(np.asarray(render(k / FPS)).tobytes())
        if k % 60 == 0:
            print(f"{k}/{n}", flush=True)
    ff.stdin.close()
    ff.wait()
    print("vidéo :", out)
