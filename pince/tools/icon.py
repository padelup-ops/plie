"""PEEKACLAW : dessine l'icône de l'app (1024 x 1024, sans transparence).

    python3 pince/tools/icon.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

S = 2048  # dessiné en double, puis réduit : les bords sont lisses
OUT = os.path.join(os.path.dirname(__file__), "..", "Pince", "Assets.xcassets", "AppIcon.appiconset", "icon.png")


def lerp(a, b, k):
    return tuple(round(a[i] + (b[i] - a[i]) * k) for i in range(3))


def background():
    stops = [(0.0, (169, 164, 245)), (0.45, (240, 180, 228)), (0.75, (255, 196, 218)), (1.0, (255, 227, 189))]
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        k = y / (S - 1)
        for (k0, c0), (k1, c1) in zip(stops, stops[1:]):
            if k0 <= k <= k1:
                color = lerp(c0, c1, (k - k0) / (k1 - k0))
                break
        for x in range(S):
            px[x, y] = color
    return img


def sparkle(d, x, y, r, fill=(255, 255, 255)):
    pts = []
    for i in range(8):
        a = i * math.pi / 4
        rr = r if i % 2 == 0 else r * 0.3
        pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr))
    d.polygon(pts, fill=fill)


def ellipse(d, cx, cy, rx, ry, fill):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill)


def main():
    img = background()
    d = ImageDraw.Draw(img)

    # Un halo derrière le doudou
    glow = Image.new("RGBA", (S, S), (255, 250, 220, 0))
    ImageDraw.Draw(glow).ellipse([S * 0.14, S * 0.34, S * 0.86, S * 1.06], fill=(255, 250, 220, 150))
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    img.paste(glow, (0, 0), glow)
    d = ImageDraw.Draw(img)

    for x, y, r in [(250, 330, 70), (1790, 520, 56), (330, 1180, 44), (1760, 1300, 64), (1560, 230, 36)]:
        sparkle(d, x, y, r)

    cx = S / 2
    fur, fur_shade, pink, ink = (255, 248, 243), (240, 222, 226), (255, 157, 181), (58, 40, 58)

    # Le lapin : les oreilles, le corps, les pieds
    by = 1390
    for s in (-1, 1):
        ear = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ed = ImageDraw.Draw(ear)
        ed.rounded_rectangle([cx - 115, by - 900, cx + 115, by - 250], radius=115, fill=fur + (255,))
        ed.rounded_rectangle([cx - 55, by - 830, cx + 55, by - 330], radius=55, fill=(255, 183, 203, 255))
        ear = ear.rotate(-s * 13, center=(cx, by - 250), resample=Image.BICUBIC)
        img.paste(ear, (int(s * 230), 0), ear)
    d = ImageDraw.Draw(img)
    ellipse(d, cx, by + 40, 600, 560, fur_shade)
    ellipse(d, cx, by, 600, 560, fur)
    for s in (-1, 1):
        ellipse(d, cx + s * 250, by + 500, 170, 110, (255, 227, 232))

    # Le visage
    for s in (-1, 1):
        ellipse(d, cx + s * 215, by - 60, 66, 78, ink)
        ellipse(d, cx + s * 215 - 22, by - 92, 22, 22, (255, 255, 255))
        ellipse(d, cx + s * 370, by + 80, 92, 58, pink)
    ellipse(d, cx, by + 40, 44, 30, (255, 127, 160))
    d.arc([cx - 70, by + 40, cx, by + 130], 20, 170, fill=ink, width=16)
    d.arc([cx, by + 40, cx + 70, by + 130], 10, 160, fill=ink, width=16)

    # La pince : le câble, le dôme, deux griffes qui encadrent les oreilles
    coral, coral_dark, cream, metal = (255, 143, 163), (242, 100, 126), (255, 246, 234), (236, 234, 246)
    d.rounded_rectangle([cx - 22, -40, cx + 22, 250], radius=20, fill=(185, 179, 214))
    for s in (-1, 1):
        elbow = (cx + s * 520, 620)
        tip = (cx + s * 400, 1010)
        d.line([(cx + s * 170, 330), elbow], fill=metal, width=64)
        d.line([elbow, tip], fill=metal, width=64)
        ellipse(d, elbow[0], elbow[1], 36, 36, metal)
        ellipse(d, cx + s * 170, 330, 34, 34, metal)
        ellipse(d, tip[0], tip[1], 56, 56, cream)
    d.pieslice([cx - 300, 110, cx + 300, 560], 180, 360, fill=coral)
    d.rounded_rectangle([cx - 320, 318, cx + 320, 400], radius=40, fill=cream)
    ellipse(d, cx - 150, 230, 54, 30, (255, 196, 208))
    for s in (-1, 1):
        ellipse(d, cx + s * 95, 262, 24, 24, ink)
        ellipse(d, cx + s * 185, 290, 34, 20, coral_dark)

    img.resize((1024, 1024), Image.LANCZOS).save(OUT)
    print(OUT)


if __name__ == "__main__":
    main()
