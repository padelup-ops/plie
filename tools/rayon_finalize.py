import json, math
from PIL import Image, ImageDraw
import rayon_gen as G

levels = json.load(open("rayon_levels.json"))
for lv in levels:
    lv["emitter"] = tuple(lv["emitter"]); lv["target"] = tuple(lv["target"])
    lv["mirrors"] = [tuple(m) for m in lv["mirrors"]]
    lv["walls"] = [tuple(w) for w in lv["walls"]]
    lv["controls"] = [tuple(c) for c in lv["controls"]]
    wins, _ = G.solution_windows(lv)
    best = max(wins, key=lambda w: w[1]-w[0])
    lv["_w"] = best
    _, _, b = G.trace(lv, (best[0]+best[1])/2)
    lv["_b"] = b
# tri : dans chaque monde, du plus facile au plus dur
ordered = []
for world in (1, 2, 3):
    ws = [l for l in levels if l["world"] == world]
    ws.sort(key=lambda l: (l["_b"], -(l["_w"][1]-l["_w"][0])))
    ordered += ws
open("RayonLevels.swift", "w").write(G.to_swift(ordered))

# planche de contrôle : chaque niveau avec le rayon gagnant
S = 220
sheet = Image.new("RGB", (S*9, S*5), (14, 16, 32))
for i, lv in enumerate(ordered):
    img = Image.new("RGB", (S, S), (20, 22, 40)); d = ImageDraw.Draw(img)
    f = lambda p: (p[0]*(S-20)+10, p[1]*(S-20)+10)
    for w in lv["walls"]:
        p, q = G.seg_points(*w); d.line([f(p), f(q)], fill=(110, 110, 130), width=6)
    for m in lv["mirrors"]:
        p, q = G.seg_points(*m); d.line([f(p), f(q)], fill=(220, 220, 235), width=3)
    t = (lv["_w"][0]+lv["_w"][1])/2
    for c in lv["controls"]:
        ang = c[3] + t*lv["span"]*c[4]
        p, q = G.seg_points(c[0], c[1], c[2], ang); d.line([f(p), f(q)], fill=(61, 224, 255), width=4)
    pts, ok, _ = G.trace(lv, t)
    d.line([f(p) for p in pts], fill=(255, 60, 90) if ok else (120, 0, 0), width=2)
    tx, ty = f(lv["target"]); r = lv["targetRadius"]*(S-20)
    d.ellipse([tx-r, ty-r, tx+r, ty+r], outline=(255, 197, 61), width=3)
    ex, ey = f(lv["emitter"]); d.ellipse([ex-6, ey-6, ex+6, ey+6], fill=(255, 92, 77))
    pts0, ok0, _ = G.trace(lv, lv["startT"])
    d.text((6, 4), f"{i+1} w{lv['world']} {lv['_w'][1]-lv['_w'][0]:.3f} {'BAD' if ok0 else ''}", fill=(255, 255, 255))
    sheet.paste(img, ((i % 9)*S, (i//9)*S))
sheet.save("rayon_sheet.png")
print("ok", len(ordered))
