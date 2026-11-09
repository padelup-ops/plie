"""Compose les captures de l'App Store de Foldboard : un titre, puis la vraie capture du simulateur.

Usage : python3 compose.py <dossier des captures brutes> <dossier de sortie>
Entrées : duo-<lang>-0N-<écran>-in.png (écran déplié) et -out.png (écran extérieur).
Sorties : duo-<lang>-N.png (2007×2853, iPhone Duo) et <lang>-N.png (1290×2796, iPhone 6,7").
"""
import base64, os, sys
from PIL import Image
from playwright.sync_api import sync_playwright

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
ROUTES = ["right", "split", "left", "themes", "pro"]
CAP = {
    "fr": {"right": ("Il vient du côté", "de ta main"), "split": ("À deux mains,", "il se coupe en deux"),
           "split-out": ("Pleine largeur sur", "l’écran extérieur"), "left": ("Tes phrases", "en un toucher"),
           "themes": ("Couleurs, polices,", "sons et vibrations"), "pro": ("Essai gratuit", "de 3 jours")},
    "en": {"right": ("It comes to the side", "of your hand"), "split": ("Two hands?", "It splits in two"),
           "split-out": ("Full width on", "the outer screen"), "left": ("Your phrases", "in one tap"),
           "themes": ("Colors, fonts,", "sounds and haptics"), "pro": ("Free 3-day", "trial")},
}
HTML = """<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:%(w)dpx;height:%(h)dpx;overflow:hidden}
body{background:radial-gradient(%(w)dpx %(h)dpx at 20%% 0%%,#3a6df0 0%%,rgba(58,109,240,0) 55%%),linear-gradient(165deg,#1b2a6b 0%%,#0b1030 100%%);
 font-family:"Inter Display","Inter",-apple-system,sans-serif;color:#fff}
.t{position:absolute;left:0;right:0;top:%(ty)dpx;text-align:center;font-weight:800;font-size:%(fs)dpx;line-height:1.08;letter-spacing:-.02em}
.t b{display:block;background:linear-gradient(90deg,#7fd8ff,#53e3b0);-webkit-background-clip:text;background-clip:text;color:transparent}
.s{position:absolute;left:50%%;top:%(sy)dpx;transform:translateX(-50%%);width:%(sw)dpx;border-radius:%(r)dpx;overflow:hidden;
 box-shadow:0 30px 90px rgba(0,0,0,.45),0 0 0 %(bw)dpx #0a0c14}
.s img{display:block;width:100%%}
</style></head><body><div class="t">%(l1)s<b>%(l2)s</b></div><div class="s"><img src="data:image/png;base64,%(img)s"></div></body></html>"""

def render(page, w, h, shot, l1, l2, out):
    iw, ih = Image.open(shot).size
    sy = int(h * 0.2)
    sw = int(min(w * 0.88, (h - sy - h * 0.035) * iw / ih))
    sh = sw * ih / iw
    top = int(sy + max(0, (h - sy - sh) / 2 - h * 0.02))
    ty = int(max(h * 0.05, (top - w * 0.09 * 2.2) / 2))
    params = dict(w=w, h=h, ty=ty, fs=int(w * 0.088), sy=top, sw=sw, r=int(sw * 0.07), bw=int(w * 0.012),
                  l1=l1, l2=l2, img=base64.b64encode(open(shot, "rb").read()).decode())
    page.set_viewport_size({"width": w, "height": h})
    page.set_content(HTML % params)
    page.evaluate("document.fonts.ready")
    page.wait_for_timeout(150)
    page.screenshot(path=out)

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page()
    for lang in ("fr", "en"):
        n_duo = n_ph = 0
        for i, r in enumerate(ROUTES, 1):
            inner = os.path.join(SRC, f"duo-{lang}-{i:02d}-{r}-in.png")
            outer = os.path.join(SRC, f"duo-{lang}-{i:02d}-{r}-out.png")
            if os.path.exists(inner):
                n_duo += 1
                l1, l2 = CAP[lang][r]
                render(pg, 2007, 2853, inner, l1, l2, os.path.join(OUT, f"duo-{lang}-{n_duo}.png"))
            if os.path.exists(outer):
                n_ph += 1
                l1, l2 = CAP[lang]["split-out" if r == "split" else r]
                render(pg, 1290, 2796, outer, l1, l2, os.path.join(OUT, f"{lang}-{n_ph}.png"))
        print(lang, "duo", n_duo, "iphone", n_ph)
    b.close()
