"""Dessine les illustrations de Waffle Fold en PNG dans Waffle/Assets.xcassets.

python3 waffle/art/build.py [--sheet planche.png]
"""
import json
import os
import sys

from playwright.sync_api import sync_playwright

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Waffle", "Assets.xcassets")


def items():
    out = {}
    for lvl in range(5):
        out[f"waffle{lvl}"] = (art.waffle(lvl), 3)
    out["batter"] = (art.batter(), 3)
    out["jug"] = (art.jug(), 3)
    for name, fn in art.INGREDIENTS.items():
        out[f"ing_{name}"] = (fn(), 3)
    out["iron_base"] = (art.iron("base"), 2)
    out["iron_lid"] = (art.iron("lid"), 2)
    out["iron_closed"] = (art.iron_closed(), 2)
    for i in range(len(art.CUSTOMERS)):
        for mood in ("wait", "happy", "angry"):
            out[f"cust{i}_{mood}"] = (art.customer(i, mood), 2)
    out["coin"] = (art.coin(), 3)
    out["star_on"] = (art.star(True), 3)
    out["star_off"] = (art.star(False), 3)
    out["wall_tile"] = (art.wall_tile(), 3)
    return out


def imageset(name, png):
    folder = os.path.join(ROOT, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, name + ".png"), "wb") as f:
        f.write(png)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": name + ".png", "idiom": "universal", "scale": "3x"}],
                   "info": {"author": "xcode", "version": 1}}, f)


def main():
    os.makedirs(ROOT, exist_ok=True)
    with open(os.path.join(ROOT, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f)
    rendered = {}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for name, (svg, scale) in items().items():
            w = int(svg.split('width="')[1].split('"')[0])
            h = int(svg.split('height="')[1].split('"')[0])
            # Les PNG sont à ×3 de la taille en points voulue : taille en points = SVG / scale... on garde simple :
            # l'image fait (w, h) pixels SVG × (3 / scale) ; l'app l'affiche redimensionnée de toute façon.
            factor = 3 / scale
            page = browser.new_page(viewport={"width": w, "height": h}, device_scale_factor=factor)
            page.set_content(f'<html><body style="margin:0;background:transparent">{svg}</body></html>')
            png = page.locator("svg").screenshot(omit_background=True)
            page.close()
            imageset(name, png)
            rendered[name] = svg
        # L'icône (sans transparence)
        page = browser.new_page(viewport={"width": 1024, "height": 1024}, device_scale_factor=1)
        page.set_content(f'<html><body style="margin:0">{art.icon()}</body></html>')
        png = page.locator("svg").screenshot()
        page.close()
        folder = os.path.join(ROOT, "AppIcon.appiconset")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "icon.png"), "wb") as f:
            f.write(png)
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump({"images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                       "info": {"author": "xcode", "version": 1}}, f)
        if "--sheet" in sys.argv:
            out = sys.argv[sys.argv.index("--sheet") + 1]
            cells = "".join(f'<div style="display:inline-block;margin:6px;text-align:center;font:11px sans-serif">'
                            f'<div style="width:150px;height:150px;display:flex;align-items:center;justify-content:center;background:#F3E9D8">'
                            f'<div style="max-width:150px;max-height:150px;transform-origin:center">{s.replace("<svg ", "<svg style=\'max-width:150px;max-height:150px;width:auto;height:auto\' ")}</div></div>{n}</div>'
                            for n, s in rendered.items())
            page = browser.new_page(viewport={"width": 1300, "height": 900})
            page.set_content(f'<html><body style="margin:10px;background:#fff">{cells}<div style="display:inline-block;width:300px">{art.icon().replace("<svg ", "<svg style=\'width:280px;height:280px\' ")}</div></body></html>')
            page.screenshot(path=out, full_page=True)
            page.close()
        browser.close()
    print(len(rendered), "illustrations")


if __name__ == "__main__":
    main()
