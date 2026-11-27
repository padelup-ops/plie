"""VICEFOLD : les véhicules rares de Leonida et leur emplacement, depuis Open GTA 6 Map (CC BY 4.0).

Source : https://github.com/fbritoferreira/gta6 (public/data/locations.json), « Map data from Open GTA 6 Map
(fbritoferreira), CC BY 4.0 » — https://creativecommons.org/licenses/by/4.0/
On ne garde que la catégorie « vehicle » : les véhicules remarquables (des variantes uniques garées à un endroit
fixe), les véhicules demandés et les points d'apparition. Changements : positions converties dans le repère de la
carte de l'app (le même que gtadb.py : 343 lieux communs aux deux sources retombent à 1 m près). On ne reprend que
des faits : le nom, le genre et la position. Les descriptions de la source (souvent le texte du jeu), ses captures
d'écran et ses liens ne sont pas repris. Les deux sources sont créditées dans l'app.

Usage : python3 opengta6.py [chemin ou URL de locations.json]
Écrit vicefold/tools/opengta6_vehicles.json (lu par content.py).
"""
import json
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "opengta6_vehicles.json")
SRC = "https://raw.githubusercontent.com/fbritoferreira/gta6/main/public/data/locations.json"
# Le cadre de la carte dans l'app, en mètres du jeu (voir gtadb.py).
MIN_X, MAX_X = -11264.0, 3840.0
MAX_Y, MIN_Y = 11264.0, -9216.0
W, H = MAX_X - MIN_X, MAX_Y - MIN_Y
TYPES = {"Standout vehicle": "standout", "Vehicle request": "request", "Vehicle spawn": "spawn"}


def load(src):
    if src.startswith("http"):
        with urllib.request.urlopen(urllib.request.Request(src, headers={"User-Agent": "vicefold-sync"}), timeout=60) as r:
            return json.load(r)
    return json.load(open(src))


def to_map(x, y):
    """Unités de la carte source → mètres du jeu → position de 0 à 1 sur la carte de l'app."""
    gx, gy = float(x) * 32 - 16384, 16384 - float(y) * 32
    return round((gx - MIN_X) / W, 5), round((MAX_Y - gy) / H, 5)


def main():
    out = []
    for p in load(sys.argv[1] if len(sys.argv) > 1 else SRC):
        if p.get("kind") != "vehicle" or p.get("type") not in TYPES or not (p.get("name") or "").strip():
            continue
        x, y = to_map(p["x"], p["y"])
        if not (0 <= x <= 1 and 0 <= y <= 1):
            continue
        out.append({"id": "o-" + p["id"], "name": " ".join(p["name"].split()), "type": TYPES[p["type"]], "x": x, "y": y})
    out.sort(key=lambda d: d["id"])
    json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    kinds = {}
    for d in out:
        kinds[d["type"]] = kinds.get(d["type"], 0) + 1
    print("ok", len(out), "véhicules", kinds)


if __name__ == "__main__":
    main()
