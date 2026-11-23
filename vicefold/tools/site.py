"""VICEFOLD : le site (présentation, assistance, confidentialité) en anglais et en français.

Sortie : clapet/tools/site/vicefold/{en,fr}/index.html, privacy.html, img/, video/ (publié avec le site Foldly).
Images : vicefold/store/site/*.jpg (captures de l'app), vidéos : vicefold/store/video/*.mp4 (le modèle 3D du Duo).
"""
import html
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "clapet", "tools", "site", "vicefold")
SHOTS = os.path.join(HERE, "..", "store", "site")
VIDEOS = os.path.join(HERE, "..", "store", "video")
ICON = os.path.join(HERE, "..", "App", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")
STORE = os.environ.get("VICEFOLD_STORE", "https://apps.apple.com/app/id6838298570")
MAIL = "hfreecsapple@gmail.com"

T = {
    "en": {
        "title": "GTA 6 Fan Guide — every mission, your map, your 100%",
        "desc": "An unofficial companion for GTA VI: all 91 missions spoiler-free, the full 100% checklist, 61 cheat codes, the radio and a map with your own pins. For iPhone, iPad and iPhone Duo.",
        "kicker": "Unofficial fan guide for GTA VI",
        "h1": "All of Leonida, <span>one fold away.</span>",
        "lead": "Every story mission without spoilers, the whole 100% checklist, every cheat code and a map with your own pins. Made for iPhone Duo, great on iPhone and iPad.",
        "cta": "Download on the App Store", "free": "Free. No account, no ads.",
        "film": "See it on the Duo",
        "f": [
            ("Spoiler-free, by default", "Tell it which chapter you're in. Missions, places and characters after it stay hidden until you get there.", "home"),
            ("All 91 missions", "Five chapters in order. Tick off missions and objectives, and see what's next on your Home Screen.", "tracker"),
            ("A map with your pins", "Leonida drawn like a real map, with search, filters and visited places. Pro: import the game's own map and line it up once.", "map"),
            ("The whole 100%", "Gang operations, bank jobs, stunts, cards, flamingos, drones… how many you need for each, and a counter.", "collectibles"),
        ],
        "more_h": "And everything around it",
        "more": [("61 cheat codes", "PlayStation and Xbox, with how to unlock each one."), ("21 radio stations", "Track lists, 30-second previews and Apple Music links."),
                 ("Characters", "Who's who, with your own notes and favorites."), ("Widgets", "Your ring and your next mission, on the Home and Lock Screen."),
                 ("iCloud sync", "Your progress on iPhone, iPad and Duo (Pro)."), ("PlayStation hours", "Your play time, read from your account (Pro).")],
        "duo_h": "Made for the fold",
        "duo_p": "Open your iPhone Duo: the list sits on one half, the details or the map on the other, and nothing ever falls into the fold. On iPad, side by side. On any iPhone, one page at a time.",
        "price_h": "Free, with an optional Pro",
        "price_free": ("Free", "Every guide, every mission, the 100% checklist, cheats, radio, the map and 10 pins."),
        "price_pro": ("Pro", "€5.99 once — or €2.99 a year, or €0.99 a month", "Unlimited pins, map layers, your own map, iCloud sync, widgets of your progress, PlayStation hours."),
        "faq_h": "Questions",
        "faq": [("Is this an official app?", "No. It's an unofficial fan guide, not affiliated with, endorsed or approved by Rockstar Games or Take-Two Interactive. The map is our own drawing and no game art is included."),
                ("Does it work offline?", "Yes. Everything is on your iPhone; new guides arrive in free content updates."),
                ("How do I get help?", f"Write to <a href=\"mailto:{MAIL}\">{MAIL}</a>. We answer every message."),
                ("What about my data?", "No account, no ads, no tracking. See the <a href=\"privacy.html\">privacy policy</a>.")],
        "legal": "Unofficial fan guide. Grand Theft Auto and related names are trademarks of Take-Two Interactive. Not affiliated with or endorsed by Rockstar Games or Take-Two Interactive.",
        "privacy": "Privacy", "support": "Support", "other": "Français", "other_href": "../fr/",
        "pp_title": "Privacy policy",
        "pp": [("The short version", "The app has no account, no ads and no tracking. Your progress, pins, notes and photo stay on your devices."),
               ("What stays on your device", "Missions and objectives you tick, places you visit, collectible counters, pins, character notes, your name and photo, and the chapter you're in. With Pro, they're copied to your own iCloud so your devices stay in sync; we can't see them."),
               ("What the app downloads", "New guide content from our server (a public file; nothing about you is sent). Music previews come from Apple's public iTunes Search service."),
               ("PlayStation (optional, Pro)", "If you connect PlayStation, you sign in on Sony's own page. The app never sees your password. It keeps a sign-in token in this device's keychain and only reads your list of games and play time. Disconnect at any time in Profile."),
               ("Purchases", "Purchases and subscriptions go through Apple. We don't receive your payment details."),
               ("Contact", f"<a href=\"mailto:{MAIL}\">{MAIL}</a>")],
    },
    "fr": {
        "title": "GTA 6 : fan guide — chaque mission, ta carte, ton 100 %",
        "desc": "Un compagnon non officiel de GTA VI : les 91 missions sans spoiler, toute la liste du 100 %, 61 codes de triche, la radio et une carte avec tes épingles. Pour iPhone, iPad et iPhone Duo.",
        "kicker": "Fan guide non officiel de GTA VI",
        "h1": "Tout Leonida, <span>à un pli près.</span>",
        "lead": "Toutes les missions de l'histoire sans spoiler, toute la liste du 100 %, tous les codes de triche et une carte avec tes épingles. Pensé pour l'iPhone Duo, parfait sur iPhone et iPad.",
        "cta": "Télécharger dans l'App Store", "free": "Gratuit. Sans compte, sans pub.",
        "film": "En vrai, sur le Duo",
        "f": [
            ("Sans spoiler, par défaut", "Indique le chapitre où tu en es. Ce qui vient après reste masqué jusqu'à ce que tu y arrives.", "home"),
            ("Les 91 missions", "Cinq chapitres dans l'ordre. Coche missions et objectifs, et vois la suite sur ton écran d'accueil.", "tracker"),
            ("Une carte avec tes épingles", "Leonida dessiné comme une vraie carte, avec recherche, filtres et lieux visités. Pro : importe la carte du jeu et cale-la une fois.", "map"),
            ("Tout le 100 %", "Opérations de gangs, braquages, cascades, cartes, flamants roses, drones… combien il en faut, et un compteur.", "collectibles"),
        ],
        "more_h": "Et tout ce qui va avec",
        "more": [("61 codes de triche", "PlayStation et Xbox, avec comment débloquer chacun."), ("21 radios", "Les morceaux, des extraits de 30 secondes et les liens Apple Music."),
                 ("Personnages", "Qui est qui, avec tes notes et tes favoris."), ("Widgets", "Ton anneau et ta prochaine mission, sur l'écran d'accueil et verrouillé."),
                 ("Synchro iCloud", "Ta progression sur iPhone, iPad et Duo (Pro)."), ("Heures PlayStation", "Ton temps de jeu, lu sur ton compte (Pro).")],
        "duo_h": "Pensé pour le pli",
        "duo_p": "Ouvre ton iPhone Duo : la liste sur une moitié, le détail ou la carte sur l'autre, et rien ne tombe jamais dans le pli. Sur iPad, côte à côte. Sur tout iPhone, une page à la fois.",
        "price_h": "Gratuit, avec un Pro facultatif",
        "price_free": ("Gratuit", "Tous les guides, toutes les missions, la liste du 100 %, les codes, la radio, la carte et 10 épingles."),
        "price_pro": ("Pro", "5,99 € une fois — ou 2,99 € par an, ou 0,99 € par mois", "Épingles illimitées, calques de la carte, ta propre carte, synchro iCloud, widgets de progression, heures PlayStation."),
        "faq_h": "Questions",
        "faq": [("C'est une app officielle ?", "Non. C'est un guide de fan non officiel, ni affilié à Rockstar Games ou Take-Two Interactive, ni approuvé par eux. La carte est dessinée par nous et aucune image du jeu n'est incluse."),
                ("Ça marche hors ligne ?", "Oui. Tout est sur ton iPhone ; les nouveaux guides arrivent par des mises à jour gratuites du contenu."),
                ("Comment avoir de l'aide ?", f"Écris à <a href=\"mailto:{MAIL}\">{MAIL}</a>. On répond à chaque message."),
                ("Et mes données ?", "Pas de compte, pas de pub, pas de pistage. Voir la <a href=\"privacy.html\">politique de confidentialité</a>.")],
        "legal": "Guide de fan non officiel. Grand Theft Auto et les noms associés sont des marques de Take-Two Interactive. Non affilié à Rockstar Games ni à Take-Two Interactive, ni approuvé par eux.",
        "privacy": "Confidentialité", "support": "Assistance", "other": "English", "other_href": "../en/",
        "pp_title": "Politique de confidentialité",
        "pp": [("En bref", "L'app n'a ni compte, ni pub, ni pistage. Ta progression, tes épingles, tes notes et ta photo restent sur tes appareils."),
               ("Ce qui reste sur ton appareil", "Les missions et objectifs cochés, les lieux visités, les compteurs d'objets, les épingles, les notes sur les personnages, ton nom et ta photo, et le chapitre où tu en es. Avec Pro, ils sont copiés dans ton propre iCloud pour synchroniser tes appareils ; nous ne pouvons pas les voir."),
               ("Ce que l'app télécharge", "Les nouveaux contenus du guide depuis notre serveur (un fichier public ; rien sur toi n'est envoyé). Les extraits musicaux viennent du service public iTunes Search d'Apple."),
               ("PlayStation (facultatif, Pro)", "Si tu connectes PlayStation, tu te connectes sur la page de Sony. L'app ne voit jamais ton mot de passe. Elle garde un jeton de connexion dans le trousseau de cet appareil et lit seulement ta liste de jeux et ton temps de jeu. Déconnecte-toi quand tu veux dans Profil."),
               ("Achats", "Les achats et abonnements passent par Apple. Nous ne recevons pas tes moyens de paiement."),
               ("Contact", f"<a href=\"mailto:{MAIL}\">{MAIL}</a>")],
    },
}

CSS = r"""
:root{--night:#120f24;--plum:#2b1240;--berry:#7a1f55;--coral:#ff6b5c;--sun:#ffbc46;--sea:#1cbcb8;--ink:#f6f1ff;--mute:#c9bfdc;--card:rgba(255,255,255,.06);--line:rgba(255,255,255,.12)}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--night);color:var(--ink);font:17px/1.55 -apple-system,BlinkMacSystemFont,"Inter","Segoe UI",sans-serif}
a{color:var(--sun)}
.wrap{max-width:1120px;margin:0 auto;padding:0 24px}
header.top{display:flex;align-items:center;justify-content:space-between;padding:18px 0}
.brand{display:flex;align-items:center;gap:12px;color:var(--ink);text-decoration:none;font-weight:700}
.brand img{width:40px;height:40px;border-radius:10px}
.top nav a{color:var(--mute);text-decoration:none;margin-left:18px;font-size:15px}
.hero{position:relative;overflow:hidden;background:linear-gradient(180deg,var(--night) 0%,var(--plum) 40%,var(--berry) 72%,var(--coral) 96%)}
.hero:after{content:"";position:absolute;left:50%;bottom:-260px;width:620px;height:620px;margin-left:-310px;border-radius:50%;background:radial-gradient(circle,#ffe39a 0%,var(--sun) 35%,rgba(255,107,92,0) 70%);opacity:.75}
.hero .wrap{position:relative;z-index:1;padding-bottom:120px}
.kicker{display:inline-block;margin-top:56px;padding:6px 12px;border:1px solid var(--line);border-radius:999px;color:var(--mute);font-size:14px}
h1{font-family:"Bricolage Grotesque",-apple-system,sans-serif;font-size:clamp(44px,7.4vw,92px);line-height:.98;letter-spacing:-.035em;margin:22px 0 18px;max-width:880px}
h1 span{background:linear-gradient(90deg,var(--sun),var(--coral),#ee3b8f);-webkit-background-clip:text;background-clip:text;color:transparent}
.lead{font-size:clamp(18px,2.2vw,22px);color:var(--mute);max-width:680px;margin:0 0 30px}
.cta{display:inline-flex;align-items:center;gap:10px;background:#fff;color:#111;font-weight:700;padding:14px 22px;border-radius:14px;text-decoration:none}
.cta svg{width:20px;height:20px}
.free{display:block;margin-top:12px;color:var(--mute);font-size:14px}
.film{margin:-70px auto 0;position:relative;z-index:2;max-width:1120px;padding:0 24px}
.film video{width:100%;border-radius:24px;display:block;box-shadow:0 30px 80px rgba(0,0,0,.5);background:#000}
.film p{color:var(--mute);font-size:14px;text-align:center}
section{padding:72px 0}
h2{font-family:"Bricolage Grotesque",-apple-system,sans-serif;font-size:clamp(30px,4.2vw,48px);letter-spacing:-.025em;line-height:1.05;margin:0 0 28px}
.feat{display:grid;grid-template-columns:1fr 1fr;gap:56px;align-items:center;margin-bottom:72px}
.feat:nth-child(even) .shot{order:-1}
.feat h3{font-family:"Bricolage Grotesque",-apple-system,sans-serif;font-size:32px;letter-spacing:-.02em;margin:0 0 10px}
.feat p{color:var(--mute);font-size:19px;margin:0}
.shot img{width:100%;max-width:380px;display:block;margin:0 auto;border-radius:34px;box-shadow:0 24px 60px rgba(0,0,0,.45)}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}
.grid div{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:20px}
.grid b{display:block;margin-bottom:4px}.grid span{color:var(--mute);font-size:15px}
.duo{display:grid;grid-template-columns:1.2fr 1fr;gap:40px;align-items:center}
.duo img{width:100%;border-radius:22px}
.duo p{color:var(--mute);font-size:19px}
.prices{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.price{border:1px solid var(--line);border-radius:22px;padding:26px;background:var(--card)}
.price.pro{background:linear-gradient(160deg,rgba(255,107,92,.18),rgba(238,59,143,.14));border-color:rgba(255,107,92,.5)}
.price h3{margin:0 0 4px;font-size:24px}.price .amt{color:var(--sun);font-weight:700;margin-bottom:10px}.price p{color:var(--mute);margin:0}
details{border-bottom:1px solid var(--line);padding:16px 0}summary{cursor:pointer;font-weight:600;font-size:18px}details p{color:var(--mute)}
footer{padding:40px 0 60px;color:var(--mute);font-size:13px;border-top:1px solid var(--line)}
footer a{color:var(--mute)}
.pp{max-width:760px}.pp h1{font-size:44px}.pp h2{font-size:22px;margin:32px 0 6px}.pp p{color:var(--mute)}
@media (max-width:820px){.feat,.duo,.prices{grid-template-columns:1fr;gap:24px}.feat:nth-child(even) .shot{order:0}.grid{grid-template-columns:1fr 1fr}.top nav a{margin-left:12px}}
@media (max-width:520px){.grid{grid-template-columns:1fr}.film{margin-top:-60px}}
@media (prefers-reduced-motion:reduce){video{display:none}}
"""

APPLE = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9s-1.8-.9-3-.8c-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3 .7c1.3 0 2.1-1.1 2.8-2.3.9-1.3 1.3-2.6 1.3-2.6s-2.5-1-2.5-3.8zM14.2 5.8c.6-.8 1.1-1.9 1-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1 .1 2.1-.5 2.7-1.3z"/></svg>'


def head(t, title, lang, desc):
    return f"""<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title><meta name="description" content="{html.escape(desc)}">
<meta property="og:title" content="{html.escape(title)}"><meta property="og:description" content="{html.escape(desc)}"><meta property="og:image" content="../img/og.jpg">
<meta name="apple-itunes-app" content="app-id=6838298570">
<link rel="icon" href="../icon.png"><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&display=swap" rel="stylesheet">
<style>{CSS}</style></head><body>"""


def topbar(t):
    return f"""<header class="top wrap"><a class="brand" href="./"><img src="../icon.png" alt="">GTA 6 Fan Guide</a>
<nav><a href="privacy.html">{t['privacy']}</a><a href="mailto:{MAIL}">{t['support']}</a><a href="{t['other_href']}">{t['other']}</a></nav></header>"""


def foot(t):
    return f"""<footer><div class="wrap">{t['legal']}<br><br><a href="privacy.html">{t['privacy']}</a> · <a href="mailto:{MAIL}">{MAIL}</a></div></footer></body></html>"""


def img(name, alt):
    if os.path.exists(os.path.join(SHOTS, name + ".jpg")):
        return f'<img src="../img/{name}.jpg" alt="{html.escape(alt)}" loading="lazy">'
    return ""


def build(lang):
    t = T[lang]
    feats = "".join(f'<div class="feat"><div><h3>{h}</h3><p>{p}</p></div><div class="shot">{img(f"{lang}-{s}", h)}</div></div>' for h, p, s in t["f"])
    more = "".join(f"<div><b>{a}</b><span>{b}</span></div>" for a, b in t["more"])
    faq = "".join(f"<details><summary>{q}</summary><p>{a}</p></details>" for q, a in t["faq"])
    video = ""
    if os.path.exists(os.path.join(VIDEOS, f"header-{lang}.mp4")):
        video = f"""<div class="film"><video src="../video/header-{lang}.mp4" poster="../video/header-{lang}.jpg" autoplay muted loop playsinline></video><p>{t['film']}</p></div>"""
    page = head(t, t["title"], lang, t["desc"]) + f"""
<div class="hero">{topbar(t)}<div class="wrap"><span class="kicker">{t['kicker']}</span><h1>{t['h1']}</h1><p class="lead">{t['lead']}</p>
<a class="cta" href="{STORE}">{APPLE}{t['cta']}</a><span class="free">{t['free']}</span></div></div>
{video}
<section><div class="wrap">{feats}</div></section>
<section><div class="wrap"><h2>{t['more_h']}</h2><div class="grid">{more}</div></div></section>
<section><div class="wrap duo"><div>{img(f"{lang}-duo", t['duo_h'])}</div><div><h2>{t['duo_h']}</h2><p>{t['duo_p']}</p></div></div></section>
<section><div class="wrap"><h2>{t['price_h']}</h2><div class="prices">
<div class="price"><h3>{t['price_free'][0]}</h3><p>{t['price_free'][1]}</p></div>
<div class="price pro"><h3>{t['price_pro'][0]}</h3><div class="amt">{t['price_pro'][1]}</div><p>{t['price_pro'][2]}</p></div></div></div></section>
<section id="faq"><div class="wrap"><h2>{t['faq_h']}</h2>{faq}</div></section>
""" + foot(t)
    pp = head(t, t["pp_title"], lang, t["desc"]) + topbar(t) + '<main class="wrap pp"><h1>' + t["pp_title"] + "</h1>" + \
        "".join(f"<h2>{h}</h2><p>{p}</p>" for h, p in t["pp"]) + "</main>" + foot(t)
    d = os.path.join(OUT, lang)
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "index.html"), "w").write(page)
    open(os.path.join(d, "privacy.html"), "w").write(pp)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for lang in T:
        build(lang)
    if os.path.isdir(SHOTS):
        shutil.copytree(SHOTS, os.path.join(OUT, "img"), dirs_exist_ok=True)
    if os.path.isdir(VIDEOS):
        shutil.copytree(VIDEOS, os.path.join(OUT, "video"), dirs_exist_ok=True)
    from PIL import Image
    Image.open(ICON).resize((180, 180)).save(os.path.join(OUT, "icon.png"))
    open(os.path.join(OUT, "index.html"), "w").write(
        '<!doctype html><meta charset="utf-8"><script>location.replace((navigator.language||"en").startsWith("fr")?"fr/":"en/")</script><a href="en/">English</a> · <a href="fr/">Français</a>')
    print("ok", OUT)
