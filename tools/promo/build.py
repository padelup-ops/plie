"""Construit la page de la vidéo et rend les images (python3 build.py fr|en [t1 t2 …])."""
import base64, json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cues as C
from pieces_src import PIECES
from playwright.sync_api import sync_playwright

TEXTS = {
    "fr": {
        "hubSub": "13 jeux pensés pour l'iPhone Duo", "yourMove": "À toi de jouer", "waiting": "En attente",
        "white": "Blancs", "black": "Noirs", "goal": "BUT !", "focus": "CONCENTRATION", "song": "Ode à la joie · Beethoven",
        "made": "Pensé pour l'iPhone Duo", "cta": "Bientôt sur l'App Store",
        "names": ["RAYON", "PLIAGE", "BASCULE", "LE COFFRE", "PANIER", "FILET", "FLÉCHETTES", "AIR HOCKEY", "ÉCHECS", "DAMES", "PIANO", "1, 2, 3 SOLEIL", "FERME"],
        "scenes": {
            "hook": ["Ce téléphone se plie. Ses jeux *aussi.*", ""],
            "rayon": ["Plie-le pour *viser*", "RAYON · le miroir suit la charnière"],
            "chess": ["Déplie-le. Jouez *face à face.*", "ÉCHECS & DAMES · la charnière sépare les camps"],
            "piano": ["Ton téléphone devient un *piano*", "PIANO · la partition sur l'écran du haut"],
            "filet": ["La charnière devient le *filet*", "FILET · ping-pong"],
            "hockey": ["2 joueurs. *1 téléphone.*", "AIR HOCKEY · à plat, face à face"],
            "ferme": ["Ferme-le pour te *concentrer*", "FERME · ta plante pousse sur l'écran extérieur"],
            "grid": ["13 jeux", "pensés pour l'iPhone Duo"],
        },
    },
    "en": {
        "hubSub": "13 games made for iPhone Duo", "yourMove": "Your move", "waiting": "Waiting",
        "white": "White", "black": "Black", "goal": "GOAL!", "focus": "FOCUS", "song": "Ode to Joy · Beethoven",
        "made": "Made for iPhone Duo", "cta": "Coming soon to the App Store",
        "names": ["BEAM", "INKFOLD", "RAMP", "THE SAFE", "HOOPS", "PING PONG", "DARTS", "AIR HOCKEY", "CHESS", "CHECKERS", "PIANO", "RED LIGHT, GREEN LIGHT", "FOCUS"],
        "scenes": {
            "hook": ["This phone folds. So do the *games.*", ""],
            "rayon": ["Fold it to *aim*", "BEAM · the mirror follows the hinge"],
            "chess": ["Unfold it. Play *face to face.*", "CHESS & CHECKERS · the hinge splits the board"],
            "piano": ["Your phone becomes a *piano*", "PIANO · sheet music on the top screen"],
            "filet": ["The hinge becomes the *net*", "PING PONG"],
            "hockey": ["2 players. *1 phone.*", "AIR HOCKEY · flat, face to face"],
            "ferme": ["Close it to *focus*", "FOCUS · your plant grows on the outer screen"],
            "grid": ["13 games", "made for iPhone Duo"],
        },
    },
}

CUES = {
    "scenes": C.SCENES, "rayonHits": C.RAYON_HITS, "chessMoves": C.CHESS_MOVES, "piano": C.PIANO,
    "filet": [list(x[:4]) for x in C.FILET], "hockey": [list(x[:3]) for x in C.HOCKEY],
    "fermeClose": C.FERME_CLOSE, "fermeBloom": C.FERME_BLOOM, "gridPops": C.GRID_POPS,
}

HTML = """<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;background:#000}
#stage{position:relative;width:1080px;height:1920px;overflow:hidden;font-family:Inter}
canvas{position:absolute;left:0;top:0}
#persp{position:absolute;inset:0;perspective:2400px;perspective-origin:540px 980px}
#cam{position:absolute;left:0;top:0;transform-style:preserve-3d}
#device{position:absolute;left:0;top:0;transform-style:preserve-3d}
.panel{position:absolute;width:860px;height:600px;border-radius:40px;transform-style:preserve-3d}
.face{position:absolute;inset:0;border-radius:40px;backface-visibility:hidden;-webkit-backface-visibility:hidden;
 background:linear-gradient(135deg,#3b3d48,#16171d 40%,#0a0a0d);box-shadow:inset 0 0 0 2px rgba(255,255,255,.18), inset 0 0 0 6px #0b0b0f}
.face canvas{left:24px;top:24px;border-radius:20px}
#bottom{left:-430px;top:0;transform:translateZ(-6px)}
#top{left:-430px;top:-600px;transform-origin:50% 100%}
#topBack{transform:rotateX(180deg) translateZ(3px)}
#hinge{position:absolute;left:-424px;top:-9px;width:848px;height:18px;border-radius:9px;background:linear-gradient(#55575f,#1a1b20 60%,#0a0a0c)}
#shadow{position:absolute;left:-470px;top:-640px;width:940px;height:1280px;border-radius:80px;background:rgba(0,0,0,.55);filter:blur(40px);transform:translateZ(-40px)}
#texts{position:absolute;left:0;top:250px;width:100%;text-align:center}
#headline{font:900 96px/1.04 'Inter Display';color:#fff;padding:0 70px;letter-spacing:-1px;text-shadow:0 6px 30px rgba(0,0,0,.45)}
#headline .w{display:inline-block}
#headline b{background:linear-gradient(90deg,#3DE0FF,#FF4F9A,#FFC53D);-webkit-background-clip:text;background-clip:text;color:transparent}
#sub{margin-top:26px;font:700 38px Inter;color:rgba(255,255,255,.85);padding:0 90px;letter-spacing:.5px}
</style></head><body><div id="stage">
<canvas id="bg" width="1080" height="1920"></canvas>
<div id="persp"><div id="cam"><div id="device">
 <div id="shadow"></div>
 <div id="bottom" class="panel"><div class="face"><canvas id="scrBot" width="812" height="552"></canvas></div></div>
 <div id="top" class="panel"><div class="face"><canvas id="scrTop" width="812" height="552"></canvas></div>
   <div id="topBack" class="face"><canvas id="scrOut" width="812" height="552"></canvas></div></div>
 <div id="hinge"></div>
</div></div></div>
<div id="texts"><div id="headline"></div><div id="sub"></div></div>
<canvas id="grid" width="1080" height="1920"></canvas>
<canvas id="endc" width="1080" height="1920"></canvas>
</div>
<script>const CUES=__CUES__;const PIECES=__PIECES__;const TEXTS=__TEXTS__;const ICON="__ICON__";</script>
<script>__JS__</script></body></html>"""


def page_html():
    icon = "data:image/png;base64," + base64.b64encode(open("icon.png", "rb").read()).decode()
    return (HTML.replace("__CUES__", json.dumps(CUES)).replace("__PIECES__", json.dumps(PIECES))
            .replace("__TEXTS__", json.dumps(TEXTS, ensure_ascii=False)).replace("__ICON__", icon)
            .replace("__JS__", open("page.js").read()))


def render(lang, times=None, fps=30, out=None):
    open("page.html", "w").write(page_html())
    with sync_playwright() as p:
        b = p.chromium.launch(args=["--enable-gpu-rasterization", "--ignore-gpu-blocklist"])
        pg = b.new_page(viewport={"width": 1080, "height": 1920})
        errors = []
        pg.on("pageerror", lambda e: errors.append(str(e)))
        pg.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        pg.goto("file://" + os.path.abspath("page.html") + f"?lang={lang}")
        pg.evaluate("ready()")
        pg.wait_for_timeout(300)
        if times is None:
            n = int(C.DURATION * fps)
            times = [i / fps for i in range(n)]
        os.makedirs(out or f"frames_{lang}", exist_ok=True)
        t0 = time.time()
        for i, t in enumerate(times):
            pg.evaluate(f"render({t})")
            pg.screenshot(path=f"{out or 'frames_' + lang}/f{i:05d}.jpg", type="jpeg", quality=93)
        b.close()
        if errors:
            print("ERREURS JS :", errors[:5])
        print(f"{len(times)} images en {time.time() - t0:.0f} s")


if __name__ == "__main__":
    lang = sys.argv[1]
    if len(sys.argv) > 2:
        render(lang, [float(x) for x in sys.argv[2:]], out=f"test_{lang}")
    else:
        render(lang)
