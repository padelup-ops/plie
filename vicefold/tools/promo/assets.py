"""VICEFOLD promo video: prepares the pictures (python3 assets.py <work dir>).

Raw app screens are cut back out of the composed App Store screenshots in ../../store, the Leonida map is stitched
from the bundled tiles (GTADB.org, CC BY 4.0), and the places come from the app's own content file.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
BORDER = np.array([11, 15, 22])
POOL = (234, 246, 245)       # the page colour of the app by day


def screen(path):
    """The app screen inside a composed store picture: the box drawn with the dark frame colour, minus the frame."""
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(int)
    m = (np.abs(a - BORDER).sum(axis=2) < 6)
    bw = int(im.width * 0.011)
    cols = np.where(m.sum(axis=0) > im.height * 0.2)[0]
    rows = np.where(m.sum(axis=1) > im.width * 0.2)[0]
    x0, x1, y0, y1 = cols.min(), cols.max(), rows.min(), rows.max()
    return unband(im.crop((x0 + bw, y0 + bw, x1 - bw + 1, y1 - bw + 1)))


def unband(im):
    """Older captures of the open Duo have a black band on the fold; the app now leaves the fold in the colour of
    the page, so the band is painted that way here too (same picture as a new capture)."""
    a = np.asarray(im).astype(int)
    h, w = a.shape[:2]
    dark = (a.sum(axis=2) < 40).mean(axis=0) > 0.8
    mid = [x for x in np.where(dark)[0] if w * 0.3 < x < w * 0.7]
    if not mid or w < h:
        return im
    out = im.copy()
    out.paste(POOL, (min(mid) - 3, 0, max(mid) + 4, h))
    return out


sizes = {}
# English screens are "iphone-1.png"; French ones (for the App Store header in French) are "fr-iphone-1.png".
for lang, pre in (("en", ""), ("fr", "fr-")):
    for prefix, name, n, h in (("", "iphone", 8, 1500), ("duo-", "duo", 9, 1100), ("ipad-", "ipad", 9, 1400)):
        for i in range(1, n + 1):
            im = screen(os.path.join(ROOT, "store", f"{prefix}{lang}-{i}.png"))
            im = im.resize((round(im.width * h / im.height), h), Image.LANCZOS)
            im.save(os.path.join(OUT, f"{pre}{name}-{i}.png"))
            sizes[f"{pre}{name}-{i}"] = im.size
        print(lang, name, im.size)

# The map: level 3 for the whole state (3776 x 5120), level 4 around Vice City.
W, H = 15104, 20480


def stitch(z, box):
    side = 8192 / 2 ** z
    px = 256 / side
    x0, y0, x1, y1 = box
    out = Image.new("RGB", (round((x1 - x0) * px), round((y1 - y0) * px)), (44, 103, 164))
    for ty in range(int((y0 + 5120) // side), int((y1 + 5120 - 1) // side) + 1):
        for tx in range(int((x0 + 5120) // side), int((x1 + 5120 - 1) // side) + 1):
            f = os.path.join(ROOT, "Tiles", str(z), f"{z},{ty},{tx}.jpg")
            if os.path.exists(f):
                out.paste(Image.open(f), (round((tx * side - 5120 - x0) * px), round((ty * side - 5120 - y0) * px)))
    return out


stitch(3, (0, 0, W, H)).save(os.path.join(OUT, "map.jpg"), quality=90)
# Vice City sits around x 0.75, y 0.5: a 6144 m square around it at level 4 (3072 px).
VC = (W * 0.75 - 3584, H * 0.5 - 3072, W * 0.75 + 2560, H * 0.5 + 3072)
stitch(4, VC).save(os.path.join(OUT, "vice.jpg"), quality=90)

content = json.load(open(os.path.join(ROOT, "Content", "content-en.json")))
places = [[p["x"], p["y"], p["kind"]] for p in content["places"] if p["kind"] not in ("region",)]
data = {
    "sizes": sizes, "places": places, "vice": [VC[0] / W, VC[1] / H, VC[2] / W, VC[3] / H],
    "regions": [[p["name"], p["x"], p["y"]] for p in content["places"] if p["kind"] == "region"],
    "stations": [s["name"] for s in content["stations"]],
    "cheats": [[c["name"], c["playstation"]] for c in content["cheats"]],
    "eggs": [e["title"] for e in content["eggs"]],
    "characters": [c["name"] for c in content["characters"]],
    "missions": [m["title"] for m in content["missions"]],
    "collectibles": [[c["title"], c["count"]] for c in content["collectibles"]],
    "counts": {"missions": 91, "places": len(content["places"]), "cheats": len(content["cheats"]), "stations": len(content["stations"]),
               "eggs": len(content["eggs"]), "vehicles": len(json.load(open(os.path.join(ROOT, "Content", "vehicles.json")))["vehicles"])},
}
json.dump(data, open(os.path.join(OUT, "data.json"), "w"))
Image.open(os.path.join(ROOT, "App", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")).resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icon.png"))
print(data["counts"], data["regions"])
