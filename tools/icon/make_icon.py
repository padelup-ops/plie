"""Icône de Plié : une cocotte en papier (le jeu plié par excellence), chaque pétale porte un mini-jeu."""
import math, random, sys
from playwright.sync_api import sync_playwright

S = 1024
C = (512, 516)
R = 418          # pointe des pétales
r = 0.46 * R     # creux entre deux pétales

def mix(c, other, t):
    a = [int(c[i:i+2], 16) for i in (1, 3, 5)]
    b = [int(other[i:i+2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(a[i] + (b[i]-a[i]) * t):02x}" for i in range(3))

def pt(angle_deg, radius):
    a = math.radians(angle_deg)
    return (C[0] + radius * math.cos(a), C[1] + radius * math.sin(a))

light = (-0.62, -0.78)
petals = [  # angle de la pointe, couleur, glyphe
    (-90 - 9, "#3DE0FF", "target"),
    (0 - 9, "#FF4F9A", "paddle"),
    (90 - 9, "#FFC53D", "ball"),
    (180 - 9, "#8BDB4F", "star"),
]

faces = []
for ang, col, _ in petals:
    tip = pt(ang, R)
    for side in (-45, 45):
        sp = pt(ang + side, r)
        # normale du pan : vers son côté
        mid = ((tip[0] + C[0]) / 2, (tip[1] + C[1]) / 2)
        nx, ny = sp[0] - mid[0], sp[1] - mid[1]
        n = math.hypot(nx, ny)
        b = (nx * light[0] + ny * light[1]) / n   # -1..1
        fill = mix(col, "#ffffff", 0.28 * b) if b > 0 else mix(col, "#1a1030", -0.38 * b)
        faces.append((C, tip, sp, fill, b, len(faces)))

def poly(points):
    return " ".join(f"{x:.1f},{y:.1f}" for x, y in points)

glyphs = {
    "target": """<circle r="44" fill="none" stroke="#fff" stroke-width="13"/><circle r="17" fill="#fff"/>""",
    "ball": """<circle r="44" fill="none" stroke="#fff" stroke-width="11"/>
               <path d="M-44 0H44M0 -44V44" stroke="#fff" stroke-width="8"/>
               <path d="M-28 -34 Q-6 0 -28 34M28 -34 Q6 0 28 34" fill="none" stroke="#fff" stroke-width="8"/>""",
    "paddle": """<g transform="rotate(-35)"><rect x="-9" y="20" width="18" height="44" rx="8" fill="#fff"/>
               <ellipse cx="0" cy="-8" rx="36" ry="38" fill="#fff"/></g>
               <circle cx="40" cy="-40" r="12" fill="#fff"/>""",
    "star": None,
}
def star_path(radius=50, inner=0.46):
    pts = []
    for i in range(10):
        rr = radius if i % 2 == 0 else radius * inner
        a = math.radians(-90 + i * 36)
        pts.append((rr * math.cos(a), rr * math.sin(a)))
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
glyphs["star"] = f'<path d="{star_path()}" fill="#fff" stroke="#fff" stroke-width="6" stroke-linejoin="round"/>'

rays = ""
for k in range(16):
    a0 = math.radians(k * 22.5 - 9 - 4.5)
    a1 = math.radians(k * 22.5 - 9 + 4.5)
    far = 900
    p0 = (C[0] + far * math.cos(a0), C[1] + far * math.sin(a0))
    p1 = (C[0] + far * math.cos(a1), C[1] + far * math.sin(a1))
    rays += f'<polygon points="{C[0]},{C[1]} {p0[0]:.0f},{p0[1]:.0f} {p1[0]:.0f},{p1[1]:.0f}" fill="#ffffff" opacity="0.045"/>'
random.seed(7)
confetti = []
palette = ["#3DE0FF", "#FF4F9A", "#FFC53D", "#8BDB4F", "#FF8A3D", "#B48CFF"]
spots = [(150, 180), (880, 170), (120, 860), (905, 880), (215, 520), (820, 515), (512, 95), (520, 965),
         (300, 110), (735, 935), (95, 395), (935, 650)]
for i, (x, y) in enumerate(spots):
    col = palette[i % len(palette)]
    rot = random.uniform(0, 180)
    if i % 3 == 0:
        confetti.append(f'<circle cx="{x}" cy="{y}" r="11" fill="{col}" opacity="0.9"/>')
    else:
        confetti.append(f'<rect x="{x-15}" y="{y-6}" width="30" height="12" rx="4" fill="{col}" opacity="0.9" transform="rotate({rot:.0f} {x} {y})"/>')

grads = []
face_parts = []
for a, b_, c_, f, br, i in faces:
    grads.append(f'<linearGradient id="fg{i}" gradientUnits="userSpaceOnUse" x1="{b_[0]:.1f}" y1="{b_[1]:.1f}" x2="{C[0]}" y2="{C[1]}">'
                 f'<stop offset="0" stop-color="{mix(f, "#ffffff", 0.18)}"/><stop offset="0.65" stop-color="{f}"/><stop offset="1" stop-color="{mix(f, "#140a2e", 0.35)}"/></linearGradient>')
    face_parts.append(f'<polygon points="{poly([a,b_,c_])}" fill="url(#fg{i})"/>')
face_svg = "\n".join(face_parts)
# Plis : liserés clairs sur les arêtes des pétales, creux sombres
ridges = "\n".join(f'<line x1="{C[0]}" y1="{C[1]}" x2="{pt(a, R)[0]:.1f}" y2="{pt(a, R)[1]:.1f}" stroke="#ffffff" stroke-opacity="0.55" stroke-width="3"/>' for a, _, _ in petals)
valleys = "\n".join(f'<line x1="{C[0]}" y1="{C[1]}" x2="{pt(a+45, r)[0]:.1f}" y2="{pt(a+45, r)[1]:.1f}" stroke="#14092a" stroke-opacity="0.35" stroke-width="4"/>' for a, _, _ in petals)
outline = []
for ang, _, _ in petals:
    outline += [pt(ang - 45, r), pt(ang, R)]
outline_pts = poly(outline)

glyph_svg = ""
for ang, col, g in petals:
    gx, gy = pt(ang, R * 0.54)
    glyph_svg += f'<g transform="translate({gx:.1f} {gy:.1f}) scale(1.12)" filter="url(#gshadow)">{glyphs[g]}</g>\n'

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
<defs>{''.join(grads)}
  <radialGradient id="bg" cx="50%" cy="45%" r="75%">
    <stop offset="0" stop-color="#3B2E8C"/><stop offset="0.55" stop-color="#1C1A4D"/><stop offset="1" stop-color="#0B0B22"/>
  </radialGradient>
  <radialGradient id="halo" cx="50%" cy="50%" r="50%">
    <stop offset="0" stop-color="#FF8AD8" stop-opacity="0.55"/><stop offset="0.5" stop-color="#7B5CFF" stop-opacity="0.25"/><stop offset="1" stop-color="#7B5CFF" stop-opacity="0"/>
  </radialGradient>
  <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="22"/></filter>
  <filter id="gshadow" x="-50%" y="-50%" width="200%" height="200%">
    <feDropShadow dx="0" dy="4" stdDeviation="5" flood-color="#14092a" flood-opacity="0.45"/>
  </filter>
  <linearGradient id="sheen" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="0.22"/><stop offset="0.5" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.12"/>
  </linearGradient>
  <clipPath id="shape"><polygon points="{outline_pts}"/></clipPath>
</defs>
<rect width="{S}" height="{S}" fill="url(#bg)"/>
{rays}
<circle cx="{C[0]}" cy="{C[1]}" r="470" fill="url(#halo)"/>
{''.join(confetti)}
<polygon points="{outline_pts}" fill="#05030f" opacity="0.55" transform="translate(0 34)" filter="url(#shadow)"/>
{face_svg}
<g clip-path="url(#shape)"><rect width="{S}" height="{S}" fill="url(#sheen)"/></g>
{valleys}
{ridges}
<circle cx="{C[0]}" cy="{C[1]}" r="22" fill="#14092a" opacity="0.5" filter="url(#gshadow)"/>
{glyph_svg}
</svg>'''

open("icon.svg", "w").write(svg)
html = f'<html><body style="margin:0;background:#000">{svg}</body></html>'
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={"width": S, "height": S})
    pg.set_content(html)
    pg.screenshot(path="icon.png", clip={"x": 0, "y": 0, "width": S, "height": S})
    b.close()
print("ok")
