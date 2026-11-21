"""Site Twinfold (assistance + confidentialité) en anglais et en français.

python3 twinfold/tools/site_gen.py  -> clapet/tools/site/twinfold/{en,fr}/index.html et privacy.html
"""
import os, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.join(HERE, "..", "..", "clapet", "tools", "site", "twinfold")
MAIL = "hfreecsapple@gmail.com"

CSS = """
:root{--ink:#13232a;--teal:#0d9e8f;--coral:#fa6b54;--bg:#f6faf8;--card:#fff;--muted:#5b6b70}
@media (prefers-color-scheme:dark){:root{--ink:#e8f1ef;--bg:#0f1a1d;--card:#16252a;--muted:#9fb3b5}}
*{box-sizing:border-box}body{margin:0;font:17px/1.6 -apple-system,system-ui,sans-serif;background:var(--bg);color:var(--ink)}
main{max-width:720px;margin:0 auto;padding:32px 20px 64px}
header{display:flex;align-items:center;gap:14px;margin-bottom:24px}header img{width:64px;height:64px;border-radius:15px}
header b{font-size:28px;letter-spacing:-.01em}nav{margin-left:auto;font-size:14px}a{color:var(--teal)}
h1{font-size:34px;line-height:1.15;margin:8px 0 12px}h2{font-size:21px;margin:32px 0 8px}
.card{background:var(--card);border-radius:16px;padding:18px 20px;margin:14px 0;box-shadow:0 1px 3px rgba(0,0,0,.06)}
.lede{font-size:19px;color:var(--muted)}ul{padding-left:22px}small{color:var(--muted)}
.cta{display:inline-block;background:var(--teal);color:#fff;text-decoration:none;padding:12px 20px;border-radius:12px;font-weight:600}
"""

T = {
 "en": dict(other="fr", other_name="Français", privacy="Privacy",
   title="Twinfold: two web pages at once on iPhone Duo",
   h1="Two pages. One fold.",
   lede="Twinfold is a web browser built for iPhone Duo: one page above the fold, another below, or side by side. On any other iPhone, the two pages share the screen.",
   features=["Two pages at once, split exactly at the fold (or wherever you drag the handle).",
             "Tabs in each pane, private tabs, and a long-press to open any link in the other pane.",
             "Pairs: save two pages that go together and open both in one tap, even from the Home Screen icon.",
             "Bookmarks (import them from another browser), history, find on page, desktop sites.",
             "Blocks ads and trackers. No account, no server, no analytics."],
   faq_h="Help",
   faq=[("How do I switch between one and two pages?", "Tap the split button in the bottom bar. On an unfolded iPhone Duo, Twinfold opens two pages by default; on the cover screen it shows one."),
        ("Which pane does the address bar control?", "The active one, outlined in teal. Tap a pane to make it active."),
        ("How do I open a link in the other pane?", "Touch and hold the link, then choose Open in Other Pane."),
        ("How do I import my bookmarks?", "Export them from your other browser as an HTML file (on a Mac, Safari: File > Export > Bookmarks), save it to Files, then in Twinfold open Bookmarks and History > ••• > Import Bookmarks.")],
   contact="Questions, bugs or ideas: write to", updated="Updated November 21, 2026",
   p_h="Privacy policy",
   p=["Twinfold does not collect any personal data. It has no account, no server, no analytics and no advertising.",
      "Your history, bookmarks, pairs and open tabs are stored only on your iPhone, in Twinfold's own storage. Deleting the app deletes them.",
      "The websites you visit receive what any browser sends them, and their own privacy policies apply. Private tabs keep no cookies or history once closed.",
      "Twinfold fetches no favicons and calls no third-party service on its own. Searches go to the search engine you choose in Settings.",
      "Ad and tracker blocking happens on your iPhone, with a list built into the app."]),
 "fr": dict(other="en", other_name="English", privacy="Confidentialité",
   title="Twinfold : deux pages web à la fois sur iPhone Duo",
   h1="Deux pages. Un pli.",
   lede="Twinfold est un navigateur pensé pour l'iPhone Duo : une page au-dessus du pli, une autre en dessous, ou côte à côte. Sur tout autre iPhone, les deux pages se partagent l'écran.",
   features=["Deux pages à la fois, séparées pile au pli (ou là où vous faites glisser la poignée).",
             "Des onglets dans chaque volet, des onglets privés, et un appui long pour ouvrir un lien dans l'autre volet.",
             "Les paires : enregistrez deux pages qui vont ensemble et ouvrez-les d'un geste, même depuis l'icône sur l'écran d'accueil.",
             "Signets (importables depuis un autre navigateur), historique, recherche dans la page, version ordinateur.",
             "Bloque pubs et traqueurs. Ni compte, ni serveur, ni statistiques."],
   faq_h="Aide",
   faq=[("Comment passer d'une page à deux ?", "Touchez le bouton de partage de l'écran dans la barre du bas. Sur l'iPhone Duo ouvert, Twinfold affiche deux pages par défaut ; sur l'écran extérieur, une seule."),
        ("Quel volet la barre d'adresse commande-t-elle ?", "Le volet actif, entouré en turquoise. Touchez un volet pour le rendre actif."),
        ("Comment ouvrir un lien dans l'autre volet ?", "Maintenez le doigt sur le lien, puis choisissez « Ouvrir dans l'autre volet »."),
        ("Comment importer mes signets ?", "Exportez-les depuis votre autre navigateur en fichier HTML (sur Mac, Safari : Fichier > Exporter > Signets), enregistrez-le dans Fichiers, puis dans Twinfold : Signets et historique > ••• > Importer des signets.")],
   contact="Questions, bugs ou idées : écrivez à", updated="Mis à jour le 21 novembre 2026",
   p_h="Politique de confidentialité",
   p=["Twinfold ne collecte aucune donnée personnelle. Il n'a ni compte, ni serveur, ni statistiques, ni publicité.",
      "Votre historique, vos signets, vos paires et vos onglets ouverts restent uniquement sur votre iPhone, dans le stockage de Twinfold. Supprimer l'app les supprime.",
      "Les sites que vous visitez reçoivent ce que tout navigateur leur envoie, et leurs propres règles de confidentialité s'appliquent. Les onglets privés ne gardent ni cookies ni historique une fois fermés.",
      "Twinfold ne télécharge pas d'icônes de sites et n'appelle de lui-même aucun service tiers. Les recherches vont au moteur choisi dans les réglages.",
      "Le blocage des pubs et des traqueurs se fait sur votre iPhone, avec une liste intégrée à l'app."]),
}

def page(lang, title, body):
    t = T[lang]
    return f"""<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title><meta name="description" content="{t['lede']}"><style>{CSS}</style></head><body><main>
<header><img src="../icon.png" alt=""><b>Twinfold</b><nav><a href="./">Twinfold</a> · <a href="privacy.html">{t['privacy']}</a> · <a href="../{t['other']}/">{t['other_name']}</a></nav></header>
{body}
</main></body></html>"""

for lang, t in T.items():
    d = os.path.join(SITE, lang)
    os.makedirs(d, exist_ok=True)
    feats = "".join(f"<li>{f}</li>" for f in t["features"])
    faq = "".join(f'<div class="card"><b>{q}</b><br>{a}</div>' for q, a in t["faq"])
    body = f"""<h1>{t['h1']}</h1><p class="lede">{t['lede']}</p><ul>{feats}</ul>
<h2>{t['faq_h']}</h2>{faq}<p>{t['contact']} <a href="mailto:{MAIL}">{MAIL}</a>.</p>"""
    open(os.path.join(d, "index.html"), "w").write(page(lang, t["title"], body))
    pb = f"<h1>{t['p_h']}</h1><small>{t['updated']}</small>" + "".join(f"<p>{x}</p>" for x in t["p"]) + \
         f"<p>{t['contact']} <a href=\"mailto:{MAIL}\">{MAIL}</a>.</p>"
    open(os.path.join(d, "privacy.html"), "w").write(page(lang, t["p_h"] + " · Twinfold", pb))
open(os.path.join(SITE, "index.html"), "w").write('<!doctype html><meta charset="utf-8"><script>location.replace((navigator.language||"en").startsWith("fr")?"fr/":"en/")</script><a href="en/">Twinfold</a>')
from PIL import Image
Image.open(os.path.join(HERE, "..", "App", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")).resize((256, 256)).save(os.path.join(SITE, "icon.png"))
print("ok")
