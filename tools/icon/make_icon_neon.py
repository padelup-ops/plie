# Icône néon d'Origamo (variante 2 : le Duo ouvert). Usage : python3 make_icon_neon.py (écrit n1/n2/n3.svg et .png)
import math
from render_svg import render

def defs(extra=""):
    return f"""<defs>
 <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#07021A"/><stop offset="0.62" stop-color="#2A0A4F"/><stop offset="0.68" stop-color="#4A0E5E"/><stop offset="1" stop-color="#0A0218"/>
 </linearGradient>
 <radialGradient id="hz" cx="50%" cy="66%" r="45%">
  <stop offset="0" stop-color="#FF2BD6" stop-opacity="0.55"/><stop offset="0.5" stop-color="#7A2BFF" stop-opacity="0.18"/><stop offset="1" stop-color="#7A2BFF" stop-opacity="0"/>
 </radialGradient>
 <linearGradient id="cm" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#21F3FF"/><stop offset="1" stop-color="#FF2BD6"/></linearGradient>
 <linearGradient id="cm2" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#21F3FF"/><stop offset="1" stop-color="#B44BFF"/></linearGradient>
 <filter id="glowL" filterUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><feGaussianBlur stdDeviation="22"/></filter>
 <filter id="glowM" filterUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><feGaussianBlur stdDeviation="7"/></filter>
 <filter id="glowS" filterUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><feGaussianBlur stdDeviation="2"/></filter>
 {extra}
</defs>"""

def neon(shape_svg, color, width, core="#FFFFFF", core_w=None):
    """Un tube néon : grand halo flou, halo moyen, trait coloré, cœur blanc."""
    core_w = core_w or max(2, width * 0.35)
    s = shape_svg
    return f"""
 <g fill="none" stroke-linecap="round" stroke-linejoin="round">
  <g stroke="{color}" stroke-width="{width*2.6}" opacity="0.75" filter="url(#glowL)">{s}</g>
  <g stroke="{color}" stroke-width="{width*1.4}" opacity="0.9" filter="url(#glowM)">{s}</g>
  <g stroke="{color}" stroke-width="{width}">{s}</g>
  <g stroke="{core}" stroke-width="{core_w}" opacity="0.85" filter="url(#glowS)">{s}</g>
 </g>"""

def backdrop(grid=True, horizon=690):
    out = ['<rect width="1024" height="1024" fill="url(#sky)"/>', '<rect width="1024" height="1024" fill="url(#hz)"/>']
    # étoiles
    import random
    random.seed(7)
    for _ in range(40):
        x, y = random.uniform(30, 994), random.uniform(30, horizon - 60)
        r = random.choice([1.5, 2, 2.5, 3])
        out.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r}" fill="#FFFFFF" opacity="{random.uniform(0.3, 0.9):.2f}"/>')
    if grid:
        g = []
        vx, vy = 512, horizon
        for k in range(-12, 13):
            g.append(f'<line x1="{vx}" y1="{vy}" x2="{vx + k * 150}" y2="1100"/>')
        y, step = horizon + 8, 10
        while y < 1040:
            g.append(f'<line x1="0" y1="{y:.0f}" x2="1024" y2="{y:.0f}"/>')
            step *= 1.35; y += step
        lines = "".join(g)
        out.append(f'<g stroke="#FF2BD6" stroke-width="3" opacity="0.55" filter="url(#glowS)">{lines}</g>')
        out.append(f'<g stroke="#FF8AF0" stroke-width="1.5" opacity="0.6">{lines}</g>')
        out.append(f'<rect x="0" y="{horizon-3}" width="1024" height="6" fill="#FF6AE8" opacity="0.9" filter="url(#glowM)"/>')
    return "\n".join(out)

def svg(body, extra=""):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{defs(extra)}{body}</svg>'

# --- 1. Le « O » plié en néon ---
def v1():
    cx, cy, R2, R1, n = 512, 440, 300, 165, 10
    out, inn = [], []
    for i in range(n):
        a = -math.pi / 2 + 2 * math.pi * i / n
        out.append((cx + R2 * math.cos(a), cy + R2 * math.sin(a)))
        b = a + math.pi / n
        inn.append((cx + R1 * math.cos(b), cy + R1 * math.sin(b)))
    poly = lambda pts: "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
    creases = "".join(f'<path d="M{out[i][0]:.1f} {out[i][1]:.1f} L{inn[i][0]:.1f} {inn[i][1]:.1f} L{out[(i+1)%n][0]:.1f} {out[(i+1)%n][1]:.1f}"/>' for i in range(n))
    # facettes légèrement teintées
    facets = "".join(f'<path d="M{out[i][0]:.1f} {out[i][1]:.1f} L{inn[i][0]:.1f} {inn[i][1]:.1f} L{out[(i+1)%n][0]:.1f} {out[(i+1)%n][1]:.1f} Z" fill="{"#21F3FF" if i%2==0 else "#FF2BD6"}" opacity="{0.10 if i%2==0 else 0.16}"/>' for i in range(n))
    body = backdrop(horizon=760) + facets
    body += neon(f'<path d="{poly(out)}"/>', "url(#cm)", 16)
    body += neon(f'<path d="{poly(inn)}"/>', "url(#cm2)", 12)
    body += neon(creases, "#B44BFF", 6, core_w=2.5)
    return svg(body)

# --- 2. Le Duo ouvert, en néon ---
def v2():
    hx, hy = 512, 745
    def screen(angle, color, x):
        return f'<g transform="rotate({angle} {hx} {hy})">' + neon(f'<rect x="{x}" y="{hy-455}" width="215" height="455" rx="48"/>', color, 13) + '</g>'
    left_g = neon(f'<path d="M{hx-178} 520 h64 M{hx-146} 488 v64"/>', "#21F3FF", 12)
    right_g = neon(f'<circle cx="{hx+128}" cy="476" r="19"/><circle cx="{hx+168}" cy="516" r="19"/><circle cx="{hx+128}" cy="556" r="19"/><circle cx="{hx+88}" cy="516" r="19"/>', "#FF2BD6", 9)
    body = backdrop(horizon=700)
    body += screen(-17, "#21F3FF", hx - 219) + screen(17, "#FF2BD6", hx + 4)
    body += f'<g transform="rotate(-17 {hx} {hy})">{left_g}</g><g transform="rotate(17 {hx} {hy})">{right_g}</g>'
    body += neon(f'<path d="M{hx-30} {hy+6} Q {hx} {hy+34} {hx+30} {hy+6}"/>', "#FFFFFF", 8)
    return svg(body)

# --- 3. La manette pliée, en néon ---
def v3():
    pad = ("M 300 380 C 250 380 205 420 190 490 L 150 660 C 135 735 205 770 250 720 L 330 630 "
           "L 694 630 L 774 720 C 819 770 889 735 874 660 L 834 490 C 819 420 774 380 724 380 Z")
    left = f'<clipPath id="cl"><rect x="0" y="0" width="512" height="1024"/></clipPath><clipPath id="cr"><rect x="512" y="0" width="512" height="1024"/></clipPath>'
    body = backdrop(horizon=740)
    lefthalf = neon(f'<path d="{pad}"/>', "#21F3FF", 14)
    righthalf = neon(f'<path d="{pad}"/>', "#FF2BD6", 14)
    dpad = neon('<path d="M 290 505 h 90 M 335 460 v 90"/>', "#21F3FF", 14)
    btns = (neon('<circle cx="690" cy="460" r="17"/>', "#FFE45C", 9) + neon('<circle cx="740" cy="508" r="17"/>', "#FF2BD6", 9)
            + neon('<circle cx="690" cy="556" r="17"/>', "#3DFF8B", 9) + neon('<circle cx="640" cy="508" r="17"/>', "#21F3FF", 9))
    body += f'<g clip-path="url(#cl)">{lefthalf}{dpad}</g>'
    # la moitié droite, pliée vers l'arrière
    body += f'<g transform="translate(512 0) skewY(-7) scale(0.86 1) translate(-512 30)"><g clip-path="url(#cr)">{righthalf}{btns}</g></g>'
    body += neon('<path d="M 512 330 L 512 700" stroke-dasharray="18 16"/>', "#FFFFFF", 6)
    return svg(body, left)

for name, f in [("n1", v1), ("n2", v2), ("n3", v3)]:
    open(name + ".svg", "w").write(f())
    render(name + ".svg", name + ".png")
from PIL import Image, ImageDraw
ims = [Image.open(f"n{i}.png") for i in (1, 2, 3)]
W = Image.new("RGB", (3 * 1024 + 4 * 60, 1024 + 120 + 260), "#f2f2f7")
for i, im in enumerate(ims):
    m = Image.new("L", (1024, 1024), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, 1023, 1023), radius=230, fill=255)
    W.paste(im, (60 + i * 1084, 60), m)
    W.paste(im.resize((180, 180), Image.LANCZOS), (60 + i * 1084 + 422, 1124), m.resize((180, 180)))
W.resize((W.width // 3, W.height // 3), Image.LANCZOS).save("board.png")
