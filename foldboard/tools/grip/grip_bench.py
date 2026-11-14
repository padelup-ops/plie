#!/usr/bin/env python3
"""Banc d'essai de la détection de la main, à partir des vrais journaux de prise en main.

Les journaux viennent du clavier : menu de position › « Copier les données de la main pour le développeur »
(texte « FOLDBOARD-GRIPLOG: » + JSON compressé en base64). On les range dans tools/grip/logs/ (un fichier
par personne et par jour, nommé sans adresse ni nom complet). Ils ne contiennent aucune lettre tapée, mais
ce sont des données de testeurs : ce dossier est ignoré par git, les journaux ne vont JAMAIS dans le dépôt (public).

Ce que le banc mesure :
  - les déplacements automatiques du clavier (événements 3), et lesquels étaient faux : défaits dans les
    20 secondes, par le clavier lui-même (aller-retour) ou par la personne (correction à la main, événement 4) ;
  - pour chaque règle candidate (voir RULES), combien de sauts faux elle aurait évités, et combien de bons
    déplacements elle aurait retenus.

Usage : python3 grip_bench.py [fichiers…]   (sans argument : tous les journaux de logs/)
À lancer avant et après chaque changement de GripDetector.swift : on ne garde une règle que si elle évite
nettement plus de sauts faux qu'elle ne retient de bons déplacements, sur l'ensemble des journaux.
"""
import base64
import glob
import json
import os
import sys
import zlib
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = {0: "gauche", 1: "droite", 2: "deux mains"}
UNDO = 20  # secondes : un déplacement défait dans ce délai était faux


def load(path):
    t = open(path, encoding="utf-8").read()
    i = t.index("FOLDBOARD-GRIPLOG:")
    raw = base64.b64decode("".join(t[i + 18:].split()))
    try:
        data = zlib.decompress(raw, -15)  # NSData .zlib : deflate brut
    except zlib.error:
        data = zlib.decompress(raw)
    d = json.loads(data)
    d["events"].sort(key=lambda e: e["t"])
    return d


def wrap(a):
    return (a + 180) % 360 - 180


def moves(d):
    """Chaque déplacement automatique, avec son contexte et s'il était faux."""
    ev = d["events"]
    sw = [e for e in ev if e["k"] in (3, 4)]
    out = []
    cur = None
    enter = {}  # posture au moment où l'on est arrivé dans chaque côté
    for i, e in enumerate(sw):
        if e["k"] == 3 and cur is not None and e["g"] != cur:
            nxt = [x for x in sw[i + 1:] if x["t"] - e["t"] <= UNDO]
            wrong = bool(nxt) and nxt[0]["g"] == cur
            out.append({
                "from": cur, "to": e["g"], "wrong": wrong,
                "roll": e.get("roll"), "inc": e.get("inc"),
                "ctx": d["contexts"][int(e["c"])] if int(e["c"]) < len(d["contexts"]) else "?",
                "enter_roll": enter.get(cur, {}).get("roll"),
                "since_enter": e["t"] - enter.get(cur, {}).get("t", e["t"]),
            })
        if e["g"] != cur:
            enter[e["g"]] = {"roll": e.get("roll"), "t": e["t"]}
        cur = e["g"]
    return out


# Règles candidates : une fonction qui dit si la règle aurait empêché ce déplacement.
# « actuelle » = le comportement de la version en test (à tenir à jour avec GripDetector.swift).
RULES = {
    "deux mains : tourner de 8° pour repartir": lambda m: m["from"] == 2 and m["roll"] is not None
        and m["enter_roll"] is not None and abs(wrap(m["roll"] - m["enter_roll"])) < 8,
    "deux mains : tourner de 12° pour repartir": lambda m: m["from"] == 2 and m["roll"] is not None
        and m["enter_roll"] is not None and abs(wrap(m["roll"] - m["enter_roll"])) < 12,
    "une main : tourner de 8° pour changer de côté": lambda m: m["from"] in (0, 1) and m["to"] in (0, 1)
        and m["roll"] is not None and m["enter_roll"] is not None and abs(wrap(m["roll"] - m["enter_roll"])) < 8,
    "allongé (écran vers le bas) : ne pas bouger": lambda m: m["inc"] is not None and m["inc"] < 0,
}
RULES["8° à deux mains + allongé immobile"] = lambda m: RULES["deux mains : tourner de 8° pour repartir"](m) \
    or RULES["allongé (écran vers le bas) : ne pas bouger"](m)


def pct(a, b):
    return f"{100 * a / b:.0f} %" if b else "–"


def main(paths):
    paths = paths or sorted(glob.glob(os.path.join(HERE, "logs", "*.txt")))
    all_moves = []
    for p in paths:
        d = load(p)
        ev = d["events"]
        taps = sum(1 for e in ev if e["k"] == 1)
        ms = moves(d)
        all_moves += ms
        bad = sum(m["wrong"] for m in ms)
        print(f"{os.path.basename(p)} · v{d['extra'].get('version', '?')} · {', '.join(d['contexts'])}")
        print(f"  appuis {taps} · déplacements auto {len(ms)} · faux {bad} ({pct(bad, len(ms))}) · "
              f"corrections à la main {sum(1 for e in ev if e['k'] == 4)}")
    if not all_moves:
        print("aucun déplacement")
        return
    print()
    print("Déplacements automatiques (tous journaux)")
    by = Counter((m["from"], m["to"], m["wrong"]) for m in all_moves)
    for (a, b) in sorted({(m["from"], m["to"]) for m in all_moves}):
        n = by[(a, b, True)] + by[(a, b, False)]
        print(f"  {NAMES[a]:>10} → {NAMES[b]:<10} {n:4d}   faux {by[(a, b, True)]:3d} ({pct(by[(a, b, True)], n)})")
    total_bad = sum(m["wrong"] for m in all_moves)
    total_good = len(all_moves) - total_bad
    print(f"  total {len(all_moves)} · faux {total_bad} ({pct(total_bad, len(all_moves))})")
    print()
    print("Règles candidates : sauts faux évités / bons déplacements retenus")
    for name, rule in RULES.items():
        hit = [m for m in all_moves if rule(m)]
        b = sum(m["wrong"] for m in hit)
        g = len(hit) - b
        print(f"  {name:<48} évite {b:3d}/{total_bad} ({pct(b, total_bad)})   retient {g:3d}/{total_good} ({pct(g, total_good)})")


if __name__ == "__main__":
    main(sys.argv[1:])
