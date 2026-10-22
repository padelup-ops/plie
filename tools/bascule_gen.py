"""BASCULE : génère et vérifie les niveaux.

Plateau 1 × 1, y vers le HAUT, la charnière du Duo est la ligne x = 0,5.
La bille descend la pente de départ et arrive au pivot P = (0,5 ; yp) avec la vitesse
v0 = sqrt(2 g drop). Elle monte le tremplin (longueur L, angle alpha réglé par le pli),
le quitte avec v1 = sqrt(v0² - 2 g L sin alpha), puis vole (gravité, vent éventuel).
Le vol est intégré pas à pas (dt fixe) : BasculeEngine.swift en est la traduction exacte.

Usage : python3 bascule_gen.py   (écrit BasculeLevels.swift et bascule_levels.json)
"""
import json
import math
import random
import sys

G = 2.0
DT = 1.0 / 240.0
MAX_STEPS = 240 * 6
RAMP_LEN = 0.18
BALL_R = 0.018
STAR_R = 0.03
ALPHA_MIN = -25.0
ALPHA_MAX = 65.0
BOUNCE = 0.9
BASKET_DEPTH = 0.06


def point_seg_dist(px, py, ax, ay, bx, by):
    ex, ey = bx - ax, by - ay
    l2 = ex * ex + ey * ey
    if l2 == 0:
        return math.hypot(px - ax, py - ay)
    u = max(0.0, min(1.0, ((px - ax) * ex + (py - ay) * ey) / l2))
    return math.hypot(px - (ax + u * ex), py - (ay + u * ey))


def basket_walls(b):
    x1, x2, top = b
    bottom = top - BASKET_DEPTH
    return [(x1, top, x1, bottom), (x1, bottom, x2, bottom), (x2, bottom, x2, top)]


def simulate(lv, alpha, record=False):
    """Renvoie (résultat, étoiles, a rebondi, trajectoire). Résultat : 'win', 'short', 'wall', 'out'."""
    yp = lv["yp"]
    v0sq = 2 * G * lv["drop"]
    a = math.radians(alpha)
    v1sq = v0sq - 2 * G * RAMP_LEN * math.sin(a)
    path = []
    if v1sq <= 0:
        return "short", set(), False, path
    v1 = math.sqrt(v1sq)
    x = 0.5 + RAMP_LEN * math.cos(a)
    y = yp + RAMP_LEN * math.sin(a)
    vx = v1 * math.cos(a)
    vy = v1 * math.sin(a)
    wind = lv["wind"]
    x1, x2, top = lv["basket"]
    walls = [tuple(w) for w in lv["walls"]] + basket_walls(lv["basket"])
    stars = set()
    bounced = False
    if record:
        path.append((x, y))
    for _ in range(MAX_STEPS):
        vx += wind * DT
        vy -= G * DT
        nx = x + vx * DT
        ny = y + vy * DT
        for pad in lv["pads"]:
            px1, px2, py = pad
            if vy < 0 and y >= py + BALL_R and ny < py + BALL_R and px1 <= nx <= px2:
                ny = py + BALL_R
                vy = -vy * BOUNCE
                if not bounced and record:
                    lv["_bounce_at"] = len(path)
                bounced = True
        if vy < 0 and y >= top and ny < top and x1 + BALL_R <= nx <= x2 - BALL_R:
            if record:
                path.append((nx, ny))
            return "win", stars, bounced, path
        for (ax, ay, bx, by) in walls:
            if nx < min(ax, bx) - BALL_R or nx > max(ax, bx) + BALL_R or ny < min(ay, by) - BALL_R or ny > max(ay, by) + BALL_R:
                continue
            if point_seg_dist(nx, ny, ax, ay, bx, by) < BALL_R:
                if record:
                    path.append((nx, ny))
                return "wall", stars, bounced, path
        for i, (sx, sy) in enumerate(lv["stars"]):
            if math.hypot(nx - sx, ny - sy) < BALL_R + STAR_R:
                stars.add(i)
        if nx < -0.05 or nx > 1.05 or ny < 0 or ny > 1.6:
            return "out", stars, bounced, path
        x, y = nx, ny
        if record:
            path.append((x, y))
    return "out", stars, bounced, path


def scan(lv, step=0.1, coarse=0.5):
    """Fenêtres d'angle gagnantes [(début, fin, a rebondi)], précises à `step` près.

    Balayage grossier, puis affinage des bords par dichotomie (beaucoup plus rapide).
    """
    def ok(a):
        res, _, bounced, _ = simulate(lv, a)
        return res == "win", bounced

    n = int(round((ALPHA_MAX - ALPHA_MIN) / coarse))
    samples = [ALPHA_MIN + i * coarse for i in range(n + 1)]
    flags = [ok(a) for a in samples]

    def refine(lo, hi, lo_ok):
        while hi - lo > step / 2:
            mid = (lo + hi) / 2
            if ok(mid)[0] == lo_ok:
                lo = mid
            else:
                hi = mid
        return lo if lo_ok else hi

    wins = []
    i = 0
    while i <= n:
        if flags[i][0]:
            j = i
            while j + 1 <= n and flags[j + 1][0]:
                j += 1
            start = samples[i] if i == 0 else refine(samples[i - 1], samples[i], False)
            end = samples[j] if j == n else refine(samples[j], samples[j + 1], True)
            wins.append((start, end, flags[i][1]))
            i = j + 1
        else:
            i += 1
    return wins


WORLD_NAMES = {1: "Premier saut", 2: "Coup de vent", 3: "Rebonds"}


def spec(world, idx):
    if world == 1:
        return {"wind": 0.0, "pads": 0, "walls": (0, 1) if idx < 4 else (1, 2), "bw": 0.1 if idx < 4 else 0.085,
                "win": (3.0, 11.0), "preview": idx < 3}
    if world == 2:
        return {"wind": 1.0, "pads": 0, "walls": (1, 2), "bw": 0.08, "win": (2.5, 8.0), "preview": False}
    return {"wind": 0.0 if idx < 5 else 0.6, "pads": 1, "walls": (1, 2), "bw": 0.08, "win": (2.5, 7.0), "preview": False}


def build(rng, world, idx):
    sp = spec(world, idx)
    lv = {"world": world, "yp": rng.uniform(0.28, 0.5), "drop": rng.uniform(0.22, 0.38),
          "wind": 0.0, "pads": [], "walls": [], "stars": [], "basket": (0, 0, 0), "preview": sp["preview"]}
    if lv["yp"] + lv["drop"] > 0.9:
        return None
    if sp["wind"]:
        lv["wind"] = rng.choice([-1, 1]) * rng.uniform(0.35, 0.9) * sp["wind"]
    alpha = rng.uniform(-12, 58)
    free = dict(lv, basket=(5, 5.1, -5))  # pas de panier : on suit la trajectoire libre
    res, _, _, path = simulate(free, alpha, record=True)
    if len(path) < 40:
        return None

    if sp["pads"]:
        # la bille rebondit sur un ressort, puis tombe dans le panier
        cands = [i for i in range(1, len(path)) if path[i][1] < path[i - 1][1] and 0.56 <= path[i][0] <= 0.86 and 0.08 <= path[i][1] <= 0.4]
        if not cands:
            return None
        i = rng.choice(cands)
        px, py = path[i]
        w = 0.12
        lv["pads"] = [(px - w / 2, px + w / 2, py - BALL_R - 0.002)]
        probe = dict(lv, basket=(5, 5.1, -5))
        res, _, bounced, path2 = simulate(probe, alpha, record=True)
        if not bounced or "_bounce_at" not in probe:
            return None
        k0 = probe["_bounce_at"] + 3
        cands = [k for k in range(k0 + 1, len(path2)) if path2[k][1] < path2[k - 1][1] and 0.08 <= path2[k][1] <= 0.75 and 0.56 <= path2[k][0] <= 0.95]
        if not cands:
            return None
        k = rng.choice(cands[len(cands) // 3:] or cands)
        bx, by = path2[k]
        track = path2[:k]
    else:
        cands = [i for i in range(1, len(path)) if path[i][1] < path[i - 1][1] and 0.6 <= path[i][0] <= 0.95 and 0.06 <= path[i][1] <= 0.7]
        if not cands:
            return None
        i = rng.choice(cands)
        bx, by = path[i]
        track = path[:i]

    bw = sp["bw"]
    lv["basket"] = (bx - bw / 2, bx + bw / 2, by)
    if lv["basket"][0] < 0.53 or lv["basket"][1] > 0.98:
        return None

    # murs supplémentaires près de la trajectoire, sans la toucher
    for _ in range(rng.randint(*sp["walls"])):
        for _try in range(30):
            j = rng.randrange(len(track) // 4, max(len(track) // 4 + 1, len(track) - 10))
            tx, ty = track[j]
            if tx < 0.62:
                continue
            side = rng.choice([-1, 1])
            off = rng.uniform(0.05, 0.09)
            length = rng.uniform(0.08, 0.2)
            if rng.random() < 0.5:  # mur vertical au-dessus ou en dessous
                cx, cy = tx, ty + side * (off + length / 2)
                wall = (cx, cy - length / 2, cx, cy + length / 2)
            else:  # plafond ou plancher
                cx, cy = tx, ty + side * off
                wall = (cx - length / 2, cy, cx + length / 2, cy)
            if any(point_seg_dist(px, py, *wall) < BALL_R + 0.02 for px, py in track):
                continue
            if min(wall[1], wall[3]) < 0.0 or max(wall[1], wall[3]) > 0.98 or min(wall[0], wall[2]) < 0.55 or max(wall[0], wall[2]) > 0.99:
                continue
            if point_seg_dist(lv["basket"][0], lv["basket"][2], *wall) < 0.05 or point_seg_dist(lv["basket"][1], lv["basket"][2], *wall) < 0.05:
                continue
            lv["walls"].append(wall)
            break
    return lv


def accept(lv, world, idx):
    if lv is None:
        return None
    sp = spec(world, idx)
    wins = scan(lv)
    if not wins:
        return None
    best = max(wins, key=lambda w: w[1] - w[0])
    width = best[1] - best[0]
    wmin, wmax = sp["win"]
    progress = idx / 9
    cap = wmax - (wmax - wmin) * progress * 0.6
    if width < wmin or width > cap:
        return None
    total = sum(w[1] - w[0] for w in wins)
    if total > width * 1.6 + 0.2:
        return None
    if sp["pads"] and any(not w[2] for w in wins):
        return None
    center = (best[0] + best[1]) / 2
    res, _, _, path = simulate(lv, center, record=True)
    if res != "win" or len(path) < 30:
        return None
    # trois étoiles sur la trajectoire du centre de la fenêtre
    n = len(path)
    lv["stars"] = [path[int(n * f)] for f in (0.25, 0.5, 0.75)]
    if any(s[0] < 0.55 for s in lv["stars"]):
        return None
    res, stars, _, _ = simulate(lv, center)
    if res != "win" or len(stars) != 3:
        return None
    lv["solution"] = center
    lv["_width"] = width
    return lv


def make(job):
    world, idx = job
    rng = random.Random(7000 * world + idx + 20261022)
    for attempt in range(300000):
        lv = accept(build(rng, world, idx), world, idx)
        if lv:
            lv["_attempts"] = attempt
            return lv
    raise RuntimeError(f"échec monde {world} niveau {idx + 1}")


def generate():
    from multiprocessing import Pool
    jobs = [(world, idx) for world in (1, 2, 3) for idx in range(10)]
    with Pool(2) as pool:
        made = list(pool.imap(make, jobs))
    levels = []
    for world in (1, 2, 3):
        batch = [l for l in made if l["world"] == world]
        for l in batch:
            print(f"monde {world}: fenêtre {l['_width']:.1f}°, {len(l['walls'])} mur(s), vent {l['wind']:+.2f}, "
                  f"{len(l['pads'])} ressort(s), {l['_attempts']} essais", file=sys.stderr)
        batch.sort(key=lambda l: -l["_width"])
        levels += batch
    return levels


def r4(x):
    return round(x, 4)


def rounded(lv):
    return {
        "world": lv["world"], "yp": r4(lv["yp"]), "drop": r4(lv["drop"]), "wind": r4(lv["wind"]),
        "pads": [tuple(r4(v) for v in p) for p in lv["pads"]],
        "walls": [tuple(r4(v) for v in w) for w in lv["walls"]],
        "stars": [tuple(r4(v) for v in s) for s in lv["stars"]],
        "basket": tuple(r4(v) for v in lv["basket"]),
        "preview": lv["preview"], "solution": r4(lv["solution"]),
    }


def to_swift(levels):
    out = ["// Fichier généré par tools/bascule_gen.py : ne pas modifier à la main.",
           "// Chaque niveau a été vérifié : l'angle « solution » fait tomber la bille dans le panier",
           "// en ramassant les trois étoiles.",
           "", "import Foundation", "", "extension BasculeLevel {", "    static let all: [BasculeLevel] = ["]
    for i, lv in enumerate(levels):
        walls = ", ".join(f"BasculeWall({w[0]}, {w[1]}, {w[2]}, {w[3]})" for w in lv["walls"])
        pads = ", ".join(f"BasculePad({p[0]}, {p[1]}, {p[2]})" for p in lv["pads"])
        stars = ", ".join(f"BPt({s[0]}, {s[1]})" for s in lv["stars"])
        b = lv["basket"]
        out += [
            "        BasculeLevel(",
            f"            number: {i + 1}, world: {lv['world']}, pivotY: {lv['yp']}, drop: {lv['drop']}, wind: {lv['wind']},",
            f"            basket: BasculeBasket({b[0]}, {b[1]}, {b[2]}),",
            f"            walls: [{walls}],",
            f"            pads: [{pads}],",
            f"            stars: [{stars}],",
            f"            preview: {'true' if lv['preview'] else 'false'}, solution: {lv['solution']}",
            "        )" + ("," if i < len(levels) - 1 else ""),
        ]
    out += ["    ]", "}"]
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    levels = [rounded(l) for l in generate()]
    for i, lv in enumerate(levels):
        res, stars, _, _ = simulate(lv, lv["solution"])
        if res != "win" or len(stars) != 3:
            raise SystemExit(f"niveau {i + 1} : la solution arrondie ne marche plus ({res}, {len(stars)} étoiles)")
        wins = scan(lv)
        if not any(w[0] <= lv["solution"] <= w[1] for w in wins):
            raise SystemExit(f"niveau {i + 1} : solution hors fenêtre")
    json.dump(levels, open("bascule_levels.json", "w"), indent=1)
    open("BasculeLevels.swift", "w").write(to_swift(levels))
    print("OK", len(levels), "niveaux", file=sys.stderr)
