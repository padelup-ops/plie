"""RAYON v2 : génère et vérifie les niveaux à miroirs pivotants.

Plateau unité [0,1]x[0,1], y vers le bas, angles en degrés.
- miroir commandé (charnière) : angle = base + t * span * factor, t dans [0, 1]
- pivot : angle = étape * 45 (4 orientations), un tap = +1 étape
Le traceur ci-dessous est la référence : RayonEngine.swift en est la traduction exacte.

Usage : python3 rayon2_gen.py   (écrit RayonLevels.swift et rayon2_levels.json)
"""
import json
import math
import random
import sys
from itertools import product
from multiprocessing import Pool

EPS = 1e-7
MAX_SEGMENTS = 30
FINE = 1400
COARSE = 300
CENTER = (0.5, 0.5)
ROTOR_LEN = 0.17
CONTROL_LEN = 0.24
TWIN_LEN = 0.2


# ---------------------------------------------------------------- géométrie

def seg_points(cx, cy, length, angle):
    a = math.radians(angle)
    dx, dy = math.cos(a) * length / 2, math.sin(a) * length / 2
    return (cx - dx, cy - dy), (cx + dx, cy + dy)


def cross(ax, ay, bx, by):
    return ax * by - ay * bx


def ray_seg(ox, oy, dx, dy, p, q):
    ex, ey = q[0] - p[0], q[1] - p[1]
    den = cross(dx, dy, ex, ey)
    if abs(den) < 1e-12:
        return None
    wx, wy = p[0] - ox, p[1] - oy
    t = cross(wx, wy, ex, ey) / den
    s = cross(wx, wy, dx, dy) / den
    if t > EPS and -1e-9 <= s <= 1 + 1e-9:
        return t
    return None


def ray_circle(ox, oy, dx, dy, cx, cy, r):
    fx, fy = ox - cx, oy - cy
    b = fx * dx + fy * dy
    c = fx * fx + fy * fy - r * r
    disc = b * b - c
    if disc < 0:
        return None
    sq = math.sqrt(disc)
    t = -b - sq
    if t <= EPS:
        t = -b + sq
    return t if t > EPS else None


BORDER = [((0, 0), (1, 0)), ((1, 0), (1, 1)), ((1, 1), (0, 1)), ((0, 1), (0, 0))]


def build_segments(level, t, steps):
    """Même ordre que RayonEngine.lines : miroirs fixes, commandés, pivots, murs, bords."""
    segs = []
    for m in level["mirrors"]:
        p, q = seg_points(*m)
        segs.append((p, q, True))
    for c in level["controls"]:
        cx, cy, length, base, factor = c
        p, q = seg_points(cx, cy, length, base + t * level["span"] * factor)
        segs.append((p, q, True))
    for r, step in zip(level["rotors"], steps):
        p, q = seg_points(r[0], r[1], r[2], step * 45.0)
        segs.append((p, q, True))
    for w in level["walls"]:
        p, q = seg_points(*w)
        segs.append((p, q, False))
    for p, q in BORDER:
        segs.append((p, q, False))
    return segs


def trace(level, t, steps):
    segs = build_segments(level, t, steps)
    ox, oy = level["emitter"]
    a = math.radians(level["emitterAngle"])
    dx, dy = math.cos(a), math.sin(a)
    tx, ty = level["target"]
    tr = level["targetRadius"]
    pts = [(ox, oy)]
    last = -1
    for _ in range(MAX_SEGMENTS):
        best_t, best_i = None, -1
        for i, (p, q, _m) in enumerate(segs):
            if i == last:
                continue
            h = ray_seg(ox, oy, dx, dy, p, q)
            if h is not None and (best_t is None or h < best_t):
                best_t, best_i = h, i
        ht = ray_circle(ox, oy, dx, dy, tx, ty, tr)
        if ht is not None and (best_t is None or ht < best_t):
            pts.append((ox + dx * ht, oy + dy * ht))
            return pts, True
        if best_t is None:
            return pts, False
        hx, hy = ox + dx * best_t, oy + dy * best_t
        pts.append((hx, hy))
        p, q, is_mirror = segs[best_i]
        if not is_mirror:
            return pts, False
        ex, ey = q[0] - p[0], q[1] - p[1]
        ln = math.hypot(ex, ey)
        nx, ny = -ey / ln, ex / ln
        dot = dx * nx + dy * ny
        dx, dy = dx - 2 * dot * nx, dy - 2 * dot * ny
        ox, oy = hx, hy
        last = best_i
    return pts, False


def windows(level, steps, samples):
    res = []
    start = None
    for i in range(samples + 1):
        t = i / samples
        _, ok = trace(level, t, steps)
        if ok and start is None:
            start = i
        if (not ok or i == samples) and start is not None:
            end = i - 1 if not ok else i
            res.append((start / samples, end / samples))
            start = None
    return res


# ---------------------------------------------------------------- aides

def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def point_seg_dist(pt, p, q):
    px, py = pt
    ax, ay = p
    bx, by = q
    ex, ey = bx - ax, by - ay
    l2 = ex * ex + ey * ey
    if l2 == 0:
        return dist(pt, p)
    u = max(0.0, min(1.0, ((px - ax) * ex + (py - ay) * ey) / l2))
    return dist(pt, (ax + u * ex, ay + u * ey))


def segs_intersect(p1, q1, p2, q2):
    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    d1, d2 = orient(p2, q2, p1), orient(p2, q2, q1)
    d3, d4 = orient(p1, q1, p2), orient(p1, q1, q2)
    return d1 * d2 < 0 and d3 * d4 < 0


def seg_seg_dist(p1, q1, p2, q2):
    if segs_intersect(p1, q1, p2, q2):
        return 0.0
    return min(point_seg_dist(p1, p2, q2), point_seg_dist(q1, p2, q2),
               point_seg_dist(p2, p1, q1), point_seg_dist(q2, p1, q1))


def ang(a, b):
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))


def unit(deg):
    r = math.radians(deg)
    return math.cos(r), math.sin(r)


def norm180(x):
    return x % 180.0


def inside(p, lo=0.12, hi=0.88):
    return lo <= p[0] <= hi and lo <= p[1] <= hi


def edge_emitter(rng):
    side = rng.randrange(4)
    u = rng.uniform(0.15, 0.85)
    m = 0.06
    return [(u, m), (1 - m, u), (u, 1 - m), (m, u)][side]


# ---------------------------------------------------------------- construction

WORLD_NAMES = {1: "Premier reflet", 2: "Les pivots", 3: "Le labyrinthe", 4: "Les jumeaux"}


def plan(world, idx):
    """Ce que contient le niveau idx (0..14) du monde."""
    if world == 2:
        return {"rotors": 1 if idx < 6 else 2, "statics": 0, "twin": False,
                "walls": (1, 2) if idx < 6 else (1, 3), "decoys": (0, 0),
                "win": (0.035, 0.10) if idx < 6 else (0.03, 0.09), "span": (90, 110), "maxsol": 2}
    if world == 3:
        three = idx >= 9
        return {"rotors": 3 if three else 2, "statics": 1 if (idx % 3 == 1 and not three) else 0, "twin": False,
                "walls": (2, 4), "decoys": (0, 2),
                "win": (0.025, 0.07) if three else (0.028, 0.08), "span": (85, 95), "maxsol": 3}
    return {"rotors": 1 if idx < 7 else 2, "statics": 0, "twin": True,
            "walls": (2, 3), "decoys": (0, 1),
            "win": (0.026, 0.075), "span": (90, 100), "maxsol": 3}


def construct(rng, world, idx):
    pl = plan(world, idx)
    span = rng.uniform(*pl["span"])
    emitter = edge_emitter(rng)
    psi = ang(emitter, CENTER) + rng.uniform(-1.5, 1.5)

    kinds = ["rotor"] * pl["rotors"] + ["static"] * pl["statics"]
    rng.shuffle(kinds)
    if pl["twin"]:
        kinds.insert(rng.randrange(len(kinds) + 1), "twin")

    waypoints = []  # (kind, point)
    prev = CENTER
    prev_dir = None  # direction du rayon arrivant sur le miroir précédent (None = miroir commandé)
    prev_kind = "control"
    path = [emitter, CENTER]
    for kind in kinds + ["target"]:
        placed = None
        for _ in range(60):
            if prev_kind in ("control", "twin", "static"):
                out = rng.uniform(0, 360)
            else:  # pivot : 4 directions possibles
                out = 2 * (rng.randrange(4) * 45.0) - prev_dir
            d = rng.uniform(0.22, 0.36) if len(kinds) >= 3 else rng.uniform(0.24, 0.46)
            ux, uy = unit(out)
            p = (prev[0] + ux * d, prev[1] + uy * d)
            lo, hi = (0.14, 0.86) if kind != "target" else (0.12, 0.88)
            if not inside(p, lo, hi):
                continue
            if any(dist(p, q) < 0.2 for q in path):
                continue
            placed = (out, p)
            break
        if placed is None:
            return None
        out, p = placed
        # orientation du miroir précédent qui envoie le rayon vers p
        if prev_kind != "control":
            waypoints[-1]["out"] = out
        else:
            control_out = out
        if kind == "target":
            target = p
        else:
            waypoints.append({"kind": kind, "p": p, "in": out})
        path.append(p)
        prev, prev_dir, prev_kind = p, out, kind

    # longueur totale après le miroir commandé
    total = sum(dist(path[i], path[i + 1]) for i in range(1, len(path) - 1))
    if total > (1.32 if len(kinds) >= 3 else 1.25):
        return None

    t_star = rng.uniform(0.22, 0.78)
    alpha = norm180((control_out + psi) / 2)
    controls = [(CENTER[0], CENTER[1], CONTROL_LEN, norm180(alpha - t_star * span), 1.0)]
    rotors, mirrors = [], []
    for w in waypoints:
        theta = norm180((w["out"] + w["in"]) / 2)
        if w["kind"] == "rotor":
            step = int(round(theta / 45.0)) % 4
            if abs(norm180(step * 45.0 - theta + 90) - 90) > 1e-6:
                return None
            rotors.append({"p": w["p"], "solution": step})
        elif w["kind"] == "static":
            mirrors.append((w["p"][0], w["p"][1], rng.uniform(0.15, 0.19), theta))
        else:
            factor = rng.choice([-1.0, -0.6, 0.6, 1.4])
            controls.append((w["p"][0], w["p"][1], TWIN_LEN, norm180(theta - t_star * span * factor), factor))

    level = {
        "world": world,
        "emitter": emitter,
        "emitterAngle": psi,
        "target": target,
        "targetRadius": 0.05 if world == 2 else 0.046,
        "mirrors": mirrors,
        "walls": [],
        "controls": controls,
        "rotors": [],
        "span": span,
        "startT": 0.5,
        "_path": path,
        "_tstar": t_star,
    }
    solution = tuple(r["solution"] for r in rotors)
    level["rotors"] = [[r["p"][0], r["p"][1], ROTOR_LEN, 0, r["solution"]] for r in rotors]

    # sweep radii of moving parts, for clearance checks
    movers = [(CENTER, CONTROL_LEN / 2)] + [((c[0], c[1]), c[2] / 2) for c in controls[1:]] + \
             [((r[0], r[1]), ROTOR_LEN / 2) for r in level["rotors"]]
    fixed = [(m[0], m[1], m[2], m[3]) for m in mirrors]

    # path legs must not graze other elements
    elems = [(emitter, 0.05), (target, level["targetRadius"] + 0.02)] + [(c, r + 0.02) for c, r in movers] + \
            [((m[0], m[1]), m[2] / 2 + 0.02) for m in fixed]
    for i in range(len(path) - 1):
        a, b = path[i], path[i + 1]
        for c, r in elems:
            if dist(c, a) < 1e-9 or dist(c, b) < 1e-9:
                continue
            if point_seg_dist(c, a, b) < r:
                return None

    # walls and decoy mirrors that keep clear of the intended path
    def free_spot(length, tries=80):
        for _ in range(tries):
            cx, cy = rng.uniform(0.1, 0.9), rng.uniform(0.1, 0.9)
            a = rng.choice([0, 90, rng.uniform(0, 180)])
            p, q = seg_points(cx, cy, length, a)
            if not (inside(p, 0.04, 0.96) and inside(q, 0.04, 0.96)):
                continue
            if any(seg_seg_dist(p, q, path[i], path[i + 1]) < 0.045 for i in range(len(path) - 1)):
                continue
            if any(point_seg_dist(c, p, q) < r + 0.05 for c, r in elems):
                continue
            if any(seg_seg_dist(p, q, *seg_points(*o)) < 0.05 for o in level["walls"] + level["mirrors"]):
                continue
            return (cx, cy, length, a)
        return None

    for _ in range(rng.randint(*pl["walls"])):
        w = free_spot(rng.uniform(0.14, 0.3))
        if w:
            level["walls"].append(w)
    for _ in range(rng.randint(*pl["decoys"])):
        m = free_spot(rng.uniform(0.15, 0.2))
        if m:
            level["mirrors"].append(m)

    level["_solution"] = solution
    return level


def layout_ok(level):
    pts = [level["emitter"], level["target"]] + [(c[0], c[1]) for c in level["controls"]] + \
          [(r[0], r[1]) for r in level["rotors"]]
    for i in range(len(pts)):
        for j in range(i + 1, len(pts)):
            if dist(pts[i], pts[j]) < 0.19:
                return False
    return True


def evaluate(level, world, idx):
    """Renvoie le niveau finalisé, ou None s'il ne respecte pas les critères."""
    if level is None or not layout_ok(level):
        return None
    pl = plan(world, idx)
    sol = level["_solution"]
    k = len(sol)

    # 1. la configuration prévue a une fenêtre jouable autour de t*
    progress = idx / 14
    wmin, wmax = pl["win"]
    cap = wmax - (wmax - wmin) * progress * 0.7
    rough = windows(level, sol, COARSE)
    if not rough:
        return None
    rw = max(w[1] - w[0] for w in rough)
    if rw < wmin * 0.7 or rw > max(cap, wmin * 1.25) * 1.3:
        return None
    wins = windows(level, sol, FINE)
    if not wins:
        return None
    best = max(wins, key=lambda w: w[1] - w[0])
    width = best[1] - best[0]
    if width < wmin or width > max(cap, wmin * 1.25):
        return None
    if best[0] < 0.06 or best[1] > 0.94:
        return None
    if sum(w[1] - w[0] for w in wins) > width * 1.6:
        return None

    # 2. le rayon touche bien chaque pivot dans la solution
    mid = (best[0] + best[1]) / 2
    pts, ok = trace(level, mid, sol)
    if not ok:
        return None
    for r in level["rotors"]:
        if not any(dist(p, (r[0], r[1])) < r[2] / 2 + 0.005 for p in pts[1:-1]):
            return None
    bounces = len(pts) - 2

    # 3. toutes les configurations de pivots : peu de solutions
    solving = []
    for cfg in product(range(4), repeat=k):
        if cfg == sol:
            solving.append(cfg)
            continue
        if windows(level, cfg, COARSE):
            solving.append(cfg)
            if len(solving) > pl["maxsol"]:
                return None

    # 4. départ : chaque pivot doit être tourné, et aucune position de charnière ne marche
    rng = random.Random(hash((world, idx, round(level["emitterAngle"], 6))))
    starts = [cfg for cfg in product(range(4), repeat=k)
              if all(all(a != b for a, b in zip(cfg, s)) for s in solving)]
    rng.shuffle(starts)
    start = None
    for cfg in starts[:12]:
        if not windows(level, cfg, FINE):
            start = cfg
            break
    if start is None:
        return None

    # 5. position de départ de la charnière loin de la solution
    cands = [x / 20 for x in range(2, 19)]
    cands = [c for c in cands if abs(c - mid) > 0.25]
    if not cands:
        return None
    level["startT"] = min(cands, key=lambda c: abs(c - 0.5))
    for r, s in zip(level["rotors"], start):
        r[3] = s
    level["_window"] = best
    level["_bounces"] = bounces
    level["_solutions"] = len(solving)
    level["solutionT"] = mid
    return level


def make_level(args):
    world, idx, seed = args
    rng = random.Random(seed)
    for attempt in range(400000):
        lv = evaluate(construct(rng, world, idx), world, idx)
        if lv:
            lv["_attempts"] = attempt
            return lv
    raise RuntimeError(f"échec monde {world} niveau {idx + 1}")


# ---------------------------------------------------------------- monde 1 (niveaux d'origine)

def world_one():
    """Les 15 premiers niveaux d'origine (sans pivot), dans l'ordre du jeu."""
    import rayon_gen as G
    levels = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "rayon_levels.json"))
    w1 = []
    for lv in levels:
        if lv["world"] != 1:
            continue
        lv = dict(lv)
        lv["emitter"] = tuple(lv["emitter"])
        lv["target"] = tuple(lv["target"])
        lv["mirrors"] = [tuple(m) for m in lv["mirrors"]]
        lv["walls"] = [tuple(w) for w in lv["walls"]]
        lv["controls"] = [tuple(c) for c in lv["controls"]]
        wins, _ = G.solution_windows(lv)
        best = max(wins, key=lambda w: w[1] - w[0])
        _, _, b = G.trace(lv, (best[0] + best[1]) / 2)
        lv["_w"] = best
        lv["_b"] = b
        lv["rotors"] = []
        lv["solutionT"] = (best[0] + best[1]) / 2
        w1.append(lv)
    w1.sort(key=lambda l: (l["_b"], -(l["_w"][1] - l["_w"][0])))
    return w1


# ---------------------------------------------------------------- sortie Swift

def r4(x):
    return round(x, 4)


def to_swift(levels):
    out = [
        "// Fichier généré par tools/rayon2_gen.py : ne pas modifier à la main.",
        "// Chaque niveau a été vérifié : avec les bons pivots, une position de charnière envoie",
        "// le rayon sur la cible ; au départ, aucune position de charnière ne marche.",
        "",
        "import Foundation",
        "",
        "extension RayonLevel {",
        "    static let all: [RayonLevel] = [",
    ]
    for i, lv in enumerate(levels):
        mirrors = ", ".join(f"Seg({r4(m[0])}, {r4(m[1])}, {r4(m[2])}, {r4(m[3])})" for m in lv["mirrors"])
        walls = ", ".join(f"Seg({r4(w[0])}, {r4(w[1])}, {r4(w[2])}, {r4(w[3])})" for w in lv["walls"])
        ctrls = ", ".join(f"ControlMirror({r4(c[0])}, {r4(c[1])}, {r4(c[2])}, {r4(c[3])}, {r4(c[4])})" for c in lv["controls"])
        rotors = ", ".join(f"Rotor({r4(r[0])}, {r4(r[1])}, {r4(r[2])}, start: {r[3]}, solution: {r[4]})" for r in lv["rotors"])
        out += [
            "        RayonLevel(",
            f"            number: {i + 1}, world: {lv['world']},",
            f"            emitter: Pt({r4(lv['emitter'][0])}, {r4(lv['emitter'][1])}), emitterAngle: {r4(lv['emitterAngle'])},",
            f"            target: Pt({r4(lv['target'][0])}, {r4(lv['target'][1])}), targetRadius: {r4(lv['targetRadius'])},",
            f"            mirrors: [{mirrors}],",
            f"            walls: [{walls}],",
            f"            controls: [{ctrls}],",
            f"            rotors: [{rotors}],",
            f"            span: {r4(lv['span'])}, startT: {r4(lv['startT'])}, solutionT: {r4(lv['solutionT'])}",
            "        )" + ("," if i < len(levels) - 1 else ""),
        ]
    out += ["    ]", "}"]
    return "\n".join(out) + "\n"


def rounded(lv):
    return {
        "world": lv["world"],
        "emitter": (r4(lv["emitter"][0]), r4(lv["emitter"][1])),
        "emitterAngle": r4(lv["emitterAngle"]),
        "target": (r4(lv["target"][0]), r4(lv["target"][1])),
        "targetRadius": r4(lv["targetRadius"]),
        "mirrors": [tuple(r4(x) for x in m) for m in lv["mirrors"]],
        "walls": [tuple(r4(x) for x in w) for w in lv["walls"]],
        "controls": [tuple(r4(x) for x in c) for c in lv["controls"]],
        "rotors": [[r4(r[0]), r4(r[1]), r4(r[2]), r[3], r[4]] for r in lv["rotors"]],
        "span": r4(lv["span"]),
        "startT": r4(lv["startT"]),
        "solutionT": r4(lv["solutionT"]),
    }


def final_check(lv):
    """Revérifie un niveau arrondi, tel que l'app le lira."""
    start = tuple(r[3] for r in lv["rotors"])
    sol = tuple(r[4] for r in lv["rotors"])
    _, ok = trace(lv, lv["solutionT"], sol)
    if not ok:
        return "la solution enregistrée ne touche pas la cible"
    if lv["rotors"] and windows(lv, start, FINE):
        return "le départ est déjà soluble"
    _, ok = trace(lv, lv["startT"], start)
    if ok:
        return "résolu dès le départ"
    return None


if __name__ == "__main__":
    w1 = world_one()
    jobs = [(world, idx, 1000 * world + idx + 20261022) for world in (2, 3, 4) for idx in range(15)]
    with Pool(2) as pool:
        generated = []
        for lv in pool.imap(make_level, jobs):
            print(f"monde {lv['world']} : fenêtre {lv['_window'][1] - lv['_window'][0]:.3f}, "
                  f"{len(lv['rotors'])} pivot(s), {lv['_bounces']} rebonds, {lv['_solutions']} config(s) gagnante(s), "
                  f"{lv['_attempts']} essais", file=sys.stderr, flush=True)
            generated.append(lv)
    ordered = list(w1)
    for world in (2, 3, 4):
        ws = [l for l in generated if l["world"] == world]
        ws.sort(key=lambda l: (len(l["rotors"]), l["_bounces"], -(l["_window"][1] - l["_window"][0])))
        ordered += ws
    final = [rounded(l) for l in ordered]
    for i, lv in enumerate(final):
        err = final_check(lv)
        if err:
            raise SystemExit(f"niveau {i + 1} : {err}")
    json.dump(final, open("rayon2_levels.json", "w"), indent=1)
    open("RayonLevels.swift", "w").write(to_swift(final))
    print("OK", len(final), "niveaux", file=sys.stderr)
