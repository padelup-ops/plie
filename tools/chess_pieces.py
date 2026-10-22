"""Pièces d'échecs vectorielles (boîte 100 × 100) : aperçu SVG et génération du code Swift."""
BASE = [("rr", 21, 83, 79, 93, 4.5)]
FOOT = [("p", "M 27 85 C 29 79 33 76.5 36 75 L 64 75 C 67 76.5 71 79 73 85 Z")]

PIECES = {
    "pawn": {
        "shapes": BASE + FOOT + [
            ("p", "M 38.5 76 C 40.5 67 43.5 61 44.5 55 L 55.5 55 C 56.5 61 59.5 67 61.5 76 Z"),
            ("e", 50, 54, 12.5, 3.6),
            ("c", 50, 40, 12.5),
        ],
        "details": [],
    },
    "rook": {
        "shapes": BASE + FOOT + [
            ("p", "M 35.5 76 L 37.5 46 L 62.5 46 L 64.5 76 Z"),
            ("rr", 32, 41, 68, 48, 2.5),
            ("p", "M 31 43 L 31 21 L 39.5 21 L 39.5 27.5 L 46 27.5 L 46 21 L 54 21 L 54 27.5 L 60.5 27.5 L 60.5 21 L 69 21 L 69 43 Z"),
        ],
        "details": [("ln", 34, 36, 66, 36), ("ln", 37.5, 52, 62.5, 52)],
    },
    "knight": {
        "shapes": BASE + FOOT + [
            ("p", "M 31 76 C 31 66 36 58 44 51 C 40 50.5 34 52 30 54.5 C 26 57 21 55.5 19.5 51.5 C 18 47.5 20 43 23 39 "
                  "C 27 33 31 27 35 22 C 37.5 18.5 40 16 42.5 14.5 L 43 8 L 48 13 C 49.5 12.8 51 12.8 52.5 13 L 56 8 L 57 14.5 "
                  "C 67 18 73 28 73.5 41 C 74 54 70 64 69 76 Z"),
        ],
        "details": [("dc", 37.5, 27, 2.6), ("dc", 23.2, 47, 1.5), ("dp", "M 57 16 C 64 21 68.5 30 69 42")],
    },
    "bishop": {
        "shapes": BASE + FOOT + [
            ("p", "M 38 76 C 40 67 43 61 43.5 55 L 56.5 55 C 57 61 60 67 62 76 Z"),
            ("e", 50, 53.5, 14, 3.8),
            ("p", "M 50 15 C 39 24 34.5 32.5 36 40 C 37.5 47 43.5 50.5 50 50.5 C 56.5 50.5 62.5 47 64 40 C 65.5 32.5 61 24 50 15 Z"),
            ("c", 50, 12.5, 4.6),
        ],
        "details": [("dp", "M 56.5 25 L 47.5 37")],
    },
    "queen": {
        "shapes": BASE + FOOT + [
            ("p", "M 34.5 76 C 37.5 63 41 53 42 45 L 58 45 C 59 53 62.5 63 65.5 76 Z"),
            ("e", 50, 44, 15.5, 4.2),
            ("p", "M 31 43 L 24 20 L 34 31.5 L 37.5 13 L 44.5 29.5 L 50 9 L 55.5 29.5 L 62.5 13 L 66 31.5 L 76 20 L 69 43 Z"),
            ("c", 24, 19, 3.9), ("c", 37.5, 12, 3.9), ("c", 50, 8, 3.9), ("c", 62.5, 12, 3.9), ("c", 76, 19, 3.9),
        ],
        "details": [("ln", 32.5, 38, 67.5, 38)],
    },
    "king": {
        "shapes": BASE + FOOT + [
            ("p", "M 34.5 76 C 37.5 63 41 53 42 45 L 58 45 C 59 53 62.5 63 65.5 76 Z"),
            ("e", 50, 44, 15.5, 4.2),
            ("p", "M 33 43 C 29.5 32 37 25 50 25 C 63 25 70.5 32 67 43 Z"),
            ("rr", 46.8, 3.5, 53.2, 26.5, 1.6),
            ("rr", 40.5, 9.5, 59.5, 15.9, 1.6),
        ],
        "details": [("ln", 35.5, 37.5, 64.5, 37.5)],
    },
}


def svg_shape(s):
    k = s[0]
    if k == "rr":
        _, x0, y0, x1, y1, r = s
        return f'<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{y1-y0}" rx="{r}"/>'
    if k == "c":
        return f'<circle cx="{s[1]}" cy="{s[2]}" r="{s[3]}"/>'
    if k == "e":
        return f'<ellipse cx="{s[1]}" cy="{s[2]}" rx="{s[3]}" ry="{s[4]}"/>'
    return f'<path d="{s[1]}"/>'


def svg_piece(name, white, x, y, size, uid):
    sc = size / 100
    shapes = "".join(svg_shape(s) for s in PIECES[name]["shapes"])
    if white:
        fill = f"url(#ivory{uid})"; outline = "#2A1D12"; detail = "#2A1D12"; dop = 0.55
        grad = f'<linearGradient id="ivory{uid}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="0.55" stop-color="#F3EAD8"/><stop offset="1" stop-color="#D6C3A0"/></linearGradient>'
    else:
        fill = f"url(#ebony{uid})"; outline = "#050507"; detail = "#D8D8E6"; dop = 0.5
        grad = f'<linearGradient id="ebony{uid}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5A5A68"/><stop offset="0.5" stop-color="#2A2A33"/><stop offset="1" stop-color="#0C0C10"/></linearGradient>'
    det = ""
    for d in PIECES[name]["details"]:
        if d[0] == "ln":
            det += f'<line x1="{d[1]}" y1="{d[2]}" x2="{d[3]}" y2="{d[4]}" stroke="{detail}" stroke-opacity="{dop}" stroke-width="2.2" stroke-linecap="round"/>'
        elif d[0] == "dp":
            det += f'<path d="{d[1]}" fill="none" stroke="{detail}" stroke-opacity="{dop}" stroke-width="2.2" stroke-linecap="round"/>'
        elif d[0] == "dc":
            det += f'<circle cx="{d[1]}" cy="{d[2]}" r="{d[3]}" fill="{detail}" fill-opacity="0.85"/>'
    sheen = f'<linearGradient id="sheen{uid}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff" stop-opacity="{0.45 if white else 0.32}"/><stop offset="0.45" stop-color="#fff" stop-opacity="0"/></linearGradient>'
    rim = "" if white else f'<g fill="none" stroke="#B9B9CC" stroke-opacity="0.45" stroke-width="1.6">{shapes}</g>'
    return f'''<g transform="translate({x} {y}) scale({sc})">
<defs>{grad}{sheen}<clipPath id="clip{uid}">{shapes}</clipPath><filter id="sh{uid}"><feGaussianBlur stdDeviation="2.2"/></filter></defs>
<g transform="translate(3 4)" fill="#000" fill-opacity="0.38" filter="url(#sh{uid})">{shapes}</g>
<g fill="none" stroke="{outline}" stroke-width="5" stroke-linejoin="round">{shapes}</g>
<g fill="{fill}">{shapes}</g>
{rim}
<g clip-path="url(#clip{uid})"><rect x="0" y="0" width="100" height="100" fill="url(#sheen{uid})"/></g>
{det}
</g>'''


if __name__ == "__main__":
    import sys
    from playwright.sync_api import sync_playwright
    names = ["king", "queen", "rook", "bishop", "knight", "pawn"]
    W, H = 760, 300
    parts = []
    uid = 0
    for row, white in enumerate([True, False]):
        for i, n in enumerate(names):
            parts.append(svg_piece(n, white, 20 + i * 122, 20 + row * 135, 110, uid)); uid += 1
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}"><rect width="{W}" height="{H}" fill="#B07A4A"/>{"".join(parts)}</svg>'
    with sync_playwright() as p:
        b = p.chromium.launch(); pg = b.new_page(viewport={"width": W, "height": H})
        pg.set_content(f'<html><body style="margin:0">{svg}</body></html>'); pg.screenshot(path="pieces.png"); b.close()
    print("ok")
