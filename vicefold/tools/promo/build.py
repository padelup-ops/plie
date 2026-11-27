"""VICEFOLD promo video (English, for X and vertical feeds).

  python3 assets.py <work>                     the pictures (app captures, map, icon)
  python3 audio.py <work>                      the soundtrack (original music, written here)
  python3 build.py <work> wide|tall [now|soon] the frames, then the film: <work>/vicefold-<format>-<cta>.mp4
  python3 build.py <work> wide now 3.2 10.5    a few still frames, to check a moment
  python3 build.py <work> wide now --link https://apps.apple.com/app/id...   the same film with the link on the last screen
                                               (only the last seconds are drawn again)

Everything on screen is a real capture of the app or drawn here; no game art, logo or footage.
"""
import base64
import json
import os
import subprocess
import sys
import time
from multiprocessing import Process
from urllib.parse import quote

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cues as C

HERE = os.path.dirname(os.path.abspath(__file__))
FPS = 30
SIZES = {"wide": (1920, 1080), "tall": (1080, 1920)}

CSS = """
@font-face{font-family:Anton;src:url(data:font/ttf;base64,__ANTON__)}
html,body{margin:0;background:#091422}
#stage{position:relative;overflow:hidden;font-family:Inter,sans-serif;color:#fff;background:#091422}
#bg{position:absolute;left:0;top:0}
.scene{position:absolute;inset:0}
.persp{position:absolute;inset:0;perspective:2300px;perspective-origin:__PO__;transform-style:preserve-3d}
.txt{position:absolute}
.txt.center{text-align:center}
.kicker{display:inline-flex;align-items:center;gap:14px;font:800 25px Inter;letter-spacing:.2em;text-transform:uppercase;color:#fff;
 padding:11px 22px 11px 22px;border-radius:999px;background:rgba(255,79,139,.2);box-shadow:inset 0 0 0 2px rgba(255,79,139,.85);margin-bottom:26px;white-space:nowrap}
.kicker .pro{font:900 20px Inter;letter-spacing:.12em;color:#0E1B2B;background:linear-gradient(100deg,#FFC94A,#FF8A3D);padding:4px 11px;border-radius:8px}
.head{font-family:Anton;line-height:1.07;letter-spacing:.004em;text-shadow:0 8px 40px rgba(4,10,20,.5)}
.txt.center .head{text-shadow:0 10px 60px rgba(4,10,20,.85),0 2px 10px rgba(4,10,20,.5)}
.line{white-space:nowrap;overflow:hidden;padding:.09em .04em .05em;margin:-.06em -.04em}
.w{display:inline-block;will-change:transform}
.acc{background:linear-gradient(100deg,#FFC94A,#FF8A3D 45%,#FF4F8B);-webkit-background-clip:text;background-clip:text;color:transparent;text-shadow:none}
.sub{font:600 __SUB__px/1.38 Inter;color:rgba(255,255,255,.86);margin-top:30px;text-shadow:0 2px 18px rgba(4,10,20,.7)}
.dev{position:absolute;transform-style:preserve-3d;will-change:transform}
.dev .face{position:absolute;inset:0;border-radius:var(--r);overflow:hidden;background:#EAF6F5;
 box-shadow:0 0 0 var(--bz) #0b0f16,0 0 0 calc(var(--bz) + 2px) #4a5263}
.dev .face>img{display:block;width:100%;height:100%}
.dev .shadow{position:absolute;inset:6% -2% -8% -2%;border-radius:var(--r);background:rgba(2,6,14,.6);filter:blur(46px);transform:translateZ(-80px)}
.dev.duo .half{position:absolute;top:0;width:50%;height:100%;transform-style:preserve-3d}
.dev.duo .half.left{left:0;transform-origin:100% 50%}
.dev.duo .half.right{left:50%}
.dev.duo .half .face{backface-visibility:hidden;-webkit-backface-visibility:hidden}
.dev.duo .half.left .face{border-radius:var(--r) 0 0 var(--r)}
.dev.duo .half.right .face{border-radius:0 var(--r) var(--r) 0}
.dev.duo .half .face>img{width:auto;height:auto;max-width:none}
.dev.duo .backface{position:absolute;inset:0;border-radius:0 var(--r) var(--r) 0;transform:rotateY(180deg);backface-visibility:hidden;-webkit-backface-visibility:hidden;
 background:linear-gradient(135deg,#3a4050,#171b24 45%,#0b0f16);box-shadow:0 0 0 var(--bz) #0b0f16,0 0 0 calc(var(--bz) + 2px) #4a5263}
.dev.duo .backface:after{content:"";position:absolute;right:9%;top:6%;width:22%;aspect-ratio:1;border-radius:26%;background:#0b0f16;box-shadow:inset 0 0 0 3px #2b3140}
.dev.duo .hinge{position:absolute;left:calc(50% - 1px);width:2px;top:0;bottom:0;background:rgba(14,27,43,.07)}
.dev .face>img.alt,.dev.duo .half .face>img.alt{position:absolute;left:0;top:0;opacity:0}
.dark .dev .face{background:#091422;box-shadow:0 0 0 var(--bz) #0b0f16,0 0 0 calc(var(--bz) + 2px) #667086,0 0 90px rgba(255,79,139,.2)}
.dark .blur:after{background:rgba(9,20,34,.45)}
.dark .lock{background:linear-gradient(100deg,#FF8A3D,#FF4F8B)}
.dark .dev.duo .hinge{background:rgba(0,0,0,.2)}
.blur{position:absolute;inset:0;overflow:hidden}
.blur img{width:100%;height:100%;filter:blur(13px) saturate(.7);transform:scale(1.04)}
.blur:after{content:"";position:absolute;inset:0;background:rgba(234,246,245,.35)}
.lock{position:absolute;left:50%;top:72%;display:flex;align-items:center;gap:12px;white-space:nowrap;font:800 __LOCK__px Inter;color:#fff;
 background:#0E1B2B;padding:16px 26px 16px 20px;border-radius:999px;box-shadow:0 14px 40px rgba(14,27,43,.45)}
.lock svg{width:1.5em;height:1.5em}
.chip{position:absolute;display:flex;align-items:center;gap:12px;white-space:nowrap;font:800 __CHIP__px Inter;color:#0E1B2B;background:#fff;
 padding:14px 24px 14px 18px;border-radius:999px;box-shadow:0 16px 44px rgba(2,6,14,.5),0 0 0 1px rgba(14,27,43,.06)}
.chip i{width:.8em;height:.8em;border-radius:50%;display:block}
.ringcard{position:absolute;border-radius:19%;background:#11243A;box-shadow:0 30px 80px rgba(2,6,14,.6),inset 0 0 0 2px rgba(255,255,255,.1);display:grid;place-items:center}
.ringcard svg{position:absolute;inset:9%}
.ringcard.full{box-shadow:0 0 90px rgba(255,138,61,.75),0 30px 80px rgba(2,6,14,.6),inset 0 0 0 3px rgba(255,201,74,.9)}
.ringcard .pct{position:relative;text-align:center}
.ringcard .pct b{display:block;font:400 __PCT__px Anton;line-height:1}
.ringcard .pct span{font:700 __PCTS__px Inter;color:rgba(255,255,255,.7)}
.burst{position:absolute;left:50%;top:50%}
.burst i{position:absolute;left:-11px;top:-11px;width:22px;height:22px;border-radius:50%}
.cheatwrap{position:absolute;transform-style:preserve-3d}
.cheat{position:relative;background:#fff;color:#0E1B2B;border-radius:38px;padding:34px 38px 38px;box-shadow:0 30px 90px rgba(2,6,14,.55)}
.more{display:flex;flex-wrap:wrap;gap:16px;margin-top:34px}
.more span{font:800 __CHIP__px Inter;color:#fff;background:rgba(17,36,58,.92);box-shadow:inset 0 0 0 2px rgba(255,255,255,.16);padding:14px 24px;border-radius:999px;white-space:nowrap}
.cheat.done{box-shadow:0 0 0 5px #FFC94A,0 0 100px rgba(255,138,61,.8),0 30px 90px rgba(2,6,14,.55)}
.ctop{display:flex;justify-content:space-between;align-items:center}
.ctop b{display:block;font:400 __CH__px Anton;line-height:1.05}
.ctop span{font:700 26px Inter;color:#FF4F8B}
.seg{display:flex;background:#EAF6F5;border-radius:999px;padding:6px;font:800 22px Inter}
.seg i{font-style:normal;padding:10px 20px;border-radius:999px;color:rgba(14,27,43,.5)}
.seg i.on{background:#0E1B2B;color:#fff}
.keys{display:flex;flex-wrap:wrap;gap:14px;margin-top:34px}
.key{width:__KEY__px;height:__KEY__px;border-radius:24%;background:#0E1B2B;color:#fff;display:grid;place-items:center;font:800 __KEYF__px Inter;box-shadow:0 8px 0 #060d17}
.key.wide{width:auto;padding:0 26px;font-size:__KEYW__px;background:linear-gradient(100deg,#FF8A3D,#FF4F8B);box-shadow:0 8px 0 #b3285a}
.key.hot{background:linear-gradient(100deg,#FFC94A,#FF8A3D);color:#0E1B2B}
.radio{position:absolute;border-radius:44px;background:linear-gradient(180deg,#5c45db,#FF4F8B 62%,#FF8A3D);box-shadow:0 30px 90px rgba(2,6,14,.55);overflow:hidden}
.eq{position:absolute;left:6%;right:6%;top:8%;height:52%;display:flex;align-items:flex-end;gap:1.2%}
.eq i{flex:1;height:100%;border-radius:999px;background:linear-gradient(180deg,#fff,rgba(255,255,255,.55));transform-origin:50% 100%}
.stations{position:absolute;left:-400px;white-space:nowrap;display:flex;gap:16px}
.stations:nth-of-type(2){bottom:25%}.stations:nth-of-type(3){bottom:13.500%}.stations:nth-of-type(4){bottom:2%}
.stations span{font:800 __ST__px Inter;color:#0E1B2B;background:rgba(255,255,255,.94);padding:12px 24px;border-radius:999px}
.devlabel{position:absolute;font:800 27px Inter;letter-spacing:.06em;color:rgba(255,255,255,.9);white-space:nowrap}
.trust{position:absolute;display:grid;grid-template-columns:1fr 1fr;grid-auto-rows:1fr;gap:26px}
.tcard{background:rgba(17,36,58,.92);border-radius:36px;padding:30px 30px 28px;box-shadow:0 24px 70px rgba(2,6,14,.5),inset 0 0 0 2px rgba(255,255,255,.1);display:flex;flex-direction:column;justify-content:center}
.tcard svg{width:62px;height:62px;margin-bottom:20px}
.tcard b{font:400 __TC__px Anton;line-height:1.08}
.tcard span{font:600 __TCS__px Inter;color:rgba(255,255,255,.72);margin-top:10px}
.endwrap{position:absolute;left:0;right:0;top:__ENDTOP__px;display:flex;flex-direction:column;align-items:center}
.endicon{width:__ICON__px;height:__ICON__px;border-radius:22.500%;box-shadow:0 30px 90px rgba(2,6,14,.7),0 0 0 2px rgba(255,255,255,.14);position:relative;z-index:1}
.halo{position:absolute;left:50%;top:calc(__ICON__px / 2);width:calc(__ICON__px * 3.4);height:calc(__ICON__px * 3.4);border-radius:50%;
 background:radial-gradient(closest-side,rgba(255,79,139,.5),rgba(255,138,61,.22) 45%,rgba(255,138,61,0))}
.endname{font:400 __ENDN__px Anton;line-height:1.06;text-align:center;margin-top:44px;position:relative;z-index:1}
.endname div{overflow:hidden;padding:.08em .05em .04em}
.endname div:nth-child(2){font-size:1.75em;margin-top:-.04em}
.endname span{display:inline-block}
.endtag{font:700 __ENDT__px Inter;color:rgba(255,255,255,.88);margin-top:18px;position:relative;z-index:1}
.cta{margin-top:44px;background:#fff;color:#0E1B2B;border-radius:28px;padding:18px 54px 22px;text-align:center;box-shadow:0 20px 70px rgba(255,79,139,.55);position:relative;z-index:1}
.cta small{display:block;font:700 __CTAS__px Inter;letter-spacing:.02em}
.cta b{display:block;font:800 __CTAB__px 'Inter Display',Inter;letter-spacing:-.02em;line-height:1.05}
.enddevs{font:800 27px Inter;letter-spacing:.05em;color:rgba(255,255,255,.85);margin-top:30px;white-space:pre;position:relative;z-index:1}
.endlink{margin-top:26px;font:700 __ENDT__px 'JetBrains Mono',monospace;color:#fff;padding:12px 26px;border-radius:999px;background:rgba(255,79,139,.2);box-shadow:inset 0 0 0 2px rgba(255,79,139,.85);position:relative;z-index:1}
.legal{position:absolute;left:8%;right:8%;bottom:__LEGALB__px;text-align:center;font:500 __LEGAL__px/1.45 Inter;color:#fff}
.swipe{position:absolute;left:0;top:-10%;width:62%;height:120%;background:linear-gradient(90deg,rgba(255,201,74,0),rgba(255,201,74,.95) 22%,#FF8A3D 50%,rgba(255,79,139,.95) 78%,rgba(91,69,219,0));display:none}
.foot{position:absolute;left:__FOOTX__px;right:__FOOTX__px;bottom:__FOOTB__px;display:flex;justify-content:space-between;align-items:center;font:600 __FOOT__px Inter;color:rgba(255,255,255,.6);__FOOTDIR__}
.foot span{display:flex;align-items:center;gap:12px}
.foot img{width:1.9em;height:1.9em;border-radius:24%}
#fade{position:absolute;inset:0;background:#040a14;opacity:0;pointer-events:none}
"""

VARS = {
    "wide": dict(PO="1390px 520px", SUB=33, LOCK=26, CHIP=26, PCT=72, PCTS=18, CH=66, KEY=96, KEYF=50, KEYW=34, ST=28, TC=44, TCS=22, ENDTOP=96, ICON=250, ENDN=64,
                 ENDT=32, CTAS=24, CTAB=58, LEGALB=34, LEGAL=18, FOOTX=56, FOOTB=30, FOOT=19, FOOTDIR=""),
    "tall": dict(PO="540px 1190px", SUB=37, LOCK=24, CHIP=27, PCT=78, PCTS=20, CH=70, KEY=104, KEYF=54, KEYW=36, ST=30, TC=46, TCS=23, ENDTOP=330, ICON=330, ENDN=74,
                 ENDT=31, CTAS=28, CTAB=68, LEGALB=120, LEGAL=21, FOOTX=60, FOOTB=62, FOOT=20, FOOTDIR="flex-direction:column;gap:10px"),
}

HTML = """<!doctype html><html><head><meta charset="utf-8"><style>__CSS__</style></head><body>
<div id="stage"><canvas id="bg"></canvas></div>
<script>const DATA=__DATA__;const CUES=__CUES__;</script><script>__JS__</script></body></html>"""


def page(work, fmt):
    css = CSS.replace("__ANTON__", base64.b64encode(open(os.path.join(HERE, "..", "..", "Fonts", "Anton-Regular.ttf"), "rb").read()).decode())
    for k, v in sorted(VARS[fmt].items(), key=lambda kv: -len(kv[0])):
        css = css.replace(f"__{k}__", str(v))
    cues = {"scenes": C.SCENES, "ringStart": C.RING_START, "ringFull": C.RING_FULL, "cheatKeys": C.CHEAT_KEYS, "unfold": C.UNFOLD,
            "trustCards": C.TRUST_CARDS, "endCta": C.END_CTA}
    html = (HTML.replace("__CSS__", css).replace("__DATA__", open(os.path.join(work, "data.json")).read())
            .replace("__CUES__", json.dumps(cues)).replace("__JS__", open(os.path.join(HERE, "page.js")).read()))
    path = os.path.join(work, f"page-{fmt}.html")
    open(path, "w").write(html)
    return path


def shoot(path, fmt, cta, jobs, out, link=""):
    """Renders the frames (index, time) of `jobs` into `out`."""
    from playwright.sync_api import sync_playwright
    w, h = SIZES[fmt]
    with sync_playwright() as p:
        # Where a browser is already installed (cloud sessions), use it instead of Playwright's own download.
        local = "/opt/pw-browsers/chromium"
        b = p.chromium.launch(executable_path=local if os.path.exists(local) else None,
                              args=["--enable-gpu-rasterization", "--ignore-gpu-blocklist", "--force-color-profile=srgb"])
        pg = b.new_page(viewport={"width": w, "height": h})
        errors = []
        pg.on("pageerror", lambda e: errors.append(str(e)))
        pg.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        pg.goto("file://" + os.path.abspath(path) + f"?fmt={fmt}&cta={cta}&link={quote(link)}")
        pg.evaluate("ready()")
        pg.wait_for_timeout(300)
        for i, t in jobs:
            pg.evaluate(f"render({t})")
            pg.screenshot(path=os.path.join(out, f"f{i:05d}.jpg"), type="jpeg", quality=95)
        b.close()
        if errors:
            print("JS ERRORS:", errors[:5])


def main():
    link = ""
    if "--link" in sys.argv:
        i = sys.argv.index("--link")
        link = sys.argv[i + 1]
        del sys.argv[i:i + 2]
    work, fmt = sys.argv[1], sys.argv[2]
    cta = sys.argv[3] if len(sys.argv) > 3 else "now"
    path = page(work, fmt)
    if len(sys.argv) > 4:
        out = os.path.join(work, f"test-{fmt}")
        os.makedirs(out, exist_ok=True)
        times = [float(x) for x in sys.argv[4:]]
        shoot(path, fmt, cta, [(round(t * 100), t) for t in times], out, link)
        return
    out = os.path.join(work, f"frames-{fmt}-{cta}")
    os.makedirs(out, exist_ok=True)
    n = int(C.DURATION * FPS)
    jobs = [(i, i / FPS) for i in range(n)]
    # The endings (download, coming soon, with a link) share every frame before the last scene: those are drawn once.
    end = int(C.SCENES[-1][1] * FPS)
    if link and all(os.path.exists(os.path.join(out, f"f{i:05d}.jpg")) for i in range(end)):
        jobs = jobs[end:]
    other = os.path.join(work, f"frames-{fmt}-{'soon' if cta == 'now' else 'now'}")
    if len(jobs) == n and os.path.isdir(other):
        for i in range(end):
            src, dst = os.path.join(other, f"f{i:05d}.jpg"), os.path.join(out, f"f{i:05d}.jpg")
            if os.path.exists(src) and not os.path.exists(dst):
                os.link(src, dst)
        jobs = jobs[end:]
    t0 = time.time()
    workers = 4
    ps = [Process(target=shoot, args=(path, fmt, cta, jobs[k::workers], out, link)) for k in range(workers)]
    [p.start() for p in ps]
    [p.join() for p in ps]
    print(f"{len(jobs)} frames in {time.time() - t0:.0f} s")
    film = os.path.join(work, f"vicefold-{fmt}-{cta}{'-link' if link else ''}.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(out, "f%05d.jpg"), "-i", os.path.join(work, "music.wav"),
                    "-c:v", "libx264", "-preset", "slow", "-crf", "20", "-pix_fmt", "yuv420p", "-profile:v", "high", "-colorspace", "bt709", "-color_primaries", "bt709",
                    "-color_trc", "bt709", "-c:a", "aac", "-b:a", "192k", "-ar", "44100", "-movflags", "+faststart", "-shortest", film], check=True)
    print(film, f"{os.path.getsize(film) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
