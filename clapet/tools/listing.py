"""La fiche App Store de Foldly dans toutes les langues (nom, sous-titre, mots-clés, texte promo, description).
Lue par asc.py. Nom et sous-titre : 30 caractères au plus ; mots-clés : 100."""

NAMES = {
    "en-US": ["Foldly: Fold Counter", "Foldly - Fold Counter", "Foldly: Hinge Counter", "Foldly: Fold Tracker"],
    "fr-FR": ["Foldly : compteur de plis", "Foldly - compteur de plis", "Foldly : compteur de pliages"],
    "de-DE": ["Foldly: Faltzähler", "Foldly – Faltzähler", "Foldly: Scharnierzähler"],
    "es-ES": ["Foldly: contador de pliegues", "Foldly - contador de pliegues", "Foldly: contador plegable"],
    "ja": ["Foldly: 折りたたみカウンター", "Foldly - 折りたたみカウンター"],
    "ko": ["Foldly: 접기 카운터", "Foldly - 접기 카운터"],
    "zh-Hans": ["Foldly：折叠计数器", "Foldly - 折叠计数器"],
}

SUBTITLE = {
    "en-US": "Keep your folds under control",
    "fr-FR": "Garde tes plis sous contrôle",
    "de-DE": "Deine Faltungen im Griff",
    "es-ES": "Controla tus pliegues",
    "ja": "折りたたむ回数をコントロール",
    "ko": "접는 횟수를 관리하세요",
    "zh-Hans": "掌控你的折叠次数",
}

KEYWORDS = {
    "en-US": "fold,hinge,counter,foldable,folding,widget,limit,habit,screen time,tracker,stats,digital wellbeing",
    "fr-FR": "pli,charnière,compteur,pliable,pliant,widget,limite,habitude,temps d'écran,suivi,statistiques",
    "de-DE": "falten,scharnier,zähler,faltbar,klapphandy,widget,limit,gewohnheit,bildschirmzeit,statistik",
    "es-ES": "plegar,bisagra,contador,plegable,widget,límite,hábito,tiempo de pantalla,estadísticas,bienestar",
    "ja": "折りたたみ,ヒンジ,カウンター,折りたたみスマホ,ウィジェット,上限,習慣,スクリーンタイム,記録,統計",
    "ko": "접기,힌지,카운터,폴더블,위젯,한도,습관,스크린타임,기록,통계,디지털웰빙",
    "zh-Hans": "折叠,铰链,计数器,折叠屏,小组件,上限,习惯,屏幕使用时间,记录,统计,数字健康",
}

PROMO = {
    "en-US": "How many times a day do you open your phone? Set a daily limit, climb the leaderboards and keep an eye on your folds, right from your Home Screen.",
    "fr-FR": "Combien de fois par jour ouvres-tu ton téléphone ? Fixe une limite, grimpe dans les classements et garde un œil sur tes plis, directement sur ton écran d'accueil.",
    "de-DE": "Wie oft am Tag öffnest du dein Handy? Lege ein Tageslimit fest, steig in den Bestenlisten auf und behalte deine Faltungen direkt auf dem Home-Bildschirm im Blick.",
    "es-ES": "¿Cuántas veces al día abres tu teléfono? Fija un límite diario, sube en las clasificaciones y vigila tus pliegues desde tu pantalla de inicio.",
    "ja": "1日に何回スマホを開いていますか？1日の上限を決めて、ランキングに挑戦し、ホーム画面から折りたたみ回数をチェックしましょう。",
    "ko": "하루에 휴대폰을 몇 번 여나요? 하루 한도를 정하고, 순위표에 도전하고, 홈 화면에서 접는 횟수를 확인하세요.",
    "zh-Hans": "你一天打开手机多少次？设定每日上限，冲上排行榜，在主屏幕上随时关注你的折叠次数。",
}

DESCRIPTION = {
    "en-US": """Every time you unfold your phone, you glance at it. Foldly counts your folds, so you can see your habit and keep it under control.

Made for iPhone Duo. On screen, Foldly reads the hinge itself: every time you close your phone, it counts. Set your own daily limit and watch the ring: green while you're under it, orange when you get close, red when you're over.

• Folds and opens today, the last 7 days and your total
• Your own daily limit, and how many folds you have left
• Just the essentials on the outer screen; unfold for everything
• Desk mode: open your Duo halfway, like a book or a little laptop
• Apple Watch app and complications
• Widgets for the Home Screen and the Lock Screen
• Break reminder when your Duo stays open for a while
• Themes, including the new Aurora theme
• A short guided tour to find everything

Foldly is free. Foldly+ unlocks everything with a single purchase, no subscription:
• Leaderboards with Game Center: your longest streak under your limit, and your last 30 days
• My theme: your own colors for the whole app
• Every widget and widget colors
• Limit alerts at 80 % and 100 %
• Your full history, trends and records, and export (CSV)

Counting all day: to count even when Foldly isn't on screen, plug its "Count a fold" action into the Shortcuts automation "When iPhone is Closed": the app shows you how. No ads, no account. Your numbers stay on your iPhone.""",
    "fr-FR": """Chaque fois que tu déplies ton téléphone, tu y jettes un œil. Foldly compte tes plis, pour que tu voies cette habitude et que tu la gardes sous contrôle.

Conçu pour l'iPhone Duo. À l'écran, Foldly lit lui-même la charnière : chaque fois que tu fermes ton téléphone, il compte. Fixe ta propre limite par jour et regarde l'anneau : vert tant que tu es en dessous, orange quand tu t'en approches, rouge quand tu la dépasses.

• Fermetures et ouvertures du jour, les 7 derniers jours et ton total
• Ta propre limite par jour, et combien de plis il te reste
• L'essentiel sur l'écran extérieur ; déplie pour tout voir
• Mode bureau : ouvre ton Duo à moitié, comme un livre ou un petit portable
• App Apple Watch et complications
• Widgets pour l'écran d'accueil et l'écran verrouillé
• Rappel de pause quand ton Duo reste ouvert longtemps
• Des thèmes, dont le nouveau thème Aurore
• Une courte visite guidée pour tout trouver

Foldly est gratuit. Foldly+ débloque tout en un seul achat, sans abonnement :
• Classements avec Game Center : ta plus longue série sous ta limite, et tes 30 derniers jours
• Mon thème : tes propres couleurs pour toute l'app
• Tous les widgets et leurs couleurs
• Alertes de limite à 80 % et 100 %
• Tout l'historique, tes tendances et records, et l'export (CSV)

Compter toute la journée : pour compter même quand Foldly n'est pas à l'écran, branche son action « Compter un pli » sur l'automatisation Raccourcis « iPhone fermé » : l'app te montre comment. Sans pub, sans compte. Tes chiffres restent sur ton iPhone.""",
    "de-DE": """Jedes Mal, wenn du dein Handy aufklappst, wirfst du einen Blick darauf. Foldly zählt deine Faltungen, damit du deine Gewohnheit siehst und im Griff behältst.

Gemacht für das iPhone Duo. Auf dem Bildschirm liest Foldly das Scharnier selbst: Jedes Mal, wenn du dein Handy zuklappst, zählt es. Lege dein eigenes Tageslimit fest und beobachte den Ring: grün, solange du darunter bleibst, orange, wenn du dich näherst, rot, wenn du es überschreitest.

• Faltungen und Öffnungen heute, die letzten 7 Tage und deine Gesamtzahl
• Dein eigenes Tageslimit und wie viele Faltungen dir bleiben
• Nur das Wichtigste auf dem Außendisplay; aufklappen für alles
• Schreibtischmodus: Öffne dein Duo zur Hälfte, wie ein Buch oder ein kleiner Laptop
• Apple Watch-App und Komplikationen
• Widgets für Home- und Sperrbildschirm
• Pausenerinnerung, wenn dein Duo länger offen bleibt
• Designs, darunter das neue Design Polarlicht
• Ein kurzer Rundgang, um alles zu finden

Foldly ist kostenlos. Foldly+ schaltet alles mit einem einzigen Kauf frei, ohne Abo:
• Bestenlisten mit Game Center: deine längste Serie unter deinem Limit und deine letzten 30 Tage
• Mein Design: deine eigenen Farben für die ganze App
• Alle Widgets und Widget-Farben
• Limit-Hinweise bei 80 % und 100 %
• Dein vollständiger Verlauf, Trends und Rekorde sowie Export (CSV)

Den ganzen Tag zählen: Damit Foldly auch zählt, wenn es nicht auf dem Bildschirm ist, verbinde die Aktion „Faltung zählen“ mit der Kurzbefehle-Automation „Wenn iPhone geschlossen wird“: Die App zeigt dir, wie. Keine Werbung, kein Konto. Deine Zahlen bleiben auf deinem iPhone.""",
    "es-ES": """Cada vez que despliegas tu teléfono, le echas un vistazo. Foldly cuenta tus pliegues para que veas tu hábito y lo mantengas bajo control.

Hecho para iPhone Duo. En pantalla, Foldly lee la bisagra por sí mismo: cada vez que cierras tu teléfono, cuenta. Fija tu propio límite diario y mira el anillo: verde mientras estás por debajo, naranja cuando te acercas, rojo cuando lo superas.

• Pliegues y aperturas de hoy, los últimos 7 días y tu total
• Tu propio límite diario y cuántos pliegues te quedan
• Solo lo esencial en la pantalla exterior; despliega para verlo todo
• Modo escritorio: abre tu Duo hasta la mitad, como un libro o un pequeño portátil
• App para Apple Watch y complicaciones
• Widgets para la pantalla de inicio y de bloqueo
• Recordatorio de pausa cuando tu Duo queda abierto un buen rato
• Temas, incluido el nuevo tema Aurora
• Un breve recorrido guiado para encontrarlo todo

Foldly es gratis. Foldly+ lo desbloquea todo con una sola compra, sin suscripción:
• Clasificaciones con Game Center: tu racha más larga bajo tu límite y tus últimos 30 días
• Mi tema: tus propios colores para toda la app
• Todos los widgets y sus colores
• Avisos de límite al 80 % y al 100 %
• Tu historial completo, tendencias y récords, y exportación (CSV)

Contar todo el día: para contar incluso cuando Foldly no está en pantalla, conecta su acción «Contar un pliegue» a la automatización de Atajos «Cuando el iPhone se cierra»: la app te enseña cómo. Sin anuncios, sin cuenta. Tus cifras se quedan en tu iPhone.""",
    "ja": """スマホを開くたびに、つい画面を見てしまいます。Foldlyは折りたたむ回数をカウントして、習慣を見える化し、コントロールしやすくします。

iPhone Duoのために作りました。画面に表示中は、Foldlyが自分でヒンジを読み取り、スマホを閉じるたびにカウントします。自分だけの1日の上限を決めて、リングを見てみましょう。上限内は緑、近づくとオレンジ、超えると赤になります。

• 今日の閉じた回数と開いた回数、直近7日、累計
• 自分だけの1日の上限と、残りの回数
• 外側の画面には要点だけ。開くとすべて表示
• デスクモード：Duoを半分開いて、本や小さなノートパソコンのように
• Apple Watchアプリとコンプリケーション
• ホーム画面とロック画面のウィジェット
• Duoを開いたままのときの休憩リマインダー
• 新しいテーマ「オーロラ」を含むテーマ
• すべての場所がわかる短いガイドツアー

Foldlyは無料です。Foldly+は一度の購入ですべてを解放します（サブスクリプションなし）：
• Game Centerのランキング：上限内の最長連続日数と直近30日
• マイテーマ：アプリ全体を自分の色に
• すべてのウィジェットとウィジェットの色
• 80%と100%の上限アラート
• すべての履歴、傾向と記録、書き出し（CSV）

1日中カウント：Foldlyが画面にないときもカウントするには、アクション「1回カウント」をショートカットのオートメーション「iPhoneを閉じたとき」に設定します。手順はアプリが案内します。広告なし、アカウント不要。数字はiPhoneの中だけに保存されます。""",
    "ko": """휴대폰을 펼칠 때마다 화면을 보게 됩니다. Foldly는 접는 횟수를 세어 습관을 보여 주고 관리할 수 있게 도와줍니다.

iPhone Duo를 위해 만들었습니다. 화면에 있을 때 Foldly가 직접 힌지를 읽어 휴대폰을 닫을 때마다 셉니다. 나만의 하루 한도를 정하고 링을 확인하세요: 한도 이내면 초록색, 가까워지면 주황색, 넘으면 빨간색입니다.

• 오늘 닫은 횟수와 연 횟수, 최근 7일, 전체 횟수
• 나만의 하루 한도와 남은 횟수
• 바깥 화면에는 핵심만, 펼치면 모두 표시
• 데스크 모드: Duo를 반쯤 열어 책이나 작은 노트북처럼
• Apple Watch 앱과 컴플리케이션
• 홈 화면과 잠금 화면 위젯
• Duo를 한동안 열어 두면 휴식 알림
• 새 오로라 테마를 포함한 테마
• 모든 기능을 찾을 수 있는 짧은 둘러보기

Foldly는 무료입니다. Foldly+는 한 번의 구입으로 모든 기능을 엽니다(구독 없음):
• Game Center 순위표: 한도 이내 최장 연속 기록과 최근 30일
• 나의 테마: 앱 전체를 나만의 색으로
• 모든 위젯과 위젯 색상
• 80%와 100% 한도 알림
• 전체 기록, 추세와 최고 기록, 내보내기(CSV)

하루 종일 카운트: Foldly가 화면에 없을 때도 세려면 '1번 세기' 동작을 단축어 자동화 'iPhone을 닫을 때'에 연결하세요. 앱이 방법을 안내합니다. 광고 없음, 계정 없음. 숫자는 iPhone에만 저장됩니다.""",
    "zh-Hans": """每次展开手机，你都会看一眼。Foldly 会计数你的折叠次数，让你看清习惯并加以控制。

专为 iPhone Duo 打造。在屏幕上时，Foldly 会自己读取铰链：每次合上手机，它都会计数。设定你自己的每日上限并留意圆环：在上限内是绿色，接近时变橙色，超出时变红色。

• 今天的合上和打开次数、最近 7 天以及总计
• 你自己的每日上限，以及剩余次数
• 外屏只显示重点；展开即可查看全部
• 桌面模式：把 Duo 打开一半，像书或小笔记本电脑一样
• Apple Watch App 和复杂功能
• 主屏幕和锁定屏幕小组件
• Duo 打开较久时的休息提醒
• 多款主题，包括全新的“极光”主题
• 简短导览，帮你找到一切

Foldly 免费。Foldly+ 一次购买即可解锁全部功能，无需订阅：
• Game Center 排行榜：上限内最长连续天数和最近 30 天
• 我的主题：为整个 App 设置你自己的颜色
• 所有小组件和小组件颜色
• 80% 和 100% 的上限提醒
• 完整历史记录、趋势和纪录，以及导出（CSV）

全天计数：若想在 Foldly 不在屏幕上时也计数，把它的“计数一次折叠”操作接入快捷指令自动化“iPhone 合上时”：App 会教你怎么做。无广告，无需账户。你的数据只保存在你的 iPhone 上。""",
}

# Les captures d'écran de chaque langue (en attendant des captures traduites : l'anglais)
SHOT_LANG = {"en-US": "en", "fr-FR": "fr", "de-DE": "en", "es-ES": "en", "ja": "en", "ko": "en", "zh-Hans": "en"}

# Les nouveautés de la 1.0.3
WHATS_NEW_103 = {
    "en-US": "• Foldly is now free! Foldly+ unlocks everything with a single purchase. Bought Foldly 1.0? You keep everything, nothing to pay.\n• With Foldly+: leaderboards with Game Center, and My theme: your own colors.\n• New Aurora theme, Apple Watch app, break reminder, a richer desk mode, and just the essentials on the outer screen.\n• Now in German, Spanish, Japanese, Korean and Chinese.",
    "fr-FR": "• Foldly est maintenant gratuit ! Foldly+ débloque tout en un seul achat. Tu as acheté Foldly 1.0 ? Tu gardes tout, sans rien payer.\n• Avec Foldly+ : les classements Game Center, et Mon thème : tes propres couleurs.\n• Nouveau thème Aurore, app Apple Watch, rappel de pause, un mode bureau plus complet, et l'essentiel sur l'écran extérieur.\n• Disponible en allemand, espagnol, japonais, coréen et chinois.",
    "de-DE": "• Foldly ist jetzt kostenlos! Foldly+ schaltet alles mit einem einzigen Kauf frei. Foldly 1.0 gekauft? Du behältst alles, ohne etwas zu zahlen.\n• Mit Foldly+: Bestenlisten mit Game Center und Mein Design: deine eigenen Farben.\n• Neues Design Polarlicht, Apple Watch-App, Pausenerinnerung, ein umfangreicherer Schreibtischmodus und nur das Wichtigste auf dem Außendisplay.\n• Jetzt auf Deutsch.",
    "es-ES": "• ¡Foldly ahora es gratis! Foldly+ lo desbloquea todo con una sola compra. ¿Compraste Foldly 1.0? Lo conservas todo, sin pagar nada.\n• Con Foldly+: clasificaciones con Game Center y Mi tema: tus propios colores.\n• Nuevo tema Aurora, app para Apple Watch, recordatorio de pausa, un modo escritorio más completo y solo lo esencial en la pantalla exterior.\n• Ahora en español.",
    "ja": "• Foldlyが無料になりました！Foldly+は一度の購入ですべてを解放します。Foldly 1.0を購入した方は、追加料金なしですべて使えます。\n• Foldly+：Game Centerのランキングと、自分の色にできるマイテーマ。\n• 新テーマ「オーロラ」、Apple Watchアプリ、休憩リマインダー、充実したデスクモード、外側の画面には要点だけ。\n• 日本語に対応しました。",
    "ko": "• 이제 Foldly는 무료입니다! Foldly+는 한 번의 구입으로 모든 기능을 엽니다. Foldly 1.0을 구입하셨다면 추가 비용 없이 모두 그대로 사용하세요.\n• Foldly+: Game Center 순위표와 나만의 색상을 고르는 나의 테마.\n• 새 오로라 테마, Apple Watch 앱, 휴식 알림, 더 풍성해진 데스크 모드, 바깥 화면에는 핵심만.\n• 이제 한국어를 지원합니다.",
    "zh-Hans": "• Foldly 现已免费！Foldly+ 一次购买即可解锁全部功能。已购买 Foldly 1.0？你保留所有功能，无需再付费。\n• Foldly+：Game Center 排行榜，以及可自定义颜色的“我的主题”。\n• 全新“极光”主题、Apple Watch App、休息提醒、更丰富的桌面模式，外屏只显示重点。\n• 现已支持简体中文。",
}
