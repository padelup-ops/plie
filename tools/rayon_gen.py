"""Génère et vérifie les niveaux de RAYON.

Le traceur ci-dessous est la référence : RayonEngine.swift en est la traduction exacte.
Plateau unité [0,1]x[0,1], y vers le bas, angles en degrés.
"""
import math, random, json, sys

EPS = 1e-7
MAX_SEGMENTS = 30
SAMPLES = 1400


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


def build_segments(level, t):
    """Liste (p, q, kind) ; kind = 'mirror' ou 'wall'."""
    segs = []
    for m in level["mirrors"]:
        p, q = seg_points(*m)
        segs.append((p, q, "mirror"))
    for c in level["controls"]:
        cx, cy, length, base, factor = c
        ang = base + t * level["span"] * factor
        p, q = seg_points(cx, cy, length, ang)
        segs.append((p, q, "mirror"))
    for w in level["walls"]:
        p, q = seg_points(*w)
        segs.append((p, q, "wall"))
    for p, q in BORDER:
        segs.append((p, q, "wall"))
    return segs


def trace(level, t):
    segs = build_segments(level, t)
    ox, oy = level["emitter"]
    a = math.radians(level["emitterAngle"])
    dx, dy = math.cos(a), math.sin(a)
    tx, ty = level["target"]
    tr = level["targetRadius"]
    pts = [(ox, oy)]
    last = -1
    bounces = 0
    for _ in range(MAX_SEGMENTS):
        best_t, best_i = None, -1
        for i, (p, q, kind) in enumerate(segs):
            if i == last:
                continue
            h = ray_seg(ox, oy, dx, dy, p, q)
            if h is not None and (best_t is None or h < best_t):
                best_t, best_i = h, i
        ht = ray_circle(ox, oy, dx, dy, tx, ty, tr)
        if ht is not None and (best_t is None or ht < best_t):
            pts.append((ox + dx * ht, oy + dy * ht))
            return pts, True, bounces
        if best_t is None:
            return pts, False, bounces
        hx, hy = ox + dx * best_t, oy + dy * best_t
        pts.append((hx, hy))
        p, q, kind = segs[best_i]
        if kind != "mirror":
            return pts, False, bounces
        ex, ey = q[0] - p[0], q[1] - p[1]
        ln = math.hypot(ex, ey)
        nx, ny = -ey / ln, ex / ln
        dot = dx * nx + dy * ny
        dx, dy = dx - 2 * dot * nx, dy - 2 * dot * ny
        ox, oy = hx, hy
        last = best_i
        bounces += 1
    return pts, False, bounces


def solution_windows(level, samples=SAMPLES):
    hits = []
    for i in range(samples + 1):
        t = i / samples
        _, ok, b = trace(level, t)
        hits.append((ok, b))
    windows = []
    start = None
    for i, (ok, b) in enumerate(hits):
        if ok and start is None:
            start = i
        if (not ok or i == samples) and start is not None:
            end = i if not ok else i + 1
            windows.append((start / samples, (end - 1) / samples))
            start = None
    return windows, hits


# ---------- Génération ----------

def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def segs_intersect(p1, q1, p2, q2):
    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    d1 = orient(p2, q2, p1); d2 = orient(p2, q2, q1)
    d3 = orient(p1, q1, p2); d4 = orient(p1, q1, q2)
    return (d1 * d2 < 0) and (d3 * d4 < 0)


def point_seg_dist(pt, p, q):
    px, py = pt; ax, ay = p; bx, by = q
    ex, ey = bx - ax, by - ay
    L2 = ex * ex + ey * ey
    if L2 == 0:
        return dist(pt, p)
    u = max(0, min(1, ((px - ax) * ex + (py - ay) * ey) / L2))
    return dist(pt, (ax + u * ex, ay + u * ey))


def seg_seg_dist(p1, q1, p2, q2):
    if segs_intersect(p1, q1, p2, q2):
        return 0.0
    return min(point_seg_dist(p1, p2, q2), point_seg_dist(q1, p2, q2),
               point_seg_dist(p2, p1, q1), point_seg_dist(q2, p1, q1))


def edge_emitter(rng):
    side = rng.randrange(4)
    u = rng.uniform(0.15, 0.85)
    m = 0.06
    if side == 0:
        return (u, m)
    if side == 1:
        return (1 - m, u)
    if side == 2:
        return (u, 1 - m)
    return (m, u)


def layout_ok(level):
    """Vérifie que les éléments ne se chevauchent pas et restent lisibles."""
    pts = [level["emitter"], level["target"]]
    for c in level["controls"]:
        pts.append((c[0], c[1]))
    for i in range(len(pts)):
        for j in range(i + 1, len(pts)):
            if dist(pts[i], pts[j]) < 0.17:
                return False
    statics = [seg_points(*m) for m in level["mirrors"]] + [seg_points(*w) for w in level["walls"]]
    for (p, q) in statics:
        for v in (p, q):
            if not (0.04 <= v[0] <= 0.96 and 0.04 <= v[1] <= 0.96):
                return False
        if point_seg_dist(level["emitter"], p, q) < 0.08:
            return False
        if point_seg_dist(level["target"], p, q) < level["targetRadius"] + 0.04:
            return False
        for c in level["controls"]:
            if point_seg_dist((c[0], c[1]), p, q) < c[2] / 2 + 0.05:
                return False
    for i in range(len(statics)):
        for j in range(i + 1, len(statics)):
            if seg_seg_dist(*statics[i], *statics[j]) < 0.05:
                return False
    if not (0.1 <= level["target"][0] <= 0.9 and 0.1 <= level["target"][1] <= 0.9):
        return False
    return True


def aim(src, dst, jitter, rng):
    return math.degrees(math.atan2(dst[1] - src[1], dst[0] - src[0])) + rng.uniform(-jitter, jitter)


def rand_point(rng, lo=0.14, hi=0.86):
    return (rng.uniform(lo, hi), rng.uniform(lo, hi))


def make_candidate(rng, world, idx_in_world):
    ctrl_len = 0.24 if world < 3 else 0.22
    center = (0.5, 0.5)
    level = {"mirrors": [], "walls": [], "controls": [], "span": 0, "startT": 0.5}
    level["emitter"] = edge_emitter(rng)
    level["targetRadius"] = 0.05 if world == 1 else (0.045 if world == 2 else 0.042)
    level["span"] = rng.choice([110, 120, 130, 140]) if world == 1 else rng.choice([120, 140, 150, 160])

    if world == 3:
        # deux miroirs commandés : le central et un « jumeau » qui tourne autrement
        cx = rng.choice([0.25, 0.75]) if rng.random() < 0.5 else 0.5
        cy = rng.choice([0.25, 0.75]) if cx == 0.5 else rng.uniform(0.25, 0.75)
        twin = (cx, cy)
        if dist(twin, center) < 0.2:
            return None
        factor = rng.choice([-1.0, -0.5, 0.5, 1.5])
        level["controls"] = [
            (center[0], center[1], ctrl_len, rng.uniform(0, 180), 1.0),
            (twin[0], twin[1], 0.2, rng.uniform(0, 180), factor),
        ]
    else:
        level["controls"] = [(center[0], center[1], ctrl_len, rng.uniform(0, 180), 1.0)]

    level["emitterAngle"] = aim(level["emitter"], center, 3.0 if world == 1 else 5.0, rng)
    level["target"] = rand_point(rng)

    n_static = 0
    if world == 1:
        n_static = 0 if idx_in_world < 6 else (1 if idx_in_world < 12 else rng.choice([1, 2]))
        n_walls = 1 if idx_in_world < 4 else rng.choice([1, 2, 2, 3])
    elif world == 2:
        n_static = rng.choice([1, 2, 2, 3])
        n_walls = rng.choice([2, 3, 3, 4])
    else:
        n_static = rng.choice([0, 1, 1, 2])
        n_walls = rng.choice([2, 3, 4])

    for _ in range(n_static):
        level["mirrors"].append((rng.uniform(0.12, 0.88), rng.uniform(0.12, 0.88), rng.uniform(0.16, 0.24), rng.uniform(0, 180)))
    for _ in range(n_walls):
        level["walls"].append((rng.uniform(0.1, 0.9), rng.uniform(0.1, 0.9), rng.uniform(0.14, 0.3), rng.choice([0, 90, rng.uniform(0, 180)])))
    return level


CRITERIA = {
    # monde: (fenêtre min, fenêtre max, rebonds min, rebonds max)
    1: (0.045, 0.16, 1, 3),
    2: (0.03, 0.09, 2, 5),
    3: (0.025, 0.07, 2, 6),
}


def accept(level, world, idx):
    if not layout_ok(level):
        return None
    coarse, _ = solution_windows(level, 300)
    if not coarse:
        return None
    windows, hits = solution_windows(level)
    if not windows:
        return None
    wmin, wmax, bmin, bmax = CRITERIA[world]
    # difficulté croissante dans le monde : fenêtre qui rétrécit
    progress = idx / 14
    target_w = wmax - (wmax - wmin) * progress
    best = max(windows, key=lambda w: w[1] - w[0])
    width = best[1] - best[0]
    if width < wmin or width > max(target_w * 1.35, wmin * 1.2):
        return None
    if best[0] < 0.08 or best[1] > 0.92:
        return None
    total = sum(w[1] - w[0] for w in windows)
    if total > 0.3:
        return None
    mid = (best[0] + best[1]) / 2
    _, ok, b = trace(level, mid)
    if not ok or b < bmin or b > bmax:
        return None
    # le rayon doit vraiment passer par le miroir central (sinon la charnière ne sert à rien)
    pts, _, _ = trace(level, mid)
    touches_center = any(dist(p, (0.5, 0.5)) < level["controls"][0][2] / 2 + 0.01 for p in pts[1:-1])
    if not touches_center:
        return None
    # point de départ loin de la solution
    candidates = [x / 20 for x in range(2, 19)]
    rng_start = [c for c in candidates if all(abs(c - (w[0] + w[1]) / 2) > 0.25 and not (w[0] - 0.05 <= c <= w[1] + 0.05) for w in windows)]
    if not rng_start:
        return None
    start = min(rng_start, key=lambda c: abs(c - 0.5))
    level["startT"] = start
    level["_window"] = best
    level["_bounces"] = b
    return level


def generate():
    rng = random.Random(20261022)
    levels = []
    for world in (1, 2, 3):
        for idx in range(15):
            for attempt in range(200000):
                cand = make_candidate(rng, world, idx)
                if cand is None:
                    continue
                ok = accept(cand, world, idx)
                if ok:
                    ok["world"] = world
                    levels.append(ok)
                    print(f"monde {world} niveau {idx+1}: fenêtre {ok['_window'][1]-ok['_window'][0]:.3f} rebonds {ok['_bounces']} essais {attempt}", file=sys.stderr)
                    break
            else:
                raise SystemExit(f"échec monde {world} niveau {idx+1}")
    return levels


def r(x):
    return round(x, 4)


def to_swift(levels):
    out = []
    out.append("// Fichier généré par tools/rayon_gen.py : ne pas modifier à la main.")
    out.append("// Chaque niveau a été vérifié : il existe une position de charnière qui envoie le rayon sur la cible.")
    out.append("")
    out.append("import Foundation")
    out.append("")
    out.append("extension RayonLevel {")
    out.append("    static let all: [RayonLevel] = [")
    for i, lv in enumerate(levels):
        mirrors = ", ".join(f"Seg({r(m[0])}, {r(m[1])}, {r(m[2])}, {r(m[3])})" for m in lv["mirrors"])
        walls = ", ".join(f"Seg({r(w[0])}, {r(w[1])}, {r(w[2])}, {r(w[3])})" for w in lv["walls"])
        ctrls = ", ".join(f"ControlMirror({r(c[0])}, {r(c[1])}, {r(c[2])}, {r(c[3])}, {r(c[4])})" for c in lv["controls"])
        out.append("        RayonLevel(")
        out.append(f"            number: {i+1}, world: {lv['world']},")
        out.append(f"            emitter: Pt({r(lv['emitter'][0])}, {r(lv['emitter'][1])}), emitterAngle: {r(lv['emitterAngle'])},")
        out.append(f"            target: Pt({r(lv['target'][0])}, {r(lv['target'][1])}), targetRadius: {r(lv['targetRadius'])},")
        out.append(f"            mirrors: [{mirrors}],")
        out.append(f"            walls: [{walls}],")
        out.append(f"            controls: [{ctrls}],")
        out.append(f"            span: {r(lv['span'])}, startT: {r(lv['startT'])}")
        out.append("        )" + ("," if i < len(levels) - 1 else ""))
    out.append("    ]")
    out.append("}")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    levels = generate()
    # Re-vérification après arrondi (ce que l'app utilisera vraiment)
    rounded = []
    for lv in levels:
        rl = {
            "emitter": (r(lv["emitter"][0]), r(lv["emitter"][1])),
            "emitterAngle": r(lv["emitterAngle"]),
            "target": (r(lv["target"][0]), r(lv["target"][1])),
            "targetRadius": r(lv["targetRadius"]),
            "mirrors": [tuple(r(x) for x in m) for m in lv["mirrors"]],
            "walls": [tuple(r(x) for x in w) for w in lv["walls"]],
            "controls": [tuple(r(x) for x in c) for c in lv["controls"]],
            "span": r(lv["span"]),
            "startT": r(lv["startT"]),
            "world": lv["world"],
        }
        windows, _ = solution_windows(rl)
        assert windows, "niveau devenu impossible après arrondi"
        _, start_hit, _ = trace(rl, rl["startT"])
        assert not start_hit, "niveau résolu dès le départ"
        rounded.append(rl)
    json.dump(rounded, open("rayon_levels.json", "w"), indent=1)
    open("RayonLevels.swift", "w").write(to_swift(rounded))
    print("OK", len(rounded), "niveaux", file=sys.stderr)
