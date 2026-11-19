"""Site RetroFold (accueil + assistance, confidentialité) en anglais et en français.

python3 retrofold/tools/site_gen.py  -> clapet/tools/site/retrofold/{en,fr}/index.html et privacy.html
Les styles et le script sont partagés : clapet/tools/site/retrofold/assets/rf.css et rf.js.
"""
import html, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.join(HERE, "..", "..", "clapet", "tools", "site", "retrofold")
STORE = "https://apps.apple.com/app/id6836120890"
MAIL = "hfreecsapple@gmail.com"
UPDATED = {"en": "November 18, 2026", "fr": "18 novembre 2026"}

CARTS = [  # (clé du dessin, couleur de l'étiquette, nom, genre en/fr, sous-titre en/fr)
    ("brick", "#FF6B6B", "Brick Breaker", ("Arcade", "Arcade"), ("Twelve walls, four power-ups", "Douze murs, quatre bonus")),
    ("racer", "#4ECDC4", "Retro Racer", ("Racing", "Course"), ("8-bit highway dodge", "Slalom sur l'autoroute 8 bits")),
    ("snake", "#45B7D1", "Snake", ("Action", "Action"), ("Neon grid serpent", "Le serpent de la grille néon")),
    ("blocks", "#F7DC6F", "Falling Blocks", ("Puzzle", "Puzzle"), ("Block stacking puzzle", "Empile les blocs, efface les lignes")),
    ("invaders", "#C77DFF", "Pixel Invaders", ("Shooter", "Tir"), ("Hold the line", "Tiens la ligne")),
    ("mines", "#A8DADC", "Mine Sweep", ("Puzzle", "Puzzle"), ("Flag every mine", "Trouve toutes les mines")),
    ("maze", "#FFB703", "Maze Muncher", ("Maze", "Labyrinthe"), ("Pellets, ghosts, tunnels", "Pastilles, fantômes, tunnels")),
    ("frog", "#80ED99", "Frog Hop", ("Action", "Action"), ("Cross the road and river", "Traverse la route et la rivière")),
    ("lunar", "#E0E1DD", "Lunar Hinge", ("Lander", "Alunissage"), ("Fold to fire the thrusters", "Plie pour allumer les moteurs")),
    ("paddle", "#F9844A", "Paddle Duel", ("Sports", "Sport"), ("Table tennis against the machine", "Ping-pong contre la machine")),
    ("astro", "#6D9DC5", "Astro Drift", ("Shooter", "Tir"), ("Rocks, a ship and a lot of space", "Des rochers, un vaisseau, beaucoup d'espace")),
    ("tower", "#F15BB5", "Tower Stack", ("Timing", "Timing"), ("Drop it right on top", "Lâche-le pile dessus")),
]
SKINS = ["classic", "purple", "neon", "arcade", "ice", "crimson", "yellow", "gold"]

T = {
    "en": dict(
        lang="en", other="fr", other_name="Français",
        title="RetroFold: a 90s handheld for iPhone Duo",
        desc="RetroFold turns your iPhone Duo into a 90s handheld console: 12 retro cartridges, picked on the cover screen and played on the open clamshell. 8 cartridges free, the others 3 minutes a day.",
        skip="Skip to content", nav=["Cartridges", "How it plays", "Support"],
        h1=["Unfold.", "Play."],
        lede="RetroFold turns your iPhone Duo into a 90s handheld. Pick a cartridge on the cover screen, unfold it like a clamshell, and play with the screen up top and the buttons below. Fold it to pause.",
        cta="Get it on the App Store", cta_small="Free download",
        price="<b>8 cartridges free, every other one 3 minutes a day.</b> RetroFold Pro unlocks everything, one purchase: 2.99&nbsp;€ or $2.99.",
        console_label="Playable demo: Snake. Focus the console, press Enter to start, arrows to steer.",
        hint="This one works. Press <kbd>START</kbd>, then steer with the arrow keys, the D-pad, or a swipe on the screen.",
        skin="Skin", screen="Screen",
        screens=[("lcd", "Pocket LCD", "DOT MATRIX"), ("crt", "Color CRT", "COLOR CRT"), ("trinitron", "Trinitron", "TRINITRON"), ("arcade", "Arcade Monitor", "ARCADE")],
        game=dict(press="PRESS START", over="GAME OVER", again="START: AGAIN", pause="PAUSE", score="SCORE", hi="HI"),
        carts_h="12 cartridges",
        carts_intro="Each one has its own label, its own sounds, high scores in every mode and a round of the day. Slide one in on the cover screen, then unfold.",
        hinge_badge="Uses the hinge",
        how_h="Closed, it's a shelf. Open, it's a console.",
        steps=[("Pick a cartridge", "On the cover screen, swipe through your cartridges and choose one."),
               ("Unfold", "Open your iPhone Duo like a clamshell: the game on the top half, the D-pad and buttons on the bottom half."),
               ("Fold to pause", "Close it and the game waits for you. Unfold to pick up exactly where you left off.")],
        shot_cover="Closed: the cover screen is your cartridge shelf.",
        shot_open="Open: screen above the fold, buttons below.",
        deal_h="Try every cartridge",
        deal_p="Eight cartridges are free. Each Pro cartridge plays free for 3 minutes a day, so you can try them all. RetroFold Pro unlocks every cartridge, skin and screen for one purchase of 2.99&nbsp;€ ($2.99 in the US).",
        deal_list=["No subscription", "No ads", "No account, nothing collected", "8 console skins and 4 screens: Pocket LCD, Color CRT, Trinitron, Arcade Monitor"],
        sticker=("3 MIN", "A DAY"),
        support_h="Support",
        faq=[("How do I play?", "Closed: pick a cartridge on the cover screen. Unfold your iPhone Duo like a clamshell: the screen is above the fold, the controls below. Fold it again to pause, unfold to resume."),
             ("How does the demo work?", "Slide in any Pro cartridge: it plays free for 3 minutes a day, with a timer at the top of the screen. When the time is up, come back tomorrow, or unlock everything with RetroFold Pro."),
             ("How do I get RetroFold Pro back on another iPhone?", "Open the store and tap Restore Purchases, signed in with the same Apple Account you bought it with."),
             ("Does RetroFold collect anything?", "No. No account, no ads, no analytics. Your scores, achievements and settings stay on your iPhone. <a href=\"privacy.html\">Privacy</a>")],
        contact="Questions, ideas, a bug? Write to",
        foot="Made for iPhone Duo.", privacy="Privacy", home="RetroFold",
        p_title="RetroFold: privacy", p_h1="Privacy",
        p_short="RetroFold collects no data. No account, no ads, no analytics, no third-party services, no internet access.",
        p_sections=[("On your iPhone", "Your scores, achievements, settings and demo time stay on your iPhone. They never leave it."),
                    ("Purchase", "The purchase of RetroFold Pro is handled by Apple. We receive no payment information."),
                    ("This website", "This site uses no cookies and no trackers. Its fonts are hosted here, not loaded from another service."),
                    ("Contact", f"<a href=\"mailto:{MAIL}\">{MAIL}</a>")],
        p_updated="Updated",
    ),
    "fr": dict(
        lang="fr", other="en", other_name="English",
        title="RetroFold : une console des années 90 pour iPhone Duo",
        desc="RetroFold transforme ton iPhone Duo en console portable des années 90 : 12 cartouches rétro, choisies sur l'écran extérieur et jouées sur le Duo ouvert. 8 cartouches gratuites, les autres 3 minutes par jour.",
        skip="Aller au contenu", nav=["Cartouches", "Comment on joue", "Assistance"],
        h1=["Déplie.", "Joue."],
        lede="RetroFold transforme ton iPhone Duo en console portable des années 90. Choisis une cartouche sur l'écran extérieur, déplie-le comme une console à clapet, et joue : l'écran en haut, les boutons en bas. Replie-le pour mettre en pause.",
        cta="Télécharger sur l'App Store", cta_small="Téléchargement gratuit",
        price="<b>8 cartouches gratuites, les autres 3 minutes par jour.</b> RetroFold Pro débloque tout, un seul achat : 2,99&nbsp;€.",
        console_label="Démo jouable : Snake. Sélectionne la console, appuie sur Entrée pour commencer, flèches pour diriger.",
        hint="Celle-ci marche. Appuie sur <kbd>START</kbd>, puis dirige avec les flèches du clavier, la croix ou en glissant sur l'écran.",
        skin="Coque", screen="Écran",
        screens=[("lcd", "LCD de poche", "DOT MATRIX"), ("crt", "Cathodique couleur", "COLOR CRT"), ("trinitron", "Trinitron", "TRINITRON"), ("arcade", "Moniteur d'arcade", "ARCADE")],
        game=dict(press="APPUIE SUR START", over="PERDU", again="START : REJOUER", pause="PAUSE", score="SCORE", hi="RECORD"),
        carts_h="12 cartouches",
        carts_intro="Chacune a son étiquette, ses sons, ses records dans chaque mode et sa partie du jour. Glisse-la sur l'écran extérieur, puis déplie.",
        hinge_badge="Se joue avec la charnière",
        how_h="Fermé, c'est une étagère. Ouvert, c'est une console.",
        steps=[("Choisis une cartouche", "Sur l'écran extérieur, fais défiler tes cartouches et choisis-en une."),
               ("Déplie", "Ouvre ton iPhone Duo comme une console à clapet : le jeu sur la moitié du haut, la croix et les boutons sur celle du bas."),
               ("Replie pour faire pause", "Ferme-le et la partie t'attend. Déplie pour reprendre exactement là où tu t'étais arrêté.")],
        shot_cover="Fermé : l'écran extérieur est ton étagère à cartouches.",
        shot_open="Ouvert : l'écran au-dessus de la charnière, les boutons en dessous.",
        deal_h="Essaie toutes les cartouches",
        deal_p="Huit cartouches sont gratuites. Chaque cartouche Pro se joue gratuitement 3 minutes par jour, pour toutes les essayer. RetroFold Pro débloque toutes les cartouches, coques et écrans pour un seul achat de 2,99&nbsp;€.",
        deal_list=["Pas d'abonnement", "Pas de pub", "Pas de compte, rien n'est collecté", "8 coques et 4 écrans : LCD de poche, cathodique couleur, Trinitron, moniteur d'arcade"],
        sticker=("3 MIN", "PAR JOUR"),
        support_h="Assistance",
        faq=[("Comment on joue ?", "Fermé : choisis une cartouche sur l'écran extérieur. Déplie ton iPhone Duo comme une console à clapet : l'écran au-dessus de la charnière, les commandes en dessous. Replie-le pour faire pause, déplie pour reprendre."),
             ("Comment marche la démo ?", "Glisse n'importe quelle cartouche Pro : elle se joue gratuitement 3 minutes par jour, avec un minuteur en haut de l'écran. Quand le temps est écoulé, reviens demain, ou débloque tout avec RetroFold Pro."),
             ("Comment récupérer RetroFold Pro sur un autre iPhone ?", "Ouvre la boutique et touche Restore Purchases, avec le même compte Apple que pour l'achat."),
             ("RetroFold collecte-t-il des données ?", "Non. Pas de compte, pas de pub, pas de statistiques. Tes scores, succès et réglages restent sur ton iPhone. <a href=\"privacy.html\">Confidentialité</a>")],
        contact="Une question, une idée, un bug ? Écris à",
        foot="Fait pour l'iPhone Duo.", privacy="Confidentialité", home="RetroFold",
        p_title="RetroFold : confidentialité", p_h1="Confidentialité",
        p_short="RetroFold ne collecte aucune donnée. Pas de compte, pas de pub, pas de statistiques, aucun service tiers, aucun accès à internet.",
        p_sections=[("Sur ton iPhone", "Tes scores, succès, réglages et ton temps de démo restent sur ton iPhone. Ils n'en sortent jamais."),
                    ("Achat", "L'achat de RetroFold Pro est géré par Apple. Nous ne recevons aucune information de paiement."),
                    ("Ce site", "Ce site n'utilise ni cookies ni traceurs. Ses polices sont hébergées ici, pas chargées depuis un autre service."),
                    ("Contact", f"<a href=\"mailto:{MAIL}\">{MAIL}</a>")],
        p_updated="Mis à jour le",
    ),
}

E = html.escape


def head(t, title, desc, page):
    return f"""<!doctype html>
<html lang="{t['lang']}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{E(title)}</title>
<meta name="description" content="{E(desc)}">
<meta name="theme-color" content="#cdcac3" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#1b1b21" media="(prefers-color-scheme: dark)">
<meta property="og:title" content="{E(title)}">
<meta property="og:description" content="{E(desc)}">
<meta property="og:image" content="https://foldly.netlify.app/retrofold/assets/img/og.png">
<meta name="apple-itunes-app" content="app-id=6836120890">
<link rel="icon" href="../icon.png">
<link rel="apple-touch-icon" href="../icon.png">
<link rel="alternate" hreflang="{t['other']}" href="../{t['other']}/{page}">
<link rel="preload" href="../assets/fonts/Silkscreen-Bold.woff" as="font" type="font/woff" crossorigin>
<link rel="stylesheet" href="../assets/rf.css">
</head>
<body>
<a class="skip" href="#main">{t['skip']}</a>
<div class="wrap">
<header class="bar">
  <a class="brand" href="./"><img src="../icon.png" alt="" width="40" height="40">RETROFOLD</a>
  <nav aria-label="Menu">
    <a class="hide-s" href="./#cartridges">{t['nav'][0]}</a>
    <a class="hide-s" href="./#how">{t['nav'][1]}</a>
    <a href="./#support">{t['nav'][2]}</a>
    <a href="../{t['other']}/{page}" lang="{t['other']}">{t['other_name']}</a>
  </nav>
</header>
</div>
"""


def foot(t, page):
    return f"""<footer class="foot">
  <div class="wrap">
    <span class="molded" aria-hidden="true">RETROFOLD</span>
    <span>{t['foot']} © 2026</span>
    <nav aria-label="Footer"><a href="privacy.html">{t['privacy']}</a><a href="./#support">{t['nav'][2]}</a><a href="../{t['other']}/{page}" lang="{t['other']}">{t['other_name']}</a></nav>
  </div>
</footer>
"""


def index(t):
    k = 0 if t["lang"] == "en" else 1
    carts = "\n".join(
        f"""      <li class="cart"><div class="label" style="--lc:{c}"><div class="g">{E(g[k].upper())}</div><canvas data-art="{a}" width="10" height="10" aria-hidden="true"></canvas><h3>{E(n)}</h3></div>
        <p>{E(s[k])}</p>{f'<span class="fold">{t["hinge_badge"]}</span>' if a == "lunar" else ""}</li>"""
        for a, c, n, g, s in CARTS)
    skins = "".join(f'<button class="chip" type="button" data-skin="{s}" aria-pressed="false"></button>' for s in SKINS)
    screens = "".join(f'<button class="pill" type="button" data-screen-pick="{k_}" data-tag="{tag}" aria-pressed="false">{E(n)}</button>' for k_, n, tag in t["screens"])
    steps = "\n".join(f"        <li><div><h3>{E(h)}</h3><p>{E(p)}</p></div></li>" for h, p in t["steps"])
    faq = "\n".join(f"      <details{' open' if i == 0 else ''}><summary>{E(q)}</summary><p>{a}</p></details>" for i, (q, a) in enumerate(t["faq"]))
    deal = "".join(f"<li>{E(x)}</li>" for x in t["deal_list"])
    return head(t, t["title"], t["desc"], "") + f"""<main id="main">
<div class="wrap">
  <section class="hero">
    <div>
      <h1><span>{t['h1'][0]}</span><span>{t['h1'][1]}</span></h1>
      <p class="lede">{E(t['lede'])}</p>
      <div class="buy">
        <a class="store" href="{STORE}"><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M11 3h2v10.2l3.6-3.6 1.4 1.4-6 6-6-6 1.4-1.4 3.6 3.6zM5 19h14v2H5z"/></svg><span>{t['cta']}<small>{t['cta_small']}</small></span></a>
        <p class="price">{t['price']}</p>
      </div>
    </div>
    <div class="stage">
      <div class="console" data-screen="lcd" tabindex="0" role="application" aria-label="{E(t['console_label'])}">
        <div class="bezel"><span class="led"></span><span class="tag">POWER</span><span class="mode">DOT MATRIX</span>
          <div class="screen"><canvas width="192" height="128"></canvas></div><div class="score"></div></div>
        <div class="logo"><i></i>RETROFOLD</div>
        <div class="dpad"><button type="button" class="u" data-d="u" aria-label="Up"></button><button type="button" class="l" data-d="l" aria-label="Left"></button><span class="c"></span><button type="button" class="r" data-d="r" aria-label="Right"></button><button type="button" class="d" data-d="d" aria-label="Down"></button></div>
        <div class="ab"><button type="button" class="b" data-start aria-label="B"></button><button type="button" class="a" data-start aria-label="A"></button><span class="lb">B</span><span class="la">A</span></div>
        <div class="ss"><button type="button" data-start aria-label="Select"><span>SELECT</span></button><button type="button" data-start aria-label="Start"><span>START</span></button></div>
        <div class="grille"></div>
      </div>
      <div class="pickers">
        <p class="hint">{t['hint']}</p>
        <div class="row"><span class="k">{t['skin']}: <span id="skin-name" aria-live="polite"></span></span>{skins}</div>
        <div class="row"><span class="k">{t['screen']}</span>{screens}</div>
      </div>
    </div>
  </section>
</div>

<section class="block" id="cartridges">
  <div class="wrap">
    <h2>{t['carts_h']}</h2>
    <p class="intro">{E(t['carts_intro'])}</p>
    <ul class="shelf">
{carts}
    </ul>
  </div>
</section>

<section class="block" id="how">
  <div class="wrap steps">
    <div>
      <h2>{E(t['how_h'])}</h2>
      <ol>
{steps}
      </ol>
    </div>
    <div class="shots">
      <div class="pair">
        <figure><img src="../assets/img/cover.webp" width="900" height="619" alt="{E(t['shot_cover'])}" loading="lazy"><figcaption>{E(t['shot_cover'])}</figcaption></figure>
        <figure><img src="../assets/img/open.webp" width="600" height="853" alt="{E(t['shot_open'])}" loading="lazy"><figcaption>{E(t['shot_open'])}</figcaption></figure>
      </div>
    </div>
  </div>
</section>

<section class="block" id="price">
  <div class="wrap deal">
    <div class="sticker" aria-hidden="true"><div><b>{t['sticker'][0]}</b><span>{t['sticker'][1]}</span></div></div>
    <div>
      <h2>{E(t['deal_h'])}</h2>
      <p class="intro" style="margin-bottom:0">{t['deal_p']}</p>
      <ul>{deal}</ul>
    </div>
  </div>
</section>

<section class="block" id="support">
  <div class="wrap">
    <h2>{t['support_h']}</h2>
    <div class="faq">
{faq}
    </div>
    <p class="contact">{t['contact']} <a href="mailto:{MAIL}">{MAIL}</a></p>
  </div>
</section>
</main>
{foot(t, "")}<script>window.RF_TEXT={json.dumps(t['game'], ensure_ascii=False)};</script>
<script src="../assets/rf.js" defer></script>
</body>
</html>
"""


def privacy(t):
    secs = "\n".join(f"  <h2>{E(h)}</h2>\n  <p>{p}</p>" for h, p in t["p_sections"])
    return head(t, t["p_title"], t["p_short"], "privacy.html") + f"""<main id="main">
<div class="wrap page">
  <h1>{t['p_h1']}</h1>
  <p class="short">{E(t['p_short'])}</p>
{secs}
  <p style="margin-top:40px">{t['p_updated']} {UPDATED[t['lang']]}.</p>
</div>
</main>
{foot(t, "privacy.html")}</body>
</html>
"""


for lang, t in T.items():
    d = os.path.join(SITE, lang)
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "index.html"), "w").write(index(t))
    open(os.path.join(d, "privacy.html"), "w").write(privacy(t))
    print("ok", lang)
