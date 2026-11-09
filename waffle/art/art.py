"""Les illustrations de Toastie Fold, en SVG (style cartoon : contours bruns, ombres douces, reflets).

`python3 toastie/art/build.py` les dessine en PNG (×3) dans Toastie/Assets.xcassets.
Chaque fonction rend un SVG complet. Les aliments sont vus de dessus, dans une boîte de 200×200.
"""

OL = "#3B2418"      # le contour, brun très foncé
SW = 7               # épaisseur du contour

def svg(w, h, body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
            f'<defs>{defs}</defs>{body}</svg>')

def shadow(cx, cy, rx, ry, op=0.18):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#000" opacity="{op}"/>'

def grad(id_, c1, c2, x1=0, y1=0, x2=0, y2=1):
    return (f'<linearGradient id="{id_}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
            f'<stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient>')

def rgrad(id_, c1, c2, cx=0.4, cy=0.35, r=0.75):
    return (f'<radialGradient id="{id_}" cx="{cx}" cy="{cy}" r="{r}">'
            f'<stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></radialGradient>')

# ---------------------------------------------------------------- la gaufre

# (arêtes, alvéoles, bord) : pâte crue, pâle, dorée, bien cuite, brûlée
DONENESS = [
    ("#FCEFC2", "#F2DC9C", "#E8CF8A"),
    ("#F8DE9A", "#EBC473", "#DDB063"),
    ("#F6BE5C", "#DC9030", "#C87A22"),
    ("#CC7A30", "#A3581C", "#8A4614"),
    ("#5A3622", "#3E2416", "#2A180E"),
]
WX, WY, WW, WH = 20, 38, 160, 124   # la gaufre dans sa boîte de 200×200

def waffle(level):
    ridge, pocket, rim = DONENESS[level]
    cols, rows = 6, 4
    pw, ph = (WW - 22) / cols, (WH - 22) / rows
    cells = ""
    for r in range(rows):
        for c in range(cols):
            x = WX + 11 + c * pw + 3
            y = WY + 11 + r * ph + 3
            cells += (f'<rect x="{x:.1f}" y="{y:.1f}" width="{pw - 6:.1f}" height="{ph - 6:.1f}" rx="4" fill="{pocket}"/>'
                      f'<rect x="{x:.1f}" y="{y + ph - 9:.1f}" width="{pw - 6:.1f}" height="3" rx="1.5" fill="#fff" opacity="0.18"/>'
                      f'<rect x="{x:.1f}" y="{y:.1f}" width="{pw - 6:.1f}" height="3.5" rx="1.5" fill="#000" opacity="0.12"/>')
    smoke = ""
    if level == 4:
        smoke = '<path d="M60,40 q12,-18 0,-34 M140,40 q-12,-18 0,-34" stroke="#777" stroke-width="6" fill="none" opacity="0.4" stroke-linecap="round"/>'
    body = (shadow(102, 170, 82, 9) +
            f'<rect x="{WX}" y="{WY}" width="{WW}" height="{WH}" rx="20" fill="{rim}" stroke="{OL}" stroke-width="{SW}"/>'
            f'<rect x="{WX + 8}" y="{WY + 8}" width="{WW - 16}" height="{WH - 16}" rx="13" fill="{ridge}"/>' + cells +
            f'<path d="M{WX + 16},{WY + 12} L{WX + 70},{WY + 12}" stroke="#fff" stroke-width="6" opacity="0.45" stroke-linecap="round"/>' + smoke)
    return svg(200, 200, body)

def batter():
    """La pâte versée sur la plaque, pas encore cuite."""
    return svg(200, 200,
               f'<path d="M34,96 C30,60 70,42 102,50 C138,38 174,62 168,98 C176,132 146,160 108,152 C74,166 30,146 34,112 Z" fill="#FCEBB4" stroke="{OL}" stroke-width="6" stroke-linejoin="round"/>'
               '<path d="M52,88 C60,64 90,58 108,64" stroke="#fff" stroke-width="7" fill="none" opacity="0.7" stroke-linecap="round"/>'
               '<ellipse cx="128" cy="118" rx="12" ry="7" fill="#F4D98E"/><ellipse cx="80" cy="128" rx="8" ry="5" fill="#F4D98E"/>')

def jug():
    """Le pichet de pâte (bouton « Verser »)."""
    defs = grad("j", "#FFFFFF", "#DCE6F0")
    return svg(200, 200, shadow(100, 182, 60, 9) +
               f'<path d="M58,40 L142,40 L150,170 Q150,180 140,180 L60,180 Q50,180 50,170 Z" fill="url(#j)" stroke="{OL}" stroke-width="{SW}" stroke-linejoin="round"/>'
               f'<path d="M58,40 L42,24 L70,30" fill="#fff" stroke="{OL}" stroke-width="6" stroke-linejoin="round"/>'
               f'<path d="M146,70 C182,70 182,140 148,140" fill="none" stroke="{OL}" stroke-width="12" stroke-linecap="round"/>'
               f'<path d="M146,70 C182,70 182,140 148,140" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round"/>'
               '<path d="M56,96 L144,96 L149,170 Q149,176 141,176 L59,176 Q51,176 51,170 Z" fill="#FCE3A0"/>'
               '<path d="M56,96 L144,96" stroke="#F0C870" stroke-width="5"/>'
               '<path d="M68,52 L66,150" stroke="#fff" stroke-width="7" opacity="0.8" stroke-linecap="round"/>')

# ---------------------------------------------------------------- les garnitures (posées sur la gaufre)

def _rng(seed):
    import random
    r = random.Random(seed)
    return r

def sugar():
    r = _rng(1)
    dots = "".join(f'<circle cx="{r.uniform(30, 170):.1f}" cy="{r.uniform(44, 156):.1f}" r="{r.uniform(1.8, 3.6):.1f}" fill="#FFFFFF" opacity="{r.uniform(0.75, 1):.2f}"/>' for _ in range(160))
    return svg(200, 200, dots + '<ellipse cx="104" cy="98" rx="30" ry="18" fill="#fff" opacity="0.85"/><ellipse cx="96" cy="94" rx="14" ry="7" fill="#fff"/>')

def spread():
    """Pâte choco-noisette étalée."""
    return svg(200, 200,
               f'<path d="M44,70 C60,48 100,60 120,52 C150,44 170,70 158,96 C168,124 140,146 110,138 C84,154 46,142 46,118 C30,104 32,84 44,70 Z" fill="#6B3A1E" stroke="{OL}" stroke-width="6" stroke-linejoin="round"/>'
               '<path d="M66,84 C86,70 116,86 136,74 M70,112 C92,100 118,124 140,108" stroke="#8C5230" stroke-width="7" fill="none" stroke-linecap="round"/>'
               '<path d="M58,74 C66,64 78,62 88,64" stroke="#C08A60" stroke-width="5" fill="none" opacity="0.8" stroke-linecap="round"/>'
               '<circle cx="128" cy="120" r="5" fill="#C08A60" opacity="0.7"/><ellipse cx="74" cy="126" rx="6" ry="3" fill="#C08A60" opacity="0.6"/>')

def cream():
    def swirl(cx, cy, s):
        return (f'<g transform="translate({cx} {cy}) scale({s})">'
                f'<path d="M-30,10 C-34,-8 -18,-16 -10,-10 C-12,-26 12,-30 14,-14 C26,-20 38,-6 28,6 C34,18 18,26 6,20 C-4,28 -24,26 -30,10 Z" fill="#FFFDF6" stroke="{OL}" stroke-width="5.5" stroke-linejoin="round"/>'
                '<path d="M-18,4 C-10,-6 6,-4 12,4 M-8,-6 C0,-14 10,-12 14,-6" stroke="#EADFCB" stroke-width="3.5" fill="none" stroke-linecap="round"/>'
                '<path d="M4,-20 Q8,-30 2,-34" stroke="#FFFDF6" stroke-width="7" fill="none" stroke-linecap="round"/>'
                f'<path d="M4,-20 Q8,-30 2,-34" stroke="{OL}" stroke-width="2" fill="none" opacity="0.0"/>'
                '<circle cx="-12" cy="-6" r="4" fill="#fff"/></g>')
    return svg(200, 200, swirl(66, 82, 1.0) + swirl(136, 86, 1.0) + swirl(100, 126, 1.15))

def strawberry():
    def s(cx, cy, a):
        seeds = "".join(f'<ellipse cx="{dx}" cy="{dy}" rx="1.6" ry="2.6" fill="#FFE7A8"/>' for dx, dy in [(-8, -6), (6, -10), (-4, 6), (8, 4), (0, 16), (-12, 10)])
        return (f'<g transform="translate({cx} {cy}) rotate({a})">'
                f'<path d="M0,-26 C22,-26 28,-6 20,10 C14,22 6,30 0,32 C-6,30 -14,22 -20,10 C-28,-6 -22,-26 0,-26 Z" fill="#E8303C" stroke="{OL}" stroke-width="5.5" stroke-linejoin="round"/>'
                '<path d="M0,-18 C14,-18 18,-4 12,8 C8,16 4,22 0,24 C-4,22 -8,16 -12,8 C-18,-4 -14,-18 0,-18 Z" fill="#FF7A84"/>'
                '<path d="M0,-16 L0,20" stroke="#FFC2C6" stroke-width="3"/>' + seeds +
                '<path d="M-12,-18 q4,-6 10,-6" stroke="#fff" stroke-width="3.5" fill="none" opacity="0.7" stroke-linecap="round"/></g>')
    return svg(200, 200, s(62, 82, -20) + s(104, 70, 6) + s(144, 92, 24) + s(82, 128, -8) + s(128, 134, 16))

def banana():
    def b(cx, cy, r):
        seeds = "".join(f'<circle cx="{cx + dx}" cy="{cy + dy}" r="2.2" fill="#8A6A3A"/>' for dx, dy in [(-5, -3), (5, -3), (0, 6)])
        return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#FFF0B0" stroke="{OL}" stroke-width="5.5"/>'
                f'<circle cx="{cx}" cy="{cy}" r="{r - 7}" fill="#FFF7D6"/>' + seeds)
    return svg(200, 200, b(58, 76, 22) + b(104, 70, 22) + b(148, 80, 22) + b(78, 122, 22) + b(124, 124, 22))

def drizzle(color, light, seed):
    path = "M30,64 C60,40 70,96 96,70 C120,46 128,104 152,78 C168,62 176,96 160,112 C140,132 120,92 98,118 C78,140 64,104 44,128"
    return svg(200, 200,
               f'<path d="{path}" stroke="{OL}" stroke-width="20" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
               f'<path d="{path}" stroke="{color}" stroke-width="11" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
               f'<path d="M36,60 C46,52 54,56 60,64" stroke="{light}" stroke-width="4" fill="none" stroke-linecap="round"/>'
               f'<circle cx="160" cy="112" r="9" fill="{color}" stroke="{OL}" stroke-width="5"/>')

def jam():
    return svg(200, 200,
               f'<path d="M54,82 C50,56 86,48 102,58 C124,44 158,60 150,88 C162,112 136,136 108,128 C88,146 52,134 56,110 C40,102 42,88 54,82 Z" fill="#D9263A" stroke="{OL}" stroke-width="6" stroke-linejoin="round"/>'
               '<path d="M70,74 C80,64 96,64 104,70" stroke="#FF8A98" stroke-width="6" fill="none" stroke-linecap="round" opacity="0.9"/>'
               '<circle cx="120" cy="104" r="6" fill="#A8182A"/><circle cx="84" cy="112" r="4" fill="#A8182A"/><circle cx="130" cy="80" r="3.5" fill="#FF8A98"/>')

def icecream():
    return svg(200, 200, shadow(100, 150, 46, 8, 0.15) +
               f'<path d="M58,110 C48,70 76,46 100,48 C126,46 154,70 142,110 C150,118 140,132 128,124 C120,134 108,128 100,134 C92,128 80,134 72,124 C60,132 50,118 58,110 Z" fill="#FFF6DA" stroke="{OL}" stroke-width="6" stroke-linejoin="round"/>'
               '<path d="M74,72 C82,60 96,56 108,58" stroke="#fff" stroke-width="7" fill="none" stroke-linecap="round"/>'
               + "".join(f'<ellipse cx="{x}" cy="{y}" rx="2" ry="1.4" fill="#3B2418" opacity="0.6"/>' for x, y in [(90, 88), (114, 96), (102, 110), (126, 80), (78, 104)]))

def sprinkles():
    import random
    r = random.Random(7)
    cols = ["#FF4F7B", "#3FB5E8", "#FFD23A", "#5BC25A", "#C48AFF", "#FF8A3D", "#FFFFFF"]
    bits = ""
    for _ in range(70):
        x, y, a = r.uniform(34, 166), r.uniform(48, 152), r.uniform(0, 180)
        c = r.choice(cols)
        bits += (f'<g transform="translate({x:.1f} {y:.1f}) rotate({a:.0f})"><rect x="-7" y="-2.6" width="14" height="5.2" rx="2.6" fill="{OL}"/>'
                 f'<rect x="-5.8" y="-1.6" width="11.6" height="3.2" rx="1.6" fill="{c}"/></g>')
    return svg(200, 200, bits)

def almonds():
    import random
    r = random.Random(3)
    flakes = ""
    for _ in range(14):
        x, y, a = r.uniform(42, 158), r.uniform(56, 144), r.uniform(0, 180)
        flakes += (f'<g transform="translate({x:.1f} {y:.1f}) rotate({a:.0f})"><path d="M-12,0 C-8,-9 8,-9 12,0 C8,7 -8,7 -12,0 Z" fill="#F4DDB4" stroke="{OL}" stroke-width="3.5"/>'
                   '<path d="M-6,-2 L6,-2" stroke="#D9B47E" stroke-width="2"/></g>')
    return svg(200, 200, flakes)

# ---- nouvelles garnitures sucrées

def chocobar():
    """Barre choco-caramel coupée en tronçons (chocolat, caramel, nougat)."""
    def piece(cx, cy, a):
        return (f'<g transform="translate({cx} {cy}) rotate({a})">'
                f'<rect x="-22" y="-15" width="44" height="30" rx="7" fill="#5A2E16" stroke="{OL}" stroke-width="5"/>'
                '<rect x="-16" y="-9" width="32" height="8" rx="3" fill="#F2C27A"/>'
                '<rect x="-16" y="1" width="32" height="8" rx="3" fill="#E08A2A"/>'
                '<path d="M-17,-12 L10,-12" stroke="#8C5230" stroke-width="3" stroke-linecap="round"/></g>')
    return svg(200, 200, piece(62, 78, -18) + piece(122, 70, 12) + piece(90, 120, 6) + piece(146, 118, -24))

def wafer():
    """Gaufrette fourrée crème noisette, rayée de chocolat."""
    def bar(cx, cy, a):
        return (f'<g transform="translate({cx} {cy}) rotate({a})">'
                f'<rect x="-34" y="-12" width="68" height="24" rx="9" fill="#F3D79A" stroke="{OL}" stroke-width="5"/>'
                '<rect x="-30" y="-2" width="60" height="6" rx="3" fill="#FFF3D6"/>'
                + "".join(f'<path d="M{x},-10 l6,20" stroke="#5A2E16" stroke-width="3.2" stroke-linecap="round"/>' for x in (-24, -12, 0, 12, 24)) +
                '</g>')
    return svg(200, 200, bar(70, 80, -14) + bar(130, 96, 18) + bar(90, 132, -4))

def cookie():
    import random
    r = random.Random(11)
    def bit(cx, cy, s):
        chips = "".join(f'<circle cx="{cx + r.uniform(-s * .5, s * .5):.1f}" cy="{cy + r.uniform(-s * .4, s * .4):.1f}" r="{r.uniform(2.5, 4):.1f}" fill="#4A2414"/>' for _ in range(3))
        return (f'<path d="M{cx - s},{cy} q{s * .3},{-s} {s},{-s * .9} q{s * .8},{s * .1} {s},{s * .9} q{-s * .2},{s * .9} {-s},{s * .9} q{-s * .9},0 {-s},{-s * .9} z" '
                f'fill="#D9A15E" stroke="{OL}" stroke-width="4.5" stroke-linejoin="round"/>' + chips)
    return svg(200, 200, bit(62, 84, 20) + bit(118, 70, 18) + bit(148, 116, 16) + bit(92, 128, 22) + bit(60, 132, 12))

def speculoos():
    import random
    r = random.Random(5)
    crumbs = "".join(f'<rect x="{r.uniform(36, 160):.1f}" y="{r.uniform(52, 148):.1f}" width="{r.uniform(5, 10):.1f}" height="{r.uniform(4, 8):.1f}" rx="2" fill="#B8692A" opacity="0.9"/>' for _ in range(40))
    def bis(cx, cy, a):
        return (f'<g transform="translate({cx} {cy}) rotate({a})">'
                f'<rect x="-24" y="-16" width="48" height="32" rx="5" fill="#C27733" stroke="{OL}" stroke-width="5"/>'
                '<rect x="-17" y="-9" width="34" height="18" rx="3" fill="none" stroke="#8E4D1C" stroke-width="2.5"/>'
                '<circle cx="-8" cy="0" r="3" fill="#8E4D1C"/><circle cx="8" cy="0" r="3" fill="#8E4D1C"/></g>')
    return svg(200, 200, crumbs + bis(78, 90, -16) + bis(132, 112, 14))

def coconut():
    import random
    r = random.Random(9)
    shreds = ""
    for _ in range(46):
        x, y, a = r.uniform(36, 164), r.uniform(50, 150), r.uniform(0, 180)
        shreds += (f'<g transform="translate({x:.1f} {y:.1f}) rotate({a:.0f})"><path d="M-8,0 q8,-5 16,0" stroke="{OL}" stroke-width="5.5" fill="none" stroke-linecap="round"/>'
                   '<path d="M-8,0 q8,-5 16,0" stroke="#FFFFFF" stroke-width="3" fill="none" stroke-linecap="round"/></g>')
    return svg(200, 200, shreds)

def blueberry():
    def b(cx, cy):
        return (f'<circle cx="{cx}" cy="{cy}" r="13" fill="#3E4FA8" stroke="{OL}" stroke-width="4.5"/>'
                f'<circle cx="{cx - 4}" cy="{cy - 4}" r="4" fill="#8C9BE8" opacity="0.8"/>'
                f'<path d="M{cx - 3},{cy + 5} l3,-3 l3,3" stroke="#22296A" stroke-width="2.5" fill="none"/>')
    pts = [(56, 78), (84, 66), (112, 74), (142, 70), (70, 108), (100, 102), (130, 104), (156, 98), (60, 136), (92, 134), (124, 136), (150, 130)]
    return svg(200, 200, "".join(b(x, y) for x, y in pts))

def marshmallow():
    import random
    r = random.Random(4)
    cols = ["#FFD1E3", "#FFFFFF", "#D6F0FF", "#FFF2C2", "#E6D9FF"]
    bits = ""
    for _ in range(16):
        x, y, a = r.uniform(44, 156), r.uniform(58, 142), r.uniform(-30, 30)
        bits += (f'<g transform="translate({x:.1f} {y:.1f}) rotate({a:.0f})"><rect x="-10" y="-9" width="20" height="18" rx="7" fill="{r.choice(cols)}" stroke="{OL}" stroke-width="4"/>'
                 '<rect x="-6" y="-6" width="7" height="4" rx="2" fill="#fff" opacity="0.9"/></g>')
    return svg(200, 200, bits)

# ---- garnitures salées

def ham():
    def slice_(cx, cy, a):
        return (f'<g transform="translate({cx} {cy}) rotate({a})">'
                f'<path d="M-34,-6 C-30,-26 26,-30 34,-10 C38,8 20,22 0,20 C-24,22 -38,12 -34,-6 Z" fill="#F4A3B0" stroke="{OL}" stroke-width="5" stroke-linejoin="round"/>'
                '<path d="M-28,-8 C-22,-20 18,-22 28,-10" stroke="#FFF1F3" stroke-width="5" fill="none" stroke-linecap="round"/>'
                '<path d="M-20,6 C-6,12 10,10 22,2" stroke="#E07A8C" stroke-width="3" fill="none" stroke-linecap="round"/></g>')
    return svg(200, 200, slice_(76, 84, -12) + slice_(128, 112, 16))

def cheese():
    import random
    r = random.Random(21)
    shreds = ""
    for _ in range(38):
        x, y, a = r.uniform(36, 164), r.uniform(50, 150), r.uniform(0, 180)
        shreds += (f'<g transform="translate({x:.1f} {y:.1f}) rotate({a:.0f})"><rect x="-11" y="-3.4" width="22" height="6.8" rx="3.4" fill="{OL}"/>'
                   '<rect x="-9.5" y="-2" width="19" height="4" rx="2" fill="#FFD84A"/></g>')
    return svg(200, 200, shreds)

def egg():
    return svg(200, 200,
               f'<path d="M50,96 C40,62 82,46 104,58 C134,44 166,70 154,100 C166,130 128,152 104,140 C76,154 40,134 50,96 Z" fill="#FFFFFF" stroke="{OL}" stroke-width="5.5" stroke-linejoin="round"/>'
               f'<circle cx="104" cy="98" r="24" fill="#FFB81C" stroke="{OL}" stroke-width="5"/>'
               '<circle cx="96" cy="90" r="7" fill="#FFE59A"/>'
               '<path d="M64,80 C72,66 86,62 96,64" stroke="#EDEDED" stroke-width="5" fill="none" stroke-linecap="round"/>')

def avocado():
    def sl(cx, cy, a):
        return (f'<g transform="translate({cx} {cy}) rotate({a})">'
                f'<path d="M-30,0 C-24,-16 24,-16 30,0 C24,14 -24,14 -30,0 Z" fill="#B6D96A" stroke="{OL}" stroke-width="4.5"/>'
                '<path d="M-26,-2 C-18,-12 18,-12 26,-2" stroke="#4E7A2A" stroke-width="4" fill="none"/>'
                '<path d="M-18,2 C-8,6 8,6 18,2" stroke="#E4F5B6" stroke-width="3" fill="none" stroke-linecap="round"/></g>')
    return svg(200, 200, sl(70, 76, -20) + sl(126, 86, 14) + sl(84, 126, 8) + sl(138, 132, -16))

def salmon():
    def rib(cx, cy, a):
        return (f'<g transform="translate({cx} {cy}) rotate({a})">'
                f'<path d="M-34,0 C-24,-18 -8,10 4,-8 C16,-24 28,4 36,-6 C34,12 20,16 8,8 C-4,22 -22,12 -34,0 Z" fill="#FF8A5C" stroke="{OL}" stroke-width="4.5" stroke-linejoin="round"/>'
                '<path d="M-22,-2 C-14,-8 -6,4 2,-4 M10,-10 C18,-14 24,-4 30,-6" stroke="#FFD0B8" stroke-width="3" fill="none" stroke-linecap="round"/></g>')
    return svg(200, 200, rib(74, 82, -10) + rib(126, 104, 18) + rib(86, 130, 4))

def tomato():
    def t(cx, cy):
        return (f'<circle cx="{cx}" cy="{cy}" r="16" fill="#E8303C" stroke="{OL}" stroke-width="4.5"/>'
                f'<circle cx="{cx}" cy="{cy}" r="10" fill="#FF6A6A"/>'
                + "".join(f'<ellipse cx="{cx + dx}" cy="{cy + dy}" rx="2.4" ry="3.4" fill="#FFE08A"/>' for dx, dy in [(-5, -3), (5, -3), (0, 5)]) +
                f'<circle cx="{cx - 6}" cy="{cy - 7}" r="3" fill="#fff" opacity="0.7"/>')
    return svg(200, 200, "".join(t(x, y) for x, y in [(62, 78), (108, 70), (148, 92), (78, 122), (124, 128)]))

def bacon():
    def strip(cx, cy, a):
        return (f'<g transform="translate({cx} {cy}) rotate({a})">'
                f'<path d="M-44,0 C-30,-14 -16,10 0,-4 C16,-16 30,10 44,-2 L44,12 C30,24 16,-2 0,10 C-16,24 -30,0 -44,14 Z" fill="#C2452E" stroke="{OL}" stroke-width="4.5" stroke-linejoin="round"/>'
                '<path d="M-38,6 C-26,-2 -14,14 0,4 C14,-6 28,14 40,6" stroke="#FFD8C2" stroke-width="3.5" fill="none" stroke-linecap="round"/></g>')
    return svg(200, 200, strip(98, 80, -8) + strip(102, 124, 10))

def rocket():
    def leaf(cx, cy, a):
        return (f'<g transform="translate({cx} {cy}) rotate({a})">'
                f'<path d="M-24,0 C-18,-10 -10,-4 -6,-12 C0,-18 6,-6 12,-12 C20,-12 26,-4 26,0 C20,6 12,4 8,10 C0,14 -6,6 -12,10 C-20,10 -24,4 -24,0 Z" fill="#4FAE3C" stroke="{OL}" stroke-width="4"/>'
                '<path d="M-20,0 L22,0" stroke="#2E7A22" stroke-width="2.5"/></g>')
    return svg(200, 200, leaf(64, 74, -30) + leaf(112, 64, 10) + leaf(150, 96, 60) + leaf(80, 116, 20) + leaf(126, 130, -40) + leaf(56, 140, 70))

def sourcream():
    def d(cx, cy, s):
        return (f'<g transform="translate({cx} {cy}) scale({s})">'
                f'<path d="M-20,6 C-24,-10 -6,-18 2,-12 C12,-20 26,-8 20,6 C22,18 6,20 0,14 C-8,20 -22,18 -20,6 Z" fill="#FFFBEE" stroke="{OL}" stroke-width="4.5"/>'
                '<circle cx="-6" cy="-4" r="3.5" fill="#fff"/></g>')
    return svg(200, 200, d(68, 84, 1) + d(134, 80, 0.9) + d(100, 128, 1.1))

def chives():
    import random
    r = random.Random(13)
    bits = ""
    for _ in range(48):
        x, y, a = r.uniform(36, 164), r.uniform(50, 150), r.uniform(0, 180)
        bits += (f'<g transform="translate({x:.1f} {y:.1f}) rotate({a:.0f})"><rect x="-6" y="-2.6" width="12" height="5.2" rx="2.6" fill="{OL}"/>'
                 '<rect x="-4.8" y="-1.5" width="9.6" height="3" rx="1.5" fill="#5CC24A"/></g>')
    return svg(200, 200, bits)

# ---- les crêpes

CREPE = [
    ("#FFF1C8", "#F6E2A6"),
    ("#FBE2A2", "#EFCB7A"),
    ("#F5C672", "#D99A3E"),
    ("#D99442", "#A8601F"),
    ("#6A4026", "#3E2416"),
]

def crepe(level):
    import random
    base, spot = CREPE[level]
    r = random.Random(30 + level)
    spots = "".join(f'<ellipse cx="{r.uniform(40, 160):.1f}" cy="{r.uniform(42, 158):.1f}" rx="{r.uniform(4, 11):.1f}" ry="{r.uniform(3, 7):.1f}" fill="{spot}" opacity="0.85"/>'
                    for _ in range(28 if level > 0 else 6))
    smoke = ""
    if level == 4:
        smoke = '<path d="M60,30 q12,-18 0,-28 M140,30 q-12,-18 0,-28" stroke="#777" stroke-width="6" fill="none" opacity="0.4" stroke-linecap="round"/>'
    return svg(200, 200, shadow(102, 176, 80, 8) +
               f'<circle cx="100" cy="100" r="80" fill="{base}" stroke="{OL}" stroke-width="{SW}"/>'
               '<clipPath id="cc"><circle cx="100" cy="100" r="76"/></clipPath>'
               f'<g clip-path="url(#cc)">{spots}</g>'
               f'<circle cx="100" cy="100" r="72" fill="none" stroke="{spot}" stroke-width="4" opacity="0.6"/>'
               '<path d="M48,62 C60,44 80,36 100,34" stroke="#fff" stroke-width="6" fill="none" opacity="0.45" stroke-linecap="round"/>' + smoke)

def crepe_batter():
    return svg(200, 200,
               f'<circle cx="100" cy="100" r="74" fill="#FCEBB4" stroke="{OL}" stroke-width="6"/>'
               '<path d="M50,78 C62,54 86,42 108,42" stroke="#fff" stroke-width="7" fill="none" opacity="0.7" stroke-linecap="round"/>'
               '<ellipse cx="126" cy="122" rx="12" ry="7" fill="#F4D98E"/><ellipse cx="78" cy="128" rx="8" ry="5" fill="#F4D98E"/>')

INGREDIENTS = {
    "sugar": sugar, "spread": spread, "cream": cream, "strawberry": strawberry, "banana": banana,
    "caramel": lambda: drizzle("#E8941A", "#FFD27A", 1), "honey": lambda: drizzle("#F6B21B", "#FFF2B8", 2),
    "chocmelt": lambda: drizzle("#4A2414", "#8C5230", 3), "jam": jam, "icecream": icecream, "sprinkles": sprinkles, "almonds": almonds,
    "chocobar": chocobar, "wafer": wafer, "cookie": cookie, "speculoos": speculoos, "coconut": coconut, "blueberry": blueberry,
    "marshmallow": marshmallow, "pistachio": lambda: drizzle("#93C24A", "#D8F0A0", 4),
    "ham": ham, "cheese": cheese, "egg": egg, "avocado": avocado, "salmon": salmon, "tomato": tomato, "bacon": bacon,
    "rocket": rocket, "sourcream": sourcream, "chives": chives, "cheesesauce": lambda: drizzle("#F5A623", "#FFE08A", 5),
}

# ---------------------------------------------------------------- le gaufrier

def iron(part):
    """part = 'base' (plaque du bas, charnière en haut) ou 'lid' (couvercle, charnière en bas)."""
    w, h = 600, 300
    cells = ""
    cols, rows = 7, 4
    px0, py0, pw, ph = 112, 58, 376, 184
    cw, ch = pw / cols, ph / rows
    for r in range(rows):
        for c in range(cols):
            cells += (f'<rect x="{px0 + c * cw + 5:.1f}" y="{py0 + r * ch + 5:.1f}" width="{cw - 10:.1f}" height="{ch - 10:.1f}" rx="5" fill="#3A3640"/>'
                      f'<rect x="{px0 + c * cw + 5:.1f}" y="{py0 + r * ch + 5:.1f}" width="{cw - 10:.1f}" height="4" rx="2" fill="#000" opacity="0.35"/>')
    plate = (f'<rect x="96" y="44" width="408" height="212" rx="30" fill="#55505C" stroke="{OL}" stroke-width="7"/>'
             f'<rect x="{px0}" y="{py0}" width="{pw}" height="{ph}" rx="14" fill="#6A6474"/>' + cells +
             '<path d="M120,56 L300,56" stroke="#fff" stroke-width="5" opacity="0.18" stroke-linecap="round"/>')
    defs = grad("body", "#7FE0D6", "#2FA79E") + grad("chrome", "#F4F6FA", "#A8AEBC")
    body = (f'<rect x="40" y="16" width="520" height="268" rx="64" fill="url(#body)" stroke="{OL}" stroke-width="9"/>'
            '<path d="M86,40 Q300,22 514,40" stroke="#fff" stroke-width="10" fill="none" opacity="0.4" stroke-linecap="round"/>'
            + plate)
    hinge = (f'<rect x="200" y="0" width="200" height="30" rx="12" fill="url(#chrome)" stroke="{OL}" stroke-width="6"/>'
             '<rect x="214" y="8" width="172" height="6" rx="3" fill="#fff" opacity="0.7"/>')
    lamp = (f'<circle cx="524" cy="258" r="12" fill="#FF6B5A" stroke="{OL}" stroke-width="5"/>'
            '<circle cx="520" cy="254" r="4" fill="#fff" opacity="0.8"/>')
    g = body + hinge + lamp
    if part == "lid":
        g = f'<g transform="translate(0 {h}) scale(1 -1)">{body + hinge}</g>'
    return svg(w, h, g, defs)

def iron_closed():
    """Le gaufrier fermé, vu de face (pendant la cuisson)."""
    defs = grad("body", "#7FE0D6", "#2FA79E") + grad("chrome", "#F4F6FA", "#A8AEBC") + grad("dark", "#4A4650", "#2B2830")
    body = (shadow(300, 330, 230, 18, 0.25) +
            f'<rect x="60" y="150" width="480" height="170" rx="60" fill="url(#body)" stroke="{OL}" stroke-width="9"/>'
            f'<path d="M70,160 C70,60 530,60 530,160 Z" fill="url(#body)" stroke="{OL}" stroke-width="9" stroke-linejoin="round"/>'
            f'<rect x="76" y="152" width="448" height="20" fill="url(#dark)" stroke="{OL}" stroke-width="6"/>'
            + "".join(f'<rect x="{90 + k * 30}" y="157" width="18" height="10" rx="3" fill="#F6BE5C" opacity="0.9"/>' for k in range(15)) +
            f'<path d="M250,64 L250,40 Q250,28 262,28 L338,28 Q350,28 350,40 L350,64" fill="none" stroke="{OL}" stroke-width="18" stroke-linecap="round"/>'
            '<path d="M250,64 L250,40 Q250,28 262,28 L338,28 Q350,28 350,40 L350,64" fill="none" stroke="#3A3640" stroke-width="10" stroke-linecap="round"/>'
            '<path d="M130,110 Q300,76 470,110" stroke="#fff" stroke-width="12" fill="none" opacity="0.4" stroke-linecap="round"/>'
            '<path d="M110,200 Q300,186 490,200" stroke="#fff" stroke-width="10" fill="none" opacity="0.3" stroke-linecap="round"/>'
            # le voyant est dessiné par l'app (il change de couleur) ; ici, son socle chromé
            f'<circle cx="470" cy="270" r="24" fill="url(#chrome)" stroke="{OL}" stroke-width="6"/>'
            # deux boutons de réglage
            f'<circle cx="140" cy="270" r="17" fill="url(#dark)" stroke="{OL}" stroke-width="6"/><rect x="137" y="256" width="6" height="12" rx="3" fill="#fff" opacity="0.8"/>'
            f'<circle cx="196" cy="270" r="17" fill="url(#dark)" stroke="{OL}" stroke-width="6"/><rect x="193" y="256" width="6" height="12" rx="3" fill="#fff" opacity="0.8"/>')
    return svg(600, 350, body, defs)

# ---------------------------------------------------------------- les clients

CUSTOMERS = [
    # couleur du corps, ombre, accessoire
    ("#7CC6FF", "#4E9BD8", "cap"),
    ("#FF9EC7", "#E46FA0", "bow"),
    ("#8EE08A", "#5BB257", "glasses"),
    ("#FFC86B", "#E59E2F", "chef"),
    ("#C4A8FF", "#9A7AE8", "tuft"),
]

def customer(i, mood):
    body_c, shade, acc = CUSTOMERS[i]
    defs = grad("b", body_c, shade)
    # Fâché : de la vapeur qui sort de la tête
    tint = (f'<path d="M60,40 q-14,-14 0,-28 M240,40 q14,-14 0,-28" stroke="{OL}" stroke-width="7" fill="none" stroke-linecap="round"/>'
            '<path d="M60,40 q-14,-14 0,-28 M240,40 q14,-14 0,-28" stroke="#fff" stroke-width="3" fill="none" stroke-linecap="round"/>') if mood == "angry" else ""
    body = (shadow(150, 300, 100, 14, 0.2) +
            f'<path d="M58,300 C40,150 70,40 150,40 C230,40 260,150 242,300 Z" fill="url(#b)" stroke="{OL}" stroke-width="9" stroke-linejoin="round"/>'
            '<path d="M92,90 C108,62 136,56 160,58" stroke="#fff" stroke-width="12" fill="none" opacity="0.4" stroke-linecap="round"/>'
            # bras
            f'<path d="M62,220 C34,230 34,262 60,262" fill="{body_c}" stroke="{OL}" stroke-width="8" stroke-linejoin="round"/>'
            f'<path d="M238,220 C266,230 266,262 240,262" fill="{body_c}" stroke="{OL}" stroke-width="8" stroke-linejoin="round"/>')
    # visage
    if mood == "happy":
        eyes = (f'<path d="M104,140 q14,-18 28,0" stroke="{OL}" stroke-width="9" fill="none" stroke-linecap="round"/>'
                f'<path d="M168,140 q14,-18 28,0" stroke="{OL}" stroke-width="9" fill="none" stroke-linecap="round"/>')
        mouth = f'<path d="M122,172 Q150,206 178,172 Z" fill="#7A1E1E" stroke="{OL}" stroke-width="7" stroke-linejoin="round"/><path d="M134,186 Q150,198 166,186" fill="#FF7A8A"/>'
        brows = ""
    elif mood == "angry":
        eyes = (f'<ellipse cx="118" cy="146" rx="12" ry="14" fill="{OL}"/><ellipse cx="182" cy="146" rx="12" ry="14" fill="{OL}"/>'
                '<circle cx="122" cy="141" r="4" fill="#fff"/><circle cx="186" cy="141" r="4" fill="#fff"/>')
        brows = (f'<path d="M98,118 L136,132" stroke="{OL}" stroke-width="9" stroke-linecap="round"/>'
                 f'<path d="M202,118 L164,132" stroke="{OL}" stroke-width="9" stroke-linecap="round"/>')
        mouth = f'<path d="M126,192 Q150,170 174,192" stroke="{OL}" stroke-width="9" fill="none" stroke-linecap="round"/>'
    else:
        eyes = (f'<ellipse cx="118" cy="142" rx="13" ry="17" fill="{OL}"/><ellipse cx="182" cy="142" rx="13" ry="17" fill="{OL}"/>'
                '<circle cx="123" cy="135" r="5" fill="#fff"/><circle cx="187" cy="135" r="5" fill="#fff"/>')
        brows = ""
        mouth = f'<ellipse cx="150" cy="184" rx="11" ry="9" fill="#7A1E1E" stroke="{OL}" stroke-width="6"/>'
    cheeks = '<ellipse cx="96" cy="170" rx="15" ry="9" fill="#FF6B8A" opacity="0.45"/><ellipse cx="204" cy="170" rx="15" ry="9" fill="#FF6B8A" opacity="0.45"/>'
    # accessoire
    if acc == "cap":
        accs = (f'<path d="M86,74 C96,28 204,28 214,74 Z" fill="#E8453C" stroke="{OL}" stroke-width="8" stroke-linejoin="round"/>'
                f'<path d="M190,70 Q250,66 262,84 Q230,90 196,82 Z" fill="#C8302A" stroke="{OL}" stroke-width="7" stroke-linejoin="round"/>'
                f'<circle cx="150" cy="34" r="8" fill="#C8302A" stroke="{OL}" stroke-width="5"/>')
    elif acc == "bow":
        accs = (f'<path d="M150,46 L112,24 L112,70 Z M150,46 L188,24 L188,70 Z" fill="#FF4F7B" stroke="{OL}" stroke-width="7" stroke-linejoin="round"/>'
                f'<circle cx="150" cy="46" r="12" fill="#FF7A9C" stroke="{OL}" stroke-width="6"/>')
    elif acc == "glasses":
        accs = (f'<circle cx="118" cy="142" r="28" fill="#fff" opacity="0.25" stroke="{OL}" stroke-width="7"/>'
                f'<circle cx="182" cy="142" r="28" fill="#fff" opacity="0.25" stroke="{OL}" stroke-width="7"/>'
                f'<path d="M146,140 L154,140" stroke="{OL}" stroke-width="7"/>')
    elif acc == "chef":
        accs = (f'<path d="M100,70 C70,64 74,18 108,24 C116,0 184,0 192,24 C226,18 230,64 200,70 Z" fill="#FFFFFF" stroke="{OL}" stroke-width="8" stroke-linejoin="round"/>'
                f'<rect x="100" y="62" width="100" height="22" rx="6" fill="#F2F2F2" stroke="{OL}" stroke-width="7"/>')
    else:
        accs = (f'<path d="M150,44 C140,14 158,4 162,18 C170,4 186,16 170,34" fill="none" stroke="{OL}" stroke-width="9" stroke-linecap="round"/>')
    g = body + accs + cheeks + brows + eyes + mouth + tint
    return svg(300, 320, g, defs)

# ---------------------------------------------------------------- petites icônes

def coin():
    return svg(100, 100, f'<circle cx="50" cy="52" r="42" fill="#E8941A" stroke="{OL}" stroke-width="6"/>'
                         f'<circle cx="50" cy="48" r="38" fill="#FFC93C" stroke="{OL}" stroke-width="5"/>'
                         '<circle cx="50" cy="48" r="26" fill="none" stroke="#E8941A" stroke-width="5"/>'
                         '<path d="M30,34 a26,26 0 0 1 16,-10" stroke="#fff" stroke-width="6" fill="none" opacity="0.7" stroke-linecap="round"/>')

def star(on=True):
    c1, c2 = ("#FFE066", "#FFB627") if on else ("#E2D8C8", "#C8BCA8")
    d = "M50,8 L62,36 L92,38 L68,58 L76,88 L50,72 L24,88 L32,58 L8,38 L38,36 Z"
    return svg(100, 100, f'<defs>{grad("s", c1, c2)}</defs><path d="{d}" fill="url(#s)" stroke="{OL}" stroke-width="7" stroke-linejoin="round"/>'
                         + ('<path d="M40,30 L46,18" stroke="#fff" stroke-width="6" stroke-linecap="round" opacity="0.8"/>' if on else ""))

def wall_tile():
    """Un carreau de métro (se répète)."""
    return svg(120, 60, '<rect width="120" height="60" fill="#E9DCC6"/>'
                        '<rect x="3" y="3" width="114" height="24" rx="6" fill="#FFF6E6"/><rect x="3" y="3" width="114" height="8" rx="4" fill="#fff" opacity="0.6"/>'
                        '<rect x="-57" y="33" width="114" height="24" rx="6" fill="#FFF6E6"/><rect x="63" y="33" width="114" height="24" rx="6" fill="#FFF6E6"/>')

def icon(size=1024):
    """L'icône : une gaufre dorée, chocolat, chantilly et fraise, sur fond orange."""
    defs = grad("bg", "#FFB347", "#FF6A3D")
    inner = waffle(2).split('<defs></defs>')[1].replace('</svg>', '')
    choco = drizzle("#4A2414", "#8C5230", 3).split('<defs></defs>')[1].replace('</svg>', '')
    cr = cream().split('<defs></defs>')[1].replace('</svg>', '')
    st = strawberry().split('<defs></defs>')[1].replace('</svg>', '')
    body = (f'<rect width="1024" height="1024" fill="url(#bg)"/>'
            '<circle cx="840" cy="170" r="260" fill="#fff" opacity="0.12"/><circle cx="150" cy="900" r="220" fill="#fff" opacity="0.08"/>'
            f'<g transform="translate(512 560) rotate(-10) scale(4.3) translate(-100 -100)">{inner}{choco}'
            f'<g transform="translate(100 100) scale(0.62) translate(-100 -100)">{cr}</g>'
            f'<g transform="translate(150 70) scale(0.42) translate(-100 -100)">{st}</g></g>'
            '<path d="M330,230 q-30,-50 0,-100 M512,200 q-30,-50 0,-100 M694,230 q-30,-50 0,-100" stroke="#fff" stroke-width="26" fill="none" opacity="0.7" stroke-linecap="round"/>')
    return svg(1024, 1024, body, defs)
