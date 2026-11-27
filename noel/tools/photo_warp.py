#!/usr/bin/env python3
# Allô Père Noël — la photo du Père Noël qui prend vie.
#
# Le portrait (noel/ai/portrait-2.png, généré avec FLUX.1 [schnell], Apache 2.0 : ce n'est la photo de personne) est
# déformé ici, hors de l'app : la mâchoire qui s'ouvre (la lèvre du bas et la barbe descendent, le sombre de la bouche
# apparaît sous la moustache) et les yeux qui se ferment. L'app n'a plus qu'à fondre ces images les unes dans les
# autres au rythme de la voix (App/SantaPhoto.swift) : pas de calcul sur l'iPhone, et ce qu'on voit dans l'app est
# exactement ce qu'on a réglé ici, image par image.
#
#   python3 noel/tools/photo_warp.py sheet out.png      planche de contrôle (bouche fermée → ouverte, clignement)
#   python3 noel/tools/photo_warp.py assets             SantaPhoto (au repos), SantaMouth1…5 (bouche de plus en plus
#                                                       ouverte), SantaBlink (yeux fermés)
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "ai" / "portrait-2.png"
ASSETS = ROOT / "App" / "Assets.xcassets"

W, H = 768.0, 1024.0
# La bouche : son milieu, la ligne entre les dents du haut et la lèvre du bas, sa demi-largeur.
MX, MY, MW = 438.0, 539.8, 43.0
# Les yeux : centre et rayons de l'ouverture visible.
EYES = [(357.0, 369.0, 33.0, 12.5), (504.0, 371.5, 31.0, 12.5)]
DARK = (384, 460)       # une narine : le sombre de l'intérieur de la bouche
LIP = (438, 550)        # la lèvre du bas : la couleur de la langue


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def sample(img, x, y):
    h, w, _ = img.shape
    x = np.clip(x, 0, w - 1.001)
    y = np.clip(y, 0, h - 1.001)
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]
    a, b, c, d = img[y0, x0], img[y0, x0 + 1], img[y0 + 1, x0], img[y0 + 1, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def render(img, openness=0.0, blink=0.0):
    h, w, _ = img.shape
    sx, sy = W / w, H / h
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    X, Y = xx * sx, yy * sy
    u = (X - MX) / MW
    ym = MY + 0.03 * (X - MX) + 0.6 * u * u
    below = Y - ym
    open_px = 15.0 * openness
    lip = np.maximum(0, 1 - u * u) ** 1.5
    lip_y = 1 - smooth(18, 95, below)
    beard_x = np.exp(-((X - MX) / 150.0) ** 2)
    beard_y = smooth(0, 55, below) * (1 - smooth(210, 420, below))
    shift = open_px * np.maximum(lip * lip_y, 0.82 * beard_x * beard_y) * (below > 0)
    out = sample(img, X / sx, (Y - shift) / sy)

    gap = open_px * lip
    inside = smooth(0.0, 1.6, below) * smooth(0.0, 1.8, gap - below) * (gap > 0.3) * (below > 0) * (below < gap + 2)
    depth = np.clip(below / np.maximum(gap, 1e-3), 0, 1)
    dark = img[int(DARK[1] / sy), int(DARK[0] / sx)]
    lipc = img[int(LIP[1] / sy), int(LIP[0] / sx)] * np.array([0.85, 0.8, 0.85])
    tongue = smooth(0.5, 1.0, depth) * np.clip(1 - u * u, 0, 1) * 0.6
    mouth = dark[None, None, :] * (1 - tongue[..., None]) + lipc[None, None, :] * tongue[..., None]
    mouth = mouth * (0.75 + 0.25 * smooth(0.0, 0.5, depth))[..., None]
    out = out * (1 - inside[..., None]) + mouth * inside[..., None]

    if blink > 0.01:
        for (ex, ey, rx, ry) in EYES:
            d = ((X - ex) / rx) ** 2 + ((Y - ey) / ry) ** 2
            mask = (1 - smooth(0.75, 1.0, d)) * (d < 1)
            top = ey - ry
            edge = top + blink * 2.15 * ry
            lid = smooth(0.0, 2.0, edge - Y) * mask
            bottom = ey + ry + 5
            skin = sample(img, X / sx, (2 * bottom - Y + 3) / sy)
            skin = skin * (0.9 + 0.1 * smooth(top, ey + ry, Y))[..., None]
            out = out * (1 - lid[..., None]) + skin * lid[..., None]
            lash = np.exp(-((Y - edge) / 1.4) ** 2) * mask * (0.5 if blink > 0.05 else 0.0)
            out = out * (1 - lash[..., None])
    return np.clip(out, 0, 255).astype(np.uint8)


def load():
    return np.asarray(Image.open(SRC).convert("RGB")).astype(np.float64)


def sheet(path):
    img = load()
    tiles = []
    for o, b in [(0, 0), (0.35, 0), (0.7, 0), (1.0, 0), (0.2, 0.5), (0.0, 1.0)]:
        tiles.append(Image.fromarray(render(img, o, b)).crop((250, 300, 630, 700)))
    w, h = tiles[0].size
    out = Image.new("RGB", (w * 3, h * 2))
    for i, t in enumerate(tiles):
        out.paste(t, ((i % 3) * w, (i // 3) * h))
    out.save(path)


def asset(name, arr):
    # Deux fois plus grande (l'appel la montre en plein écran), avec un rien de netteté.
    im = Image.fromarray(arr).resize((1536, 2048), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=1.6, percent=60, threshold=2))
    d = ASSETS / f"{name}.imageset"
    d.mkdir(parents=True, exist_ok=True)
    im.save(d / f"{name}.jpg", quality=85, optimize=True, progressive=True)
    (d / "Contents.json").write_text(
        '{\n  "images" : [\n    {\n      "filename" : "%s.jpg",\n      "idiom" : "universal"\n    }\n  ],\n'
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' % name)
    print(name, (d / f"{name}.jpg").stat().st_size // 1024, "Ko")


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "sheet":
        sheet(sys.argv[2])
    elif len(sys.argv) >= 2 and sys.argv[1] == "assets":
        img = load()
        asset("SantaPhoto", render(img, 0.0, 0.0))
        for k in range(1, 6):
            asset(f"SantaMouth{k}", render(img, k / 5, 0.0))
        asset("SantaBlink", render(img, 0.0, 1.0))
    else:
        print(__doc__ or "sheet <fichier> | assets")
