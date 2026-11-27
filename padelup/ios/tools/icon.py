"""PADELUP NEO : l'icône, dessinée ici. Un terrain de padel en perspective aux lignes néon cyan, sur une nuit bleu
profond, et une balle jaune fluo lumineuse avec sa traînée. Usage : python3 tools/icon.py"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

S = 2048
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'App', 'Assets.xcassets', 'AppIcon.appiconset', 'icon-1024.png')


def hexc(h, a=255):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


NIGHT, DEEP, COURT, CYAN, VOLT = map(hexc, ['04070F', '0A1A4A', '1747FF', '22E6FF', 'D4FF3A'])

# fond : dégradé vertical nuit -> bleu terrain, halo central
img = Image.new('RGBA', (S, S))
px = img.load()
for y in range(S):
    k = y / S
    for x in range(S):
        d = math.hypot((x - S * 0.5) / S, (y - S * 0.62) / S)
        glow = max(0.0, 0.55 - d) * 0.9
        c = [NIGHT[i] * (1 - k) + DEEP[i] * k + COURT[i] * glow * 0.55 for i in range(3)]
        px[x, y] = tuple(min(255, int(v)) for v in c) + (255,)

# terrain en perspective : trapèze
top_y, bot_y = S * 0.42, S * 0.95
top_half, bot_half = S * 0.20, S * 0.47
cx = S / 2


def lerp_pt(t, side):
    y = top_y + (bot_y - top_y) * t
    half = top_half + (bot_half - top_half) * t
    return (cx + side * half, y)


lines = Image.new('RGBA', (S, S), (0, 0, 0, 0))
ld = ImageDraw.Draw(lines)
W = 16
# surface du terrain, légèrement plus claire
ld.polygon([lerp_pt(0, -1), lerp_pt(0, 1), lerp_pt(1, 1), lerp_pt(1, -1)], fill=COURT[:3] + (70,))
# contour
for a, b in [((0, -1), (0, 1)), ((0, 1), (1, 1)), ((1, 1), (1, -1)), ((1, -1), (0, -1))]:
    ld.line([lerp_pt(*a), lerp_pt(*b)], fill=CYAN, width=W)
# filet (milieu en perspective)
tn = 0.42
ld.line([lerp_pt(tn, -1.04), lerp_pt(tn, 1.04)], fill=(255, 255, 255, 235), width=W + 6)
# lignes de service
for t in (0.16, 0.74):
    ld.line([lerp_pt(t, -1), lerp_pt(t, 1)], fill=CYAN, width=W - 4)
# ligne centrale de service
ld.line([((lerp_pt(0.16, 0)[0]), lerp_pt(0.16, 0)[1]), (lerp_pt(0.74, 0)[0], lerp_pt(0.74, 0)[1])], fill=CYAN, width=W - 4)
glow = lines.filter(ImageFilter.GaussianBlur(26))
img = Image.alpha_composite(img, glow)
img = Image.alpha_composite(img, glow)
img = Image.alpha_composite(img, lines)

# traînée de la balle : arc lumineux
trail = Image.new('RGBA', (S, S), (0, 0, 0, 0))
td = ImageDraw.Draw(trail)
bx, by, br = S * 0.66, S * 0.30, S * 0.115
for i in range(60):
    t = i / 59
    x = S * 0.18 + (bx - S * 0.18) * t
    y = S * 0.62 - math.sin(t * math.pi * 0.92) * S * 0.36 + (by - S * 0.62 + S * 0.36 * math.sin(math.pi * 0.92)) * t
    r = 8 + 70 * t
    td.ellipse([x - r, y - r, x + r, y + r], fill=VOLT[:3] + (int(10 + 70 * t),))
trail = trail.filter(ImageFilter.GaussianBlur(30))
img = Image.alpha_composite(img, trail)

# balle
ball = Image.new('RGBA', (S, S), (0, 0, 0, 0))
bd = ImageDraw.Draw(ball)
for r, a in [(br * 2.3, 40), (br * 1.7, 70)]:
    bd.ellipse([bx - r, by - r, bx + r, by + r], fill=VOLT[:3] + (a,))
ball = ball.filter(ImageFilter.GaussianBlur(60))
img = Image.alpha_composite(img, ball)
d = ImageDraw.Draw(img)
d.ellipse([bx - br, by - br, bx + br, by + br], fill=VOLT)
d.ellipse([bx - br * 0.78, by - br * 0.86, bx + br * 0.5, by + br * 0.2], fill=hexc('ECFF8A'))
# couture de la balle
seam = [(bx - br * 0.95 + i * br * 1.9 / 40, by + math.sin(i / 40 * math.pi * 2) * br * 0.32) for i in range(41)]
d.line(seam, fill=(255, 255, 255, 230), width=18, joint='curve')

img = img.convert('RGB').resize((1024, 1024), Image.LANCZOS)
img.save(OUT, optimize=True)
print('icône écrite :', OUT)
