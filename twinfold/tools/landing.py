"""Page d'accueil Twinfold (en, fr) : clapet/tools/site/twinfold/{en,fr}/index.html.

python3 twinfold/tools/landing.py   (après site_gen.py, qui écrit les pages de confidentialité)
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.join(HERE, "..", "..", "clapet", "tools", "site", "twinfold")
STORE = "https://apps.apple.com/app/id6837801236"
MAIL = "hfreecsapple@gmail.com"

T = {
    "en": dict(
        other="fr", other_name="Français", lang_label="Langue",
        title="Twinfold: two web pages at once, made for iPhone Duo",
        desc="Twinfold is a free web browser that shows two pages at once: one above the fold of your iPhone Duo, one below. Tabs, pairs, AI beside the page, reader view, tracker blocking. No account, no server.",
        nav=["What it does", "Scenes", "Privacy", "Help"],
        h1a="One page above", h1b="the fold.", h1c="One below.",
        lede="Twinfold is a web browser that opens two pages at once. On iPhone Duo they meet exactly at the fold. On any other iPhone, they share the screen.",
        cta="Download on the App Store", cta_note="Free. No account. No in-app purchases.",
        demo_hint="Tap a scene, tap a page to make it active.",
        scenes_h="Pick a scene",
        scenes=[("cook", "Cook along"), ("ai", "Ask AI about it"), ("study", "Read and take notes"), ("shop", "Compare two shops")],
        bar="dailyloaf.example",
        f_h="Everything a browser does, twice",
        feats=[
            ("Split at the fold", "Unfold your Duo and the two pages sit on each half, never across the crease. Hold it sideways for side by side."),
            ("One bar, the active page", "The address bar, back and forward act on the page outlined in teal. Tap the other page to switch."),
            ("Open in the other pane", "Touch and hold any link and send it to the other half. Read the article, keep the list."),
            ("Two videos, two sounds", "Each pane has its own sound button. Watch the match, mute the cooking show, or stretch a video over its half."),
            ("AI beside the page", "ChatGPT, Claude or Gemini open in the other pane, on their own sites, with your own account: summarize, translate, explain."),
            ("Pairs", "Save two pages that go together and open both in one tap, even from the Home Screen icon."),
            ("Reader and read aloud", "The text alone, in your size and colours, read out loud if you like. Or save the whole page as a PDF."),
            ("Follow sites", "Follow a site's feed and get every new article in one list, fetched straight from the site."),
        ],
        p_h="Private by design",
        p_lede="Twinfold has no account, no server and no analytics. It blocks ads and trackers with a list built into the app, and can hide cookie banners.",
        p_points=["History and bookmarks stay on your iPhone", "Private tabs forget everything when closed", "No favicons fetched, no third-party calls", "Your choice of search engine: Google, DuckDuckGo, Bing, Ecosia, Qwant, Startpage"],
        g_h="Gestures, if you like them",
        gestures=[("←", "Two fingers left", "Back"), ("→", "Two fingers right", "Forward"), ("↓", "Two fingers down", "One or two pages"), ("↑", "Two fingers up", "New tab")],
        faq_h="Help",
        faq=[("How do I switch between one and two pages?", "Tap the split button in the bottom bar. On an unfolded iPhone Duo, Twinfold opens two pages by default; on the cover screen it shows one."),
             ("Which pane does the address bar control?", "The active one, outlined in teal. Tap a pane to make it active."),
             ("How do I import my bookmarks?", "Export them from your other browser as an HTML file, save it to Files, then in Twinfold: Bookmarks and History, the ••• button, Import Bookmarks."),
             ("Can Twinfold be my default browser?", "Not yet: Apple has to approve it first. It's coming in an update.")],
        contact="Questions, bugs or ideas:", privacy="Privacy policy", made="Made for iPhone Duo. Works on every iPhone with iOS 27.",
        end_h="Two pages. One fold.", end_p="Free on the App Store.",
    ),
    "fr": dict(
        other="en", other_name="English", lang_label="Language",
        title="Twinfold : deux pages web à la fois, pensé pour l'iPhone Duo",
        desc="Twinfold est un navigateur gratuit qui affiche deux pages à la fois : une au-dessus du pli de l'iPhone Duo, une en dessous. Onglets, paires, IA à côté de la page, mode lecture, blocage des traqueurs. Sans compte, sans serveur.",
        nav=["Ce qu'il fait", "Scènes", "Confidentialité", "Aide"],
        h1a="Une page au-dessus", h1b="du pli.", h1c="Une en dessous.",
        lede="Twinfold est un navigateur web qui ouvre deux pages à la fois. Sur l'iPhone Duo, elles se rejoignent pile au pli. Sur tout autre iPhone, elles se partagent l'écran.",
        cta="Télécharger dans l'App Store", cta_note="Gratuit. Sans compte. Sans achat intégré.",
        demo_hint="Touchez une scène, touchez une page pour la rendre active.",
        scenes_h="Choisissez une scène",
        scenes=[("cook", "Cuisiner en suivant"), ("ai", "Demander à l'IA"), ("study", "Lire et prendre des notes"), ("shop", "Comparer deux boutiques")],
        bar="dailyloaf.example",
        f_h="Tout ce que fait un navigateur, en double",
        feats=[
            ("Séparé au pli", "Ouvrez votre Duo : chaque page occupe sa moitié, jamais à cheval sur le pli. Tenez-le à l'horizontale pour les avoir côte à côte."),
            ("Une barre, la page active", "La barre d'adresse, retour et avancer agissent sur la page entourée de turquoise. Touchez l'autre page pour changer."),
            ("Ouvrir dans l'autre volet", "Maintenez le doigt sur un lien et envoyez-le dans l'autre moitié. Lisez l'article, gardez la liste."),
            ("Deux vidéos, deux sons", "Chaque volet a son bouton son. Regardez le match, coupez l'émission de cuisine, ou étirez une vidéo sur sa moitié."),
            ("L'IA à côté de la page", "ChatGPT, Claude ou Gemini s'ouvrent dans l'autre volet, sur leurs sites, avec votre compte : résumer, traduire, expliquer."),
            ("Les paires", "Enregistrez deux pages qui vont ensemble et ouvrez-les d'un geste, même depuis l'icône de l'écran d'accueil."),
            ("Lecture et voix", "Le texte seul, à votre taille et vos couleurs, lu à voix haute si vous voulez. Ou toute la page en PDF."),
            ("Suivre des sites", "Suivez le flux d'un site et retrouvez chaque nouvel article dans une seule liste, récupéré directement sur le site."),
        ],
        p_h="Privé par nature",
        p_lede="Twinfold n'a ni compte, ni serveur, ni statistiques. Il bloque pubs et traqueurs avec une liste intégrée à l'app, et peut masquer les bandeaux cookies.",
        p_points=["L'historique et les signets restent sur votre iPhone", "Les onglets privés oublient tout une fois fermés", "Aucune icône de site téléchargée, aucun appel à un tiers", "Le moteur de recherche de votre choix : Google, DuckDuckGo, Bing, Ecosia, Qwant, Startpage"],
        g_h="Des gestes, si vous aimez",
        gestures=[("←", "Deux doigts à gauche", "Retour"), ("→", "Deux doigts à droite", "Avancer"), ("↓", "Deux doigts vers le bas", "Une ou deux pages"), ("↑", "Deux doigts vers le haut", "Nouvel onglet")],
        faq_h="Aide",
        faq=[("Comment passer d'une page à deux ?", "Touchez le bouton de partage de l'écran dans la barre du bas. Sur l'iPhone Duo ouvert, Twinfold affiche deux pages par défaut ; sur l'écran extérieur, une seule."),
             ("Quel volet la barre d'adresse commande-t-elle ?", "Le volet actif, entouré de turquoise. Touchez un volet pour le rendre actif."),
             ("Comment importer mes signets ?", "Exportez-les depuis votre autre navigateur en fichier HTML, enregistrez-le dans Fichiers, puis dans Twinfold : Signets et historique, bouton •••, Importer des signets."),
             ("Twinfold peut-il être mon navigateur par défaut ?", "Pas encore : Apple doit d'abord l'autoriser. Ça arrive dans une mise à jour.")],
        contact="Questions, bugs ou idées :", privacy="Politique de confidentialité", made="Pensé pour l'iPhone Duo. Fonctionne sur tout iPhone avec iOS 27.",
        end_h="Deux pages. Un pli.", end_p="Gratuit sur l'App Store.",
    ),
}

# Mini pages drawn in the device, per scene: (top pane, bottom pane), each a list of HTML blocks.
PAGES = {
    "cook": ("""<div class="pg dark"><div class="vid" style="--a:#e9b872;--b:#8a5424"><i class="play"></i><span class="tbar"><b style="width:38%"></b></span></div>
<div class="pad"><b class="t">Country sourdough · Ep. 3</b><span class="m">Daily Loaf · 84K views</span><span class="chip">Bread</span><span class="chip">Weekend</span></div></div>""",
             """<div class="pg cream"><div class="pad"><span class="kick">DAILY LOAF · RECIPES</span><b class="h serif">Shaping and scoring</b>
<span class="row"><i class="box"></i>800 g bread flour</span><span class="row"><i class="box"></i>750 g water</span><span class="row"><i class="box"></i>20 g sea salt</span>
<span class="line" style="width:92%"></span><span class="line" style="width:80%"></span><span class="line" style="width:86%"></span></div></div>"""),
    "ai": ("""<div class="pg"><div class="hero-img" style="--a:#9fc9e6;--b:#24506d"></div><div class="pad"><span class="kick blue">CITY</span><b class="h serif">The old pier reopens as a market hall</b>
<span class="line" style="width:95%"></span><span class="line" style="width:88%"></span><span class="line" style="width:70%"></span></div></div>""",
           """<div class="pg"><div class="pad chat"><span class="bubble me">Summarize this page in a few bullet points</span>
<span class="bubble ai"><b>•</b> 40 stalls, a bakery and a rooftop terrace<br><b>•</b> Open 8 a.m. to 8 p.m.<br><b>•</b> Island ferry returns next month</span><span class="typing"><i></i><i></i><i></i></span></div></div>"""),
    "study": ("""<div class="pg"><div class="pad"><span class="kick green">LANGUAGE LAB</span><b class="h">Lesson 12: the past tense</b>
<span class="line" style="width:90%"></span><span class="line" style="width:96%"></span><span class="hl">j'ai mangé · tu as vu · il est parti</span><span class="line" style="width:84%"></span><span class="line" style="width:60%"></span></div></div>""",
              """<div class="pg note"><div class="pad"><b class="h hand">Notes</b><span class="row tick">avoir + participe</span><span class="row tick">être: aller, partir, venir</span><span class="row">accord with être!</span><span class="caret"></span></div></div>"""),
    "shop": ("""<div class="pg"><div class="prod" style="--a:#f6c453;--b:#e0803a"></div><div class="pad"><b class="t">Trail runner 4</b><span class="price">€119</span><span class="m">★★★★☆ · Free returns</span></div></div>""",
             """<div class="pg"><div class="prod" style="--a:#8fd0b5;--b:#2f8f74"></div><div class="pad"><b class="t">Trail runner 4</b><span class="price">€104</span><span class="m">★★★★☆ · Ships Monday</span></div></div>"""),
}
HOSTS = {"cook": ("dailyloaf.example", "dailyloaf.example"), "ai": ("harbornews.example", "claude.ai"),
         "study": ("languagelab.example", "fieldnotes.example"), "shop": ("runshop.example", "trailstore.example")}

CSS = r"""
:root{--paper:#eef4f2;--card:#ffffff;--ink:#0f2427;--muted:#4e6467;--teal:#0d9e8f;--teal-d:#087a6e;--coral:#f4614a;--fold:#c3d3cf;--shell:#1a2b2e}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--paper:#0c1719;--card:#132326;--ink:#e6f0ee;--muted:#9cb2b1;--fold:#27403f;--shell:#2c4246}}
:root[data-theme=dark]{--paper:#0c1719;--card:#132326;--ink:#e6f0ee;--muted:#9cb2b1;--fold:#27403f;--shell:#2c4246}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;background:var(--paper);color:var(--ink);font:17px/1.6 "Instrument Sans",-apple-system,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
a{color:var(--teal-d)}@media (prefers-color-scheme:dark){a{color:#3cc8b8}}
:focus-visible{outline:3px solid var(--coral);outline-offset:3px;border-radius:6px}
.skip{position:absolute;left:-999px}.skip:focus{left:16px;top:16px;background:var(--card);padding:8px 12px;z-index:9}
.wrap{max-width:1140px;margin:0 auto;padding:0 20px}
header.top{display:flex;align-items:center;gap:12px;padding:18px 0}
header.top img{width:36px;height:36px;border-radius:9px}header.top b{font-family:"Bricolage Grotesque",sans-serif;font-size:21px;letter-spacing:-.01em}
header.top nav{margin-left:auto;display:flex;gap:18px;font-size:15px}header.top nav a{color:var(--ink);text-decoration:none;opacity:.8}
header.top nav a:hover{opacity:1}
@media (max-width:760px){header.top nav a:not(.lang){display:none}}

/* The hero is cut by the fold line, like the device */
.hero{position:relative;display:grid;grid-template-columns:1.05fr .95fr;gap:40px;align-items:center;padding:26px 0 64px}
@media (max-width:900px){.hero{grid-template-columns:1fr;gap:28px}}
h1{font-family:"Bricolage Grotesque",sans-serif;font-weight:800;font-size:clamp(44px,7.4vw,92px);line-height:.92;letter-spacing:-.035em;margin:0}
h1 .a{display:block}h1 .fold{display:block;height:0;border-top:2px dashed var(--fold);margin:.22em 0 .2em;width:min(100%,520px)}
h1 .b{display:block;color:var(--teal)}
.lede{font-size:20px;color:var(--muted);max-width:30em;margin:22px 0 26px}
.cta{display:inline-flex;align-items:center;gap:10px;background:var(--ink);color:var(--paper);text-decoration:none;padding:14px 22px;border-radius:14px;font-weight:600}
.cta svg{width:20px;height:20px}.note{display:block;color:var(--muted);font-size:14px;margin-top:10px}

/* The device */
.stage{display:flex;flex-direction:column;align-items:center}
.duo{perspective:1600px;width:min(100%,360px)}
.half{position:relative;background:var(--shell);padding:10px 10px 4px;border-radius:30px 30px 6px 6px;transform-origin:50% 100%;
  box-shadow:0 30px 60px -30px rgba(10,40,40,.45)}
.half.bottom{border-radius:6px 6px 30px 30px;padding:4px 10px 10px;transform-origin:50% 0}
.half.top{animation:unfold 1.5s cubic-bezier(.2,.8,.2,1) .25s both}
@keyframes unfold{from{transform:rotateX(-170deg)}to{transform:rotateX(0)}}
@media (prefers-reduced-motion:reduce){.half.top{animation:none}}
.hinge{height:8px;margin:0 22px;background:linear-gradient(90deg,#33494d,#5d7377,#33494d);border-radius:2px}
.screen{position:relative;height:250px;border-radius:22px 22px 3px 3px;overflow:hidden;background:#fff;cursor:pointer;
  outline:3px solid transparent;outline-offset:-3px;transition:outline-color .2s}
.half.bottom .screen{border-radius:3px 3px 22px 22px;height:290px}
.screen.active{outline-color:var(--teal)}
.bar{position:absolute;left:0;right:0;bottom:0;height:46px;background:rgba(246,249,248,.94);backdrop-filter:blur(8px);display:flex;align-items:center;gap:8px;padding:0 10px;font-size:12px;color:#1c2f31}
.bar .url{flex:1;background:#e5ecea;border-radius:9px;padding:6px 10px;text-align:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bar i{width:22px;height:22px;border-radius:6px;border:1.6px solid #1c2f31;display:inline-grid;place-items:center;font-style:normal;font-size:10px;font-weight:700}
.panes{position:absolute;inset:0}
.pg{position:absolute;inset:0;background:#fff;color:#1b2426;font-size:12px;line-height:1.45;transition:opacity .45s, transform .45s}
.pg.out{opacity:0;transform:translateY(8px)}
.pg.dark{background:#111214;color:#eee}.pg.cream{background:#fff8ee;color:#2b2118}.pg.note{background:#fffbea}
.pad{padding:12px 14px;display:flex;flex-direction:column;gap:6px}
.vid,.hero-img,.prod{height:118px;background:radial-gradient(circle at 35% 40%,var(--a),var(--b));position:relative}
.prod{height:126px;border-radius:0;background:radial-gradient(ellipse at 50% 60%,var(--a) 0 30%,var(--b) 31% 34%,#f4f1ec 35%)}
.play{position:absolute;left:50%;top:50%;width:34px;height:34px;margin:-17px;border-radius:50%;background:rgba(255,255,255,.25)}
.play:after{content:"";position:absolute;left:13px;top:10px;border-left:11px solid #fff;border-top:7px solid transparent;border-bottom:7px solid transparent}
.tbar{position:absolute;left:8px;right:8px;bottom:8px;height:3px;background:rgba(255,255,255,.3);border-radius:2px}.tbar b{display:block;height:100%;background:#ff5a4e;border-radius:2px}
.t{font-size:13px}.h{font-size:16px;line-height:1.2}.serif{font-family:Georgia,serif}.hand{font-family:"Bricolage Grotesque";font-size:18px}
.m{color:#8a8f90;font-size:11px}.kick{font-weight:700;font-size:10px;letter-spacing:.06em;color:#a4552b}.kick.blue{color:#1a6ea8}.kick.green{color:#1d7a5f}
.chip{display:inline-block;background:#26272a;border-radius:10px;padding:2px 8px;font-size:10px;margin-right:4px;width:max-content}
.line{display:block;height:6px;border-radius:3px;background:#dfe5e3}.pg.cream .line{background:#efe1cb}
.row{display:flex;align-items:center;gap:6px}.box{width:9px;height:9px;border:1.5px solid #a4552b;border-radius:2px}
.row.tick:before{content:"✓";color:var(--teal)}.hl{background:#fff1a8;border-radius:4px;padding:2px 5px;width:max-content}
.caret{width:2px;height:14px;background:var(--teal);animation:blink 1s steps(2) infinite}@keyframes blink{50%{opacity:0}}
.price{font-family:"Bricolage Grotesque";font-size:22px;font-weight:800}
.chat{gap:10px}.bubble{padding:8px 10px;border-radius:12px;max-width:88%}.bubble.me{align-self:flex-end;background:#e9efee}
.bubble.ai{background:#f4f1ea}.typing{display:flex;gap:4px}.typing i{width:6px;height:6px;border-radius:50%;background:#b9c5c3;animation:dot 1.2s infinite}
.typing i:nth-child(2){animation-delay:.2s}.typing i:nth-child(3){animation-delay:.4s}@keyframes dot{40%{transform:translateY(-4px)}}
.mute{position:absolute;right:10px;bottom:56px;background:rgba(0,0,0,.55);color:#fff;border-radius:16px;padding:4px 10px;font-size:11px;display:none}
.half.top .mute{bottom:10px}.screen.vid-on .mute{display:block}
.scenes{display:flex;flex-wrap:wrap;gap:8px;justify-content:center;margin-top:22px}
.scenes button{font:inherit;font-size:14px;border:1.5px solid var(--fold);background:var(--card);color:var(--ink);padding:8px 14px;border-radius:999px;cursor:pointer}
.scenes button[aria-pressed=true]{background:var(--teal);border-color:var(--teal);color:#fff}
.hint{color:var(--muted);font-size:13px;margin-top:10px;text-align:center}

section{padding:72px 0;border-top:1px solid var(--fold)}
h2{font-family:"Bricolage Grotesque",sans-serif;font-weight:800;font-size:clamp(32px,4.4vw,52px);letter-spacing:-.025em;line-height:1;margin:0 0 30px;max-width:16em}
/* Features: two columns that meet at a fold line */
.feats{display:grid;grid-template-columns:1fr 1fr;column-gap:0;row-gap:0}
.feats div{padding:22px 28px 22px 0}.feats div:nth-child(even){padding:22px 0 22px 28px;border-left:2px dashed var(--fold)}
.feats b{display:block;font-size:19px;margin-bottom:4px}.feats p{margin:0;color:var(--muted)}
@media (max-width:700px){.feats{grid-template-columns:1fr}.feats div,.feats div:nth-child(even){padding:16px 0;border-left:0}}
.priv{display:grid;grid-template-columns:1fr 1fr;gap:40px;align-items:start}
@media (max-width:800px){.priv{grid-template-columns:1fr}}
.priv p{font-size:20px;color:var(--muted);margin:0}
.priv ul{list-style:none;margin:0;padding:0}.priv li{padding:12px 0;border-bottom:1px solid var(--fold);display:flex;gap:12px}
.priv li:before{content:"";flex:none;width:10px;height:10px;margin-top:9px;border-radius:50%;background:var(--teal)}
.gest{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}
@media (max-width:760px){.gest{grid-template-columns:1fr 1fr}}
.gest div{background:var(--card);border-radius:18px;padding:18px}
.gest span{display:block;font-family:"Bricolage Grotesque";font-size:40px;line-height:1;color:var(--coral)}
.gest small{display:block;color:var(--muted);font-size:13px;margin:8px 0 2px}.gest b{font-size:17px}
details{border-bottom:1px solid var(--fold);padding:14px 0}summary{cursor:pointer;font-weight:600;font-size:18px}
details p{color:var(--muted);margin:8px 0 0}
.end{text-align:center;padding:96px 0}
.end h2{margin:0 auto 14px;font-size:clamp(44px,7vw,84px)}.end p{color:var(--muted);margin:0 0 26px}
footer{padding:26px 0 40px;color:var(--muted);font-size:14px;display:flex;flex-wrap:wrap;gap:8px 22px;border-top:1px solid var(--fold)}
"""

JS = r"""
(function(){
  var scenes = %SCENES%;
  var hosts = %HOSTS%;
  var cur = 'cook', active = 1;
  var top = document.getElementById('p0'), bot = document.getElementById('p1');
  var url = document.getElementById('url');
  function put(el, html){
    var old = el.firstElementChild;
    var wrap = document.createElement('div'); wrap.innerHTML = html; var pg = wrap.firstElementChild;
    pg.classList.add('out'); el.appendChild(pg);
    requestAnimationFrame(function(){ requestAnimationFrame(function(){ pg.classList.remove('out'); if (old) { old.classList.add('out'); setTimeout(function(){ old.remove(); }, 460); } }); });
  }
  function bar(){ url.textContent = hosts[cur][active]; }
  function show(name){
    cur = name;
    put(top, scenes[name][0]); put(bot, scenes[name][1]);
    document.getElementById('s0').classList.toggle('vid-on', name === 'cook');
    bar();
    document.querySelectorAll('.scenes button').forEach(function(b){ b.setAttribute('aria-pressed', b.dataset.s === name ? 'true' : 'false'); });
  }
  function activate(i){
    active = i;
    document.getElementById('s0').classList.toggle('active', i === 0);
    document.getElementById('s1').classList.toggle('active', i === 1);
    bar();
  }
  document.getElementById('s0').addEventListener('click', function(){ activate(0); });
  document.getElementById('s1').addEventListener('click', function(){ activate(1); });
  document.querySelectorAll('.scenes button').forEach(function(b){ b.addEventListener('click', function(){ show(b.dataset.s); }); });
  show('cook'); activate(1);
  // A slow tour through the scenes until the visitor picks one.
  var order = ['cook','ai','study','shop'], k = 0, auto = !matchMedia('(prefers-reduced-motion: reduce)').matches;
  var timer = auto ? setInterval(function(){ k = (k + 1) % order.length; show(order[k]); }, 4200) : null;
  document.querySelector('.stage').addEventListener('click', function(){ if (timer) { clearInterval(timer); timer = null; } }, true);
})();
"""

APPLE = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9s-1.8-.9-3-.8c-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3 .7c1.3 0 2.1-1.1 2.8-2.3.9-1.3 1.3-2.6 1.3-2.6s-2.5-1-2.5-3.8zM14.2 5.8c.6-.8 1.1-1.9 1-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1 .1 2.1-.5 2.7-1.3z"/></svg>'

import json

def build(lang):
    t = T[lang]
    feats = "".join(f"<div><b>{a}</b><p>{b}</p></div>" for a, b in t["feats"])
    points = "".join(f"<li>{p}</li>" for p in t["p_points"])
    gest = "".join(f"<div><span aria-hidden=\"true\">{s}</span><small>{a}</small><b>{b}</b></div>" for s, a, b in t["gestures"])
    faq = "".join(f"<details><summary>{q}</summary><p>{a}</p></details>" for q, a in t["faq"])
    scenes = "".join(f'<button type="button" data-s="{k}" aria-pressed="false">{n}</button>' for k, n in t["scenes"])
    js = JS.replace("%SCENES%", json.dumps(PAGES)).replace("%HOSTS%", json.dumps(HOSTS))
    n = t["nav"]
    return f"""<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Twinfold</title><meta name="description" content="{t['desc']}">
<meta property="og:title" content="{t['title']}"><meta property="og:description" content="{t['desc']}"><meta property="og:image" content="../icon.png">
<link rel="icon" href="../icon.png"><link rel="apple-touch-icon" href="../icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,600;12..96,800&family=Instrument+Sans:wght@400;600&display=swap" rel="stylesheet">
<style>{CSS}</style></head><body>
<a class="skip" href="#main">{n[0]}</a>
<div class="wrap">
<header class="top"><img src="../icon.png" alt=""><b>Twinfold</b>
<nav aria-label="Twinfold"><a href="#what">{n[0]}</a><a href="#scenes">{n[1]}</a><a href="#privacy">{n[2]}</a><a href="#help">{n[3]}</a><a class="lang" href="../{t['other']}/" hreflang="{t['other']}">{t['other_name']}</a></nav></header>
<main id="main">
<div class="hero">
<div><h1><span class="a">{t['h1a']}</span><span class="a">{t['h1b']}</span><span class="fold" aria-hidden="true"></span><span class="b">{t['h1c']}</span></h1>
<p class="lede">{t['lede']}</p>
<a class="cta" href="{STORE}">{APPLE}{t['cta']}</a><span class="note">{t['cta_note']}</span></div>
<div class="stage" id="scenes" aria-label="{t['scenes_h']}">
<div class="duo">
<div class="half top"><div class="screen" id="s0" role="button" tabindex="0"><div class="panes" id="p0"></div><span class="mute" aria-hidden="true">🔊 ⤢</span></div></div>
<div class="hinge" aria-hidden="true"></div>
<div class="half bottom"><div class="screen active" id="s1" role="button" tabindex="0"><div class="panes" id="p1"></div>
<div class="bar" aria-hidden="true"><span>‹</span><span>›</span><span class="url" id="url"></span><i>▭</i><i>2</i><span>•••</span></div></div></div>
</div>
<div class="scenes" role="group" aria-label="{t['scenes_h']}">{scenes}</div>
<p class="hint">{t['demo_hint']}</p>
</div>
</div>
<section id="what"><h2>{t['f_h']}</h2><div class="feats">{feats}</div></section>
<section id="privacy"><h2>{t['p_h']}</h2><div class="priv"><p>{t['p_lede']}</p><ul>{points}</ul></div></section>
<section><h2>{t['g_h']}</h2><div class="gest">{gest}</div></section>
<section id="help"><h2>{t['faq_h']}</h2>{faq}<p style="margin-top:22px">{t['contact']} <a href="mailto:{MAIL}">{MAIL}</a></p></section>
<div class="end"><h2>{t['end_h']}</h2><p>{t['end_p']}</p><a class="cta" href="{STORE}">{APPLE}{t['cta']}</a></div>
</main>
<footer><span>Twinfold</span><a href="privacy.html">{t['privacy']}</a><span>{t['made']}</span></footer>
</div>
<script>{js}</script>
</body></html>"""


for lang in T:
    os.makedirs(os.path.join(SITE, lang), exist_ok=True)
    open(os.path.join(SITE, lang, "index.html"), "w").write(build(lang))
print("ok")
