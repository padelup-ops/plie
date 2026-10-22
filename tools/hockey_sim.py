"""Portage de la physique d'AIR HOCKEY pour reproduire le palet bloqué, avant et après la correction."""
import math, random, sys

MR, PR, MAXS = 0.075, 0.042, 3.4

class V:
    def __init__(s, u, v): s.u, s.v = u, v
    def __add__(s, o): return V(s.u + o.u, s.v + o.v)
    def __sub__(s, o): return V(s.u - o.u, s.v - o.v)
    def __mul__(s, k): return V(s.u * k, s.v * k)
    def dot(s, o): return s.u * o.u + s.v * o.v
    def length(s): return math.hypot(s.u, s.v)

class Game:
    def __init__(s, fixed, human):
        s.fixed, s.human = fixed, human
        s.width = 1.4
        s.puck, s.pv = V(0.3, 0.7), V(0, 0)
        s.a, s.b = V(0.14, 0.7), V(0.86, 0.7)
        s.va, s.vb = V(0, 0), V(0, 0)
        s.slow = s.jam = s.cool = 0
        s.faceoffs = 0; s.goals = 0; s.t = 0
        s.stuck_max = 0; s.stuck = 0
    def clampA(s, p): return V(min(0.5 - MR, max(MR, p.u)), min(s.width - MR, max(MR, p.v)))
    def clampB(s, p): return V(min(1 - MR, max(0.5 + MR, p.u)), min(s.width - MR, max(MR, p.v)))
    def ai(s, h):
        attacking = s.puck.u > 0.5 and s.pv.u < 1.2
        if s.fixed and s.cool > 0:
            s.cool -= h; attacking = False
        if attacking:
            if s.fixed and s.puck.u > 1 - MR - PR - 0.01:
                side = 1 if s.puck.v > s.width / 2 else -1
                goal = V(s.puck.u, s.puck.v + side * (MR + PR))
            else:
                goal = V(s.puck.u + 0.06, s.puck.v)
        else:
            gw = min(s.width * 0.46, 0.62)
            goal = V(0.88, min(s.width / 2 + gw / 2, max(s.width / 2 - gw / 2, s.puck.v)))
        goal = s.clampB(goal)
        d = goal - s.b; dist = d.length(); m = 1.25 * h
        nxt = goal if dist <= m else s.b + d * (m / dist)
        s.vb = (nxt - s.b) * (1 / h); s.b = nxt
    def human_move(s, h):
        if s.human == "idle":
            s.va = V(0, 0); return
        # se promène au hasard dans sa moitié, parfois vers le palet
        if random.random() < 0.02:
            s.target = V(random.uniform(0.08, 0.42), random.uniform(0.1, s.width - 0.1))
        if not hasattr(s, "target"): s.target = s.a
        t = s.target if s.puck.u > 0.5 or random.random() < 0.5 else s.puck
        nxt = s.clampA(s.a + (t - s.a) * min(1, 6 * h))
        s.va = (nxt - s.a) * (1 / h); s.a = nxt
    def collide(s, m, vel, isB):
        d = s.puck - m; dist = d.length(); md = MR + PR
        if not (dist < md and dist > 1e-4): return
        n = d * (1 / dist); s.puck = m + n * md
        rel = s.pv - vel; vn = rel.dot(n)
        if vn < 0: s.pv = s.pv - n * ((1 + 0.9) * vn)
        if isB and s.fixed: s.cool = 0.35
    def move_puck(s, h):
        s.puck = s.puck + s.pv * h; s.pv = s.pv * (1 - 0.35 * h); r = PR
        if s.puck.v < r: s.puck.v = r; s.pv.v = abs(s.pv.v) * 0.9
        elif s.puck.v > s.width - r: s.puck.v = s.width - r; s.pv.v = -abs(s.pv.v) * 0.9
        gw = min(s.width * 0.46, 0.62)
        mouth = abs(s.puck.v - s.width / 2) < gw / 2 - r * 0.3
        if s.fixed and mouth and s.puck.u < r: s.pv.u -= 0.9 * h
        if s.fixed and mouth and s.puck.u > 1 - r: s.pv.u += 0.9 * h
        if s.puck.u < r:
            if mouth:
                if s.puck.u < -r: s.goal(1); return
            else: s.puck.u = r; s.pv.u = abs(s.pv.u) * 0.9
        elif s.puck.u > 1 - r:
            if mouth:
                if s.puck.u > 1 + r: s.goal(0); return
            else: s.puck.u = 1 - r; s.pv.u = -abs(s.pv.u) * 0.9
        s.collide(s.a, s.va, False); s.collide(s.b, s.vb, True)
        sp = s.pv.length()
        if sp > MAXS: s.pv = s.pv * (MAXS / sp)
    def goal(s, who):
        s.goals += 1
        s.a, s.b = V(0.14, s.width / 2), V(0.86, s.width / 2)
        s.puck = V(0.3 if who == 1 else 0.7, s.width / 2); s.pv = V(0, 0)
    def unstick(s, dt):
        r = PR
        near = s.puck.u < r + 0.02 or s.puck.u > 1 - r - 0.02 or s.puck.v < r + 0.02 or s.puck.v > s.width - r - 0.02
        c = MR + PR + 0.012
        pinned = near and ((s.puck - s.a).length() < c or (s.puck - s.b).length() < c)
        s.jam = s.jam + dt if pinned else 0
        s.slow = s.slow + dt if s.pv.length() < 0.12 else 0
        limit = 6.0 if s.puck.u < 0.5 else 3.0
        if s.jam > 1.2 or s.slow > limit:
            toward_a = s.puck.u >= 0.5
            s.jam = s.slow = 0; s.faceoffs += 1
            s.puck = V(0.5, s.width / 2); s.pv = V(-0.55 if toward_a else 0.55, random.uniform(-0.25, 0.25))
    def tick(s, dt):
        s.t += dt
        h = dt / 3
        for _ in range(3):
            s.human_move(h); s.ai(h); s.move_puck(h)
        if s.fixed: s.unstick(dt)
        # « bloqué » : le palet ne fait aucun progrès (vitesse faible ou coincé)
        if s.pv.length() < 0.12 or (s.puck.u > 1 - PR - 0.03 and (s.puck - s.b).length() < MR + PR + 0.02):
            s.stuck += dt; s.stuck_max = max(s.stuck_max, s.stuck)
        else:
            s.stuck = 0

random.seed(3)
for fixed in (False, True):
    for human in ("idle", "random"):
        worst = []
        fo = 0; goals = 0
        for g in range(60):
            game = Game(fixed, human)
            game.puck = V(random.uniform(0.55, 0.95), random.uniform(0.1, 1.3))
            game.pv = V(random.uniform(-0.5, 0.8), random.uniform(-0.8, 0.8))
            for _ in range(60 * 90):
                game.tick(1 / 60)
            worst.append(game.stuck_max); fo += game.faceoffs; goals += game.goals
        worst.sort()
        print(f"{'corrigé' if fixed else 'avant  '} joueur {human:6s} : pire blocage {worst[-1]:5.1f} s, médiane {worst[len(worst)//2]:4.1f} s, "
              f"parties bloquées > 10 s : {sum(w > 10 for w in worst)}/60, buts {goals}, remises en jeu {fo}")
