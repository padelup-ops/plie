"""VICEFOLD : compose les captures de l'App Store (titre + vraie capture du simulateur), en anglais et en français.

Usage : python3 compose.py <brutes> <sortie>
Brutes : <appareil>-<lang>/NN-<écran>.png  (appareil : duo, iphone, ipad)
Sorties : duo-<lang>-N.png (2007×2853), <lang>-N.png (1290×2796), ipad-<lang>-N.png (2064×2752).
"""
import base64
import os
import sys

from PIL import Image
from playwright.sync_api import sync_playwright

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
ROUTES = ["home", "mappins", "mission", "collectibles", "eggs", "widgets", "guide", "characters"]
C = {
    "en": {"home": ("Your Leonida,", "at 100%"), "mappins": ("A detailed map,", "600 places and your pins"), "mission": ("All 91 missions,", "spoiler-free"),
           "collectibles": ("Every 100% category,", "with a counter"), "eggs": ("Every easter egg,", "spoiler-free"), "guide": ("Guides for", "every part of the game"), "characters": ("Who's who,", "with your notes"), "widgets": ("Progress widgets,", "synced with iCloud")},
    "fr": {"home": ("Ton Leonida,", "à 100 %"), "mappins": ("Une carte détaillée,", "600 lieux et tes épingles"), "mission": ("Les 91 missions,", "sans spoiler"),
           "collectibles": ("Tout le 100 %,", "avec un compteur"), "eggs": ("Tous les easter eggs,", "sans spoiler"), "guide": ("Des guides pour", "tout le jeu"), "characters": ("Qui est qui,", "avec tes notes"), "widgets": ("Widgets de progression,", "synchro iCloud")},
}
SIZES = {"duo": (2007, 2853, "duo-"), "iphone": (1290, 2796, ""), "ipad": (2064, 2752, "ipad-")}
ANTON = base64.b64encode(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Fonts", "Anton-Regular.ttf"), "rb").read()).decode()
# Same look as the app and the promo video: pool water, sunset glow, poster titles in Anton.
HTML = """<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:Anton;src:url(data:font/ttf;base64,""" + ANTON + """)}
html,body{margin:0;width:%(w)dpx;height:%(h)dpx;overflow:hidden}
body{background:radial-gradient(%(w)dpx %(w)dpx at 100%% -8%%,rgba(255,201,74,.38),rgba(255,138,61,.16) 40%%,rgba(234,246,245,0) 70%%),
 radial-gradient(%(w)dpx %(w)dpx at 0%% 110%%,rgba(255,79,139,.22),rgba(234,246,245,0) 60%%),#EAF6F5;color:#0E1B2B}
.t{position:absolute;left:0;right:0;top:%(ty)dpx;text-align:center;font-family:Anton;font-size:%(fs)dpx;line-height:1.04;letter-spacing:.01em}
.t b{display:block;font-weight:400;color:#FF4F8B}
.s{position:absolute;left:50%%;top:%(sy)dpx;transform:translateX(-50%%);width:%(sw)dpx;border-radius:%(r)dpx;overflow:hidden;
 box-shadow:0 30px 90px rgba(14,27,43,.28),0 0 0 %(bw)dpx #0b0f16}
.s img{display:block;width:100%%}
</style></head><body><div class="t">%(l1)s<b>%(l2)s</b></div><div class="s"><img src="data:image/png;base64,%(img)s"></div></body></html>"""


def render(page, w, h, shot, l1, l2, out):
    iw, ih = Image.open(shot).size
    sy = int(h * 0.19)
    sw = int(min(w * 0.88, (h - sy - h * 0.035) * iw / ih))
    sh = sw * ih / iw
    top = int(sy + max(0, (h - sy - sh) / 2 - h * 0.015))
    ty = int(max(h * 0.045, (top - w * 0.085 * 2.15) / 2))
    params = dict(w=w, h=h, ty=ty, fs=int(min(w * 0.092, h * 0.044)), sy=top, sw=sw, r=int(sw * 0.06), bw=int(w * 0.011),
                  l1=l1, l2=l2, img=base64.b64encode(open(shot, "rb").read()).decode())
    page.set_viewport_size({"width": w, "height": h})
    page.set_content(HTML % params)
    page.wait_for_timeout(150)
    page.screenshot(path=out)


with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page()
    for dev, (w, h, prefix) in SIZES.items():
        for lang in C:
            d = os.path.join(SRC, f"{dev}-{lang}")
            if not os.path.isdir(d):
                continue
            files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
            n = 0
            for route in ROUTES:
                f = next((x for x in files if f"-{route}" in x), None)
                if not f:
                    continue
                n += 1
                l1, l2 = C[lang][route]
                render(pg, w, h, os.path.join(d, f), l1, l2, os.path.join(OUT, f"{prefix}{lang}-{n}.png"))
                print("ok", dev, lang, n, route)
    b.close()
