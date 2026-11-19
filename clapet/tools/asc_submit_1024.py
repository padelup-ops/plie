"""Envoie Foldly 1.0.24 (build donné) à la vérification, sortie automatique après accord.

Ne change que les nouveautés, le type de sortie et le build joint. Pas le prix, pas les captures,
pas les catégories. Ne touche pas aux autres apps.
"""
import json
import os
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.padelup.clapet"
VERSION = "1.0.24"
BUILD = os.environ.get("RELEASE_BUILD", "133").strip()
NOTES = {
    "en-US": "New: an All time open & closed widget showing your lifetime hours unfolded vs folded. Tap or drag any bar in Your week and Today by hour to see the exact fold count and open/closed time. Play Foldly's opening and closing sounds from Shortcuts, even when the app isn't open.",
    "fr-FR": "Nouveau : un widget « Ouvert et fermé, au total » qui montre tes heures dépliées et pliées depuis le début. Touche ou fais glisser une barre dans Ta semaine et Aujourd'hui, heure par heure pour voir le nombre exact de plis et le temps ouvert et fermé. Joue les sons d'ouverture et de fermeture de Foldly depuis Raccourcis, même quand l'app n'est pas ouverte.",
    "de-DE": "Neu: ein Widget „Offen und zu, insgesamt“, das deine Stunden aufgeklappt und zugeklappt seit dem ersten Tag zeigt. Tippe oder ziehe einen Balken in „Deine Woche“ und „Heute, Stunde für Stunde“, um die genaue Zahl der Faltungen und die offene und geschlossene Zeit zu sehen. Spiele Foldlys Öffnungs- und Schließton über Kurzbefehle ab, auch wenn die App nicht geöffnet ist.",
    "es-ES": "Nuevo: un widget «Abierto y cerrado, en total» que muestra tus horas desplegado y plegado desde el primer día. Toca o arrastra una barra en Tu semana y Hoy, hora a hora para ver el número exacto de pliegues y el tiempo abierto y cerrado. Reproduce los sonidos de apertura y cierre de Foldly desde Atajos, aunque la app no esté abierta.",
    "ja": "新機能：開いていた時間と閉じていた時間の累計を表示するウィジェットを追加しました。使い始めてからの開いていた時間と閉じていた時間が見られます。「今週」と「今日の1時間ごと」の棒をタップまたはドラッグすると、その回数と開いていた・閉じていた正確な時間が表示されます。アプリを開かなくても、ショートカットから開く音と閉じる音を鳴らせます。",
    "ko": "새로운 기능: 처음 사용한 날부터 펼친 시간과 접힌 시간을 보여주는 위젯 ‘열린·닫힌 시간 (전체)’. ‘이번 주’와 ‘오늘 시간별’에서 막대를 누르거나 드래그하면 정확한 접은 횟수와 열린·닫힌 시간을 볼 수 있어요. 앱을 열지 않아도 단축어에서 여는 소리와 닫는 소리를 재생할 수 있어요.",
    "zh-Hans": "新功能：新增小组件「打开与合上，累计」，显示你从第一天起展开与合上的总时长。在「你的一周」和「今天按小时」中点按或拖动任意柱形，即可查看准确的折叠次数以及打开和合上的时长。即使不打开 App，也可以用快捷指令播放打开音和合上音。",
    "it": "Novità: un widget «Aperto e chiuso, da sempre» che mostra le ore aperte e chiuse da sempre. Tocca o trascina una barra in La tua settimana e Oggi, ora per ora per vedere il numero esatto di chiusure e il tempo aperto e chiuso. Riproduci i suoni di apertura e chiusura di Foldly da Comandi, anche se l'app non è aperta.",
    "pt-BR": "Novidade: um widget «Aberto e fechado, desde sempre» que mostra suas horas aberto e fechado desde o primeiro dia. Toque ou arraste uma barra em Sua semana e Hoje, hora a hora para ver o número exato de fechamentos e o tempo aberto e fechado. Toque os sons de abertura e fechamento do Foldly pelos Atalhos, mesmo com o app fechado.",
    "nl-NL": "Nieuw: een widget ‘Open en gesloten, altijd’ die laat zien hoeveel uur je telefoon sinds de eerste dag open en dicht is geweest. Tik of sleep een staaf in Jouw week en Vandaag per uur om het exacte aantal keren dicht en de open- en gesloten tijd te zien. Speel Foldly's open- en sluitgeluid af via Opdrachten, ook als de app niet open is.",
    "ru": "Новое: виджет «Открыт и закрыт, за всё время» показывает, сколько часов телефон был открыт и закрыт с первого дня. Нажмите или проведите по столбцу в «Ваша неделя» и «Сегодня по часам», чтобы увидеть точное число закрытий и время в открытом и закрытом виде. Воспроизводите звуки открытия и закрытия Foldly из «Команд», даже когда приложение не открыто.",
}

token = jwt.encode(
    {"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
    os.environ["ASC_PRIVATE_KEY"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
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
            detail = "; ".join(f"{x.get('code')}: {x.get('detail')}" for x in errs) or text[:800]
        except Exception:
            detail = text[:800]
        return {"error": e.code, "detail": detail}


def step(label, result, tolerate=()):
    if isinstance(result, dict) and "error" in result:
        if any(t in result["detail"] for t in tolerate):
            print(f"ok     {label} (déjà fait)")
            return result
        problems.append(label)
        print(f"ÉCHEC  {label} -> HTTP {result['error']} {result['detail'][:500]}")
    else:
        print(f"ok     {label}")
    return result


apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}").get("data", [])
if not apps:
    print("app introuvable")
    raise SystemExit(1)
app_id = apps[0]["id"]
print("APP", app_id, apps[0]["attributes"].get("name"))

existing = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&filter[versionString]={VERSION}").get("data", [])
if existing:
    version = existing[0]
    print("version déjà là", version["attributes"].get("appStoreState"))
else:
    created = step("version 1.0.24 créée", call("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": VERSION, "releaseType": "AFTER_APPROVAL"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
    version = created.get("data")
if not version:
    raise SystemExit(1)
vid = version["id"]
step("sortie automatique après accord", call("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {
    "type": "appStoreVersions", "id": vid, "attributes": {"releaseType": "AFTER_APPROVAL"}}}))

for loc in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", []):
    locale = loc["attributes"]["locale"]
    text = NOTES.get(locale) or NOTES.get({"fr": "fr-FR", "es": "es-ES", "de": "de-DE"}.get(locale.split("-")[0], "")) or NOTES["en-US"]
    step(f"nouveautés {locale}", call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {
        "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"whatsNew": text}}}))

build = None
for attempt in range(40):
    builds = call("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={BUILD}&limit=5").get("data", [])
    states = [b["attributes"].get("processingState") for b in builds]
    build = next((b for b in builds if b["attributes"].get("processingState") == "VALID"), None)
    print(f"build {BUILD}", states or "introuvable", f"essai {attempt + 1}")
    if build or any(s in ("FAILED", "INVALID") for s in states):
        break
    time.sleep(30)
if not build:
    print("ÉCHEC build pas prêt")
    raise SystemExit(1)
step(f"build {BUILD} joint", call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
     {"data": {"type": "builds", "id": build["id"]}}))

subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW,UNRESOLVED_ISSUES&limit=10").get("data", [])
if subs:
    sub_id = subs[0]["id"]
    print("demande ouverte", sub_id, subs[0]["attributes"].get("state"))
else:
    made = step("demande de vérification créée", call("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
    if "error" in made:
        raise SystemExit(1)
    sub_id = made["data"]["id"]
step("version ajoutée à la demande", call("POST", "/v1/reviewSubmissionItems", {"data": {
    "type": "reviewSubmissionItems", "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}), tolerate=("already",))
step("ENVOI À LA VÉRIFICATION", call("PATCH", f"/v1/reviewSubmissions/{sub_id}", {"data": {
    "type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}}))

time.sleep(5)
final = call("GET", f"/v1/appStoreVersions/{vid}").get("data", {}).get("attributes", {})
print("ÉTAT", final.get("appStoreState"), "releaseType", final.get("releaseType"), "version", final.get("versionString"))
attached = call("GET", f"/v1/appStoreVersions/{vid}/build").get("data", {})
print("BUILD JOINT", (attached.get("attributes") or {}).get("version"), (attached.get("attributes") or {}).get("processingState"))
subs2 = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&limit=5").get("data", [])
for s in subs2[:3]:
    print("DEMANDE", s["id"], s["attributes"].get("state"))
if problems:
    print("À REVOIR", ", ".join(problems))
    raise SystemExit(1)
print("SOUMIS")
