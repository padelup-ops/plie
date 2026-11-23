"""Site Twinfold, version complète (en, fr) : clapet/tools/site/twinfold/{en,fr}/index.html.

Même plan qu'un site d'app soigné : nouveautés, appareils (Duo fermé, Duo ouvert, iPad, iPhone, onglets),
fonctions 01-05, et aussi, tarifs gratuit / Pro, FAQ, confidentialité. Captures : twinfold/store/site/*.png,
copiées dans clapet/tools/site/twinfold/img/.

python3 twinfold/tools/site2.py
"""
import json
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.join(HERE, "..", "..", "clapet", "tools", "site", "twinfold")
SHOTS = os.path.join(HERE, "..", "store", "site")
STORE = "https://apps.apple.com/app/id6837801236"
MAIL = "hfreecsapple@gmail.com"

# (file, device class for the frame)
DEVICES = [("duo-closed", "duo-c"), ("duo-open", "duo-o"), ("duo-wide", "duo-w"), ("ipad", "ipad"), ("iphone", "phone"), ("tabs", "phone")]

T = {
 "en": dict(
  other="fr", other_name="Français",
  title="Twinfold: two web pages at once, for iPhone Duo, iPhone and iPad",
  desc="Twinfold is a browser that shows two pages at once: a video above, your research below. Made for iPhone Duo, great on iPhone and iPad. Free, private, one-time Pro.",
  nav=[("news", "News"), ("devices", "Devices"), ("features", "Features"), ("pricing", "Pricing"), ("faq", "FAQ")],
  h1="Watch a video.<br>Look things up.<br><em>At the same time.</em>",
  lede="Twinfold splits the screen to show two web pages at once. On iPhone Duo they meet at the fold and run edge to edge, under the side band too.",
  bullets=[("Two pages", "Top and bottom, or side by side, on any device."), ("Edge to edge", "Pages fill the whole screen. Nothing hides them."), ("Controls in a bubble", "A small glass bubble, shrinking while you read.")],
  cta="Download on the App Store", cta_note="Free · iOS 27 · iPhone Duo, iPhone, iPad",
  news_h="What's new",
  video_h="See it move.", video_tabs=("iPhone Duo", "iPhone · iPad"),
  news=[("1.0", "Nov 2026", "First release: two pages at the fold, floating glass bubble, side dock, tab overview, pairs, AI beside the page, video notes, bilingual reading, linked panes.")],
  dev_eyebrow="Any device", dev_h="Closed, open, sideways.",
  dev=[("Duo, closed", "Two pages on the cover screen, right up to the edge."), ("Duo, open", "One page above the fold, one below."),
       ("Duo, sideways", "Side by side, each on its half."), ("iPad", "Two pages side by side, and Split View with any app."),
       ("iPhone", "A video above, the article below. Drag the handle."), ("Every tab", "Full-screen thumbnails, normal and private.")],
  dev_hint="Swipe for the other devices",
  feat_eyebrow="Features", feat_h="Stop switching tabs.",
  feats=[("Two panes, your way", "Long-press the handle: half and half, one third, two thirds, or video priority, sized for a 16:9 video. Swap the pages without stopping the video."),
         ("Pairs", "Save two pages that go together, with their sizes: a video and your notes, an article and its AI summary. Open them from the Home Screen icon."),
         ("An action palette", "One round button floats over the pages. Tap it: your actions open around it. Or press and slide toward one, it runs when you let go. Put it anywhere, or hide it."),
         ("Every tab at a glance", "Both pages' tabs in one grid, normal and private. And AI beside the page: ChatGPT, Claude, Gemini, Le Chat, Perplexity or Copilot in the other pane, already asked about your page."),
         ("Only in Twinfold", "Linked panes: tap links on one side, read them on the other. Bilingual reading: a page and its translation scrolling together. Video notes that keep the moment.")],
  more_h="And everything a daily browser needs",
  more=[("doc.plaintext", "Reader view", "The text alone, read aloud if you like."), ("hand.raised", "Ad and tracker blocking", "Built in, on your iPhone."),
        ("eye.slash", "Private tabs", "Nothing kept when closed."), ("hand.draw", "Your gestures", "Seven gestures, fifteen actions."),
        ("note.text", "Video notes", "Tap a note, the video jumps back."), ("newspaper", "Follow sites", "Every new article in one list.")],
  price_eyebrow="Pricing", price_h="Start free. Go Pro for everything.",
  price_lede="One purchase, not a subscription.",
  plans=[("Free", "€0", ["Two pages, at the fold or anywhere", "Unlimited tabs, private tabs", "Floating bubble, side dock, tab overview", "Linked panes, search twice", "2 saved pairs", "Ad and tracker blocking, reader view"]),
         ("Twinfold Pro", "€4.99", ["Everything in Free", "AI beside the page (6 assistants)", "Unlimited pairs", "Your own gestures", "Video notes, bilingual reading", "Scroll together, follow sites, read aloud, PDF"])],
  pro_note="One-time purchase · Yours for good",
  faq_h="Questions",
  faq=[("Is it a subscription?", "No. Twinfold is free, and Twinfold Pro is a single purchase, yours for good."),
       ("Which devices?", "iPhone Duo, every iPhone and iPad with iOS 27 or later."),
       ("Can two videos play at once?", "Yes. iOS lets one of them have sound: each pane has a sound button, so you choose which one you hear."),
       ("Can I open other apps in a pane?", "Apps themselves can't run inside another app on iOS, but their web versions can: YouTube, Maps, Gmail, Notion and more are on the start page. On iPad, Twinfold also works in Split View next to any app."),
       ("How does the AI work?", "The assistant's own website opens in the other pane, signed in with your own account. Twinfold never sees your conversations."),
       ("What does Twinfold know about me?", "Nothing. No account, no server, no analytics: your history and bookmarks stay on your device.")],
  priv_h="What you browse stays on your iPhone.",
  priv=[("No tracking", "No ads, no analytics, no account."), ("On your device", "History, bookmarks and pairs never leave it."), ("Blocked for you", "Trackers are stopped before they load.")],
  end_h="Two pages. One fold.", end_p="Free on the App Store.", privacy="Privacy policy", support="Support",
 ),
 "fr": dict(
  other="en", other_name="English",
  title="Twinfold : deux pages web à la fois, pour iPhone Duo, iPhone et iPad",
  desc="Twinfold est un navigateur qui affiche deux pages à la fois : une vidéo en haut, vos recherches en bas. Pensé pour l'iPhone Duo, parfait sur iPhone et iPad. Gratuit, privé, Pro en achat unique.",
  nav=[("news", "Nouveautés"), ("devices", "Appareils"), ("features", "Fonctions"), ("pricing", "Tarifs"), ("faq", "FAQ")],
  h1="Regardez une vidéo.<br>Faites vos recherches.<br><em>En même temps.</em>",
  lede="Twinfold partage l'écran pour afficher deux pages web à la fois. Sur l'iPhone Duo, elles se rejoignent au pli et vont jusqu'aux bords, même sous la bande latérale.",
  bullets=[("Deux pages", "En haut et en bas, ou côte à côte, sur tous les appareils."), ("Bord à bord", "Les pages remplissent tout l'écran. Rien ne les cache."), ("Commandes dans une bulle", "Une petite bulle de verre, qui se réduit pendant la lecture.")],
  cta="Télécharger dans l'App Store", cta_note="Gratuit · iOS 27 · iPhone Duo, iPhone, iPad",
  news_h="Nouveautés",
  video_h="En mouvement.", video_tabs=("iPhone Duo", "iPhone · iPad"),
  news=[("1.0", "nov. 2026", "Première version : deux pages au pli, bulle de verre flottante, dock latéral, aperçu des onglets, paires, IA à côté de la page, notes vidéo, lecture bilingue, volets liés.")],
  dev_eyebrow="Tous les appareils", dev_h="Fermé, ouvert, à l'horizontale.",
  dev=[("Duo fermé", "Deux pages sur l'écran extérieur, jusqu'au bord."), ("Duo ouvert", "Une page au-dessus du pli, une en dessous."),
       ("Duo à l'horizontale", "Côte à côte, chacune sur sa moitié."), ("iPad", "Deux pages côte à côte, et Split View avec n'importe quelle app."),
       ("iPhone", "La vidéo en haut, l'article en bas. Faites glisser la poignée."), ("Tous les onglets", "Des vignettes plein écran, normaux et privés.")],
  dev_hint="Balayez pour voir les autres appareils",
  feat_eyebrow="Fonctions", feat_h="Fini les allers-retours entre onglets.",
  feats=[("Deux volets, à votre façon", "Appui long sur la poignée : moitié-moitié, un tiers, deux tiers, ou priorité vidéo, à la taille d'une vidéo 16:9. Inversez les pages sans arrêter la vidéo."),
         ("Les paires", "Enregistrez deux pages qui vont ensemble, avec leur taille : une vidéo et vos notes, un article et son résumé par l'IA. Ouvrez-les depuis l'icône de l'écran d'accueil."),
         ("Une palette d'actions", "Un bouton rond flotte au-dessus des pages. Touchez-le : vos actions s'ouvrent autour. Ou appuyez et glissez vers l'une d'elles, elle s'exécute quand vous relâchez. Placez-le où vous voulez, ou masquez-le."),
         ("Tous les onglets d'un coup d'œil", "Les onglets des deux pages dans une seule grille, normaux et privés. Et l'IA à côté de la page : ChatGPT, Claude, Gemini, Le Chat, Perplexity ou Copilot dans l'autre volet, déjà interrogés sur votre page."),
         ("Seulement dans Twinfold", "Volets liés : touchez des liens d'un côté, lisez-les de l'autre. Lecture bilingue : une page et sa traduction qui défilent ensemble. Des notes vidéo qui gardent le moment.")],
  more_h="Et tout ce qu'il faut à un navigateur de tous les jours",
  more=[("doc.plaintext", "Mode lecture", "Le texte seul, lu à voix haute si vous voulez."), ("hand.raised", "Blocage des pubs et traqueurs", "Intégré, sur votre iPhone."),
        ("eye.slash", "Onglets privés", "Rien n'est gardé une fois fermés."), ("hand.draw", "Vos gestes", "Sept gestes, quinze actions."),
        ("note.text", "Notes vidéo", "Touchez une note, la vidéo y revient."), ("newspaper", "Suivre des sites", "Chaque nouvel article dans une seule liste.")],
  price_eyebrow="Tarifs", price_h="Gratuit pour commencer. Pro pour tout.",
  price_lede="Un seul achat, pas d'abonnement.",
  plans=[("Gratuit", "0 €", ["Deux pages, au pli ou n'importe où", "Onglets illimités, onglets privés", "Bulle flottante, dock latéral, aperçu des onglets", "Volets liés, double recherche", "2 paires enregistrées", "Blocage des pubs et traqueurs, mode lecture"]),
         ("Twinfold Pro", "4,99 €", ["Tout ce qui est gratuit", "L'IA à côté de la page (6 assistants)", "Paires illimitées", "Vos propres gestes", "Notes vidéo, lecture bilingue", "Défilement lié, sites suivis, lecture à voix haute, PDF"])],
  pro_note="Achat unique · À vous pour toujours",
  faq_h="Questions",
  faq=[("C'est un abonnement ?", "Non. Twinfold est gratuit, et Twinfold Pro est un achat unique, à vous pour toujours."),
       ("Sur quels appareils ?", "iPhone Duo, et tous les iPhone et iPad sous iOS 27 ou plus récent."),
       ("Deux vidéos peuvent-elles jouer en même temps ?", "Oui. iOS laisse le son à l'une des deux : chaque volet a un bouton son pour choisir celle que vous entendez."),
       ("Peut-on ouvrir d'autres apps dans un volet ?", "Sur iOS, une app ne peut pas tourner dans une autre, mais leurs versions web oui : YouTube, Maps, Gmail, Notion et d'autres sont sur la page d'accueil. Sur iPad, Twinfold marche aussi en Split View à côté de n'importe quelle app."),
       ("Comment marche l'IA ?", "Le site de l'assistant s'ouvre dans l'autre volet, avec votre propre compte. Twinfold ne voit jamais vos conversations."),
       ("Que sait Twinfold de moi ?", "Rien. Ni compte, ni serveur, ni statistiques : votre historique et vos signets restent sur votre appareil.")],
  priv_h="Ce que vous consultez reste sur votre iPhone.",
  priv=[("Aucun pistage", "Ni pub, ni statistiques, ni compte."), ("Sur votre appareil", "Historique, signets et paires n'en sortent jamais."), ("Bloqués pour vous", "Les traqueurs sont arrêtés avant de se charger.")],
  end_h="Deux pages. Un pli.", end_p="Gratuit sur l'App Store.", privacy="Confidentialité", support="Assistance",
 ),
}

ICONS = {  # small inline SVGs for the "and more" grid (no icon font)
 "doc.plaintext": '<path d="M7 3h7l5 5v13H7z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M10 12h6M10 15.5h6M10 19h4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
 "hand.raised": '<path d="M12 3l7 3v6c0 4.5-3 7.6-7 9-4-1.4-7-4.5-7-9V6z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
 "eye.slash": '<path d="M3 12s3.5-6 9-6 9 6 9 6-3.5 6-9 6-9-6-9-6z" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M4 4l16 16" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
 "hand.draw": '<path d="M4 17c3-6 6 2 9-4s5-3 7-1" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><circle cx="20" cy="12" r="1.6" fill="currentColor"/>',
 "note.text": '<rect x="4" y="4" width="16" height="16" rx="3" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M8 9h8M8 13h8M8 17h5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
 "newspaper": '<rect x="3" y="5" width="15" height="14" rx="2" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M18 9h3v8a2 2 0 0 1-2 2M6 9h9M6 13h9M6 16h6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
}

CSS = r"""
#video .vtabs{display:inline-flex;gap:4px;padding:4px;border-radius:999px;background:rgba(15,36,39,.07);margin:6px 0 18px}
#video .vtabs button{font:inherit;font-weight:600;border:0;border-radius:999px;padding:10px 18px;background:transparent;color:inherit;cursor:pointer}
#video .vtabs button[aria-selected=true]{background:#0f2427;color:#fff}
#video .vframe{border-radius:28px;overflow:hidden;background:#eef4f2;max-width:420px}
#video video{display:block;width:100%;height:auto;aspect-ratio:9/16}

:root{--bg:#0b1517;--bg2:#10201f;--card:#142826;--ink:#ecf4f2;--muted:#9db4b1;--teal:#2fd1bd;--teal-d:#0d9e8f;--coral:#ff7a62;--line:#21403c}
:root[data-theme=light]{--bg:#f2f7f6;--bg2:#e8f1ef;--card:#ffffff;--ink:#0f2427;--muted:#4e6467;--teal:#0b8a7d;--teal-d:#087a6e;--coral:#e8553e;--line:#cfdfdb}
@media (prefers-color-scheme:light){:root:not([data-theme=dark]){--bg:#f2f7f6;--bg2:#e8f1ef;--card:#ffffff;--ink:#0f2427;--muted:#4e6467;--teal:#0b8a7d;--teal-d:#087a6e;--coral:#e8553e;--line:#cfdfdb}}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--ink);font:17px/1.6 "Instrument Sans",-apple-system,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
a{color:var(--teal)}:focus-visible{outline:3px solid var(--coral);outline-offset:3px;border-radius:8px}
.wrap{max-width:1140px;margin:0 auto;padding:0 20px}
nav.top{position:sticky;top:0;z-index:5;backdrop-filter:blur(14px);background:color-mix(in srgb,var(--bg) 78%,transparent);border-bottom:1px solid var(--line)}
nav.top .wrap{display:flex;align-items:center;gap:18px;height:60px}
nav.top img{width:30px;height:30px;border-radius:8px}nav.top b{font-family:"Bricolage Grotesque",sans-serif;font-size:19px}
nav.top .links{margin-left:auto;display:flex;gap:18px;font-size:14px}nav.top .links a{color:var(--ink);opacity:.78;text-decoration:none}
nav.top .links a:hover{opacity:1}@media (max-width:820px){nav.top .links a:not(.lang){display:none}}
h1,h2,h3{font-family:"Bricolage Grotesque",sans-serif;letter-spacing:-.025em;margin:0}
.hero{display:grid;grid-template-columns:1.05fr .95fr;gap:48px;align-items:center;padding:56px 0 72px}
@media (max-width:900px){.hero{grid-template-columns:1fr}}
.hero h1{font-size:clamp(42px,6.4vw,78px);line-height:.98;font-weight:800}.hero h1 em{font-style:normal;color:var(--teal)}
.lede{font-size:19px;color:var(--muted);margin:22px 0 26px;max-width:32em}
.bul{display:grid;gap:12px;margin:0 0 28px;padding:0;list-style:none}.bul li{display:flex;gap:12px}
.bul li:before{content:"";flex:none;width:10px;height:10px;margin-top:9px;border-radius:3px;background:var(--teal);box-shadow:0 0 0 4px color-mix(in srgb,var(--teal) 22%,transparent)}
.bul b{display:block}.bul span{color:var(--muted);font-size:15px}
.cta{display:inline-flex;align-items:center;gap:10px;background:var(--ink);color:var(--bg);padding:14px 22px;border-radius:14px;font-weight:600;text-decoration:none}
.cta svg{width:20px;height:20px}.note{display:block;color:var(--muted);font-size:14px;margin-top:10px}
.shot{display:block;width:100%;height:auto;border-radius:22px;box-shadow:0 30px 70px -30px rgba(0,0,0,.6)}
.frame{background:#1c2b2d;padding:9px;border-radius:30px;box-shadow:0 40px 80px -40px rgba(0,0,0,.7)}
.frame img{display:block;width:100%;height:auto;border-radius:22px}
.hero .frame{max-width:520px;justify-self:center}
section{padding:80px 0;border-top:1px solid var(--line)}
.eyebrow{font-size:13px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--teal);margin:0 0 10px}
h2{font-size:clamp(32px,4.6vw,54px);line-height:1.02;font-weight:800;margin-bottom:28px;max-width:18em}
.news{display:grid;gap:12px}.news div{display:grid;grid-template-columns:90px 1fr;gap:16px;background:var(--card);border-radius:18px;padding:16px 20px}
.news b{font-family:"Bricolage Grotesque";font-size:22px;color:var(--teal)}.news small{display:block;color:var(--muted)}
.rail{display:flex;gap:18px;overflow-x:auto;scroll-snap-type:x mandatory;padding:6px 2px 20px;scrollbar-width:none}.rail::-webkit-scrollbar{display:none}
.dev{flex:none;width:min(84vw,520px);scroll-snap-align:start;background:var(--card);border-radius:26px;padding:24px;display:flex;flex-direction:column;gap:16px}
.dev h3{font-size:24px}.dev p{margin:0;color:var(--muted)}.dev .frame{margin-top:auto;max-height:520px;display:flex;justify-content:center;background:transparent;box-shadow:none;padding:0}
.dev .frame img{max-height:500px;width:auto;max-width:100%;border:8px solid #1c2b2d;border-radius:28px}
.hint{color:var(--muted);font-size:14px}
.feat{display:grid;grid-template-columns:1fr 1fr;gap:48px;align-items:center;padding:34px 0}
.feat:nth-child(even) .txt{order:2}@media (max-width:860px){.feat{grid-template-columns:1fr}.feat:nth-child(even) .txt{order:0}}
.feat .n{font-family:"Bricolage Grotesque";font-size:56px;font-weight:800;color:color-mix(in srgb,var(--teal) 55%,transparent);line-height:1}
.feat h3{font-size:30px;margin:6px 0 10px}.feat p{color:var(--muted);margin:0;font-size:18px}
.feat .frame{max-width:460px;justify-self:center}
.more{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}@media (max-width:820px){.more{grid-template-columns:1fr 1fr}}@media (max-width:520px){.more{grid-template-columns:1fr}}
.more div{background:var(--card);border-radius:20px;padding:20px}.more svg{width:28px;height:28px;color:var(--teal)}
.more b{display:block;font-size:18px;margin:10px 0 2px}.more span{color:var(--muted);font-size:15px}
.plans{display:grid;grid-template-columns:1fr 1fr;gap:18px}@media (max-width:760px){.plans{grid-template-columns:1fr}}
.plan{background:var(--card);border-radius:24px;padding:26px;border:1px solid var(--line)}
.plan.pro{background:linear-gradient(160deg,#0f2b2a,#0a4a44);color:#ecf4f2;border-color:transparent}
.plan h3{font-size:24px}.plan .p{font-family:"Bricolage Grotesque";font-size:46px;font-weight:800;margin:6px 0 14px}
.plan ul{list-style:none;padding:0;margin:0;display:grid;gap:9px}.plan li{display:flex;gap:10px}
.plan li:before{content:"✓";color:var(--teal);font-weight:700}.plan.pro li:before{color:#6be8cc}
.plan small{display:block;margin-top:16px;opacity:.8}
details{border-bottom:1px solid var(--line);padding:16px 0}summary{cursor:pointer;font-weight:600;font-size:18px}details p{color:var(--muted);margin:8px 0 0}
.priv{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}@media (max-width:760px){.priv{grid-template-columns:1fr}}
.priv div{background:var(--card);border-radius:20px;padding:22px}.priv b{display:block;font-size:19px;margin-bottom:4px}.priv span{color:var(--muted)}
.end{text-align:center;padding:100px 0}.end h2{margin:0 auto 12px;font-size:clamp(44px,7vw,86px)}.end p{color:var(--muted);margin:0 0 26px}
footer{border-top:1px solid var(--line);padding:26px 0 40px;color:var(--muted);font-size:14px}footer .wrap{display:flex;flex-wrap:wrap;gap:8px 22px}
"""

APPLE = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9s-1.8-.9-3-.8c-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3 .7c1.3 0 2.1-1.1 2.8-2.3.9-1.3 1.3-2.6 1.3-2.6s-2.5-1-2.5-3.8zM14.2 5.8c.6-.8 1.1-1.9 1-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1 .1 2.1-.5 2.7-1.3z"/></svg>'

FEATURE_SHOTS = ["iphone", "pairs", "palette", "overview", "notes"]


def img(name, alt):
    return f'<div class="frame"><img src="../img/{name}.jpg" alt="{alt}" loading="lazy"></div>'


def build(lang):
    t = T[lang]
    nav = "".join(f'<a href="#{a}">{b}</a>' for a, b in t["nav"])
    bullets = "".join(f"<li><div><b>{a}</b><span>{b}</span></div></li>" for a, b in t["bullets"])
    news = "".join(f"<div><b>{v}</b><span>{x}<small>{d}</small></span></div>" for v, d, x in t["news"])
    devs = "".join(f'<article class="dev"><h3>{h}</h3><p>{p}</p>{img(DEVICES[i][0], h)}</article>' for i, (h, p) in enumerate(t["dev"]))
    feats = "".join(f'<div class="feat"><div class="txt"><span class="n">0{i + 1}</span><h3>{h}</h3><p>{p}</p></div>{img(FEATURE_SHOTS[i], h)}</div>'
                    for i, (h, p) in enumerate(t["feats"]))
    more = "".join(f'<div><svg viewBox="0 0 24 24" aria-hidden="true">{ICONS[ic]}</svg><b>{h}</b><span>{p}</span></div>' for ic, h, p in t["more"])
    plans = "".join(f'<div class="plan{" pro" if i else ""}"><h3>{n}</h3><div class="p">{p}</div><ul>{"".join(f"<li>{x}</li>" for x in items)}</ul>'
                    + (f"<small>{t['pro_note']}</small>" if i else "") + "</div>" for i, (n, p, items) in enumerate(t["plans"]))
    faq = "".join(f"<details><summary>{q}</summary><p>{a}</p></details>" for q, a in t["faq"])
    priv = "".join(f"<div><b>{a}</b><span>{b}</span></div>" for a, b in t["priv"])
    return f"""<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Twinfold</title><meta name="description" content="{t['desc']}">
<meta property="og:title" content="{t['title']}"><meta property="og:description" content="{t['desc']}"><meta property="og:image" content="../img/duo-closed.jpg">
<link rel="icon" href="../icon.png"><link rel="apple-touch-icon" href="../icon.png"><link rel="alternate" hreflang="{t['other']}" href="../{t['other']}/">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,600;12..96,800&family=Instrument+Sans:wght@400;600&display=swap" rel="stylesheet">
<style>{CSS}</style></head><body>
<nav class="top" aria-label="Twinfold"><div class="wrap"><img src="../icon.png" alt=""><b>Twinfold</b><div class="links">{nav}<a class="lang" href="../{t['other']}/" hreflang="{t['other']}">{t['other_name']}</a></div></div></nav>
<main class="wrap">
<div class="hero"><div><h1>{t['h1']}</h1><p class="lede">{t['lede']}</p><ul class="bul">{bullets}</ul>
<a class="cta" href="{STORE}">{APPLE}{t['cta']}</a><span class="note">{t['cta_note']}</span></div>{img('hero', 'Twinfold')}</div>
<section id="video"><p class="eyebrow">Film</p><h2>{t['video_h']}</h2>
<div class="vtabs" role="tablist"><button role="tab" aria-selected="true" data-v="duo">{t['video_tabs'][0]}</button><button role="tab" aria-selected="false" data-v="phones">{t['video_tabs'][1]}</button></div>
<div class="vframe"><video id="film" src="../video/duo-{lang}.mp4" poster="../video/duo-{lang}.jpg" autoplay muted loop playsinline controls preload="metadata"></video></div>
<script>document.querySelectorAll('.vtabs button').forEach(function(b){{b.onclick=function(){{document.querySelectorAll('.vtabs button').forEach(function(x){{x.setAttribute('aria-selected',x===b)}});var v=document.getElementById('film');v.poster='../video/'+b.dataset.v+'-{lang}.jpg';v.src='../video/'+b.dataset.v+'-{lang}.mp4';v.play().catch(function(){{}});}}}});</script></section>
<section id="news"><p class="eyebrow">News</p><h2>{t['news_h']}</h2><div class="news">{news}</div></section>
<section id="devices"><p class="eyebrow">{t['dev_eyebrow']}</p><h2>{t['dev_h']}</h2><div class="rail" tabindex="0">{devs}</div><p class="hint">{t['dev_hint']} →</p></section>
<section id="features"><p class="eyebrow">{t['feat_eyebrow']}</p><h2>{t['feat_h']}</h2>{feats}</section>
<section><h2>{t['more_h']}</h2><div class="more">{more}</div></section>
<section id="pricing"><p class="eyebrow">{t['price_eyebrow']}</p><h2>{t['price_h']}</h2><p class="lede" style="margin-top:-10px">{t['price_lede']}</p><div class="plans">{plans}</div></section>
<section id="faq"><h2>{t['faq_h']}</h2>{faq}</section>
<section id="privacy"><h2>{t['priv_h']}</h2><div class="priv">{priv}</div></section>
<div class="end"><h2>{t['end_h']}</h2><p>{t['end_p']}</p><a class="cta" href="{STORE}">{APPLE}{t['cta']}</a></div>
</main>
<footer><div class="wrap"><span>Twinfold</span><a href="privacy.html">{t['privacy']}</a><a href="mailto:{MAIL}">{t['support']}</a><a href="../{t['other']}/">{t['other_name']}</a></div></footer>
</body></html>"""


os.makedirs(os.path.join(SITE, "img"), exist_ok=True)
VIDEOS = os.path.join(HERE, "..", "store", "video")
if os.path.isdir(VIDEOS):
    os.makedirs(os.path.join(SITE, "video"), exist_ok=True)
    for f in os.listdir(VIDEOS):
        shutil.copy(os.path.join(VIDEOS, f), os.path.join(SITE, "video", f))
if os.path.isdir(SHOTS):
    for f in os.listdir(SHOTS):
        shutil.copy(os.path.join(SHOTS, f), os.path.join(SITE, "img", f))
for lang in T:
    os.makedirs(os.path.join(SITE, lang), exist_ok=True)
    open(os.path.join(SITE, lang, "index.html"), "w").write(build(lang))
print("ok")
