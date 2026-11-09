"""DUO FOLDS : prépare la version 1.0 pour l'App Store, et l'envoie à la vérification d'Apple si SUBMIT=1.

Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY, ORIGAMO_BUNDLE_ID (pour reprendre les coordonnées),
RELEASE_BUILD (numéro du build), SITE_URL (pages d'assistance et de confidentialité), SUBMIT (1 = envoyer).
Fait : catégories, classification par âge, droits sur le contenu, copyright, sortie automatique après accord,
disponibilité dans tous les pays, coordonnées et notes pour la vérification, URL, captures, build.
"""
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = os.environ.get("APP_BUNDLE") or "com.padelup.clapet"
HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.environ.get("RELEASE_BUILD", "").strip()
SITE = os.environ.get("SITE_URL", "").strip().rstrip("/")
SUBMIT = os.environ.get("SUBMIT") == "1"
SHOT_TYPE = os.environ.get("SHOT_TYPE", "APP_IPHONE_67")
SHOTS_DIR = os.environ.get("SHOTS_DIR") or os.path.join(HERE, "store")
CATEGORIES = (os.environ.get("CATEGORIES") or "HEALTH_AND_FITNESS,UTILITIES").split(",")
PRICE_EUR = os.environ.get("APP_PRICE", "").strip()
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from listing import SHOT_LANG, WHATS_NEW_103  # noqa: E402
LOCALES = SHOT_LANG
REVIEW_NOTES = (
    "Foldly counts how many times a foldable iPhone (iPhone Duo) is closed and opened, so people can keep that habit under control.\n\n"
    "On an iPhone Duo: keep Foldly on screen and fold the device. The app reads the hinge (SwiftUI onHingeChange) and "
    "the count goes up; the ring turns orange near the daily limit and red above it.\n"
    "On a device without a hinge (like an iPad): tap the hinge drawing on the main screen to add a fold.\n\n"
    "Optional automatic counting: the app's Shortcuts action \"Count a fold\" can be added to the personal automation "
    "\"When iPhone is Closed\" (Shortcuts > Automation). The app shows these steps under \"Count even when the app is closed\".\n\n"
    "Following Guideline 5.2.5, the app was renamed from DUO FOLDS to Foldly: the Apple product name is no longer used "
    "in the app name, the name shown on the device or the metadata.\n\n"
    "Free app with one optional in-app purchase, Foldly+ (non-consumable, com.padelup.clapet.plus). Open it from the \"Plus\" "
    "button at the top of the main screen, or tap a locked widget or the full history. It unlocks the medium, large and Lock Screen "
    "widgets, limit alerts, the full history and records, widget colors and CSV export. Restore Purchases is on the same screen "
    "and in Settings. Foldly+ also adds \"Why you open it\": right after the Duo is unfolded, a card asks why in one tap (it can be dismissed and goes away by itself), and the answers are summed up at the top of History. People who bought the paid version 1.0 keep everything without paying again. No account, no ads, no data collection. "
    "Numbers stay on the device (shared with the widgets through the keychain).")

if os.environ.get("LISTING_JSON"):
    REVIEW_NOTES = json.load(open(os.environ["LISTING_JSON"], encoding="utf-8"))["reviewNotes"]

token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
problems = []


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path if path.startswith("/") else path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        try:
            errs = json.loads(text).get("errors", [])
            detail = "; ".join(f"{x.get('code')}: {x.get('detail')}" for x in errs)
            for x in errs:
                assoc = (x.get("meta") or {}).get("associatedErrors") or {}
                for where, items in assoc.items():
                    for it in items:
                        detail += f"\n         -> {it.get('code')}: {it.get('detail') or it.get('title')}"
        except Exception:
            detail = text[:600]
        return {"error": e.code, "detail": detail}


def step(label, result, tolerate=()):
    if isinstance(result, dict) and "error" in result:
        if any(t in result["detail"] for t in tolerate):
            print(f"ok     {label} (déjà fait)")
            return result
        problems.append(label)
        print(f"ÉCHEC  {label} -> HTTP {result['error']} {result['detail']}")
    else:
        print(f"ok     {label}")
    return result


def get_all(path):
    out, url = [], path
    while url:
        page = call("GET", url)
        if "error" in page:
            return out
        out += page.get("data", [])
        url = page.get("links", {}).get("next")
    return out


app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}").get("data", [])
if not app:
    print("app introuvable")
    sys.exit(1)
app_id = app[0]["id"]
print("APP", app_id, app[0]["attributes"]["name"])

# ---------------------------------------------------------------- retrait de la vérification (WITHDRAW=1)
if os.environ.get("WITHDRAW") == "1":
    subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&limit=20").get("data", [])
    open_states = ("WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES", "READY_FOR_REVIEW")
    found = False
    for sub in subs:
        state = sub["attributes"].get("state")
        print("demande de vérification", sub["id"], state)
        if state in open_states:
            found = True
            step(f"demande {sub['id']} retirée de la vérification",
                 call("PATCH", f"/v1/reviewSubmissions/{sub['id']}",
                      {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"canceled": True}}}))
    if not found:
        print("aucune demande en cours à retirer")
    time.sleep(8)
    for v in call("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=5").get("data", []):
        print("VERSION", v["attributes"].get("versionString"), v["attributes"].get("appStoreState"))
    sys.exit(1 if problems else 0)

# ---------------------------------------------------------------- fiche de l'app
infos = call("GET", f"/v1/apps/{app_id}/appInfos").get("data", [])
info = next((i for i in infos if i["attributes"].get("appStoreState") not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION")), infos[0])
info_id = info["id"]
if CATEGORIES[0] == "GAMES":
    rel = {"primaryCategory": {"data": {"type": "appCategories", "id": "GAMES"}}}
    for key, cid in zip(("primarySubcategoryOne", "primarySubcategoryTwo"), CATEGORIES[1:3]):
        rel[key] = {"data": {"type": "appCategories", "id": cid}}
else:
    rel = {"primaryCategory": {"data": {"type": "appCategories", "id": CATEGORIES[0]}}}
    if len(CATEGORIES) > 1:
        rel["secondaryCategory"] = {"data": {"type": "appCategories", "id": CATEGORIES[1]}}
step("catégories " + " / ".join(CATEGORIES), call("PATCH", f"/v1/appInfos/{info_id}", {"data": {"type": "appInfos", "id": info_id, "relationships": rel}}))

# Prix de l'app (base France)
if PRICE_EUR:
    current = call("GET", f"/v1/apps/{app_id}/appPriceSchedule?include=manualPrices")
    have = [x for x in current.get("included", []) if x["type"] == "appPrices"]
    point, url = None, f"/v1/apps/{app_id}/appPricePoints?filter[territory]=FRA&limit=200"
    while url and not point:
        page = call("GET", url)
        point = next((p for p in page.get("data", []) if float(p["attributes"].get("customerPrice") or -1) == float(PRICE_EUR)), None)
        url = page.get("links", {}).get("next")
    if not point:
        problems.append("prix")
        print("ÉCHEC  aucun palier à", PRICE_EUR, "€")
    elif any(x.get("relationships", {}).get("appPricePoint", {}).get("data", {}).get("id") == point["id"] for x in have):
        print(f"ok     prix {PRICE_EUR} € (déjà en place)")
    else:
        step(f"prix {PRICE_EUR} € (base France)", call("POST", "/v1/appPriceSchedules", {
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "FRA"}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${prix}"}]}}},
            "included": [{"type": "appPrices", "id": "${prix}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": point["id"]}}}}]}))

age = call("GET", f"/v1/appInfos/{info_id}/ageRatingDeclaration").get("data")
if age:
    BOOLS = {"advertising", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat", "parentalControls",
             "ageAssurance", "unrestrictedWebAccess", "userGeneratedContent", "socialMedia", "socialMediaAgeRestricted", "seventeenPlus"}
    LEVELS = {"alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
              "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity",
              "horrorOrFearThemes", "matureOrSuggestiveThemes", "violenceCartoonOrFantasy",
              "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic"}
    attrs = {}
    for k in age["attributes"]:
        if k in BOOLS:
            attrs[k] = False
        elif k in LEVELS:
            attrs[k] = "NONE"
    r = step("classification par âge (aucun contenu sensible)", call("PATCH", f"/v1/ageRatingDeclarations/{age['id']}",
             {"data": {"type": "ageRatingDeclarations", "id": age["id"], "attributes": attrs}}))
    if "error" in r:
        print("       attributs envoyés :", json.dumps(attrs)[:800])

step("droits sur le contenu (aucun contenu de tiers)", call("PATCH", f"/v1/apps/{app_id}", {"data": {"type": "apps", "id": app_id,
     "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}}))

# ---------------------------------------------------------------- disponibilité
avail = call("GET", f"/v1/apps/{app_id}/appAvailabilityV2")
if avail.get("data"):
    print("ok     disponibilité déjà définie")
else:
    territories = [t["id"] for t in get_all("/v1/territories?limit=200")]
    step(f"disponibilité ({len(territories)} pays)", call("POST", "/v2/appAvailabilities", {
        "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                 "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                                   "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": f"${{{t}}}"} for t in territories]}}},
        "included": [{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": True},
                      "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for t in territories]}))

# ---------------------------------------------------------------- nouvelle version (NEW_VERSION=1.0.1…)
# Les nouveautés affichées sur l'App Store, par version.
RELEASE_NOTES = {
    "1.0.3": WHATS_NEW_103,
    "1.0.4": {
        "en-US": "• Foldly+ is now available: every widget, limit alerts, your full history, widget colors and CSV export, in one purchase.\n• Fixes and improvements.",
        "fr-FR": "• Foldly+ est maintenant disponible : tous les widgets, les alertes de limite, tout l'historique, les couleurs des widgets et l'export CSV, en un seul achat.\n• Corrections et améliorations.",
        "de-DE": "• Foldly+ ist jetzt verfügbar: alle Widgets, Limit-Hinweise, dein ganzer Verlauf, Widget-Farben und CSV-Export, mit einem einzigen Kauf.\n• Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• Foldly+ ya está disponible: todos los widgets, avisos de límite, todo tu historial, colores de widgets y exportación CSV, en una sola compra.\n• Correcciones y mejoras.",
        "ja": "• Foldly+が利用可能になりました：すべてのウィジェット、上限の通知、全履歴、ウィジェットの色、CSV書き出しを一度の購入で。\n• 不具合の修正と改善。",
        "ko": "• 이제 Foldly+를 이용할 수 있습니다: 모든 위젯, 한도 알림, 전체 기록, 위젯 색상, CSV 내보내기를 한 번의 구입으로.\n• 버그 수정 및 개선.",
        "zh-Hans": "• Foldly+ 现已推出：所有小组件、限额提醒、完整历史、小组件颜色和 CSV 导出，一次购买即可。\n• 问题修复和改进。",
    },
    "1.0.5": {
        "en-US": "• New with Foldly+: Why you open it. When you unfold your Duo, answer in one tap (a notification, boredom, work or someone) and see the real reasons behind your opens in your history.\n• Fixed: a single fold could sometimes be counted twice when you closed your phone with Foldly on screen. Thanks to everyone who reported it!",
        "fr-FR": "• Nouveau avec Foldly+ : Pourquoi tu l'ouvres. Quand tu déplies ton Duo, réponds en un toucher (une notif, l'ennui, le boulot ou quelqu'un) et découvre dans l'historique la vraie raison de tes ouvertures.\n• Corrigé : un même pli pouvait parfois être compté deux fois quand tu fermais ton téléphone avec Foldly à l'écran. Merci à ceux qui l'ont signalé !",
        "de-DE": "• Neu mit Foldly+: Warum du es öffnest. Beim Aufklappen deines Duo antwortest du mit einem Tippen (Mitteilung, Langeweile, Arbeit oder jemand) und siehst im Verlauf die wahren Gründe für deine Öffnungen.\n• Behoben: Ein einzelnes Falten wurde manchmal doppelt gezählt, wenn du dein Telefon mit Foldly auf dem Bildschirm geschlossen hast. Danke für eure Hinweise!",
        "es-ES": "• Nuevo con Foldly+: Por qué lo abres. Al desplegar tu Duo, responde con un toque (una notificación, aburrimiento, trabajo o alguien) y descubre en el historial las verdaderas razones de tus aperturas.\n• Corregido: un mismo pliegue a veces se contaba dos veces al cerrar el teléfono con Foldly en pantalla. ¡Gracias a quienes lo avisasteis!",
        "ja": "• Foldly+の新機能「開く理由」：Duoを開いたら1タップで答える（通知、退屈、仕事、誰か）と、開く本当の理由が履歴でわかります。\n• 修正：Foldlyを表示したまま閉じたとき、1回の折りたたみが2回数えられることがある問題を修正しました。ご報告ありがとうございました！",
        "ko": "• Foldly+ 새 기능 '여는 이유': Duo를 펼칠 때 한 번 탭으로 답하면(알림, 심심해서, 일, 누군가) 기록에서 여는 진짜 이유를 볼 수 있어요.\n• 수정: Foldly를 화면에 띄운 채 휴대폰을 닫으면 한 번 접은 것이 가끔 두 번 세어지던 문제를 고쳤어요. 알려 주셔서 감사합니다!",
        "zh-Hans": "• Foldly+ 新功能“打开的原因”：展开 Duo 时轻点一下回答（通知、无聊、工作或某个人），在历史中看清你打开手机的真正原因。\n• 已修复：在 Foldly 显示时合上手机，一次折叠有时会被计为两次。感谢所有反馈的朋友！",
    },
    "1.0.6": {
        "en-US": "• Fixed: on the outer screen with the Modern look, the fold count could be cut to “…” (especially with a larger display setting). The hinge gauge now moves under the number when space is tight. Thanks Matthew for reporting it!",
        "fr-FR": "• Corrigé : sur l'écran extérieur avec le look Moderne, le nombre de plis pouvait être coupé en « … » (surtout avec un affichage agrandi). La jauge de la charnière passe maintenant sous le nombre quand la place manque. Merci à Matthew pour le signalement !",
        "de-DE": "• Behoben: Auf dem Außendisplay im Look Modern konnte die Anzahl der Faltungen zu „…“ abgeschnitten werden (vor allem mit vergrößerter Anzeige). Die Scharnieranzeige rückt jetzt unter die Zahl, wenn der Platz knapp ist. Danke für den Hinweis!",
        "es-ES": "• Corregido: en la pantalla exterior con el aspecto Moderno, el número de pliegues podía cortarse en «…» (sobre todo con la pantalla ampliada). Ahora el indicador de la bisagra se coloca debajo del número cuando falta espacio. ¡Gracias por avisar!",
        "ja": "• 修正：外側の画面でモダンの見た目のとき、折りたたみ回数が「…」と切れて表示されることがある問題（特に画面表示を拡大している場合）。スペースが足りないときは、ヒンジのゲージが数字の下に移動します。ご報告ありがとうございました！",
        "ko": "• 수정: 바깥 화면에서 모던 모양을 쓸 때 접은 횟수가 “…”로 잘려 보일 수 있던 문제(특히 화면 확대 설정 시). 이제 공간이 부족하면 힌지 게이지가 숫자 아래로 이동해요. 알려 주셔서 감사합니다!",
        "zh-Hans": "• 已修复：在外屏使用“现代”外观时，折叠次数可能被截断为“…”（尤其是放大显示时）。现在空间不足时，铰链仪表会移到数字下方。感谢反馈！",
    },
    "1.0.7": {
        "en-US": "• Bring your past stats: in Adjust the count, import a file from Scriptable, a shortcut or another app (CSV, text or JSON), or add past days by hand. Your history keeps each day.\n• Foldly+ is at its launch price until November 13: pay once, keep it for life.\n• After 3 days, Foldly sums up your first folds and your peak hour.\n• You can now buy Foldly+ straight from the App Store page.\n• Small fixes and improvements.",
        "fr-FR": "• Reprends tes anciennes stats : dans Corriger le compteur, importe un fichier de Scriptable, d'un raccourci ou d'une autre app (CSV, texte ou JSON), ou ajoute des jours à la main. L'historique garde chaque jour.\n• Foldly+ est à son prix de lancement jusqu'au 13 novembre : un seul achat, à vie.\n• Après 3 jours, Foldly résume tes premiers plis et ton heure de pointe.\n• Tu peux maintenant acheter Foldly+ directement depuis la fiche App Store.\n• Petites corrections et améliorations.",
        "de-DE": "• Übernimm deine alten Daten: Füge unter „Zähler anpassen“ die Tage vor Foldly hinzu (Faltungen und Aufklappen) sowie deine Gesamtzahl an Aufklappvorgängen.\n• Foldly+ gibt es bis 13. November zum Einführungspreis: einmal kaufen, für immer behalten.\n• Nach 3 Tagen fasst Foldly deine ersten Faltungen und deine Spitzenzeit zusammen.\n• Du kannst Foldly+ jetzt direkt auf der App Store-Seite kaufen.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• Trae tus estadísticas anteriores: en Ajustar el contador, añade los días que registraste antes de Foldly (pliegues y aperturas) y tu total de aperturas.\n• Foldly+ tiene precio de lanzamiento hasta el 13 de noviembre: un solo pago, para siempre.\n• Tras 3 días, Foldly resume tus primeros pliegues y tu hora pico.\n• Ahora puedes comprar Foldly+ directamente desde la página del App Store.\n• Pequeñas correcciones y mejoras.",
        "ja": "• 以前の記録を取り込めます：「回数を修正」で、Foldly以前に記録した日（折りたたみ・開いた回数）と、開いた回数の合計を追加できます。\n• Foldly+は11月13日までリリース記念価格：一度の購入でずっと使えます。\n• 3日後、最初の折りたたみ回数とピークの時間をまとめてお見せします。\n• App StoreのページからFoldly+を直接購入できるようになりました。\n• 細かな修正と改善。",
        "ko": "• 예전 기록 가져오기: '횟수 조정'에서 Foldly 이전에 기록한 날(접힘·펼침)과 전체 펼친 횟수를 추가할 수 있어요.\n• Foldly+를 11월 13일까지 출시 기념 가격으로: 한 번 구입으로 평생 사용.\n• 3일이 지나면 처음 접은 횟수와 가장 많이 접는 시간을 정리해 드려요.\n• 이제 App Store 페이지에서 바로 Foldly+를 구입할 수 있어요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• 导入以前的数据：在“调整计数”中添加使用 Foldly 之前记录的日子（折叠和展开），以及展开总次数。\n• Foldly+ 首发价至 11 月 13 日：一次购买，永久使用。\n• 使用 3 天后，Foldly 会总结你最初的折叠次数和高峰时段。\n• 现在可以直接在 App Store 页面购买 Foldly+。\n• 小问题修复和改进。",
    },
    "1.0.8": {
        "en-US": "• New in Foldly+: Your sessions. See how long your Duo stays open each time: your average session, short vs long sessions, your longest one, weekdays vs weekends, and how much of your waking day you spend unfolded. Thanks BraXzy for the idea!\n• Small fixes and improvements.",
        "fr-FR": "• Nouveau dans Foldly+ : Tes sessions. Combien de temps ton Duo reste ouvert à chaque fois : ta session moyenne, les courtes et les longues, la plus longue, la semaine contre le week-end, et la part de ta journée passée déplié. Merci BraXzy pour l'idée !\n• Petites corrections et améliorations.",
        "de-DE": "• Neu in Foldly+: Deine Sitzungen. Wie lange dein Duo jedes Mal offen bleibt: deine durchschnittliche Sitzung, kurze und lange Sitzungen, die längste, Wochentage gegen Wochenende und wie viel deines wachen Tages du aufgeklappt verbringst.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• Nuevo en Foldly+: Tus sesiones. Cuánto tiempo sigue abierto tu Duo cada vez: tu sesión media, sesiones cortas y largas, la más larga, entre semana frente a fin de semana, y cuánto de tu día pasas con él desplegado.\n• Pequeñas correcciones y mejoras.",
        "ja": "• Foldly+の新機能「セッション」：Duoを開くたびに開いている時間を表示。平均時間、短い／長いセッション、最長記録、平日と週末の比較、起きている時間のうち開いていた割合が分かります。\n• 細かな修正と改善。",
        "ko": "• Foldly+ 새 기능 ‘내 세션’: Duo를 펼칠 때마다 열려 있는 시간을 보여 줘요. 평균 세션, 짧은/긴 세션, 가장 긴 세션, 평일과 주말 비교, 깨어 있는 시간 중 펼친 비율까지.\n• 작은 수정 및 개선.",
        "zh-Hans": "• Foldly+ 新功能“你的使用时段”：查看 Duo 每次展开多久——平均时长、短时段与长时段、最长一次、工作日与周末对比，以及清醒时间中展开的比例。\n• 小问题修复和改进。",
    },
    "1.0.9": {
        "en-US": "• New in Foldly+: Your sessions. See how long your Duo stays open each time: your average session, short vs long sessions, your longest one, weekdays vs weekends, and how much of your waking day you spend unfolded. Thanks BraXzy for the idea!\n• A calmer, cleaner look: simpler titles, line icons instead of emoji, and shorter durations in Your sessions so everything fits.\n• Small fixes and improvements.",
        "fr-FR": "• Nouveau dans Foldly+ : Tes sessions. Combien de temps ton Duo reste ouvert à chaque fois : ta session moyenne, les courtes et les longues, la plus longue, la semaine contre le week-end, et la part de ta journée passée déplié. Merci BraXzy pour l'idée !\n• Un design plus calme et plus net : des titres plus simples, des icônes à la place des emojis, et des durées plus courtes dans Tes sessions pour que tout tienne.\n• Petites corrections et améliorations.",
        "de-DE": "• Neu in Foldly+: Deine Sitzungen. Wie lange dein Duo jedes Mal offen bleibt: deine durchschnittliche Sitzung, kurze und lange Sitzungen, die längste, Wochentage gegen Wochenende und wie viel deines wachen Tages du aufgeklappt verbringst.\n• Ein ruhigeres, klareres Design: einfachere Titel, Symbole statt Emojis und kürzere Zeitangaben in Deine Sitzungen, damit alles passt.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• Nuevo en Foldly+: Tus sesiones. Cuánto tiempo sigue abierto tu Duo cada vez: tu sesión media, sesiones cortas y largas, la más larga, entre semana frente a fin de semana, y cuánto de tu día pasas con él desplegado.\n• Un diseño más tranquilo y limpio: títulos más sencillos, iconos en lugar de emojis y duraciones más cortas en Tus sesiones para que todo quepa.\n• Pequeñas correcciones y mejoras.",
        "ja": "• Foldly+の新機能「セッション」：Duoを開くたびに開いている時間を表示。平均時間、短い／長いセッション、最長記録、平日と週末の比較、起きている時間のうち開いていた割合が分かります。\n• より落ち着いたすっきりデザインに：シンプルな見出し、絵文字の代わりにアイコン、セッションの時間表示を短くしました。\n• 細かな修正と改善。",
        "ko": "• Foldly+ 새 기능 ‘내 세션’: Duo를 펼칠 때마다 열려 있는 시간을 보여 줘요. 평균 세션, 짧은/긴 세션, 가장 긴 세션, 평일과 주말 비교, 깨어 있는 시간 중 펼친 비율까지.\n• 더 차분하고 깔끔한 디자인: 단순해진 제목, 이모지 대신 아이콘, ‘내 세션’의 더 짧은 시간 표시.\n• 작은 수정 및 개선.",
        "zh-Hans": "• Foldly+ 新功能“你的使用时段”：查看 Duo 每次展开多久——平均时长、短时段与长时段、最长一次、工作日与周末对比，以及清醒时间中展开的比例。\n• 更安静、更清爽的设计：更简洁的标题、用图标代替表情符号，“你的使用时段”中的时长更简短。\n• 小问题修复和改进。",
    },
    "1.0.13": {
        "en-US": "• Open but not in use: set your Rest hours in Settings (23:00 to 7:00 by default). Time your Duo stays open then counts as rest, and Foldly shows how much of your open time was at rest. Shortcuts for the Sleep focus are optional.\n• The App Store page now speaks more than 30 languages.\n• Small fixes and improvements.",
        "fr-FR": "• Ouvert mais pas utilisé : règle tes heures de repos dans les réglages (de 23 h à 7 h par défaut). Le temps où ton Duo reste ouvert à ces heures compte comme du repos, et Foldly montre la part de ton temps ouvert passée au repos. Des raccourcis pour le mode Repos sont facultatifs.\n• La fiche App Store parle maintenant plus de 30 langues.\n• Petites corrections et améliorations.",
        "de-DE": "• Offen, aber nicht benutzt: Lege deine Ruhezeiten in den Einstellungen fest (standardmäßig 23:00 bis 7:00 Uhr). Die Zeit, in der dein Duo dann offen bleibt, zählt als Ruhe, und Foldly zeigt, wie viel deiner offenen Zeit im Ruhemodus war. Kurzbefehle für den Schlaf-Fokus sind optional.\n• Die App-Store-Seite spricht jetzt über 30 Sprachen.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• Abierto pero sin usar: define tus horas de reposo en Ajustes (de 23:00 a 7:00 por defecto). El tiempo que tu Duo permanece abierto en ese horario cuenta como reposo, y Foldly muestra cuánto de tu tiempo abierto fue en reposo. Los atajos para el modo Sueño son opcionales.\n• La ficha de la App Store ya habla más de 30 idiomas.\n• Pequeñas correcciones y mejoras.",
        "ja": "• 開いているだけで使っていない時間：設定で休止時間を決められます（初期設定は23:00〜7:00）。その時間帯にDuoが開いている時間は休止として数え、開いている時間のうち休止中の時間が表示されます。睡眠モード用のショートカットは任意です。\n• App Storeのページが30以上の言語に対応しました。\n• 細かな修正と改善。",
        "ko": "• 열려 있지만 사용하지 않는 시간: 설정에서 휴식 시간대를 정할 수 있어요(기본 23:00~7:00). 이 시간대에 Duo가 열려 있는 시간은 휴식으로 계산하고, 열려 있던 시간 중 휴식 시간을 보여 줘요. 수면 집중 모드용 단축어는 선택 사항이에요.\n• App Store 페이지가 30개 이상의 언어를 지원해요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• 展开但未使用：可在设置中设定静置时段（默认 23:00 至 7:00）。Duo 在该时段内保持展开的时间会算作静置，Foldly 会显示展开时间中有多少处于静置状态。睡眠专注模式的快捷指令为可选项。\n• App Store 页面现已支持 30 多种语言。\n• 小问题修复和改进。",
    },
    "1.0.12": {
        "en-US": "• Leaderboards are now free for everyone, with new ones: who folds the most today, this week and since day one. Share your rank!\n• Contest of the month: the winners get Foldly+ for free and pick a new feature.\n• Today, hour by hour, right on the home screen.\n• Your weekly and monthly recaps are always one tap away, and the notification opens them.",
        "fr-FR": "• Les classements sont gratuits pour tous, avec des nouveaux : qui plie le plus aujourd'hui, cette semaine et depuis le début. Partage ton rang !\n• Le concours du mois : les gagnants reçoivent Foldly+ gratuit et choisissent une nouvelle fonctionnalité.\n• Aujourd'hui, heure par heure, directement sur l'écran principal.\n• Tes bilans de la semaine et du mois sont toujours à portée de main, et la notification les ouvre.",
        "de-DE": "• Ranglisten sind jetzt für alle kostenlos, mit neuen: Wer faltet heute, diese Woche und seit Tag eins am meisten? Teile deinen Rang!\n• Wettbewerb des Monats: Die Gewinner bekommen Foldly+ gratis und wählen eine neue Funktion.\n• Heute, Stunde für Stunde, direkt auf dem Startbildschirm.\n• Deine Wochen- und Monatsrückblicke sind immer einen Tipp entfernt, und die Mitteilung öffnet sie.",
        "es-ES": "• Las clasificaciones son gratis para todos, con nuevas: quién pliega más hoy, esta semana y desde el primer día. ¡Comparte tu puesto!\n• Concurso del mes: los ganadores reciben Foldly+ gratis y eligen una nueva función.\n• Hoy, hora a hora, en la pantalla principal.\n• Tus resúmenes semanales y mensuales siempre a un toque, y la notificación los abre.",
        "ja": "• ランキングが誰でも無料に。新ランキング：今日・今週・これまででいちばん折った人。順位をシェアしよう！\n• 今月のコンテスト：優勝者は Foldly+ が無料になり、新機能を選べます。\n• 今日の1時間ごとの回数をホーム画面に表示。\n• 週間・月間まとめにいつでもすぐアクセス。通知からも開けます。",
        "ko": "• 순위가 모두에게 무료예요. 새 순위: 오늘, 이번 주, 처음부터 가장 많이 접은 사람. 내 순위를 공유하세요!\n• 이달의 대회: 우승자는 Foldly+를 무료로 받고 새 기능을 골라요.\n• 오늘 시간대별 기록을 홈 화면에서 바로.\n• 주간·월간 요약을 언제든 한 번에 열 수 있고, 알림을 누르면 바로 열려요.",
        "zh-Hans": "• 排行榜现在对所有人免费，并新增：今天、本周和至今谁折得最多。分享你的排名！\n• 本月比赛：冠军免费获得 Foldly+ 并挑选一个新功能。\n• 今天按小时的数据，直接显示在主屏幕上。\n• 每周和每月总结随时一键打开，通知也能直接打开。",
    },
    "1.0.11": {
        "en-US": "• 1,000 downloads in 3 days, thank you! To celebrate, Foldly+ is at its lowest price ever with a gift code, until November 16.\n• New setting: count each movement. Opening and closing then count as 2 instead of 1. Your history, widgets and watch follow too.\n• Importing your history works with Scriptable files as they are, no need to convert them first.\n• When a day was counted both by Foldly and by your old tool, Foldly now keeps the higher count, today included, so no fold gets lost.\n• Small fixes and improvements.",
        "fr-FR": "• 1 000 téléchargements en 3 jours, merci ! Pour fêter ça, Foldly+ est à son prix le plus bas avec un code cadeau, jusqu'au 16 novembre.\n• Nouveau réglage : compter chaque mouvement. Ouvrir puis fermer compte alors pour 2 au lieu de 1. L'historique, les widgets et la montre suivent aussi.\n• L'import de ton historique lit directement les fichiers Scriptable, plus besoin de les convertir.\n• Quand un jour a été compté à la fois par Foldly et par ton ancien outil, Foldly garde le plus grand des deux nombres, aujourd'hui compris : aucun pli n'est perdu.\n• Petites corrections et améliorations.",
        "de-DE": "• 1.000 Downloads in 3 Tagen, danke! Zur Feier gibt es Foldly+ mit einem Geschenkcode so günstig wie nie, bis zum 16. November.\n• Neue Einstellung: jede Bewegung zählen. Öffnen und Schließen zählen dann als 2 statt 1. Verlauf, Widgets und Uhr passen sich an.\n• Der Import deines Verlaufs liest Scriptable-Dateien direkt, ohne Umwandeln.\n• Wenn ein Tag sowohl von Foldly als auch von deinem alten Tool gezählt wurde, behält Foldly die höhere Zahl, auch für heute: Kein Zuklappen geht verloren.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• ¡1000 descargas en 3 días, gracias! Para celebrarlo, Foldly+ está a su precio más bajo con un código de regalo, hasta el 16 de noviembre.\n• Nuevo ajuste: contar cada movimiento. Abrir y cerrar cuentan entonces como 2 en lugar de 1. El historial, los widgets y el reloj también.\n• La importación de tu historial lee directamente los archivos de Scriptable, sin convertirlos antes.\n• Si un día lo contaron tanto Foldly como tu herramienta anterior, Foldly conserva la cifra más alta, también la de hoy: no se pierde ningún pliegue.\n• Pequeñas correcciones y mejoras.",
        "ja": "• 3日間で1,000ダウンロード、ありがとう！お祝いに、ギフトコードで Foldly+ が過去最安値に（11月16日まで）。\n• 新しい設定：動きごとに数える。開いて閉じると1回ではなく2回に。履歴、ウィジェット、Apple Watchも同じ数え方に。\n• 履歴の読み込みがScriptableのファイルにそのまま対応。変換は不要です。\n• Foldlyと以前のツールの両方で記録された日は、多い方の数を残します（今日も含む）。折りたたみの記録が失われません。\n• 細かな修正と改善。",
        "ko": "• 3일 만에 1,000 다운로드, 고마워요! 기념으로 11월 16일까지 선물 코드로 Foldly+를 역대 최저가에 드려요.\n• 새 설정: 동작마다 세기. 열고 닫으면 1회가 아니라 2회로 셉니다. 기록, 위젯, 워치도 함께 바뀌어요.\n• 기록 가져오기가 Scriptable 파일을 그대로 읽어요. 따로 변환할 필요가 없어요.\n• Foldly와 이전 도구가 모두 센 날은 두 숫자 중 큰 쪽을 남겨요(오늘 포함). 접은 횟수가 사라지지 않아요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• 3 天 1,000 次下载，谢谢你！为了庆祝，使用礼物代码即可以史上最低价获得 Foldly+，至 11 月 16 日。\n• 新设置：每个动作都计数。打开再合上将算作 2 次而不是 1 次。历史、小组件和手表也会同步。\n• 导入历史记录可直接读取 Scriptable 文件，无需先转换。\n• 如果某一天 Foldly 和你之前的工具都有记录，Foldly 会保留较大的数字（包括今天），不会漏掉任何一次折叠。\n• 小问题修复和改进。",
    },
    "1.0.10": {
        "en-US": "• Importing your history works with Scriptable files as they are, no need to convert them first.\n• When a day was counted both by Foldly and by your old tool, Foldly now keeps the higher count, today included, so no fold gets lost.\n• Small fixes and improvements.",
        "fr-FR": "• L'import de ton historique lit directement les fichiers Scriptable, plus besoin de les convertir.\n• Quand un jour a été compté à la fois par Foldly et par ton ancien outil, Foldly garde le plus grand des deux nombres, aujourd'hui compris : aucun pli n'est perdu.\n• Petites corrections et améliorations.",
        "de-DE": "• Der Import deines Verlaufs liest Scriptable-Dateien direkt, ohne Umwandeln.\n• Wenn ein Tag sowohl von Foldly als auch von deinem alten Tool gezählt wurde, behält Foldly die höhere Zahl, auch für heute: Kein Zuklappen geht verloren.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• La importación de tu historial lee directamente los archivos de Scriptable, sin convertirlos antes.\n• Si un día lo contaron tanto Foldly como tu herramienta anterior, Foldly conserva la cifra más alta, también la de hoy: no se pierde ningún pliegue.\n• Pequeñas correcciones y mejoras.",
        "ja": "• 履歴の読み込みがScriptableのファイルにそのまま対応。変換は不要です。\n• Foldlyと以前のツールの両方で記録された日は、多い方の数を残します（今日も含む）。折りたたみの記録が失われません。\n• 細かな修正と改善。",
        "ko": "• 기록 가져오기가 Scriptable 파일을 그대로 읽어요. 따로 변환할 필요가 없어요.\n• Foldly와 이전 도구가 모두 센 날은 두 숫자 중 큰 쪽을 남겨요(오늘 포함). 접은 횟수가 사라지지 않아요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• 导入历史记录可直接读取 Scriptable 文件，无需先转换。\n• 如果某一天 Foldly 和你之前的工具都有记录，Foldly 会保留较大的数字（包括今天），不会漏掉任何一次折叠。\n• 小问题修复和改进。",
    },
    "1.3": {
        "en-US": "• New game: CASCADE! A pixel-art coin pusher made for the Duo folded into an L: coins rain down the standing half, bounce off the pins and land on the flat board, where the pusher shoves them off the edge. Upgrade your machine, aim for the pink target, find the diamond, and fold-unfold the Duo to shake the board.\n• Small fixes and improvements.",
        "fr-FR": "• Nouveau jeu : CASCADE ! Une machine à pièces en pixel art, faite pour le Duo plié en L : les pièces pleuvent sur la moitié debout, rebondissent sur les clous et tombent sur le plateau à plat, où le poussoir les fait tomber du bord. Améliore ta machine, vise la cible rose, trouve le diamant, et plie-déplie le Duo pour secouer le plateau.\n• Petites corrections et améliorations.",
        "de-DE": "• Neues Spiel: CASCADE! Ein Münzschieber in Pixel-Art für den Duo im L-Modus: Münzen regnen über die stehende Hälfte, prallen an den Stiften ab und landen auf dem flachen Brett, wo der Schieber sie über die Kante schiebt. Verbessere deinen Automaten, triff das pinke Ziel, finde den Diamanten und klappe den Duo zu und auf, um das Brett zu rütteln.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• ¡Nuevo juego: CASCADA! Una máquina de monedas en pixel art pensada para el Duo plegado en L: las monedas caen por la mitad de pie, rebotan en los clavos y aterrizan en el tablero plano, donde el empujador las tira por el borde. Mejora tu máquina, apunta a la diana rosa, encuentra el diamante y pliega y despliega el Duo para sacudir el tablero.\n• Pequeñas correcciones y mejoras.",
        "ja": "• 新ゲーム「カスケード」！L字に折ったDuoのためのピクセルアートのコインプッシャー。立てた側をコインが落ち、ピンで跳ねて平らな台へ。プッシャーで端から押し出そう。マシンを強化し、ピンクのターゲットを狙い、ダイヤを見つけ、Duoを折って戻すと台が揺れます。\n• 細かな修正と改善。",
        "ko": "• 새 게임: 캐스케이드! L자로 접은 Duo를 위한 픽셀 아트 코인 푸셔. 코인이 세운 쪽으로 쏟아져 핀에 튕기고, 평평한 판에 떨어지면 푸셔가 가장자리로 밀어내요. 머신을 업그레이드하고, 분홍 타깃을 노리고, 다이아몬드를 찾고, Duo를 접었다 펴서 판을 흔드세요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• 新游戏：瀑布！专为折成 L 形的 Duo 打造的像素风推币机：硬币从竖起的一半落下，在钉子上弹跳，落到平放的平台上，推板把它们推下边缘。升级你的机器，瞄准粉色目标，找到钻石，快速折叠再展开 Duo 来摇晃平台。\n• 小问题修复和改进。",
    },
    "1.6.1": {
        "en-US": "• The App Store page now speaks more than 30 languages.\n• Small fixes and improvements.",
        "fr-FR": "• La fiche App Store parle maintenant plus de 30 langues.\n• Petites corrections et améliorations.",
        "de-DE": "• Die App-Store-Seite gibt es jetzt in über 30 Sprachen.\n• Kleine Korrekturen und Verbesserungen.",
        "es-ES": "• La ficha del App Store ya está en más de 30 idiomas.\n• Pequeñas correcciones y mejoras.",
        "ja": "• App Storeのページが30以上の言語に対応しました。\n• 細かな修正と改善。",
        "ko": "• App Store 페이지가 이제 30개 이상의 언어로 제공돼요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• App Store 页面现已支持 30 多种语言。\n• 小问题修复和改进。",
    },
    "1.6": {
        "en-US": "• FISHING: fold the Duo into an L, the hinge is the waterline. Cast with a flick of the hinge, strike when it bites, then reel by folding gently. 15 catches to find.\n• MINI GOLF: 9 holes, solo or with two. Fold the Duo and the top half becomes a slope: the ball rolls toward the hinge.\n• COMET: a pixel shoot 'em up across both screens. Fold halfway to drop a bomb.\n• Translation fixes in German, Spanish, Japanese, Korean and Chinese.\n• Try any locked game for free once, and a new free game of the day, every day.\n• Dark mode for the home screen and menus (Settings: Auto, Light or Dark).\n• Leaderboards with Game Center: COMET, MINI GOLF, MINESWEEPER, FISHING and more.\n• CASCADE: fixed a bug that gave endless coins.",
        "fr-FR": "• PÊCHE : Duo plié en L, la charnière est la ligne de l'eau. Lance d'un coup de charnière, ferre quand ça mord, puis mouline en pliant doucement. 15 prises à trouver.\n• MINIGOLF : 9 trous, seul ou à deux. Plie le Duo : la moitié du haut devient une pente et la balle roule vers la charnière.\n• COMÈTE : un shoot'em up pixel sur les deux écrans. Plie à moitié pour lâcher une bombe.\n• Corrections de traduction en allemand, espagnol, japonais, coréen et chinois.\n• Essaie gratuitement chaque jeu fermé une fois, et un nouveau jeu du jour gratuit, tous les jours.\n• Mode sombre pour l'accueil et les menus (Réglages : Auto, Clair ou Sombre).\n• Classements Game Center : COMÈTE, MINIGOLF, DÉMINEUR, PÊCHE et d'autres.\n• CASCADE : correction d'un bug qui donnait des pièces à l'infini.",
        "de-DE": "• ANGELN: Klapp den Duo zum L, das Scharnier ist die Wasserlinie. Wirf mit einem Scharnier-Schwung, schlag an, wenn es beißt, und kurble durch sanftes Klappen. 15 Fänge zu entdecken.\n• MINIGOLF: 9 Löcher, allein oder zu zweit. Klapp den Duo und die obere Hälfte wird zum Hang: Der Ball rollt zum Scharnier.\n• KOMET: ein Pixel-Shoot-'em-up über beide Bildschirme. Halb zuklappen für eine Bombe.\n• Übersetzungen korrigiert.\n• Teste jedes gesperrte Spiel einmal gratis, und jeden Tag ein neues Gratis-Spiel des Tages.\n• Dunkelmodus für Startseite und Menüs (Einstellungen: Auto, Hell oder Dunkel).\n• Bestenlisten mit Game Center: KOMET, MINIGOLF, MINENSUCHE, ANGELN und mehr.\n• CASCADE: Fehler mit endlosen Münzen behoben.",
        "es-ES": "• PESCA: pliega el Duo en L, la bisagra es la línea del agua. Lanza con un golpe de bisagra, tira cuando piquen y recoge plegando suave. 15 capturas por descubrir.\n• MINIGOLF: 9 hoyos, solo o a dos. Pliega el Duo y la mitad de arriba se vuelve una cuesta: la bola rueda hacia la bisagra.\n• COMETA: un matamarcianos pixel en las dos pantallas. Pliega a medias para soltar una bomba.\n• Correcciones de traducción.\n• Prueba gratis una vez cada juego bloqueado, y un nuevo juego del día gratis, cada día.\n• Modo oscuro para el inicio y los menús (Ajustes: Auto, Claro u Oscuro).\n• Clasificaciones con Game Center: COMETA, MINIGOLF, BUSCAMINAS, PESCA y más.\n• CASCADE: corregido un fallo que daba monedas infinitas.",
        "ja": "• つり：DuoをL字に折ると、ヒンジが水面に。ヒンジをクイッと動かして投げ、アタリでアワセて、ゆっくり開閉して巻こう。全15種。\n• ミニゴルフ：9ホール、1人でも2人でも。Duoを折ると上半分が坂になり、ボールがヒンジへ転がる。\n• コメット：2画面を使ったドット絵シューティング。半分折ってボム。\n• 翻訳を修正しました。\n• ロック中のゲームを1回無料でお試し。毎日「今日のゲーム」が無料に。\n• ホームとメニューにダークモード（設定：自動・ライト・ダーク）。\n• Game Centerのランキング：コメット、ミニゴルフ、マインスイーパー、つりなど。\n• CASCADE：コインが無限に出る不具合を修正。",
        "ko": "• 낚시: Duo를 L자로 접으면 힌지가 수면이에요. 힌지를 휙 움직여 던지고, 입질이 오면 챔질, 천천히 접었다 펴서 감아요. 15종을 찾아요.\n• 미니 골프: 9홀, 혼자 또는 둘이서. Duo를 접으면 위쪽 절반이 경사가 되어 공이 힌지 쪽으로 굴러요.\n• 혜성: 두 화면을 쓰는 픽셀 슈팅 게임. 반쯤 접으면 폭탄!\n• 번역을 고쳤어요.\n• 잠긴 게임을 한 번씩 무료로 체험하고, 매일 새로운 오늘의 게임을 무료로.\n• 홈과 메뉴에 다크 모드 (설정: 자동, 라이트, 다크).\n• Game Center 순위표: 혜성, 미니 골프, 지뢰찾기, 낚시 등.\n• CASCADE: 코인이 끝없이 나오던 버그 수정.",
        "zh-Hans": "• 钓鱼：把 Duo 折成 L 形，铰链就是水面。动一下铰链抛竿，咬钩时提竿，再轻轻开合收线。共 15 种待发现。\n• 迷你高尔夫：9 个洞，单人或双人。折起 Duo，上半部分变成斜坡，球会滚向铰链。\n• 彗星：横跨两块屏幕的像素射击游戏。折到一半投下炸弹。\n• 修正了翻译。\n• 每个未解锁的游戏都能免费试玩一次，每天还有一个免费的今日游戏。\n• 首页和菜单支持深色模式（设置：自动、浅色或深色）。\n• Game Center 排行榜：彗星、迷你高尔夫、扫雷、钓鱼等。\n• CASCADE：修复了金币无限产生的问题。",
    },
    "1.5": {
        "en-US": "• FISHING: fold the Duo into an L, the hinge is the waterline. Cast with a flick of the hinge, strike when it bites, then reel by folding gently. 15 catches to find.\n• MINI GOLF: 9 holes, solo or with two. Fold the Duo and the top half becomes a slope: the ball rolls toward the hinge.\n• COMET: a pixel shoot 'em up across both screens. Fold halfway to drop a bomb.\n• Translation fixes in German, Spanish, Japanese, Korean and Chinese.\n• Try any locked game for free once, and a new free game of the day, every day.",
        "fr-FR": "• PÊCHE : Duo plié en L, la charnière est la ligne de l'eau. Lance d'un coup de charnière, ferre quand ça mord, puis mouline en pliant doucement. 15 prises à trouver.\n• MINIGOLF : 9 trous, seul ou à deux. Plie le Duo : la moitié du haut devient une pente et la balle roule vers la charnière.\n• COMÈTE : un shoot'em up pixel sur les deux écrans. Plie à moitié pour lâcher une bombe.\n• Corrections de traduction en allemand, espagnol, japonais, coréen et chinois.\n• Essaie gratuitement chaque jeu fermé une fois, et un nouveau jeu du jour gratuit, tous les jours.",
        "de-DE": "• ANGELN: Klapp den Duo zum L, das Scharnier ist die Wasserlinie. Wirf mit einem Scharnier-Schwung, schlag an, wenn es beißt, und kurble durch sanftes Klappen. 15 Fänge zu entdecken.\n• MINIGOLF: 9 Löcher, allein oder zu zweit. Klapp den Duo und die obere Hälfte wird zum Hang: Der Ball rollt zum Scharnier.\n• KOMET: ein Pixel-Shoot-'em-up über beide Bildschirme. Halb zuklappen für eine Bombe.\n• Übersetzungen korrigiert.\n• Teste jedes gesperrte Spiel einmal gratis, und jeden Tag ein neues Gratis-Spiel des Tages.",
        "es-ES": "• PESCA: pliega el Duo en L, la bisagra es la línea del agua. Lanza con un golpe de bisagra, tira cuando piquen y recoge plegando suave. 15 capturas por descubrir.\n• MINIGOLF: 9 hoyos, solo o a dos. Pliega el Duo y la mitad de arriba se vuelve una cuesta: la bola rueda hacia la bisagra.\n• COMETA: un matamarcianos pixel en las dos pantallas. Pliega a medias para soltar una bomba.\n• Correcciones de traducción.\n• Prueba gratis una vez cada juego bloqueado, y un nuevo juego del día gratis, cada día.",
        "ja": "• つり：DuoをL字に折ると、ヒンジが水面に。ヒンジをクイッと動かして投げ、アタリでアワセて、ゆっくり開閉して巻こう。全15種。\n• ミニゴルフ：9ホール、1人でも2人でも。Duoを折ると上半分が坂になり、ボールがヒンジへ転がる。\n• コメット：2画面を使ったドット絵シューティング。半分折ってボム。\n• 翻訳を修正しました。\n• ロック中のゲームを1回無料でお試し。毎日「今日のゲーム」が無料に。",
        "ko": "• 낚시: Duo를 L자로 접으면 힌지가 수면이에요. 힌지를 휙 움직여 던지고, 입질이 오면 챔질, 천천히 접었다 펴서 감아요. 15종을 찾아요.\n• 미니 골프: 9홀, 혼자 또는 둘이서. Duo를 접으면 위쪽 절반이 경사가 되어 공이 힌지 쪽으로 굴러요.\n• 혜성: 두 화면을 쓰는 픽셀 슈팅 게임. 반쯤 접으면 폭탄!\n• 번역을 고쳤어요.\n• 잠긴 게임을 한 번씩 무료로 체험하고, 매일 새로운 오늘의 게임을 무료로.",
        "zh-Hans": "• 钓鱼：把 Duo 折成 L 形，铰链就是水面。动一下铰链抛竿，咬钩时提竿，再轻轻开合收线。共 15 种待发现。\n• 迷你高尔夫：9 个洞，单人或双人。折起 Duo，上半部分变成斜坡，球会滚向铰链。\n• 彗星：横跨两块屏幕的像素射击游戏。折到一半投下炸弹。\n• 修正了翻译。\n• 每个未解锁的游戏都能免费试玩一次，每天还有一个免费的今日游戏。",
    },
    "1.4": {
        "en-US": "• 4 new games!\n• CASCADE: a pixel-art coin pusher made for the Duo folded into an L. Coins rain down, the pusher shoves them off the edge. Upgrade your machine and fold-unfold the Duo to shake the board.\n• SEA BATTLE: sink the other fleet. Two players: close the Duo and pass it, the fold hides your grid. Or play the computer.\n• DOTS & BOXES: face to face with the Duo open flat. Close a box, it takes your color and initial.\n• MINES: the classic, with three grid sizes. Fold the Duo a little to place flags.",
        "fr-FR": "• 4 nouveaux jeux !\n• CASCADE : une machine à pièces en pixel art, faite pour le Duo plié en L. Les pièces pleuvent, le poussoir les fait tomber. Améliore ta machine et plie-déplie le Duo pour secouer le plateau.\n• BATAILLE NAVALE : coule la flotte d'en face. À deux : ferme le Duo et passe-le, le pli cache ta grille. Ou contre l'ordinateur.\n• CARRÉS : face à face, Duo ouvert à plat. Ferme un carré, il prend ta couleur et ton initiale.\n• DÉMINEUR : le classique, en trois tailles. Plie un peu le Duo pour poser des drapeaux.",
        "de-DE": "• 4 neue Spiele!\n• CASCADE: ein Münzschieber in Pixel-Art für den Duo im L-Modus. Münzen regnen, der Schieber schiebt sie über die Kante. Verbessere deinen Automaten und klappe den Duo zu und auf, um das Brett zu rütteln.\n• SCHIFFE VERSENKEN: Versenke die gegnerische Flotte. Zu zweit: Duo zuklappen und weitergeben, der Knick versteckt dein Feld. Oder gegen den Computer.\n• KÄSTCHEN: Gesicht an Gesicht, Duo flach. Schließ ein Kästchen, es bekommt deine Farbe und deinen Buchstaben.\n• MINENSUCHE: der Klassiker in drei Größen. Klappe den Duo etwas zu, um Flaggen zu setzen.",
        "es-ES": "• ¡4 juegos nuevos!\n• CASCADA: una máquina de monedas en pixel art para el Duo plegado en L. Llueven monedas y el empujador las tira por el borde. Mejora tu máquina y pliega y despliega el Duo para sacudir el tablero.\n• HUNDIR LA FLOTA: hunde la flota rival. A dos: cierra el Duo y pásalo, el pliegue esconde tu tablero. O contra el ordenador.\n• CUADRADOS: cara a cara con el Duo abierto en plano. Cierra un cuadrado y se lleva tu color y tu inicial.\n• BUSCAMINAS: el clásico en tres tamaños. Pliega un poco el Duo para poner banderas.",
        "ja": "• 新しいゲームが4つ！\n• カスケード：L字に折ったDuoのためのピクセルアートのコインプッシャー。マシンを強化し、Duoを折って戻すと台が揺れます。\n• 海戦：相手の艦隊を沈めよう。2人ならDuoを閉じて渡すと、折り目がグリッドを隠します。コンピュータとも対戦できます。\n• ドット＆ボックス：Duoを平らに開いて向かい合って。箱を閉じると色とイニシャルが入ります。\n• マインスイーパ：定番を3サイズで。Duoを少し折ると旗を置けます。",
        "ko": "• 새 게임 4개!\n• 캐스케이드: L자로 접은 Duo를 위한 픽셀 아트 코인 푸셔. 머신을 업그레이드하고 Duo를 접었다 펴서 판을 흔드세요.\n• 해전: 상대 함대를 침몰시키세요. 2인: Duo를 닫아 건네면 접힘이 판을 숨겨요. 컴퓨터와도 대결.\n• 점과 상자: Duo를 평평하게 펼치고 마주 보고. 상자를 닫으면 내 색과 이니셜이 들어가요.\n• 지뢰 찾기: 클래식을 세 가지 크기로. Duo를 살짝 접으면 깃발을 꽂아요.",
        "zh-Hans": "• 4 款新游戏！\n• 瀑布：专为折成 L 形的 Duo 打造的像素风推币机。升级机器，折叠再展开 Duo 摇晃平台。\n• 海战：击沉对方舰队。双人：合上 Duo 递给对方，折叠藏住你的棋盘。也可以和电脑对战。\n• 点格棋：Duo 平放面对面。围成格子就填上你的颜色和首字母。\n• 扫雷：经典玩法，三种尺寸。把 Duo 稍微折起就能插旗。",
    },
}
NEW_VERSION = os.environ.get("NEW_VERSION", "").strip()
if NEW_VERSION:
    existing = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&filter[versionString]={NEW_VERSION}").get("data", [])
    if existing:
        print(f"ok     version {NEW_VERSION} déjà créée ({existing[0]['attributes'].get('appStoreState')})")
        new_vid = existing[0]["id"]
    else:
        # Une app jamais publiée garde sa première version modifiable : on la renomme plutôt que d'en créer une autre.
        all_v = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10").get("data", [])
        never_live = not any(x["attributes"].get("appStoreState") in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION") for x in all_v)
        editable_v = [x for x in all_v if x["attributes"].get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
        # 1.0.6 retirée puis remplacée par 1.0.7 : on renomme aussi la version modifiable plutôt que d'en créer une autre.
        if editable_v:
            ev = editable_v[0]
            r = step(f"version {ev['attributes']['versionString']} renommée en {NEW_VERSION}", call("PATCH", f"/v1/appStoreVersions/{ev['id']}",
                     {"data": {"type": "appStoreVersions", "id": ev["id"], "attributes": {"versionString": NEW_VERSION}}}))
            new_vid = ev["id"]
        else:
            r = step(f"version {NEW_VERSION} créée", call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions",
                     "attributes": {"platform": "IOS", "versionString": NEW_VERSION, "releaseType": "MANUAL" if BUNDLE == "com.padelup.clapet" and NEW_VERSION not in ("1.0.4", "1.0.5", "1.0.6", "1.0.7", "1.0.8", "1.0.9", "1.0.10", "1.0.11", "1.0.12", "1.0.13", "1.6", "1.6.1") else "AFTER_APPROVAL"},
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
            new_vid = r.get("data", {}).get("id")
    notes = RELEASE_NOTES.get(NEW_VERSION, {})
    if new_vid and notes:
        for l in call("GET", f"/v1/appStoreVersions/{new_vid}/appStoreVersionLocalizations").get("data", []):
            text = notes.get(l["attributes"]["locale"])
            if text:
                step(f"nouveautés {l['attributes']['locale']}", call("PATCH", f"/v1/appStoreVersionLocalizations/{l['id']}", {"data": {
                     "type": "appStoreVersionLocalizations", "id": l["id"], "attributes": {"whatsNew": text}}}))

# ---------------------------------------------------------------- version 1.0
versions = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10").get("data", [])
version = next((v for v in versions if v["attributes"].get("appStoreState") in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")), None)
if not version:
    print("aucune version modifiable :", [(v["attributes"].get("versionString"), v["attributes"].get("appStoreState")) for v in versions])
    ready = next((v for v in versions if v["attributes"].get("appStoreState") == "READY_FOR_REVIEW"), None)
    if ready and SUBMIT:
        # La version est déjà dans une demande de vérification pas encore envoyée : on l'envoie.
        subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW,UNRESOLVED_ISSUES").get("data", [])
        print("demandes ouvertes :", [(x["id"], x["attributes"].get("state")) for x in subs])
        for sub in subs:
            items = call("GET", f"/v1/reviewSubmissions/{sub['id']}/items").get("data", [])
            print("  éléments :", len(items))
            if items:
                step("ENVOI À LA VÉRIFICATION D'APPLE", call("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {
                     "type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}}))
                break
        v = call("GET", f"/v1/appStoreVersions/{ready['id']}").get("data", {}).get("attributes", {})
        print("état de la version :", v.get("appStoreState"))
        print("\nENVOYÉ" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
    sys.exit(0 if not problems else 1)
vid = version["id"]
print("VERSION", version["attributes"].get("versionString"), version["attributes"].get("appStoreState"))

origamo = call("GET", "/v1/apps?filter[bundleId]=" + os.environ.get("ORIGAMO_BUNDLE_ID", "")).get("data", [])
owner = "PadelUp"
if origamo:
    for v in call("GET", f"/v1/apps/{origamo[0]['id']}/appStoreVersions?limit=5").get("data", []):
        c = v["attributes"].get("copyright")
        if c:
            owner = c.split(" ", 1)[1] if c[:4].isdigit() and " " in c else c
            break
step(f"copyright « 2026 {owner} » et sortie dès l'accord d'Apple", call("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {
    "type": "appStoreVersions", "id": vid, "attributes": {"copyright": f"2026 {owner}", "releaseType": "MANUAL" if NEW_VERSION and BUNDLE == "com.padelup.clapet" and NEW_VERSION not in ("1.0.4", "1.0.5", "1.0.6", "1.0.7", "1.0.8", "1.0.9", "1.0.10", "1.0.11", "1.0.12", "1.0.13", "1.6", "1.6.1") else "AFTER_APPROVAL"}}}))

# Coordonnées pour la vérification : celles déjà données pour la bêta
contact = call("GET", f"/v1/apps/{app_id}/betaAppReviewDetail").get("data", {}).get("attributes", {})
attrs = {k: contact.get(k) for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail") if contact.get(k)}
attrs.update({"notes": REVIEW_NOTES, "demoAccountRequired": False})
detail = call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
if detail:
    step("coordonnées et notes pour la vérification", call("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}",
         {"data": {"type": "appStoreReviewDetails", "id": detail["id"], "attributes": attrs}}))
else:
    step("coordonnées et notes pour la vérification", call("POST", "/v1/appStoreReviewDetails", {"data": {
        "type": "appStoreReviewDetails", "attributes": attrs,
        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}))

# URL d'assistance et de confidentialité
if SITE:
    for path in ("fr/", "en/", "fr/privacy.html", "en/privacy.html"):
        try:
            code = urllib.request.urlopen(f"{SITE}/{path}", timeout=20).getcode()
        except Exception as e:
            code = str(e)
        print(f"       {SITE}/{path} -> {code}")
        if code != 200:
            problems.append(f"page {path}")
    _site_ok = {}

    def site_lang(locale):
        """La langue du site pour cette langue de fiche (l'anglais si le site n'a pas cette langue)."""
        lang = LOCALES.get(locale, "en")
        if lang not in _site_ok:
            try:
                _site_ok[lang] = urllib.request.urlopen(f"{SITE}/{lang}/privacy.html", timeout=20).getcode() == 200
            except Exception:
                _site_ok[lang] = False
        return lang if _site_ok[lang] else "en"

    for l in call("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations").get("data", []):
        lang = site_lang(l["attributes"]["locale"])
        step(f"confidentialité {l['attributes']['locale']}", call("PATCH", f"/v1/appInfoLocalizations/{l['id']}", {"data": {
            "type": "appInfoLocalizations", "id": l["id"], "attributes": {"privacyPolicyUrl": f"{SITE}/{lang}/privacy.html"}}}))
    for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", []):
        lang = site_lang(l["attributes"]["locale"])
        step(f"assistance {l['attributes']['locale']}", call("PATCH", f"/v1/appStoreVersionLocalizations/{l['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": l["id"], "attributes": {"supportUrl": f"{SITE}/{lang}/", "marketingUrl": f"{SITE}/{lang}/"}}}))
else:
    print("       pas encore de site (SITE_URL) : assistance et confidentialité à faire")

# Captures d'écran : iPhone 6,7" et iPhone Duo (le badge « conçu pour l'iPhone Duo » demande ces dernières)
SHOT_SETS = [(SHOT_TYPE, ""), ("APP_IPHONE_DUO", "duo-"), ("APP_WATCH_ULTRA", "watch-")]
for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", []):
    lang = LOCALES.get(l["attributes"]["locale"])
    if not lang:
        continue
    sets = call("GET", f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets").get("data", [])
    for shot_type, prefix in SHOT_SETS:
        files = [os.path.join(SHOTS_DIR, f"{prefix}{lang}-{i}.png") for i in range(1, 11)]
        files = [f for f in files if os.path.exists(f)]
        if not files:
            continue
        s_ = next((x for x in sets if x["attributes"].get("screenshotDisplayType") == shot_type), None)
        if not s_:
            r = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": shot_type},
                     "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": l["id"]}}}}})
            if "error" in r:
                step(f"jeu de captures {shot_type} {lang}", r)
                continue
            s_ = r["data"]
        existing_shots = call("GET", f"/v1/appScreenshotSets/{s_['id']}/appScreenshots").get("data", [])
        wanted = sorted(hashlib.md5(open(f, "rb").read()).hexdigest() for f in files)
        have = sorted((x["attributes"].get("sourceFileChecksum") or "") for x in existing_shots)
        if wanted == have:
            print(f"ok     {len(files)} capture(s) {l['attributes']['locale']} ({shot_type}) déjà à jour")
            continue
        for old in existing_shots:
            call("DELETE", f"/v1/appScreenshots/{old['id']}")
        ok_count = 0
        for f in files:
            data = open(f, "rb").read()
            r = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
                     "attributes": {"fileName": os.path.basename(f), "fileSize": len(data)},
                     "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": s_["id"]}}}}})
            if "error" in r:
                step(f"capture {os.path.basename(f)}", r)
                continue
            sid = r["data"]["id"]
            for op in r["data"]["attributes"].get("uploadOperations", []):
                req = urllib.request.Request(op["url"], data=data[op["offset"]:op["offset"] + op["length"]], method=op["method"],
                                             headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
                urllib.request.urlopen(req).read()
            r = call("PATCH", f"/v1/appScreenshots/{sid}", {"data": {"type": "appScreenshots", "id": sid,
                     "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
            if "error" in r:
                step(f"capture {os.path.basename(f)}", r)
            else:
                ok_count += 1
        print(f"ok     {ok_count} capture(s) {l['attributes']['locale']} ({shot_type})")

# Build
if BUILD:
    builds = call("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={BUILD}&limit=5").get("data", [])
    build = next((b for b in builds if b["attributes"].get("processingState") == "VALID"), None)
    if build:
        step(f"build {BUILD} choisi pour la version 1.0", call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
             {"data": {"type": "builds", "id": build["id"]}}))
    else:
        problems.append("build")
        print(f"ÉCHEC  build {BUILD} pas prêt")

# Les vidéos d'en-tête et de recherche (iOS 27), déjà dans la bibliothèque : placées sur cette version, par langue.
ASSETS_DIR = os.environ.get("ASSETS_DIR", "")
if ASSETS_DIR and os.path.isdir(ASSETS_DIR):
    import subprocess
    r = subprocess.run([sys.executable, os.path.join(HERE, "asc_assets.py")], env={**os.environ, "MODE": "place"},
                       capture_output=True, text=True)
    print("\n".join("       " + x for x in (r.stdout + r.stderr).strip().splitlines()[-12:]))

# Les captures doivent être traitées par Apple avant l'envoi
if os.environ.get("SUBMIT") == "1":
    for attempt in range(30):
        pending = 0
        for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", []):
            for s_ in call("GET", f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets").get("data", []):
                for x in call("GET", f"/v1/appScreenshotSets/{s_['id']}/appScreenshots").get("data", []):
                    st = ((x["attributes"].get("assetDeliveryState") or {}).get("state"))
                    if st not in ("COMPLETE",):
                        pending += 1
        if not pending:
            print("ok     captures traitées par Apple")
            break
        print(f"       {pending} capture(s) encore en traitement chez Apple")
        time.sleep(15)

# ---------------------------------------------------------------- envoi à Apple
if SUBMIT:
    # Sur une mise à jour d'une app déjà en ligne, la fiche (catégories, âge, confidentialité) est figée et déjà remplie.
    if NEW_VERSION:
        problems = [x for x in problems if not x.startswith(("catégories", "classification", "confidentialité", "nom "))]
    if problems:
        print("\nPAS ENVOYÉ : il reste des points à régler :", ", ".join(problems))
        sys.exit(1)
    time.sleep(20)   # le temps que les captures soient traitées
    open_subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW").get("data", [])
    if open_subs:
        sub_id = open_subs[0]["id"]
    else:
        r = step("demande de vérification créée", call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions",
                 "attributes": {"platform": "IOS"}, "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
        if "error" in r:
            sys.exit(1)
        sub_id = r["data"]["id"]
    r_ = step("version ajoutée à la demande", call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
         "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                           "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}), tolerate=("already",))
    if "error" in r_ and "already" not in r_.get("detail", ""):
        # Jamais d'envoi sans la version (sinon les vidéos partent seules).
        print(r_.get("detail", "")[:4000])
        print("\nPAS ENVOYÉ : la version n'a pas pu être ajoutée")
        sys.exit(1)
    # Les vidéos d'en-tête et de recherche (iOS 27) placées sur cette version partent avec elle.
    for v_ in call("GET", f"/v1/appAssetLibraries/{app_id}/videos?limit=50").get("data", []):
        st = str(v_["attributes"].get("state") or "")
        if "APPROVED" in st or "REVIEW" in st or "REJECTED" in st:
            continue
        step(f"vidéo d'en-tête {v_['attributes'].get('referenceName')} ajoutée à la demande", call("POST", "/v1/reviewSubmissionItems", {"data": {
             "type": "reviewSubmissionItems", "relationships": {
                 "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                 "appAssetLibraryVideo": {"data": {"type": "appAssetLibraryVideos", "id": v_["id"]}}}}}),
             tolerate=("already", "ENTITY_ERROR", "STATE_ERROR"))
    # Le premier achat intégré (Foldly+) part avec cette version.
    for x in call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50").get("data", []):
        st = x["attributes"].get("state")
        print("       achat", x["attributes"].get("productId"), st)
        if st in ("READY_TO_SUBMIT", "DEVELOPER_ACTION_NEEDED", "REJECTED"):
            r_iap = step(f"achat {x['attributes'].get('productId')} envoyé avec la version", call("POST", "/v1/inAppPurchaseSubmissions", {"data": {
                 "type": "inAppPurchaseSubmissions", "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": x["id"]}}}}}),
                 tolerate=("already",))
            if isinstance(r_iap, dict) and "error" in r_iap and "already" not in r_iap.get("detail", ""):
                print(r_iap.get("detail", "")[:3000])
                print("\nPAS ENVOYÉ : l'achat intégré n'a pas pu partir avec la version")
                sys.exit(1)
    r = step("ENVOI À LA VÉRIFICATION D'APPLE", call("PATCH", f"/v1/reviewSubmissions/{sub_id}", {"data": {
         "type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}}))
    v = call("GET", f"/v1/appStoreVersions/{vid}").get("data", {}).get("attributes", {})
    print("état de la version :", v.get("appStoreState"))

print("\nPRÊT" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
