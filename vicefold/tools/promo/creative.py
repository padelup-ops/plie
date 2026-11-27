"""VICEFOLD: the App Store "creative assets" (iOS 27) — the header video of the product page (21:9, 3840 x 1646)
and the search results video (3:2, 2400 x 1600). A silent 12 s loop with no jump, in English and French.

  python3 assets.py <work>                       the pictures (run once)
  python3 creative.py <work> en|fr header|search [t1 t2 ...]
Without times: ../../store/creative/<locale>/<kind>.mp4, where the release workflow picks them up.
With times: still frames in <work>/creative-test, to check.
The poster is the frame at half a second (see clapet/tools/asc_assets.py), so the title is on every frame.
"""
import json
import os
import subprocess
import sys
from multiprocessing import Process

HERE = os.path.dirname(os.path.abspath(__file__))
FPS, DUR = 30, 12
SIZES = {"header": (1920, 823), "search": (1200, 800)}       # drawn at 2x: 3840 x 1646 and 2400 x 1600
LOCALE = {"en": "en-US", "fr": "fr-FR"}
TEXTS = {
    "en": {"brand": "Guide for GTA VI: Leonida", "title": ["Your Leonida,", "at 100%."], "sub": "Every mission, every secret, every cheat.",
           "chips": ["91 missions", "600-place map", "Spoiler-free"]},
    "fr": {"brand": "Guide pour GTA VI : Leonida", "title": ["Ton Leonida,", "à 100 %."], "sub": "Chaque mission, chaque secret, chaque code.",
           "chips": ["91 missions", "Carte de 600 lieux", "Sans spoiler"]},
}

# Same page as Foldly's header: light, Inter Display Black for the title, the second line in the app's colours.
CSS = """
html,body{margin:0;background:#F4F7F8}
#stage{position:relative;overflow:hidden;font-family:Inter,sans-serif;color:#0E1B2B;background:#F4F7F8}
#bg{position:absolute;left:0;top:0}
.brand{display:flex;align-items:center;gap:14px;font:500 28px Inter;color:#5B6472;letter-spacing:-.01em}
.brand img{width:56px;height:56px;border-radius:23%;box-shadow:0 4px 14px rgba(14,27,43,.18)}
.title{font:900 104px/1.03 'Inter Display',Inter;letter-spacing:-.035em;color:#10151C}
.title div{white-space:nowrap}
.title .acc{background:linear-gradient(95deg,#FF8A3D,#FF4F8B 55%,#7B5CFF);-webkit-background-clip:text;background-clip:text;color:transparent;padding-bottom:.12em;margin-bottom:-.12em;display:inline-block}
.sub{font:500 33px/1.3 Inter;color:#3B4452;letter-spacing:-.015em}
.chips{display:flex;gap:14px}
.chips span{font:600 25px Inter;color:#10151C;padding:13px 22px;border-radius:999px;background:#fff;box-shadow:0 6px 22px rgba(14,27,43,.10),0 0 0 1px rgba(14,27,43,.04);white-space:nowrap;letter-spacing:-.01em}
.header .txt{position:absolute;left:148px;top:0;height:823px;display:flex;flex-direction:column;justify-content:center}
.header .title{margin:20px 0 26px}
.header .sub{margin-bottom:34px}
.search .txt{position:absolute;left:0;right:0;top:44px;display:flex;flex-direction:column;align-items:center;text-align:center}
.search .brand{font-size:25px}
.search .brand img{width:46px;height:46px}
.search .title{font-size:74px;margin:10px 0 12px}
.search .sub{font-size:27px}
.search .chips{display:none}
.persp{position:absolute;inset:0;perspective:2200px;perspective-origin:__PO__;transform-style:preserve-3d}
.ground{position:absolute;border-radius:50%;background:rgba(14,27,43,.34);filter:blur(26px)}
.dev{position:absolute;transform-style:preserve-3d}
.dev .half{position:absolute;top:0;width:50%;height:100%;transform-style:preserve-3d}
.dev .half.left{left:0;transform-origin:100% 50%}
.dev .half.right{left:50%}
.dev .face{position:absolute;inset:0;overflow:hidden;background:#EAF6F5;box-shadow:0 0 0 var(--bz) #0d1118,0 0 0 calc(var(--bz) + 2px) #5a6272}
.dev .half.left .face{border-radius:var(--r) 0 0 var(--r)}
.dev .half.right .face{border-radius:0 var(--r) var(--r) 0}
.dev .face img{position:absolute;left:0;top:0;max-width:none}
.dev .shade{position:absolute;inset:0;background:#0E1B2B;opacity:0}
.dev .hinge{position:absolute;left:47.6%;width:4.8%;top:0;bottom:0;background:linear-gradient(90deg,#05070b,#232936 50%,#05070b);transform:translateZ(1px)}
"""
HTML = """<!doctype html><html><head><meta charset="utf-8"><style>__CSS__</style></head><body>
<div id="stage"><canvas id="bg"></canvas></div>
<script>const DATA=__DATA__;const TEXTS=__TEXTS__;</script><script>__JS__</script></body></html>"""


def page(work, kind):
    css = CSS.replace("__PO__", "1340px 398px" if kind == "header" else "600px 540px")
    html = (HTML.replace("__CSS__", css).replace("__DATA__", open(os.path.join(work, "data.json")).read())
            .replace("__TEXTS__", json.dumps(TEXTS, ensure_ascii=False)).replace("__JS__", open(os.path.join(HERE, "creative.js")).read()))
    path = os.path.join(work, f"creative-{kind}.html")
    open(path, "w").write(html)
    return path


def shoot(path, kind, lang, jobs, out):
    from playwright.sync_api import sync_playwright
    w, h = SIZES[kind]
    with sync_playwright() as p:
        local = "/opt/pw-browsers/chromium"
        b = p.chromium.launch(executable_path=local if os.path.exists(local) else None,
                              args=["--enable-gpu-rasterization", "--ignore-gpu-blocklist", "--force-color-profile=srgb"])
        pg = b.new_page(viewport={"width": w, "height": h}, device_scale_factor=2)
        errors = []
        pg.on("pageerror", lambda e: errors.append(str(e)))
        pg.goto("file://" + os.path.abspath(path) + f"?kind={kind}&lang={lang}")
        pg.evaluate("ready()")
        pg.wait_for_timeout(300)
        for i, t in jobs:
            pg.evaluate(f"render({t})")
            pg.screenshot(path=os.path.join(out, f"f{i:05d}.jpg"), type="jpeg", quality=96)
        b.close()
        if errors:
            print("JS ERRORS:", errors[:5])


def main():
    work, lang, kind = sys.argv[1], sys.argv[2], sys.argv[3]
    path = page(work, kind)
    if len(sys.argv) > 4:
        out = os.path.join(work, "creative-test")
        os.makedirs(out, exist_ok=True)
        shoot(path, kind, lang, [(round(float(x) * 100), float(x)) for x in sys.argv[4:]], out)
        return
    out = os.path.join(work, f"creative-{kind}-{lang}")
    os.makedirs(out, exist_ok=True)
    jobs = [(i, i / FPS) for i in range(FPS * DUR)]
    ps = [Process(target=shoot, args=(path, kind, lang, jobs[k::4], out)) for k in range(4)]
    [p.start() for p in ps]
    [p.join() for p in ps]
    dest = os.path.join(HERE, "..", "..", "store", "creative", LOCALE[lang])
    os.makedirs(dest, exist_ok=True)
    film = os.path.join(dest, f"{kind}.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(out, "f%05d.jpg"), "-c:v", "libx264", "-preset", "medium",
                    "-crf", "17", "-profile:v", "high", "-level:v", "5.1", "-pix_fmt", "yuv420p", "-tag:v", "avc1", "-movflags", "+faststart", "-an", film], check=True)
    print(os.path.normpath(film), f"{os.path.getsize(film) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
