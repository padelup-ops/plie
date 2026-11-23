"""VICEFOLD : la carte communautaire de Leonida et ses lieux, depuis GTADB.org (CC BY 4.0).

Source : https://github.com/rolux/gtadb.org (map.gtadb.org) — « GTA VI Community Map » v18 de Yanis et de la
communauté de cartographie, et les repères (landmarks) de GTADB. Licence : Creative Commons Attribution 4.0.
Changements : tuiles recadrées sur Leonida (sans la légende ni les vignettes des bandes-annonces), lieux convertis
dans le repère de l'app, catégories regroupées, lieux démolis retirés.

Usage : python3 gtadb.py <clone de gtadb.org>
Écrit vicefold/Tiles/<z>/<z>,<y>,<x>.jpg (niveaux 0 à 4) et vicefold/tools/gtadb_places.json.
"""
import json
import os
import shutil
import sys

SRC = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
TILES_OUT = os.path.join(HERE, "..", "Tiles")
PLACES_OUT = os.path.join(HERE, "gtadb_places.json")
TILESET = "yanis,18"

# Le cadre de la carte dans l'app, en mètres du jeu (x vers l'est, y vers le nord). À l'est de 3 840 m, la
# carte source porte sa légende et des vignettes des bandes-annonces : on s'arrête avant.
MIN_X, MAX_X = -11264.0, 3840.0
MAX_Y, MIN_Y = 11264.0, -9216.0
W, H = MAX_X - MIN_X, MAX_Y - MIN_Y


def to_map(wx, wy):
    """Mètres du jeu → position de 0 à 1 sur la carte de l'app (haut-gauche = 0, 0)."""
    return (wx - MIN_X) / W, (MAX_Y - wy) / H


def tiles():
    if os.path.isdir(TILES_OUT):
        shutil.rmtree(TILES_OUT)
    n = 0
    for z in range(0, 5):
        mppx = 32 / 2 ** z
        src = os.path.join(SRC, "maps", "tiles", "6", TILESET, str(z))
        out = os.path.join(TILES_OUT, str(z))
        os.makedirs(out, exist_ok=True)
        for f in sorted(os.listdir(src)):
            _, ty, tx = map(int, f[:-4].split(","))
            x0 = tx * 256 * mppx - 16384
            y0 = 16384 - ty * 256 * mppx          # bord nord de la tuile
            x1, y1 = x0 + 256 * mppx, y0 - 256 * mppx
            if x0 >= MAX_X or x1 <= MIN_X or y1 >= MAX_Y or y0 <= MIN_Y:
                continue
            shutil.copy(os.path.join(src, f), os.path.join(out, f))
            n += 1
    with open(os.path.join(TILES_OUT, "ATTRIBUTION.md"), "w") as f:
        f.write("""# Carte de Leonida

GTA VI Community Map v18 (Yanis et la communauté de cartographie), tuiles de GTADB.org.
Licence : Creative Commons Attribution 4.0 International — https://creativecommons.org/licenses/by/4.0/
Source : https://map.gtadb.org — https://github.com/rolux/gtadb.org
Changements : recadrée sur Leonida (légende et vignettes retirées). Carte de fans, non officielle.
""")
    print("tuiles", n)


# Catégories : les étiquettes de GTADB → nos couches de carte (les plus précises d'abord).
KINDS = [
    ("#safehouse", "property"), ("#gas", "gas"), ("#airport", "transport"), ("#marina", "transport"),
    ("#bus", "transport"), ("#train", "transport"), ("#metro", "transport"), ("#metromover", "transport"),
    ("#supermarket", "shop"), ("#guns", "shop"), ("#bar", "food"), ("#tennis", "activity"), ("#racetrack", "activity"),
    ("hotel", "hotel"), ("restaurant", "food"), ("retail", "shop"), ("transportation", "transport"),
    ("leisure", "activity"), ("events", "activity"), ("landmark", "landmark"), ("natural", "nature"),
    ("government", "public"), ("public", "public"), ("utilities", "public"),
]


def kind(tags):
    for t, k in KINDS:
        if t in tags:
            return k
    return "other"


def places():
    d = json.load(open(os.path.join(SRC, "map", "data", "6", "landmarks.json")))
    out = []
    for lid, v in d.items():
        address, xy, real, tags = v[0], v[1], v[3], v[6]
        if not xy or address.startswith("?") or "demolished" in tags:
            continue
        x, y = to_map(*xy)
        if not (0 <= x <= 1 and 0 <= y <= 1):
            continue
        parts = [p.strip() for p in address.split(",")]
        name = parts[0].rstrip("?").strip()
        if not name:
            continue
        real_parts = [p.strip() for p in (real or "").split(",") if p.strip()]
        real_name = None
        if real_parts:
            city = next((p for p in reversed(real_parts[:-2]) if not any(ch.isdigit() for ch in p)), None)
            real_name = real_parts[0] if not city or city == real_parts[0] else f"{real_parts[0]}, {city}"
        out.append({
            "id": "g-" + lid,
            "name": name,
            "kind": kind(tags),
            "x": round(x, 5),
            "y": round(y, 5),
            "region": ", ".join(parts[1:]) or None,
            "real": real_name,
            "enterable": "enterable" in tags,
            "uncertain": "?" in parts[0] or "unconfirmed" in tags,
            "closed": "closed" in tags,
        })
    out.sort(key=lambda p: (p["region"] or "", p["name"]))
    json.dump(out, open(PLACES_OUT, "w"), ensure_ascii=False, indent=0)
    from collections import Counter
    print("lieux", len(out), Counter(p["kind"] for p in out).most_common())


if __name__ == "__main__":
    tiles()
    places()
