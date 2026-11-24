"""ALLÔ PÈRE NOËL : l'icône, dessinée ici (aucune image reprise). Un combiné de téléphone crème coiffé d'un bonnet
de Père Noël, sur une nuit vert sapin avec un halo doré et quelques étoiles. Usage : python3 tools/icon.py"""
import json, math, os
from PIL import Image, ImageDraw, ImageFilter

S = 4096
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "App", "Assets.xcassets", "AppIcon.appiconset")

def hexc(h, a=255): h = h.lstrip('#'); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)
FIR, FOREST, RED, BORDEAUX, GOLD, CREAM, NIGHT = map(hexc, ["123B2A", "1B4D36", "B82025", "791B24", "D6B568", "FFF7EB", "101C32"])

img = Image.new("RGBA", (S, S), NIGHT)
# fond : nuit en haut, sapin en bas
px = img.load()
grad = Image.new("RGBA", (1, S))
for y in range(S):
    k = y / S
    c = tuple(int(NIGHT[i] * (1 - k) + FIR[i] * k) for i in range(3)) + (255,)
    grad.putpixel((0, y), c)
img = grad.resize((S, S))
# une grande lune dorée derrière
moon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
md = ImageDraw.Draw(moon)
mcx, mcy, mr = S * 0.5, S * 0.47, 1350
for r, a in [(mr + 520, 26), (mr + 260, 44)]:
    md.ellipse([mcx - r, mcy - r, mcx + r, mcy + r], fill=GOLD[:3] + (a,))
moon = moon.filter(ImageFilter.GaussianBlur(180))
img = Image.alpha_composite(img, moon)
d = ImageDraw.Draw(img)
d.ellipse([mcx - mr, mcy - mr, mcx + mr, mcy + mr], fill=hexc("E8CF8E"))
d.ellipse([mcx - mr * 0.92, mcy - mr * 0.92, mcx + mr * 0.92, mcy + mr * 0.92], fill=hexc("EDD79B"))
for (x, y, r) in [(-0.35, -0.3, 0.16), (0.32, 0.18, 0.12), (-0.05, 0.42, 0.09), (0.42, -0.35, 0.07)]:
    d.ellipse([mcx + x * mr - r * mr, mcy + y * mr - r * mr, mcx + x * mr + r * mr, mcy + y * mr + r * mr], fill=hexc("E2C783"))

def star(cx, cy, r, col):
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.42
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    d.polygon(pts, fill=col)
for (x, y, r) in [(0.13, 0.12, 80), (0.88, 0.10, 100), (0.90, 0.40, 55), (0.09, 0.46, 50), (0.75, 0.07, 40)]:
    star(S * x, S * y, r, GOLD)

def bez(p0, p1, p2, n=60):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in [i / n for i in range(n + 1)]]

# le combiné, en diagonale : écouteur en haut à gauche, micro en bas à droite
hand = Image.new("RGBA", (S, S), (0, 0, 0, 0))
hdw = ImageDraw.Draw(hand)
cx, cy = S * 0.5, S * 0.56
L = 2500
hdw.rounded_rectangle([cx - L / 2 + 380, cy - 230, cx + L / 2 - 380, cy + 170], radius=210, fill=CREAM)
for side in (-1, 1):
    ex = cx + side * (L / 2 - 300)
    hdw.ellipse([ex - 400, cy - 140, ex + 400, cy + 560], fill=CREAM)
    hdw.ellipse([ex - 285, cy + 175, ex + 285, cy + 500], fill=hexc("EADFCB"))
    for gx in (-95, 0, 95):
        for gy in (270, 390):
            hdw.ellipse([ex + gx - 28, cy + gy - 28, ex + gx + 28, cy + gy + 28], fill=hexc("CDBB9E"))
# le bonnet, posé sur l'écouteur de gauche
hx, hy = cx - (L / 2 - 300), cy - 120
base_l, base_r = (hx - 470, hy + 40), (hx + 470, hy + 40)
tip = (hx + 760, hy - 520)
cone = bez(base_l, (hx - 300, hy - 900), (hx + 380, hy - 760)) + bez((hx + 380, hy - 760), (hx + 640, hy - 700), tip) \
       + bez(tip, (hx + 520, hy - 420), (hx + 300, hy - 430)) + bez((hx + 300, hy - 430), (hx + 420, hy - 120), base_r)
hdw.polygon(cone, fill=RED)
fold = bez((hx + 150, hy - 640), (hx + 420, hy - 560), (hx + 300, hy - 430)) + bez((hx + 300, hy - 430), (hx + 420, hy - 140), base_r) + [(hx + 120, hy + 40)]
hdw.polygon(fold, fill=BORDEAUX)
hdw.rounded_rectangle([hx - 560, hy - 60, hx + 560, hy + 230], radius=145, fill=hexc("FFFFFF"))
for k in range(8):
    x = hx - 500 + k * 143
    hdw.ellipse([x - 75, hy - 105, x + 75, hy + 20], fill=hexc("FFFFFF"))
hdw.ellipse([tip[0] - 190, tip[1] - 150, tip[0] + 190, tip[1] + 230], fill=hexc("FFFFFF"))
shadow = hand.split()[3].filter(ImageFilter.GaussianBlur(100))
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0)); sh.putalpha(shadow.point(lambda v: int(v * 0.5)))
sh = sh.transform(sh.size, Image.AFFINE, (1, 0, -30, 0, 1, -140))
ang = 28
hand = hand.rotate(ang, resample=Image.BICUBIC, center=(cx, cy))
sh = sh.rotate(ang, resample=Image.BICUBIC, center=(cx, cy))
img = Image.alpha_composite(img, sh)
img = Image.alpha_composite(img, hand)

# neige au sol
d = ImageDraw.Draw(img)
d.ellipse([-S * 0.35, S * 0.86, S * 1.35, S * 1.7], fill=hexc("E9F0EC"))
d.ellipse([-S * 0.25, S * 0.84, S * 0.62, S * 1.25], fill=hexc("FFFFFF"))

icon = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
icon.save(os.path.join(OUT, "icon-1024.png"))
json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(OUT, "Contents.json"), "w"), indent=1)
print("icône ok")
