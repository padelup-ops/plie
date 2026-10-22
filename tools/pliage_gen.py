"""PLIAGE : génère et vérifie les niveaux.

La feuille est une grille de cases. Chaque case porte un mélange de pigments :
rouge = 1, jaune = 2, bleu = 4 (orange = 3, violet = 5, vert = 6, brun = 7).
Plier le long d'une ligne décalque la peinture fraîche : chaque case reçoit la peinture
de la case symétrique (si elle est sur la feuille). Le pliage est donc une union symétrique.

Chaque niveau est vérifié par une recherche exhaustive : le nombre de plis demandé est
exactement le minimum pour obtenir le modèle.

Usage : python3 pliage_gen.py   (écrit PliageLevels.swift et pliage_levels.json)
"""
import json
import random
import sys
from collections import deque

RED, YELLOW, BLUE = 1, 2, 4


def ops(w, h):
    return [("v", k) for k in range(1, w)] + [("h", k) for k in range(1, h)]


def fold(grid, w, h, op):
    axis, k = op
    out = list(grid)
    for r in range(h):
        for c in range(w):
            if axis == "v":
                mc, mr = 2 * k - 1 - c, r
            else:
                mc, mr = c, 2 * k - 1 - r
            if 0 <= mc < w and 0 <= mr < h:
                out[r * w + c] = grid[r * w + c] | grid[mr * w + mc]
    return tuple(out)


def bfs(start, target, w, h, max_depth):
    """Distance minimale, et nombre de premiers plis qui mènent à une solution optimale."""
    if start == target:
        return 0, 0
    operations = ops(w, h)
    dist = {start: 0}
    q = deque([start])
    while q:
        g = q.popleft()
        d = dist[g]
        if d >= max_depth:
            continue
        for op in operations:
            n = fold(g, w, h, op)
            if n not in dist:
                dist[n] = d + 1
                q.append(n)
    if target not in dist:
        return None, 0
    best = dist[target]
    # premiers plis qui gardent une solution en best - 1 plis
    good_first = 0
    for op in operations:
        n = fold(start, w, h, op)
        if n == start:
            continue
        sub = shortest(n, target, w, h, best - 1)
        if sub is not None and sub == best - 1:
            good_first += 1
    return best, good_first


def shortest(start, target, w, h, limit):
    if start == target:
        return 0
    frontier = {start}
    seen = {start}
    for depth in range(1, limit + 1):
        nxt = set()
        for g in frontier:
            for op in ops(w, h):
                n = fold(g, w, h, op)
                if n == target:
                    return depth
                if n not in seen:
                    seen.add(n)
                    nxt.add(n)
        frontier = nxt
    return None


WORLDS = {
    1: {"name": "Premiers plis", "size": (4, 4)},
    2: {"name": "Mélanges", "size": (5, 5)},
    3: {"name": "Origami", "size": (6, 6)},
}


def spec(world, idx):
    if world == 1:
        return {"folds": 1 if idx < 4 else 2, "dots": (1, 3), "pigments": [BLUE], "first_max": 2 if idx < 4 else 2}
    if world == 2:
        pair = [(RED, YELLOW), (YELLOW, BLUE), (RED, BLUE)][idx % 3]
        return {"folds": 2 if idx < 6 else 3, "dots": (2, 4), "pigments": list(pair), "first_max": 2}
    return {"folds": 3 if idx < 7 else 4, "dots": (3, 5), "pigments": [RED, YELLOW, BLUE], "first_max": 2}


def candidate(rng, world, idx):
    w, h = WORLDS[world]["size"]
    sp = spec(world, idx)
    grid = [0] * (w * h)
    ndots = rng.randint(*sp["dots"])
    pigments = list(sp["pigments"])
    for i in range(ndots):
        pig = pigments[i % len(pigments)] if i < len(pigments) else rng.choice(pigments)
        cell = rng.randrange(w * h)
        grid[cell] |= pig
    start = tuple(grid)
    seq = []
    g = start
    operations = ops(w, h)
    for _ in range(sp["folds"]):
        choices = [op for op in operations if fold(g, w, h, op) != g]
        if not choices:
            return None
        op = rng.choice(choices)
        seq.append(op)
        g = fold(g, w, h, op)
    target = g
    return start, target, seq


def accept(world, idx, start, target, seq):
    w, h = WORLDS[world]["size"]
    sp = spec(world, idx)
    painted = sum(1 for x in target if x)
    if painted < 4 or painted > 0.62 * w * h:
        return None
    if sum(1 for x in start if x) < 1:
        return None
    best, good_first = bfs(start, target, w, h, sp["folds"])
    if best != sp["folds"]:
        return None
    if sp["folds"] >= 2 and good_first > sp["first_max"]:
        return None
    mixed = sum(1 for x in target if x not in (0, RED, YELLOW, BLUE))
    if world == 2 and mixed < 1:
        return None
    if world == 3 and mixed < 2:
        return None
    # le modèle doit différer de la feuille de départ sur au moins 3 cases
    if sum(1 for a, b in zip(start, target) if a != b) < 3:
        return None
    return {"world": world, "width": w, "height": h, "start": list(start), "target": list(target),
            "par": best, "solution": [f"{a}{k}" for a, k in seq], "_first": good_first, "_painted": painted}


def generate():
    rng = random.Random(20261022)
    levels = []
    seen = set()
    for world in (1, 2, 3):
        batch = []
        for idx in range(15):
            for attempt in range(200000):
                c = candidate(rng, world, idx)
                if not c:
                    continue
                start, target, seq = c
                if (start, target) in seen:
                    continue
                lv = accept(world, idx, start, target, seq)
                if lv:
                    seen.add((start, target))
                    batch.append(lv)
                    print(f"monde {world} niveau {idx + 1}: {lv['par']} plis, {lv['_first']} bon(s) premier(s) pli(s), "
                          f"{lv['_painted']} cases peintes, {attempt} essais", file=sys.stderr)
                    break
            else:
                raise SystemExit(f"échec monde {world} niveau {idx + 1}")
        batch.sort(key=lambda l: (l["par"], -l["_first"], l["_painted"]))
        levels += batch
    return levels


def to_swift(levels):
    out = [
        "// Fichier généré par tools/pliage_gen.py : ne pas modifier à la main.",
        "// Chaque niveau a été vérifié : « par » est exactement le nombre minimal de plis.",
        "// Cases : 0 = papier, 1 = rouge, 2 = jaune, 4 = bleu, et leurs mélanges (somme).",
        "",
        "import Foundation",
        "",
        "extension PliageLevel {",
        "    static let all: [PliageLevel] = [",
    ]
    for i, lv in enumerate(levels):
        start = "".join(str(x) for x in lv["start"])
        target = "".join(str(x) for x in lv["target"])
        out.append(f'        PliageLevel(number: {i + 1}, world: {lv["world"]}, width: {lv["width"]}, height: {lv["height"]}, '
                   f'start: "{start}", target: "{target}", par: {lv["par"]}, solution: "{" ".join(lv["solution"])}")'
                   + ("," if i < len(levels) - 1 else ""))
    out += ["    ]", "}"]
    return "\n".join(out) + "\n"


def verify(levels):
    for i, lv in enumerate(levels):
        w, h = lv["width"], lv["height"]
        g = tuple(lv["start"])
        for s in lv["solution"]:
            g = fold(g, w, h, (s[0], int(s[1:])))
        assert list(g) == lv["target"], f"niveau {i + 1} : la solution ne donne pas le modèle"
        best = shortest(tuple(lv["start"]), tuple(lv["target"]), w, h, lv["par"])
        assert best == lv["par"], f"niveau {i + 1} : par incorrect"


if __name__ == "__main__":
    levels = generate()
    verify(levels)
    json.dump(levels, open("pliage_levels.json", "w"), indent=1)
    open("PliageLevels.swift", "w").write(to_swift(levels))
    print("OK", len(levels), "niveaux", file=sys.stderr)
