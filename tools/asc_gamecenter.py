"""Classements Game Center d'Origamo dans App Store Connect.

MODE=probe  : montre l'état (Game Center activé ? classements existants ? lien avec la version).
MODE=create : active Game Center pour l'app, crée les classements manquants (avec leurs noms en 7 langues),
              puis les rattache à la version en préparation (VERSION) pour qu'ils partent avec elle.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = os.environ["BUNDLE_ID"]
MODE = os.environ.get("MODE", "probe")
VERSION = os.environ.get("VERSION", "")

# vendorIdentifier, nom interne, format, tri, noms par langue
BOARDS = [
    ("origamo.comete", "COMETE score", "INTEGER", "DESC",
     {"fr-FR": "COMÈTE : meilleur score", "en-US": "COMET: high score", "de-DE": "KOMET: Highscore", "es-ES": "COMETA: récord",
      "ja": "コメット：ハイスコア", "ko": "혜성: 최고 점수", "zh-Hans": "彗星：最高分"}),
    ("origamo.golf", "MINIGOLF strokes", "INTEGER", "ASC",
     {"fr-FR": "MINIGOLF : 9 trous (coups)", "en-US": "MINI GOLF: 9 holes (strokes)", "de-DE": "MINIGOLF: 9 Löcher (Schläge)",
      "es-ES": "MINIGOLF: 9 hoyos (golpes)", "ja": "ミニゴルフ：9ホール（打数）", "ko": "미니 골프: 9홀 (타수)", "zh-Hans": "迷你高尔夫：9 洞（杆数）"}),
    ("origamo.mines.kids", "MINES small", "ELAPSED_TIME_CENTISECOND", "ASC",
     {"fr-FR": "DÉMINEUR : petite grille", "en-US": "MINESWEEPER: small", "de-DE": "MINENSUCHE: klein", "es-ES": "BUSCAMINAS: pequeño",
      "ja": "マインスイーパー：小", "ko": "지뢰찾기: 작은 판", "zh-Hans": "扫雷：小"}),
    ("origamo.mines.normal", "MINES medium", "ELAPSED_TIME_CENTISECOND", "ASC",
     {"fr-FR": "DÉMINEUR : grille moyenne", "en-US": "MINESWEEPER: medium", "de-DE": "MINENSUCHE: mittel", "es-ES": "BUSCAMINAS: mediano",
      "ja": "マインスイーパー：中", "ko": "지뢰찾기: 중간 판", "zh-Hans": "扫雷：中"}),
    ("origamo.mines.hard", "MINES large", "ELAPSED_TIME_CENTISECOND", "ASC",
     {"fr-FR": "DÉMINEUR : grande grille", "en-US": "MINESWEEPER: large", "de-DE": "MINENSUCHE: groß", "es-ES": "BUSCAMINAS: grande",
      "ja": "マインスイーパー：大", "ko": "지뢰찾기: 큰 판", "zh-Hans": "扫雷：大"}),
    ("origamo.peche", "FISHING catches", "INTEGER", "DESC",
     {"fr-FR": "PÊCHE : poissons pêchés", "en-US": "FISHING: fish caught", "de-DE": "ANGELN: gefangene Fische", "es-ES": "PESCA: peces pescados",
      "ja": "つり：釣った数", "ko": "낚시: 잡은 물고기", "zh-Hans": "钓鱼：钓到的鱼"}),
    ("origamo.croco", "CROCO streak", "INTEGER", "DESC",
     {"fr-FR": "CROCO : meilleure série", "en-US": "CROCO: best streak", "de-DE": "CROCO: beste Serie", "es-ES": "CROCO: mejor racha",
      "ja": "クロコ：最高連続", "ko": "크로코: 최고 연속", "zh-Hans": "鳄鱼：最佳连胜"}),
    ("origamo.bonneteau", "BONNETEAU level", "INTEGER", "DESC",
     {"fr-FR": "BONNETEAU : niveau atteint", "en-US": "SHELL GAME: level reached", "de-DE": "HÜTCHENSPIEL: Level", "es-ES": "TRILE: nivel alcanzado",
      "ja": "カップゲーム：到達レベル", "ko": "야바위: 도달 레벨", "zh-Hans": "猜杯子：最高关卡"}),
    ("origamo.luciole", "LUCIOLE lights", "INTEGER", "DESC",
     {"fr-FR": "LUCIOLE : lucioles", "en-US": "FIREFLY: lights", "de-DE": "GLÜHWÜRMCHEN: Lichter", "es-ES": "LUCIÉRNAGA: luces",
      "ja": "ホタル：光の数", "ko": "반딧불: 불빛", "zh-Hans": "萤火虫：光点"}),
    ("origamo.rayon", "RAYON levels", "INTEGER", "DESC",
     {"fr-FR": "RAYON : niveaux réussis", "en-US": "BEAM: levels solved", "de-DE": "STRAHL: gelöste Level", "es-ES": "RAYO: niveles resueltos",
      "ja": "ビーム：クリア数", "ko": "빔: 클리어한 레벨", "zh-Hans": "光束：通过关卡"}),
]

token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            b = r.read()
            return json.loads(b) if b else {}
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:1500]}


def show(label, x):
    print(f"--- {label}\n{json.dumps(x, ensure_ascii=False)[:2500]}\n")


app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]
app_id = app["id"]
print("app", app_id, app["attributes"].get("name"))

detail = call("GET", f"/v1/apps/{app_id}/gameCenterDetail")
show("gameCenterDetail", detail)
detail_id = (detail.get("data") or {}).get("id")

if MODE == "create" and not detail_id:
    r = call("POST", "/v1/gameCenterDetails", {"data": {"type": "gameCenterDetails",
             "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    show("activation de Game Center", r)
    detail_id = (r.get("data") or {}).get("id")
    if not detail_id:
        sys.exit("ÉCHEC : Game Center pas activé")

existing = {}
if detail_id:
    lb = call("GET", f"/v1/gameCenterDetails/{detail_id}/gameCenterLeaderboards?limit=200")
    for x in lb.get("data", []):
        existing[x["attributes"].get("vendorIdentifier")] = x["id"]
    print("classements existants :", list(existing))

if MODE == "probe":
    if detail_id:
        show("versions Game Center", call("GET", f"/v1/gameCenterDetails/{detail_id}/gameCenterAppVersions?limit=10&include=appStoreVersion"))
    sys.exit(0)

for vid, ref, fmt, sort, names in BOARDS:
    if vid in existing:
        print("déjà là :", vid)
        continue
    r = call("POST", "/v1/gameCenterLeaderboards", {"data": {"type": "gameCenterLeaderboards",
             "attributes": {"referenceName": ref, "vendorIdentifier": vid, "defaultFormatter": fmt,
                            "submissionType": "BEST_SCORE", "scoreSortType": sort},
             "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail_id}}}}})
    if "error" in r:
        show("ÉCHEC classement " + vid, r)
        continue
    lid = r["data"]["id"]
    existing[vid] = lid
    print("ok classement", vid)
    for loc, name in names.items():
        rr = call("POST", "/v1/gameCenterLeaderboardLocalizations", {"data": {"type": "gameCenterLeaderboardLocalizations",
                  "attributes": {"locale": loc, "name": name[:32]},
                  "relationships": {"gameCenterLeaderboard": {"data": {"type": "gameCenterLeaderboards", "id": lid}}}}})
        if "error" in rr:
            show(f"ÉCHEC nom {vid} {loc}", rr)

# Rattacher Game Center (et donc les classements) à la version en préparation.
if VERSION:
    vers = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[versionString]={VERSION}&filter[platform]=IOS")
    v = (vers.get("data") or [None])[0]
    if not v:
        print("version", VERSION, "introuvable : on la rattachera à la soumission")
    else:
        r = call("POST", "/v1/gameCenterAppVersions", {"data": {"type": "gameCenterAppVersions",
                 "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
        show("Game Center rattaché à la version " + VERSION, r)
print("\nCLASSEMENTS :", len(existing), "/", len(BOARDS))
