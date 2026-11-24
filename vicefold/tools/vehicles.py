"""VICEFOLD : la liste des véhicules de GTA VI, reprise chaque jour du projet libre gta6-data (licence MIT).

Source : https://github.com/crlsmartnruiz/gta6-data (data/vehicles.json), elle-même relevée sur gta6intel.com.
On ne garde que des faits : le nom, le constructeur, la catégorie et le prix (quand il sera connu). Les textes de
présentation de la source ne sont pas repris. Les deux sources sont créditées dans l'app.

Écrit Content/vehicles.json seulement si la liste a changé (l'app télécharge le fichier toute seule).
Usage : python3 vehicles.py [chemin ou URL de vehicles.json]
"""
import datetime
import json
import os
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Content", "vehicles.json")
SRC = "https://raw.githubusercontent.com/crlsmartnruiz/gta6-data/main/data/vehicles.json"

CLASSES = {
    "super": "super", "sports": "sports", "sports classic": "classic", "muscle": "muscle", "coupe": "coupe",
    "sedan": "sedan", "compact": "compact", "suv": "suv", "off-road": "offroad", "pickup": "pickup", "van": "van",
    "motorcycle": "motorcycle", "cycle": "cycle", "boat": "boat", "plane": "plane", "helicopter": "helicopter",
    "emergency": "emergency", "service": "service", "utility": "utility", "commercial": "commercial",
    "industrial": "industrial", "military": "military",
}


def load(src):
    if src.startswith("http"):
        with urllib.request.urlopen(urllib.request.Request(src, headers={"User-Agent": "vicefold-sync"}), timeout=60) as r:
            return json.load(r)
    return json.load(open(src))


def price(v):
    p = v.get("price")
    if isinstance(p, (int, float)) and p > 0:
        return int(p)
    if isinstance(p, str):
        digits = "".join(c for c in p if c.isdigit())
        return int(digits) if digits else None
    return None


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else SRC
    raw = load(src)
    records = raw.get("records", raw) if isinstance(raw, dict) else raw
    seen, vehicles = set(), []
    for v in records:
        name = (v.get("name") or "").strip()
        vid = (v.get("id") or "").strip()
        if not name or not vid or vid in seen:
            continue
        seen.add(vid)
        vehicles.append({
            "id": vid,
            "name": name,
            "maker": (v.get("manufacturer") or None),
            "kind": CLASSES.get((v.get("vehicle_class") or "").strip().lower(), "other"),
            "price": price(v),
        })
    vehicles.sort(key=lambda x: (x["kind"], x["name"].lstrip("'0123456789 ").lower()))
    if len(vehicles) < 50:
        sys.exit(f"ÉCHEC : seulement {len(vehicles)} véhicules lus, fichier laissé tel quel")

    old = json.load(open(OUT)) if os.path.exists(OUT) else {}
    if old.get("vehicles") == vehicles:
        print(f"inchangé : {len(vehicles)} véhicules, {sum(1 for v in vehicles if v['price'])} prix")
        return
    today = datetime.date.today()
    out = {
        "version": int(today.strftime("%Y%m%d")) * 100 + (old.get("version", 0) % 100 + 1 if str(old.get("version", "")).startswith(today.strftime("%Y%m%d")) else 0),
        "updated": today.isoformat(),
        "credit": "gta6-data (MIT) · gta6intel.com",
        "vehicles": vehicles,
    }
    with open(OUT, "w") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    kinds = {}
    for v in vehicles:
        kinds[v["kind"]] = kinds.get(v["kind"], 0) + 1
    print(f"écrit : {len(vehicles)} véhicules, {sum(1 for v in vehicles if v['price'])} prix, version {out['version']}")
    print("catégories :", ", ".join(f"{k} {n}" for k, n in sorted(kinds.items(), key=lambda x: -x[1])))


if __name__ == "__main__":
    main()
