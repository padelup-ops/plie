"""RETROFOLD : textes de la fiche App Store (7 langues) -> tools/meta/retrofold.json, et notes pour Apple -> retrofold/store/listing.json.
python3 retrofold/tools/listing_gen.py (depuis la racine du dépôt)."""
import json

GAMES = ("Brick Breaker, Retro Racer, Snake, Falling Blocks, Pixel Invaders, Mine Sweep, Paddle Duel, Tower Stack, "
         "Maze Muncher, Frog Hop, Astro Drift and Lunar Hinge")

L = {
    "en-US": dict(
        name="RetroFold: Pocket Console", subtitle="Unfold it and play retro games",
        keywords="retro,arcade,handheld,console,8-bit,pixel,classic games,snake,blocks,brick breaker,foldable,offline",
        promo="Unfold your phone into a 90s handheld: 12 pixel cartridges, a CRT screen that bends with the hinge and buttons that click. No ads, no account.",
        description=f"""Fold your phone shut, pick a cartridge on the cover, unfold it, and you're holding a 90s handheld console.

Made for iPhone Duo: the screen sits above the fold, the controls below. Fold it to pause, unfold it to play.

• 12 cartridges: {GAMES} (fold your phone to fire the thrusters!)
• A Daily round for every game: the same level for everyone, new every day
• A curved CRT that bends with the hinge, with scanlines and glow, or a green Pocket LCD, a Trinitron tube and an arcade monitor
• Console skins: Classic Grey, Atomic Purple, Cyberpunk Neon, 90's Arcade Cabinet and more
• Chiptune music, sound packs, haptic buttons, achievements and records
• Draw your own 16×16 cartridge labels

NEW: the Game Pak cartridge plays your own Game Boy, Game Boy Color, Game Boy Advance and Nintendo DS games. Load the .gb, .gbc, .gba or .nds files you own from Files; their saves stay on your iPhone. RetroFold comes with no games.

Eight cartridges are free, and every Pro cartridge plays free for 3 minutes a day. RetroFold Pro is a one-time purchase, no subscription: every cartridge, every skin, every sound pack and screen, forever.

No ads. No account. No data collected. Works offline. Also playable on any iPhone."""),
    "fr-FR": dict(
        name="RetroFold : console de poche", subtitle="Déplie-le et joue en rétro",
        keywords="rétro,arcade,console,portable,8 bits,pixel,jeux classiques,serpent,briques,casse-briques,pliable",
        promo="Déplie ton téléphone en console portable des années 90 : 12 cartouches en pixels, un écran cathodique qui suit la charnière, des boutons qui cliquent.",
        description=f"""Ferme ton téléphone, choisis une cartouche sur l’écran extérieur, déplie-le : tu tiens une console portable des années 90.

Conçu pour l’iPhone Duo : l’écran au-dessus du pli, les commandes en dessous. Replie pour mettre en pause, déplie pour jouer.

• 12 cartouches : {GAMES} (plie ton téléphone pour allumer les réacteurs !)
• Une partie du jour pour chaque jeu : le même niveau pour tout le monde, nouveau chaque jour
• Un écran cathodique bombé qui suit la charnière, avec lignes de balayage et lueur, ou un LCD vert de poche, un tube Trinitron et un moniteur d’arcade
• Des coques : Classic Grey, Atomic Purple, Cyberpunk Neon, borne d’arcade des années 90 et d’autres
• Musiques chiptune, packs de sons, boutons avec retour haptique, succès et records
• Dessine tes propres étiquettes de cartouche en 16×16

NOUVEAU : la cartouche Game Pak lit vos propres jeux Game Boy, Game Boy Color, Game Boy Advance et Nintendo DS. Chargez depuis Fichiers les fichiers .gb, .gbc, .gba ou .nds qui vous appartiennent ; leurs sauvegardes restent sur l'iPhone. RetroFold ne fournit aucun jeu.

Huit cartouches sont gratuites, et chaque cartouche Pro se joue gratuitement 3 minutes par jour. RetroFold Pro est un achat unique, sans abonnement : toutes les cartouches, coques, packs de sons et écrans, pour toujours.

Pas de pub. Pas de compte. Aucune donnée collectée. Fonctionne hors ligne. Jouable aussi sur tout iPhone. L’app est en anglais."""),
    "de-DE": dict(
        name="RetroFold: Taschenkonsole", subtitle="Aufklappen und retro spielen",
        keywords="retro,arcade,handheld,konsole,8-bit,pixel,klassiker,snake,blöcke,ziegel,klapphandy,offline",
        promo="Klapp dein Handy zur Handheld-Konsole der 90er auf: 12 Pixel-Module, ein Röhrenbildschirm, der dem Scharnier folgt, und klickende Tasten.",
        description=f"""Klapp dein Handy zu, wähl auf dem Außendisplay ein Modul, klapp es auf – und du hältst eine Handheld-Konsole der 90er in der Hand.

Gemacht für das iPhone Duo: der Bildschirm über dem Knick, die Steuerung darunter. Zuklappen pausiert, aufklappen spielt weiter.

• 12 Module: {GAMES} (klapp dein Handy, um die Triebwerke zu zünden!)
• Eine Tagesrunde für jedes Spiel: dasselbe Level für alle, jeden Tag neu
• Ein gewölbter Röhrenbildschirm, der dem Scharnier folgt, oder ein grünes Pocket-LCD, eine Trinitron-Röhre und ein Arcade-Monitor
• Gehäuse: Classic Grey, Atomic Purple, Cyberpunk Neon, 90er-Spielautomat und mehr
• Chiptune-Musik, Soundpakete, haptische Tasten, Erfolge und Rekorde
• Zeichne eigene 16×16-Modul-Etiketten

NEU: Das Game-Pak-Modul spielt deine eigenen Game-Boy-, Game-Boy-Color-, Game-Boy-Advance- und Nintendo-DS-Spiele. Lade deine .gb-, .gbc-, .gba- oder .nds-Dateien aus der Dateien-App; die Spielstände bleiben auf deinem iPhone. RetroFold enthält keine Spiele.

Acht Module sind kostenlos, und jedes Pro-Modul kannst du täglich 3 Minuten gratis spielen. RetroFold Pro ist ein Einmalkauf ohne Abo: alle Module, Gehäuse, Soundpakete und Bildschirme, für immer.

Keine Werbung. Kein Konto. Keine Datenerfassung. Funktioniert offline. Auch auf jedem iPhone spielbar. Die App ist auf Englisch."""),
    "es-ES": dict(
        name="RetroFold: consola de bolsillo", subtitle="Despliégalo y juega en retro",
        keywords="retro,arcade,consola,portátil,8 bits,pixel,juegos clásicos,serpiente,bloques,ladrillos,plegable",
        promo="Despliega tu móvil y conviértelo en una consola portátil de los 90: 12 cartuchos de píxeles, una pantalla CRT que sigue la bisagra y botones que hacen clic.",
        description=f"""Cierra tu móvil, elige un cartucho en la pantalla exterior, despliégalo y tendrás en las manos una consola portátil de los 90.

Pensado para el iPhone Duo: la pantalla encima del pliegue, los controles debajo. Pliégalo para pausar, despliégalo para jugar.

• 12 cartuchos: {GAMES} (¡pliega el móvil para encender los propulsores!)
• Una partida diaria en cada juego: el mismo nivel para todos, nuevo cada día
• Una pantalla CRT curvada que sigue la bisagra, o un LCD verde de bolsillo, un tubo Trinitron y un monitor arcade
• Carcasas: Classic Grey, Atomic Purple, Cyberpunk Neon, máquina recreativa de los 90 y más
• Música chiptune, packs de sonido, botones hápticos, logros y récords
• Dibuja tus propias etiquetas de cartucho de 16×16

NUEVO: el cartucho Game Pak ejecuta tus propios juegos de Game Boy, Game Boy Color, Game Boy Advance y Nintendo DS. Carga desde Archivos tus archivos .gb, .gbc, .gba o .nds; las partidas se guardan en tu iPhone. RetroFold no incluye juegos.

Ocho cartuchos son gratis, y cada cartucho Pro se juega gratis 3 minutos al día. RetroFold Pro es una compra única, sin suscripción: todos los cartuchos, carcasas, packs de sonido y pantallas, para siempre.

Sin anuncios. Sin cuenta. Sin recogida de datos. Funciona sin conexión. También se juega en cualquier iPhone. La app está en inglés."""),
    "ja": dict(
        name="RetroFold: ポケットコンソール", subtitle="開いて遊ぶレトロ携帯ゲーム",
        keywords="レトロ,アーケード,携帯ゲーム,ドット絵,8ビット,ブロック崩し,スネーク,クラシック",
        promo="スマホを開けば90年代の携帯ゲーム機に。ドット絵の12本のカートリッジ、ヒンジに合わせて曲がるブラウン管、カチッと押せるボタン。",
        description=f"""スマホを閉じて外側の画面でカートリッジを選び、開けば、手の中には90年代の携帯ゲーム機。

iPhone Duo のために作りました。折り目の上が画面、下がコントローラー。閉じれば一時停止、開けば再開。

• 12本のカートリッジ：{GAMES}（スマホを折ってエンジン噴射！）
• 全ゲームに「デイリー」：毎日みんな同じステージ
• ヒンジに合わせて曲がるブラウン管、緑のポケット液晶、トリニトロン、アーケードモニター
• 本体カラー：Classic Grey、Atomic Purple、Cyberpunk Neon、90年代アーケード筐体など
• チップチューン、サウンドパック、触感のあるボタン、実績と記録
• 16×16のカートリッジラベルを自分で描ける

新登場：Game Pakカートリッジで、お持ちのゲームボーイ／カラー／アドバンス／ニンテンドーDSのゲームが遊べます。「ファイル」から.gb／.gbc／.gba／.ndsファイルを読み込み、セーブはiPhoneに保存されます。RetroFoldにゲームは含まれていません。

8本のカートリッジは無料。Proカートリッジも1日3分ずつ無料で遊べます。RetroFold Pro を1回購入（サブスクなし）すれば、すべてのカートリッジ、本体カラー、サウンドパック、画面がずっと使えます。

広告なし。アカウント不要。データ収集なし。オフラインで遊べます。どの iPhone でも遊べます。アプリは英語です。"""),
    "ko": dict(
        name="RetroFold: 포켓 콘솔", subtitle="펼치면 레트로 게임기",
        keywords="레트로,아케이드,휴대용,게임기,8비트,픽셀,고전게임,벽돌깨기,스네이크,블록",
        promo="휴대폰을 펼치면 90년대 휴대용 게임기로: 픽셀 카트리지 12개, 힌지를 따라 휘는 CRT 화면, 딸깍 눌리는 버튼.",
        description=f"""휴대폰을 접고 바깥 화면에서 카트리지를 고른 뒤 펼치면, 손에는 90년대 휴대용 게임기가.

iPhone Duo를 위해 만들었어요. 접힌 선 위는 화면, 아래는 컨트롤러. 접으면 일시정지, 펼치면 계속.

• 카트리지 12개: {GAMES} (휴대폰을 접어서 추진기를 켜세요!)
• 모든 게임에 데일리 라운드: 매일 모두에게 같은 레벨
• 힌지를 따라 휘는 CRT 화면, 녹색 포켓 LCD, 트리니트론, 아케이드 모니터
• 본체 스킨: Classic Grey, Atomic Purple, Cyberpunk Neon, 90년대 아케이드 캐비닛 등
• 칩튠 음악, 사운드 팩, 햅틱 버튼, 업적과 기록
• 16×16 카트리지 라벨을 직접 그리기

새로운 기능: Game Pak 카트리지로 직접 가진 게임보이·게임보이 컬러·게임보이 어드밴스·닌텐도 DS 게임을 플레이하세요. 파일 앱에서 .gb, .gbc, .gba 또는 .nds 파일을 불러오며, 저장 데이터는 iPhone에 보관됩니다. RetroFold에는 게임이 포함되어 있지 않습니다.

카트리지 8개는 무료이며, Pro 카트리지도 하루 3분씩 무료로 플레이할 수 있습니다. RetroFold Pro를 한 번만 구매(구독 없음)하면 모든 카트리지, 스킨, 사운드 팩과 화면을 계속 사용할 수 있습니다.

광고 없음. 계정 없음. 데이터 수집 없음. 오프라인 플레이. 모든 iPhone에서 플레이 가능. 앱은 영어입니다."""),
    "zh-Hans": dict(
        name="RetroFold：口袋游戏机", subtitle="展开就能玩的复古掌机",
        keywords="复古,街机,掌机,游戏机,8位,像素,经典游戏,贪吃蛇,打砖块,方块",
        promo="展开手机，变身 90 年代掌机：12 款像素卡带、随铰链弯曲的 CRT 屏幕、按下去咔哒作响的按键。无广告，无需账号。",
        description=f"""合上手机，在外屏选一张卡带，再展开——你手里就是一台 90 年代的掌上游戏机。

为 iPhone Duo 打造：折痕上方是屏幕，下方是手柄。合上暂停，展开继续。

• 12 款卡带：{GAMES}（折叠手机来点燃推进器！）
• 每款游戏都有每日挑战：每天所有人同一关
• 随铰链弯曲的 CRT 屏幕，或绿色口袋 LCD、特丽珑显像管和街机显示器
• 机身外壳：Classic Grey、Atomic Purple、Cyberpunk Neon、90 年代街机柜等
• 芯片音乐、音效包、触感按键、成就与纪录
• 自己画 16×16 的卡带标签

新功能：Game Pak 卡带可运行你自己的 Game Boy、Game Boy Color、Game Boy Advance 和 Nintendo DS 游戏。从“文件”载入你拥有的 .gb、.gbc、.gba 或 .nds 文件，存档保存在 iPhone 上。RetroFold 不附带任何游戏。

8 款卡带免费，每款 Pro 卡带每天还可免费试玩 3 分钟。只需一次购买 RetroFold Pro（无订阅），即可永久畅玩全部卡带、外壳、音效包和屏幕。

无广告。无需账号。不收集任何数据。离线可玩。任何 iPhone 都能玩。App 为英文界面。"""),
}

NOTES = ("RetroFold turns iPhone Duo into a 90s handheld console. Closed, the cover display shows the cartridges: swipe and pick one. "
         "Unfolded, the inner display shows the game screen above the fold and the controls below; folding pauses the game. "
         "On an iPhone without a hinge, the whole console shows on screen: tap a cartridge on the shelf to play "
         "(Lunar Hinge uses the A button or the up arrow instead of folding).\n\n"
         "Game Pak (new in this version): a cartridge that plays the player's own Game Boy / Color / Advance and Nintendo DS files, imported from Files (tap the Game Pak cartridge, then A on \"Load a game\"). The app includes no games and links to no game sources; it uses the "
         "open-source SameBoy (MIT), mGBA (MPL 2.0) and melonDS DS (GPL v3) cores with their own open-source BIOS replacements, as guideline 4.7 allows for retro console emulators. "
         "For testing, any homebrew .gb, .gba or .nds file works. A game controller shows the game full screen.\n\n"
         "Free download: eight cartridges are free, and each Pro cartridge can be played free for 3 minutes a day "
         "(a timer shows at the top of the screen; when it runs out, the store opens). Open Store in the toolbar, or tap a locked "
         "(dusty) cartridge, to see RetroFold Pro (non-consumable, com.padelup.retrofold.pro), which unlocks every cartridge, skin, "
         "sound pack and screen mode for good. The former \"1-day Trial\" item is no longer offered in the app. "
         "Restore Purchases is on the same screen.\n\n"
         "All games are original. No account, no ads, no network access, no data collection.")


def fit_keywords(k):
    """100 octets au plus : on retire les derniers mots-clés."""
    parts = k.split(",")
    while len(",".join(parts).encode()) > 100:
        parts.pop()
    return ",".join(parts)


for loc, v in L.items():
    assert len(v["name"]) <= 30, (loc, v["name"])
    assert len(v["subtitle"]) <= 30, (loc, v["subtitle"])
    assert len(v["promo"]) <= 170, (loc, len(v["promo"]))
    v["keywords"] = fit_keywords(v["keywords"])

json.dump({"locales": L, "skip": [], "support": "https://foldly.netlify.app/retrofold/en/"},
          open("tools/meta/retrofold.json", "w"), ensure_ascii=False, indent=1)
json.dump({"reviewNotes": NOTES}, open("retrofold/store/listing.json", "w"), ensure_ascii=False, indent=1)
print("ok", {k: len(v["keywords"].encode()) for k, v in L.items()})
