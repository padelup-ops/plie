"""VICEFOLD : dessine l'icône (le repère néon) et ses 8 variantes (originales : soleil rétro, palmier, flamant…), sans aucun visuel du jeu."""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
ROOT = os.path.join(os.path.dirname(__file__), "..", "App", "Assets.xcassets")

def grad(top, bottom, size=S):
    im = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(im)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return im

def sun(im, cx, cy, r, c1, c2, stripes=True, bg=None):
    sunimg = grad(c1, c2, S)
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    if stripes:
        for i in range(5):
            y = cy + r * (0.15 + i * 0.17)
            h = 10 + i * 7
            md.rectangle([0, y, S, y + h], fill=0)
    im.paste(sunimg, (0, 0), mask)

def sea(im, top, col, lines=None):
    d = ImageDraw.Draw(im)
    d.rectangle([0, top, S, S], fill=col)
    if lines:
        for i in range(6):
            y = top + 40 + i * 52
            w = 120 + i * 60
            d.rounded_rectangle([S / 2 - w, y, S / 2 + w, y + 10], radius=5, fill=lines)

def palm(im, x, y, scale, col):
    d = ImageDraw.Draw(im)
    pts = []
    for i in range(40):
        t = i / 39
        pts.append((x + math.sin(t * 1.6) * 60 * scale, y - t * 520 * scale))
    for i in range(len(pts) - 1):
        d.line([pts[i], pts[i + 1]], fill=col, width=int(34 * scale * (1 - i / 60)))
    tx, ty = pts[-1]
    for a in (-160, -120, -70, -20, 20, 60):
        rad = math.radians(a)
        p0 = (tx, ty)
        p1 = (tx + math.cos(rad) * 150 * scale, ty + math.sin(rad) * 80 * scale - 40 * scale)
        p2 = (tx + math.cos(rad) * 280 * scale, ty + math.sin(rad) * 60 * scale + 60 * scale)
        d.line([p0, p1, p2], fill=col, width=int(30 * scale), joint="curve")

def flamingo(im, col):
    d = ImageDraw.Draw(im)
    d.ellipse([360, 470, 700, 660], fill=col)                      # corps
    d.line([(560, 500), (600, 380), (520, 300), (470, 330)], fill=col, width=34, joint="curve")  # cou
    d.ellipse([440, 300, 500, 350], fill=col)                      # tête
    d.polygon([(445, 330), (400, 360), (448, 345)], fill=(40, 30, 40))  # bec
    d.line([(520, 650), (520, 880)], fill=col, width=14)
    d.line([(560, 650), (580, 760), (520, 780)], fill=col, width=14)

def moon(im):
    d = ImageDraw.Draw(im)
    d.ellipse([330, 210, 690, 570], fill=(250, 240, 220))
    d.ellipse([420, 170, 780, 530], fill=(22, 26, 60))
    for (x, y, r) in [(200, 200, 6), (820, 300, 5), (260, 420, 4), (760, 150, 7), (880, 520, 4), (150, 600, 5)]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255))


def leonida():
    """L'icône principale : un repère de carte au dégradé néon (bleu, violet, rose, orange), contour doré, et un
    soleil couchant dans son œil. Dessin original."""
    from PIL import ImageChops
    K = 2; SS = 1024 * K
    def vgrad(stops, size=SS):
        im = Image.new("RGB", (size, size)); d = ImageDraw.Draw(im)
        for y in range(size):
            t = y / (size - 1)
            for i in range(len(stops) - 1):
                a, ca = stops[i]; b, cb = stops[i + 1]
                if a <= t <= b:
                    u = (t - a) / (b - a); c = tuple(int(ca[j] + (cb[j] - ca[j]) * u) for j in range(3)); break
            d.line([(0, y), (size, y)], fill=c)
        return im
    def pin_mask(cx, cy, r, tip, grow=0):
        m = Image.new("L", (SS, SS), 0); d = ImageDraw.Draw(m)
        R = r + grow
        d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=255)
        k = math.sin(math.acos(R / (tip - cy)))
        left = (cx - R * k, cy + R * R / (tip - cy)); right = (cx + R * k, cy + R * R / (tip - cy))
        d.polygon([left, right, (cx, tip + grow * 1.6)], fill=255)
        return m
    S_ = SS
    cx, cy, r, tip =512 * K, 430 * K, 285 * K, 905 * K
    im = Image.new("RGB", (S_, S_), (8, 6, 14))
    # lueur magenta derrière
    glow = Image.new("RGB", (S_, S_), (0, 0, 0)); glow.paste((230, 40, 150), (0, 0), pin_mask(cx, cy, r, tip, 40 * K))
    im = ImageChops.add(im, glow.filter(ImageFilter.GaussianBlur(60 * K)).point(lambda v: int(v * 0.55)))
    # contour violet foncé, puis or, puis le dégradé
    im.paste((70, 20, 90), (0, 0), pin_mask(cx, cy, r, tip, 34 * K))
    gold = vgrad([(0, (255, 214, 90)), (1, (255, 140, 40))])
    im.paste(gold, (0, 0), pin_mask(cx, cy, r, tip, 22 * K))
    fill = vgrad([(0.0, (70, 110, 255)), (0.28, (190, 70, 230)), (0.55, (255, 60, 150)), (0.8, (255, 120, 90)), (1.0, (255, 200, 80))])
    # reflets marbrés légers
    sheen = Image.new("L", (S_, S_), 0); sd = ImageDraw.Draw(sheen)
    for i in range(7):
        y = 200 * K + i * 95 * K
        sd.arc([cx - 520 * K, y - 300 * K, cx + 520 * K, y + 300 * K], 200, 340, fill=60, width=14 * K)
    sheen = sheen.filter(ImageFilter.GaussianBlur(10 * K))
    fill = Image.composite(Image.new("RGB", (S_, S_), (255, 255, 255)), fill, sheen)
    im.paste(fill, (0, 0), pin_mask(cx, cy, r, tip, 0))
    # le trou du repère : un soleil couchant rayé sur fond nuit
    hr = 128 * K
    hole = Image.new("L", (S_, S_), 0); ImageDraw.Draw(hole).ellipse([cx - hr - 16 * K, cy - hr - 16 * K, cx + hr + 16 * K, cy + hr + 16 * K], fill=255)
    im.paste((70, 20, 90), (0, 0), hole)
    hole2 = Image.new("L", (S_, S_), 0); ImageDraw.Draw(hole2).ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=255)
    im.paste((16, 10, 34), (0, 0), hole2)
    sun = vgrad([(0, (255, 214, 90)), (1, (255, 70, 150))])
    sm = Image.new("L", (S_, S_), 0); smd = ImageDraw.Draw(sm)
    sr = 92 * K; scy = cy + 20 * K
    smd.ellipse([cx - sr, scy - sr, cx + sr, scy + sr], fill=255)
    for i in range(4):
        y = scy + sr * (0.05 + i * 0.24); h = (6 + i * 5) * K
        smd.rectangle([0, y, S_, y + h], fill=0)
    smd.rectangle([0, scy + sr * 0.98, S_, S_], fill=0)
    sm = ImageChops.multiply(sm, hole2)
    im.paste(sun, (0, 0), sm)
    return im.resize((S, S), Image.LANCZOS)


def make(name):
    if name == "AppIcon":
        im = leonida()
    elif name == "IconSunrise":
        im = grad((255, 196, 92), (232, 62, 140)); sun(im, 512, 520, 300, (255, 240, 150), (255, 106, 92)); sea(im, 640, (28, 188, 184), (120, 230, 220))
    elif name == "IconSunset":
        im = grad((60, 20, 90), (240, 90, 120)); sun(im, 512, 560, 280, (255, 210, 110), (240, 80, 110)); sea(im, 680, (40, 30, 80), (130, 70, 150))
    elif name == "IconNeon":
        im = Image.new("RGB", (S, S), (12, 10, 26)); d = ImageDraw.Draw(im)
        glow = Image.new("RGB", (S, S), (0, 0, 0)); g = ImageDraw.Draw(glow)
        for r, c in [(300, (255, 60, 170)), (230, (60, 230, 255))]:
            g.ellipse([512 - r, 512 - r, 512 + r, 512 + r], outline=c, width=26)
        for i in range(5):
            g.line([(180, 700 + i * 50), (844, 700 + i * 50)], fill=(60, 230, 255), width=8)
        im = Image.blend(im, glow.filter(ImageFilter.GaussianBlur(18)), 0.9); im.paste(glow, (0, 0), glow.convert("L"))
    elif name == "IconPalm":
        im = grad((255, 170, 80), (230, 70, 120)); sun(im, 560, 470, 250, (255, 236, 150), (255, 120, 90)); sea(im, 690, (20, 120, 140)); palm(im, 330, 1000, 1.25, (25, 18, 40))
    elif name == "IconFlamingo":
        im = grad((255, 214, 226), (255, 150, 190)); flamingo(im, (240, 70, 130)); sea(im, 860, (110, 210, 220))
    elif name == "IconMidnight":
        im = grad((22, 26, 60), (60, 40, 110)); moon(im); sea(im, 700, (14, 18, 40), (60, 70, 140))
    elif name == "IconSwamp":
        im = grad((170, 210, 150), (60, 120, 90)); sun(im, 512, 470, 230, (255, 240, 180), (240, 190, 90), stripes=False)
        d = ImageDraw.Draw(im)
        for x in range(60, 1000, 70):
            d.line([(x, 1024), (x + 20, 620 + (x * 37) % 160)], fill=(30, 70, 50), width=16)
        sea(im, 820, (40, 90, 80), (110, 170, 150))
    elif name == "IconChrome":
        im = grad((235, 238, 245), (120, 128, 145)); sun(im, 512, 520, 300, (255, 255, 255), (150, 160, 180)); sea(im, 650, (70, 78, 95), (180, 188, 205))
    return im

names = ["AppIcon", "IconSunrise", "IconSunset", "IconNeon", "IconPalm", "IconFlamingo", "IconMidnight", "IconSwamp", "IconChrome"]
os.makedirs(ROOT, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(ROOT, "Contents.json"), "w"))
for n in names:
    im = make(n)
    d = os.path.join(ROOT, f"{n}.appiconset"); os.makedirs(d, exist_ok=True)
    im.save(os.path.join(d, "icon-1024.png"))
    json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"))
    p = os.path.join(ROOT, f"{n}Preview.imageset"); os.makedirs(p, exist_ok=True)
    im.resize((180, 180), Image.LANCZOS).save(os.path.join(p, "preview.png"))
    json.dump({"images": [{"filename": "preview.png", "idiom": "universal", "scale": "3x"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(p, "Contents.json"), "w"))
ac = os.path.join(ROOT, "AccentColor.colorset"); os.makedirs(ac, exist_ok=True)
json.dump({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "1.000", "green": "0.420", "blue": "0.360", "alpha": "1.000"}}}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(ac, "Contents.json"), "w"))
# Planche de contrôle
sheet = Image.new("RGB", (len(names) * 200, 200), "white")
for i, n in enumerate(names):
    sheet.paste(make(n).resize((180, 180)), (i * 200 + 10, 10))
sheet.save(sys.argv[1] if len(sys.argv) > 1 else "/tmp/vf-icons.png")
print("ok")
