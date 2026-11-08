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

# ---------------------------------------------------------------- le pain

BREAD = "M28,72 C26,34 58,20 100,30 C142,20 174,34 172,72 L172,160 Q172,182 150,182 L50,182 Q28,182 28,160 Z"
CRUMB = "M44,76 C44,48 68,40 100,48 C132,40 156,48 156,76 L156,154 Q156,166 144,166 L56,166 Q44,166 44,154 Z"

# cru, clair, doré, foncé, brûlé
DONENESS = [
    ("#F8E6BC", "#FFF3D6", "#D9A55A"),
    ("#F4D08E", "#FBE3B0", "#C98A3C"),
    ("#E8A24C", "#F6C46E", "#A8601F"),
    ("#BE6A28", "#D88A40", "#7A3E14"),
    ("#4A2E1E", "#5E3A24", "#24140C"),
]

def bread(level):
    crumb, light, crust = DONENESS[level]
    defs = grad("cr", light, crumb) + grad("cu", crust, "#000000")
    pores = "".join(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{crust}" opacity="0.28"/>'
                    for x, y, rx, ry in [(70, 80, 4, 3), (118, 72, 3, 2.5), (92, 104, 5, 3.5), (132, 118, 4, 3), (66, 132, 3.5, 3),
                                          (104, 146, 4, 2.5), (140, 150, 3, 2.5), (80, 160, 3, 2)])
    marks = ""
    if level >= 2:
        op = 0.22 if level == 2 else 0.32
        marks = "".join(f'<path d="M{x},{48} L{x - 70},{170}" stroke="{crust}" stroke-width="9" opacity="{op}" stroke-linecap="round"/>'
                        for x in (110, 140, 170, 200))
    smoke = ""
    if level == 4:
        smoke = '<path d="M60,120 q10,-20 0,-40 M140,110 q-10,-20 0,-40" stroke="#888" stroke-width="5" fill="none" opacity="0.35"/>'
    body = (shadow(104, 186, 74, 10) +
            f'<path d="{BREAD}" fill="{crust}" stroke="{OL}" stroke-width="{SW}" stroke-linejoin="round"/>'
            f'<clipPath id="cc"><path d="{CRUMB}"/></clipPath>'
            f'<path d="{CRUMB}" fill="url(#cr)"/>'
            f'<g clip-path="url(#cc)">{marks}{pores}</g>'
            f'<path d="M58,62 C70,52 84,52 96,56" stroke="#fff" stroke-width="6" fill="none" opacity="0.45" stroke-linecap="round"/>'
            + smoke)
    return svg(200, 200, body, defs)

# ---------------------------------------------------------------- les garnitures

def ham():
    defs = rgrad("h", "#FFB8C2", "#EE7F93")
    marb = "".join(f'<path d="{d}" stroke="#FFD9DF" stroke-width="4" fill="none" opacity="0.7" stroke-linecap="round"/>'
                   for d in ["M70,90 q20,-10 40,4", "M90,130 q24,6 38,-10", "M60,118 q8,12 22,10"])
    return svg(200, 200, shadow(102, 176, 70, 10) +
               f'<circle cx="100" cy="100" r="76" fill="#FCE3E6" stroke="{OL}" stroke-width="{SW}"/>'
               f'<circle cx="100" cy="100" r="62" fill="url(#h)"/>' + marb +
               '<path d="M58,78 a50,50 0 0 1 34,-26" stroke="#fff" stroke-width="7" fill="none" opacity="0.5" stroke-linecap="round"/>', defs)

def cheese(color="#FFD34D", dark="#F0A91E", light="#FFE88A", melty=False):
    defs = grad("c", light, color)
    holes = "".join(f'<ellipse cx="{x}" cy="{y}" rx="{r}" ry="{r * 0.8}" fill="{dark}" opacity="0.8"/>'
                    for x, y, r in [(72, 78, 10), (126, 70, 7), (110, 116, 13), (68, 132, 7), (140, 140, 9)])
    drips = ""
    if melty:
        drips = (f'<path d="M48,150 q4,26 14,0 M100,156 q6,30 16,0 M140,152 q4,20 12,0" fill="{color}" stroke="{OL}" stroke-width="5" stroke-linejoin="round"/>')
    return svg(200, 200, shadow(100, 178, 72, 10) + drips +
               f'<g transform="rotate(-6 100 100)"><rect x="34" y="34" width="132" height="128" rx="14" fill="url(#c)" stroke="{OL}" stroke-width="{SW}"/>'
               + holes + '<path d="M50,52 L96,48" stroke="#fff" stroke-width="7" opacity="0.5" stroke-linecap="round"/></g>', defs)

def bechamel():
    return svg(200, 200, shadow(100, 176, 70, 9) +
               f'<path d="M40,96 C30,60 70,40 98,52 C126,36 172,58 160,96 C178,124 150,160 118,150 C98,170 60,166 54,140 C30,136 28,112 40,96 Z" fill="#FFF7EA" stroke="{OL}" stroke-width="{SW}" stroke-linejoin="round"/>'
               '<path d="M70,80 q20,-12 40,0 M84,118 q22,10 44,-4" stroke="#EADBC2" stroke-width="5" fill="none" stroke-linecap="round"/>'
               '<circle cx="66" cy="70" r="7" fill="#fff"/><circle cx="82" cy="62" r="4" fill="#fff"/>'
               + "".join(f'<circle cx="{x}" cy="{y}" r="2.2" fill="#3B2418" opacity="0.35"/>' for x, y in [(110, 90), (130, 110), (90, 132), (72, 104)]))

def egg():
    return svg(200, 200, shadow(100, 176, 72, 10) +
               f'<path d="M36,104 C26,64 66,34 104,44 C146,30 180,70 166,108 C176,146 132,174 98,162 C60,176 30,146 36,104 Z" fill="#FFFDF7" stroke="{OL}" stroke-width="{SW}" stroke-linejoin="round"/>'
               f'<circle cx="104" cy="102" r="34" fill="#FFB12A" stroke="{OL}" stroke-width="6"/>'
               '<circle cx="104" cy="102" r="26" fill="#FFC64A"/>'
               '<ellipse cx="94" cy="90" rx="10" ry="7" fill="#fff" opacity="0.75"/>')

def tomato():
    def slice_(cx, cy, r):
        seeds = "".join(f'<ellipse cx="{cx + dx}" cy="{cy + dy}" rx="4" ry="2.6" fill="#FFE7A8" transform="rotate({a} {cx + dx} {cy + dy})"/>'
                        for dx, dy, a in [(-r * 0.4, -r * 0.2, 30), (r * 0.35, -r * 0.3, -30), (0, r * 0.42, 90), (-r * 0.3, r * 0.25, 60), (r * 0.38, r * 0.2, -60)])
        return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#E8453C" stroke="{OL}" stroke-width="6"/>'
                f'<circle cx="{cx}" cy="{cy}" r="{r - 8}" fill="#FF6B5A"/>'
                f'<path d="M{cx},{cy - r + 10} L{cx},{cy + r - 10} M{cx - r + 10},{cy} L{cx + r - 10},{cy}" stroke="#E8453C" stroke-width="4" opacity="0.6"/>'
                + seeds + f'<path d="M{cx - r * 0.6},{cy - r * 0.5} a{r * 0.7},{r * 0.7} 0 0 1 {r * 0.5},{-r * 0.3}" stroke="#fff" stroke-width="5" fill="none" opacity="0.55" stroke-linecap="round"/>')
    return svg(200, 200, shadow(100, 178, 72, 9) + slice_(70, 74, 40) + slice_(132, 86, 40) + slice_(96, 136, 40))

def mushroom():
    def m(x, y, s, a):
        return (f'<g transform="translate({x} {y}) rotate({a}) scale({s})">'
                f'<path d="M-34,0 C-34,-30 34,-30 34,0 Q34,8 22,8 L12,8 L14,30 Q14,38 0,38 Q-14,38 -14,30 L-12,8 L-22,8 Q-34,8 -34,0 Z" fill="#E8D2B4" stroke="{OL}" stroke-width="6" stroke-linejoin="round"/>'
                f'<path d="M-30,-2 C-28,-24 28,-24 30,-2 Z" fill="#B07A4A"/>'
                f'<path d="M-18,-14 q10,-8 22,-6" stroke="#fff" stroke-width="4" fill="none" opacity="0.5" stroke-linecap="round"/></g>')
    return svg(200, 200, shadow(100, 178, 72, 9) + m(66, 74, 1.0, -12) + m(134, 84, 1.0, 14) + m(98, 134, 1.05, 4))

def goat():
    def g(cx, cy, r):
        return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#ECE6DA" stroke="{OL}" stroke-width="6"/>'
                f'<circle cx="{cx}" cy="{cy}" r="{r - 9}" fill="#FFFDF8"/>'
                f'<circle cx="{cx - r * 0.3}" cy="{cy - r * 0.3}" r="{r * 0.18}" fill="#fff"/>')
    return svg(200, 200, shadow(100, 178, 72, 9) + g(68, 78, 38) + g(136, 82, 38) + g(100, 138, 40))

def honey():
    return svg(200, 200,
               f'<path d="M36,70 C60,40 70,110 96,74 C120,42 128,118 150,80 C166,56 172,98 164,112" stroke="{OL}" stroke-width="22" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
               '<path d="M36,70 C60,40 70,110 96,74 C120,42 128,118 150,80 C166,56 172,98 164,112" stroke="#F6B21B" stroke-width="12" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
               f'<path d="M58,126 C40,150 60,170 78,160 C92,152 84,134 58,126 Z" fill="#F6B21B" stroke="{OL}" stroke-width="6"/>'
               f'<path d="M120,128 C106,150 122,168 138,160 C152,150 142,136 120,128 Z" fill="#FFC93C" stroke="{OL}" stroke-width="6"/>'
               '<path d="M44,62 C54,52 60,60 64,70" stroke="#FFF2B8" stroke-width="4" fill="none" stroke-linecap="round"/>'
               '<circle cx="66" cy="146" r="4" fill="#fff" opacity="0.7"/><circle cx="128" cy="146" r="4" fill="#fff" opacity="0.7"/>')

def pineapple():
    rays = "".join(f'<path d="M100,100 L{100 + 52 * __import__("math").cos(a)},{100 + 52 * __import__("math").sin(a)}" stroke="#F0B41C" stroke-width="4"/>'
                   for a in [i * 0.5236 for i in range(12)])
    return svg(200, 200, shadow(100, 178, 72, 10) +
               f'<circle cx="100" cy="100" r="74" fill="#FFE070" stroke="{OL}" stroke-width="{SW}"/>'
               f'<circle cx="100" cy="100" r="62" fill="#FFD447"/>' + rays +
               f'<circle cx="100" cy="100" r="22" fill="#F7E7C0" stroke="{OL}" stroke-width="6"/>'
               '<path d="M50,74 a56,56 0 0 1 30,-26" stroke="#fff" stroke-width="7" fill="none" opacity="0.55" stroke-linecap="round"/>')

def chicken():
    def s(x, y, a):
        return (f'<g transform="translate({x} {y}) rotate({a})"><rect x="-60" y="-16" width="120" height="32" rx="14" fill="#E9C08A" stroke="{OL}" stroke-width="6"/>'
                f'<path d="M-36,-14 L-48,14 M-6,-14 L-18,14 M24,-14 L12,14 M52,-12 L42,12" stroke="#A8692E" stroke-width="5" opacity="0.6"/>'
                '<path d="M-50,-8 L10,-8" stroke="#fff" stroke-width="4" opacity="0.45" stroke-linecap="round"/></g>')
    return svg(200, 200, shadow(100, 178, 72, 9) + s(96, 66, -10) + s(104, 104, 6) + s(94, 144, -4))

def spinach():
    def leaf(x, y, a, c):
        return (f'<g transform="translate({x} {y}) rotate({a})"><path d="M0,-46 C34,-30 34,30 0,46 C-34,30 -34,-30 0,-46 Z" fill="{c}" stroke="{OL}" stroke-width="6" stroke-linejoin="round"/>'
                '<path d="M0,-38 L0,40 M0,-10 L14,-20 M0,8 L-14,-2 M0,22 L12,14" stroke="#9BE08A" stroke-width="3.5" fill="none" stroke-linecap="round"/></g>')
    return svg(200, 200, shadow(100, 178, 72, 9) + leaf(70, 88, -30, "#3FA34D") + leaf(130, 86, 34, "#2F8E3E") + leaf(100, 126, 4, "#48B456"))

def chocolate():
    sq = "".join(f'<rect x="{46 + c * 38}" y="{50 + r * 38}" width="32" height="32" rx="5" fill="#7A4424"/>'
                 f'<path d="M{50 + c * 38},{54 + r * 38} l20,0" stroke="#A0653E" stroke-width="4" stroke-linecap="round"/>'
                 for r in range(3) for c in range(3))
    return svg(200, 200, shadow(100, 178, 72, 10) +
               f'<g transform="rotate(5 100 100)"><rect x="38" y="42" width="124" height="122" rx="12" fill="#5A2E16" stroke="{OL}" stroke-width="{SW}"/>{sq}</g>')

def banana():
    def b(cx, cy, r):
        seeds = "".join(f'<circle cx="{cx + dx}" cy="{cy + dy}" r="2.4" fill="#8A6A3A"/>' for dx, dy in [(-6, -4), (6, -4), (0, 7)])
        return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#FFF0B0" stroke="{OL}" stroke-width="6"/>'
                f'<circle cx="{cx}" cy="{cy}" r="{r - 9}" fill="#FFF7D6"/>' + seeds)
    return svg(200, 200, shadow(100, 178, 72, 9) + b(64, 72, 30) + b(130, 70, 30) + b(96, 112, 30) + b(60, 142, 28) + b(140, 136, 30))

INGREDIENTS = {
    "ham": ham, "cheese": cheese, "bechamel": bechamel, "egg": egg, "tomato": tomato, "mushroom": mushroom,
    "goat": goat, "honey": honey, "pineapple": pineapple, "chicken": chicken, "spinach": spinach,
    "raclette": lambda: cheese("#FFB938", "#E8861A", "#FFD27A", melty=True), "chocolate": chocolate, "banana": banana,
}

# ---------------------------------------------------------------- l'appareil à croque

def press(part):
    """part = 'base' (plaque du bas, charnière en haut) ou 'lid' (couvercle, charnière en bas)."""
    w, h = 600, 300
    ridges = "".join(f'<path d="M{x},60 L{x - 120},250" stroke="#4A4650" stroke-width="10" stroke-linecap="round"/>' for x in range(150, 640, 44))
    plate = (f'<clipPath id="pl"><rect x="96" y="44" width="408" height="212" rx="34"/></clipPath>'
             f'<rect x="96" y="44" width="408" height="212" rx="34" fill="#2B2830"/>'
             f'<g clip-path="url(#pl)">{ridges}<rect x="96" y="44" width="408" height="60" fill="#fff" opacity="0.05"/></g>'
             f'<rect x="96" y="44" width="408" height="212" rx="34" fill="none" stroke="{OL}" stroke-width="7"/>')
    defs = grad("red", "#FF6B5A", "#D93A2E") + grad("chrome", "#F4F6FA", "#A8AEBC")
    body = (f'<rect x="40" y="16" width="520" height="268" rx="70" fill="url(#red)" stroke="{OL}" stroke-width="9"/>'
            '<path d="M86,40 Q300,22 514,40" stroke="#fff" stroke-width="10" fill="none" opacity="0.35" stroke-linecap="round"/>'
            + plate)
    hinge = (f'<rect x="200" y="0" width="200" height="30" rx="12" fill="url(#chrome)" stroke="{OL}" stroke-width="6"/>'
             '<rect x="214" y="8" width="172" height="6" rx="3" fill="#fff" opacity="0.7"/>')
    lamp = (f'<circle cx="520" cy="256" r="12" fill="#7CFF6B" stroke="{OL}" stroke-width="5"/>'
            '<circle cx="516" cy="252" r="4" fill="#fff" opacity="0.8"/>')
    g = body + hinge + lamp
    if part == "lid":
        g = f'<g transform="translate(0 {h}) scale(1 -1)">{body + hinge}</g>'
    return svg(w, h, g, defs)

def press_closed():
    """L'appareil fermé, vu de face (pendant la cuisson)."""
    defs = grad("red", "#FF6B5A", "#D93A2E") + grad("chrome", "#F4F6FA", "#A8AEBC") + grad("dark", "#4A4650", "#2B2830")
    body = (shadow(300, 330, 230, 18, 0.25) +
            f'<rect x="60" y="150" width="480" height="170" rx="60" fill="url(#red)" stroke="{OL}" stroke-width="9"/>'
            f'<path d="M70,160 C70,60 530,60 530,160 Z" fill="url(#red)" stroke="{OL}" stroke-width="9" stroke-linejoin="round"/>'
            f'<rect x="76" y="154" width="448" height="18" fill="url(#dark)" stroke="{OL}" stroke-width="6"/>'
            f'<rect x="220" y="56" width="160" height="36" rx="18" fill="url(#chrome)" stroke="{OL}" stroke-width="7"/>'
            '<path d="M130,110 Q300,76 470,110" stroke="#fff" stroke-width="12" fill="none" opacity="0.35" stroke-linecap="round"/>'
            '<path d="M110,200 Q300,186 490,200" stroke="#fff" stroke-width="10" fill="none" opacity="0.25" stroke-linecap="round"/>'
            f'<circle cx="470" cy="270" r="15" fill="#FF8A3D" stroke="{OL}" stroke-width="6"/><circle cx="465" cy="265" r="5" fill="#fff" opacity="0.8"/>'
            f'<rect x="120" y="258" width="200" height="26" rx="13" fill="#2B2830" stroke="{OL}" stroke-width="5"/>')
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
    """L'icône de l'app : un croque doré qui sort de l'appareil, sur fond orange."""
    s = size / 1024
    defs = grad("bg", "#FFB347", "#FF6A3D") + grad("red", "#FF6B5A", "#D93A2E") + grad("cr", "#F6C46E", "#E8A24C")
    body = (f'<rect width="1024" height="1024" fill="url(#bg)"/>'
            '<circle cx="820" cy="180" r="260" fill="#fff" opacity="0.12"/>'
            # l'appareil, ouvert, de biais
            f'<g transform="translate(512 640) rotate(-8)">'
            f'<rect x="-380" y="-60" width="760" height="300" rx="110" fill="url(#red)" stroke="{OL}" stroke-width="18"/>'
            f'<rect x="-310" y="-20" width="620" height="210" rx="60" fill="#2B2830" stroke="{OL}" stroke-width="12"/>'
            '<path d="M-330,-30 Q0,-56 330,-30" stroke="#fff" stroke-width="18" fill="none" opacity="0.3" stroke-linecap="round"/></g>'
            # le croque
            f'<g transform="translate(512 470) rotate(-8) scale(2.6) translate(-100 -105)">'
            f'<path d="{BREAD}" fill="#A8601F" stroke="{OL}" stroke-width="7" stroke-linejoin="round"/>'
            f'<path d="M36,150 q20,26 40,0 q20,26 40,0 q20,26 40,0" fill="#FFD34D" stroke="{OL}" stroke-width="6" stroke-linejoin="round"/>'
            f'<clipPath id="ic"><path d="{CRUMB}"/></clipPath><path d="{CRUMB}" fill="url(#cr)"/>'
            '<g clip-path="url(#ic)">' + "".join(f'<path d="M{x},48 L{x - 70},170" stroke="#A8601F" stroke-width="10" opacity="0.3"/>' for x in (110, 140, 170, 200)) + '</g>'
            '<path d="M58,62 C70,52 84,52 96,56" stroke="#fff" stroke-width="6" fill="none" opacity="0.5" stroke-linecap="round"/></g>'
            # la vapeur
            '<path d="M380,250 q-30,-50 0,-100 q30,-50 0,-100 M512,230 q-30,-50 0,-100 q30,-50 0,-100 M644,250 q-30,-50 0,-100 q30,-50 0,-100" stroke="#fff" stroke-width="26" fill="none" opacity="0.7" stroke-linecap="round"/>')
    return svg(1024, 1024, body, defs)
