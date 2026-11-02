# Construit le site Foldly (accueil EN à la racine, accueil FR dans accueil/) à partir de landing/index.html.
# usage : python3 clapet/tools/landing/fr.py
import os
L = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.join(L, '..', 'site')
src = open(os.path.join(L, 'index.html')).read()

PAIRS = [
 ('<title>Foldly for iPhone Duo</title>', '<title>Foldly pour iPhone Duo</title>'),
 ('content="Foldly counts every time you open your iPhone Duo. See how often you unfold, how long it rests, and how your week compares. Now on the App Store."',
  'content="Foldly compte chaque ouverture de votre iPhone Duo. Voyez combien de fois vous le dépliez, combien de temps il reste fermé et comment votre semaine se compare. Disponible sur l’App Store."'),
 ('<a href="#counter">Counter</a><a href="#time">Time</a><a href="#week">Week</a><a href="#iphone-duo">iPhone Duo</a><a href="#looks">Looks</a><a href="#privacy">Privacy</a><a href="#questions">Questions</a>',
  '<a href="#counter">Compteur</a><a href="#time">Temps</a><a href="#week">Semaine</a><a href="#iphone-duo">iPhone Duo</a><a href="#looks">Styles</a><a href="#privacy">Confidentialité</a><a href="#questions">Questions</a>'),
 ('<a class="pill-btn" href="#beta">Get the app', '<a class="lang" href="../" data-lang="en">EN</a><a class="pill-btn" href="#beta">Télécharger l’app'),
 ('alt="Foldly app icon"', 'alt="Icône de l’app Foldly"'),
 ('Every fold, counted. <span>Made for iPhone Duo.</span>', 'Chaque pli, compté. <span>Pensé pour l’iPhone Duo.</span>'),
 ('Each time you open your Duo, Foldly counts it. <b>See how often you unfold,</b> how long it rests, and how your week compares.',
  'À chaque ouverture de votre Duo, Foldly compte. <b>Voyez combien de fois vous le dépliez,</b> combien de temps il reste fermé et comment se passe votre semaine.'),
 ('<small>New</small>', '<small>Nouveau</small>'),
 ('<b>Now on the App Store</b><span>Made for iPhone Duo</span>', '<b>Sur l’App Store</b><span>Conçu pour l’iPhone Duo</span>'),
 ('<a class="pill-btn big" href="#beta">Get the app', '<a class="pill-btn big" href="#beta">Télécharger l’app'),
 ('aria-label="Foldly on iPhone Duo">\n', 'aria-label="Foldly sur iPhone Duo">\n'),
 ('aria-label="Foldly on iPhone Duo"></video>', 'aria-label="Foldly sur iPhone Duo"></video>'),
 ('aria-label="Chapters"', 'aria-label="Chapitres"'),
 ('Shown on iPhone Duo. Foldly runs on any iPhone with iOS 17 or later.', 'Présenté sur iPhone Duo. Foldly fonctionne sur tout iPhone avec iOS 17 ou plus récent.'),
 ('<p class="eyebrow">Counter</p>', '<p class="eyebrow">Compteur</p>'),
 ('Open it. It counts. <span>No button to press.</span>', 'Ouvrez. Ça compte. <span>Sans appuyer sur rien.</span>'),
 ("Foldly reads the hinge while it's on screen. When it isn't, a Shortcuts automation counts for it, <b>so every opening is there.</b>",
  'Foldly lit la charnière quand l’app est à l’écran. Sinon, une automatisation Raccourcis compte à sa place, <b>pour ne rater aucune ouverture.</b>'),
 ('<b>The hinge does the work</b><p>Each opening adds one, live, with a soft click.</p>', '<b>La charnière fait tout</b><p>Chaque ouverture ajoute un, en direct, avec un petit clic.</p>'),
 ('<b>Even with Foldly closed</b><p>“When iPhone is Closed” runs “Count a fold”. Set up in a few taps.</p>',
  '<b>Même app fermée</b><p>« Quand l’iPhone est fermé » lance « Compter un pli ». Prêt en quelques touches.</p>'),
 ('<b>Against your average</b><p>Today next to your daily average and yesterday.</p>', '<b>Face à votre moyenne</b><p>Aujourd’hui, à côté de votre moyenne et d’hier.</p>'),
 ('<b>A limit, only if you want one</b><p>Off by default. Alerts at 80 % and 100 %.', '<b>Une limite, seulement si vous voulez</b><p>Désactivée par défaut. Alertes à 80 % et 100 %.'),
 ('<p class="eyebrow">Time</p>', '<p class="eyebrow">Temps</p>'),
 ('Open or closed. <span>Down to the minute.</span>', 'Ouvert ou fermé. <span>À la minute près.</span>'),
 ('Foldly keeps both clocks: how long your Duo is open, and how long it rests. <b>Your longest break</b> of the day too.',
  'Foldly tient les deux comptes : combien de temps votre Duo est ouvert, et combien de temps il reste fermé. <b>Votre plus longue pause</b> de la journée aussi.'),
 ('alt="Time closed: 2 hr, 39 min closed today, 3 hr, 39 min yesterday. Closed 61 %, open 1 hr, 42 min."',
  'alt="Temps fermé : 2 h 39 min aujourd’hui, 3 h 39 min hier. Fermé 61 %, ouvert 1 h 42 min."'),
 ('<p class="eyebrow">Week</p>', '<p class="eyebrow">Semaine</p>'),
 ('Your week. <span>Every Sunday.</span>', 'Votre semaine. <span>Chaque dimanche.</span>'),
 ('A short recap on Sunday evening: your total, the change from last week, <b>your calmest and busiest days,</b> open and closed time.',
  'Un court bilan le dimanche soir : votre total, l’écart avec la semaine d’avant, <b>vos jours les plus calmes et les plus chargés,</b> le temps ouvert et fermé.'),
 ('alt="Your week, Oct 18 to 24: 356 folds, 10 % less than the week before, 51 per day."', 'alt="Votre semaine, du 18 au 24 oct. : 356 plis, 10 % de moins que la semaine d’avant, 51 par jour."'),
 ('Ready for iPhone Duo. <span>Every pose.</span>', 'Prêt pour l’iPhone Duo. <span>Dans toutes les positions.</span>'),
 ("Closed, Foldly runs on the outer display like on any iPhone. Open, it takes the big screen. Half open, it reads like a book, or <b>stands on your desk</b> like a little dashboard. Watch the film above, or",
  'Fermé, Foldly s’affiche sur l’écran extérieur comme sur n’importe quel iPhone. Ouvert, il prend le grand écran. À moitié ouvert, il se lit comme un livre, ou <b>tient debout sur votre bureau</b> comme un petit tableau de bord. Regardez le film plus haut, ou'),
 ('id="replay">play it again</button>', 'id="replay">revoyez-le</button>'),
 ("<b>Outer display</b><p>Today's count, your average and the time it rests, right by the camera.</p>",
  '<b>Écran extérieur</b><p>Le compte du jour, votre moyenne et le temps fermé, juste à côté de l’appareil photo.</p>'),
 ('<b>Live Activity</b><p>Your count on the Lock Screen and the outer display, updated at every fold.</p>',
  '<b>Activité en direct</b><p>Votre compte sur l’écran verrouillé et l’écran extérieur, mis à jour à chaque pli.</p>'),
 ('<b>StandBy</b><p>Fold it in an L, add a Foldly widget, and your numbers stay big and readable.</p>',
  '<b>En veille</b><p>Pliez-le en L, ajoutez un widget Foldly, et vos chiffres restent grands et lisibles.</p>'),
 ('<b>Any iPhone</b><p>No hinge? Tap the number to count. Everything else works the same.</p>',
  '<b>Tout iPhone</b><p>Pas de charnière ? Touchez le chiffre pour compter. Tout le reste fonctionne pareil.</p>'),
 ('Your count. <span>Everywhere.</span>', 'Votre compte. <span>Partout.</span>'),
 ('Home Screen, Lock Screen and StandBy. <b>Open &amp; closed</b> shows both clocks side by side; the big widget adds your week.',
  'Écran d’accueil, écran verrouillé et mode En veille. <b>Ouvert et fermé</b> montre les deux temps côte à côte ; le grand widget ajoute votre semaine.'),
 ('alt="Foldly widgets on the Home Screen: 47 folds today, the week chart, open and closed time."', 'alt="Widgets Foldly sur l’écran d’accueil : 47 plis aujourd’hui, le graphique de la semaine, le temps ouvert et fermé."'),
 ('<p class="eyebrow">Looks</p>', '<p class="eyebrow">Styles</p>'),
 ('Make it yours. <span>Three looks.</span>', 'À votre goût. <span>Trois styles.</span>'),
 ('Pick one the first time you open Foldly, <b>switch anytime</b> in Settings.', 'Choisissez-en un à la première ouverture, <b>changez quand vous voulez</b> dans les Réglages.'),
 ('alt="Classic look: a ring with 47 folds"', 'alt="Style Classique : un anneau avec 47 plis"'),
 ('<b>Classic</b>Like the Health app', '<b>Classique</b>Comme l’app Santé'),
 ('alt="Modern look: 47 folds with a hinge gauge"', 'alt="Style Moderne : 47 plis avec une jauge de charnière"'),
 ('<b>Modern</b>Big numbers, dark', '<b>Moderne</b>Grands chiffres, sombre'),
 ('alt="Minimal look: a thin 47 and three figures"', 'alt="Style Minimal : un 47 fin et trois chiffres"'),
 ('<b>Minimal</b>Just your numbers', '<b>Minimal</b>Juste vos chiffres'),
 ('<p class="eyebrow">Details</p>', '<p class="eyebrow">Détails</p>'),
 ('And everything else. <span>The small things.</span>', 'Et tout le reste. <span>Les petites choses.</span>'),
 ('<b>Full history<span class="tag">Plus</span></b><p>30 days, 12 months and a calendar of your days, with your records.</p>',
  '<b>Historique complet<span class="tag">Plus</span></b><p>30 jours, 12 mois et un calendrier de vos journées, avec vos records.</p>'),
 ('<b>Export<span class="tag">Plus</span></b><p>Your history as a spreadsheet (CSV).</p>', '<b>Export<span class="tag">Plus</span></b><p>Votre historique en tableur (CSV).</p>'),
 ('<b>Widget colors<span class="tag">Plus</span></b><p>Five colors for your widgets.</p>', '<b>Couleurs des widgets<span class="tag">Plus</span></b><p>Cinq couleurs pour vos widgets.</p>'),
 ('<b>Evening summary</b><p>An optional note at the end of the day.</p>', '<b>Bilan du soir</b><p>Une notification facultative en fin de journée.</p>'),
 ("<b>Share your day</b><p>Today's numbers on a clean card.</p>", '<b>Partagez votre journée</b><p>Vos chiffres du jour sur une jolie carte.</p>'),
 ('<b>Opening animation</b><p>The hinge in the logo unfolds, then your count rolls up.</p>', '<b>Animation d’ouverture</b><p>La charnière du logo se déplie, puis votre compte défile.</p>'),
 ('<b>Shortcuts</b><p>“Count a fold” works in any automation.</p>', '<b>Raccourcis</b><p>« Compter un pli » marche dans n’importe quelle automatisation.</p>'),
 ('<b>Sounds and vibrations</b><p>Feel each fold, or keep it silent.</p>', '<b>Sons et vibrations</b><p>Sentez chaque pli, ou restez en silence.</p>'),
 ('<p class="eyebrow">Privacy</p>', '<p class="eyebrow">Confidentialité</p>'),
 ('No account. No ads. <span>Nothing leaves your iPhone.</span>', 'Pas de compte. Pas de pub. <span>Rien ne quitte votre iPhone.</span>'),
 ('Foldly collects no data. Your folds stay on your iPhone, <b>shared only with Foldly\'s own widgets.</b> <a href="https://foldly.netlify.app/en/privacy.html">Privacy policy</a>',
  'Foldly ne collecte aucune donnée. Vos plis restent sur votre iPhone, <b>partagés uniquement avec les widgets de Foldly.</b> <a href="https://foldly.netlify.app/fr/privacy.html">Politique de confidentialité</a>'),
 ('<span class="fact"><b>No</b> account</span><span class="fact"><b>No</b> ads or analytics</span><span class="fact"><b>No</b> third-party services</span><span class="fact">Works <b>offline</b></span>',
  '<span class="fact"><b>Aucun</b> compte</span><span class="fact"><b>Ni</b> pub ni statistiques</span><span class="fact"><b>Aucun</b> service tiers</span><span class="fact">Marche <b>hors ligne</b></span>'),
 ('<summary>What do I need?</summary><p>An iPhone with iOS 17 or later. On iPhone Duo, Foldly counts each fold by itself. On other iPhones, you tap the number to count.</p>',
  '<summary>De quoi ai-je besoin ?</summary><p>Un iPhone avec iOS 17 ou plus récent. Sur iPhone Duo, Foldly compte chaque pli tout seul. Sur les autres iPhone, vous touchez le chiffre pour compter.</p>'),
 ('<summary>Does it count when the app is closed?</summary><p>Yes, with a Shortcuts automation: “When iPhone is Closed”, then “Count a fold”. Foldly walks you through it.</p>',
  '<summary>Ça compte quand l’app est fermée ?</summary><p>Oui, avec une automatisation Raccourcis : « Quand l’iPhone est fermé », puis « Compter un pli ». Foldly vous guide.</p>'),
 ('<summary>Will Foldly limit how I use my phone?</summary><p>No. It only counts. The daily limit is optional and off by default; without it, Foldly compares today with your own average.</p>',
  '<summary>Foldly va-t-il limiter mon usage du téléphone ?</summary><p>Non. Il compte, c’est tout. La limite quotidienne est facultative et désactivée par défaut ; sans elle, Foldly compare aujourd’hui à votre propre moyenne.</p>'),
 ("<summary>Where do my numbers go?</summary><p>Nowhere. They stay on your iPhone, shared only with Foldly's widgets. There is no account and no server.</p>",
  '<summary>Où vont mes chiffres ?</summary><p>Nulle part. Ils restent sur votre iPhone, partagés uniquement avec les widgets de Foldly. Il n’y a ni compte ni serveur.</p>'),
 ('<summary>What does it cost?</summary><p>One purchase, once: the full history, every widget, widget colors, limit alerts and export. No subscription, no ads.</p>',
  '<summary>Combien ça coûte ?</summary><p>Un seul achat, une fois : l’historique complet, tous les widgets, leurs couleurs, les alertes de limite et l’export. Sans abonnement, sans pub.</p>'),
 ("<summary>Which languages?</summary><p>English and French. Foldly follows your iPhone's language.</p>",
  '<summary>Quelles langues ?</summary><p>Français et anglais. Foldly suit la langue de votre iPhone.</p>'),
 ('<summary>When can I try it?</summary><p>Now. Download Foldly from the App Store on your iPhone.</p>',
  '<summary>Quand puis-je l’essayer ?</summary><p>Maintenant. Téléchargez Foldly sur l’App Store depuis votre iPhone.</p>'),
 ('<h2 id="beta-h">Foldly is on the App Store.</h2>', '<h2 id="beta-h">Foldly est sur l’App Store.</h2>'),
 ('Download it on your iPhone, and <b>Foldly is yours.</b>', 'Téléchargez-le sur votre iPhone, et <b>Foldly est à vous.</b>'),
 ('>Download on the App Store</a>', '>Télécharger sur l’App Store</a>'),
 ('<small>iPhone · iOS 17 or later</small>', '<small>iPhone · iOS 17 ou plus récent</small>'),
 ('id="share">Share Foldly with a friend</button>', 'id="share">Partager Foldly avec un ami</button>'),
 ('<p>Apple, iPhone, iPhone Duo and StandBy are trademarks of Apple Inc. Foldly is an independent app, not affiliated with or endorsed by Apple.</p>',
  '<p>Apple, iPhone, iPhone Duo et StandBy sont des marques d’Apple Inc. Foldly est une app indépendante, ni affiliée à Apple ni approuvée par Apple.</p>'),
 ('<a href="https://foldly.netlify.app/en/privacy.html">Privacy</a> · <a href="https://foldly.netlify.app/en/">Support</a> · <a href="https://foldly.netlify.app/fr/">Français</a> · <a href="https://foldly.netlify.app/press/">Press</a>',
  '<a href="https://foldly.netlify.app/fr/privacy.html">Confidentialité</a> · <a href="https://foldly.netlify.app/fr/">Assistance</a> · <a href="../" data-lang="en">English</a> · <a href="https://foldly.netlify.app/press/">Presse</a>'),
 ("label: 'Closed', cap: '<b>Closed, it\\'s an iPhone.</b> Today\\'s count sits on the outer display.'", "label: 'Fermé', cap: '<b>Fermé, c\\'est un iPhone.</b> Le compte du jour est sur l\\'écran extérieur.'"),
 ("label: 'Open', cap: '<b>Open it, and it counts.</b> Every fold adds one, live.'", "label: 'Ouvert', cap: '<b>Ouvrez-le, il compte.</b> Chaque pli ajoute un, en direct.'"),
 ("label: 'Looks', cap: '<b>One tap, a new look.</b> Modern, Classic or Minimal.'", "label: 'Styles', cap: '<b>Une touche, un autre style.</b> Moderne, Classique ou Minimal.'"),
 ("label: 'Desk', cap: '<b>Fold it halfway.</b> The count stands on top, the details lie below.'", "label: 'Bureau', cap: '<b>Pliez-le à moitié.</b> Le compte en haut, les détails en bas.'"),
 ("label: 'Your hours', cap: '<b>Your hours.</b> When you fold the most, hour by hour.'", "label: 'Vos heures', cap: '<b>Vos heures.</b> Quand vous pliez le plus, heure par heure.'"),
 ("label: 'Week', cap: '<b>Every Sunday, your week.</b> The total, the change, your calmest day.'", "label: 'Semaine', cap: '<b>Chaque dimanche, votre semaine.</b> Le total, l\\'écart, votre jour le plus calme.'"),
 ("p ? 'Pause' : 'Play'", "p ? 'Pause' : 'Lecture'"),
 ("'Link copied: ' + url", "'Lien copié : ' + url"),
]

# Bascule de langue (EN à la racine, FR dans accueil/) : le choix est retenu ; sinon on suit la langue du navigateur.
LANG_CSS = '.lang{font-size:12px;font-weight:600;color:var(--soft);text-decoration:none;padding:6px 8px;border-radius:999px}.lang:hover{color:var(--fg)}\n'
LANG_JS = '''
document.querySelectorAll('[data-lang]').forEach(a => a.addEventListener('click', () => { try { localStorage.setItem('foldly-lang', a.dataset.lang); } catch {} }));
'''
REDIRECT_EN = '''<script>
try { const l = localStorage.getItem('foldly-lang'); if ((l === 'fr' || (!l && (navigator.language || '').toLowerCase().startsWith('fr'))) && !location.hash) location.replace('accueil/'); } catch {}
</script>
'''

def wrap(html, lang, extra_head=''):
    i = html.index('</style>')
    head, body = html[:i], html[i + len('</style>'):]
    reset = '*,*::before,*::after{box-sizing:border-box}body{margin:0;font:14px/1.4 -apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif}img{max-width:100%}[hidden]{display:none!important}\n'
    head = head.replace('<style>', '<style>\n' + reset + LANG_CSS, 1)
    body = body.replace('</script>', LANG_JS + '</script>')
    return (f'<!doctype html>\n<html lang="{lang}">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">\n'
            f'{extra_head}{head}</style>\n'
            '<link rel="alternate" hreflang="en" href="https://foldly.netlify.app/">\n'
            '<link rel="alternate" hreflang="fr" href="https://foldly.netlify.app/accueil/">\n'
            f'</head>\n<body>{body}\n</body>\n</html>\n')

# EN : ajoute le lien FR dans l'en-tête et le pied
en = src.replace('<a class="pill-btn" href="#beta">Get the app', '<a class="lang" href="accueil/" data-lang="fr">FR</a><a class="pill-btn" href="#beta">Get the app', 1)
en = en.replace('<a href="https://foldly.netlify.app/fr/">Français</a>', '<a href="accueil/" data-lang="fr">Français</a>')
open(os.path.join(SITE, 'index.html'), 'w').write(wrap(en, 'en', REDIRECT_EN))

fr = src
for a, b in PAIRS:
    n = fr.count(a)
    assert n >= 1, 'introuvable : ' + a[:70]
    fr = fr.replace(a, b)
for p in ('src="icon.png"', 'href="icon.png"', 'src="img/', 'poster="film/'):
    fr = fr.replace(p, p.replace('="', '="../'))
fr = fr.replace('`film/${', '`../film/${')
os.makedirs(os.path.join(SITE, 'accueil'), exist_ok=True)
open(os.path.join(SITE, 'accueil', 'index.html'), 'w').write(wrap(fr, 'fr'))
print('ok')
