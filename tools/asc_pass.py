"""Pass Origamo (non consommable) : textes dans les 7 langues, prix (base France), tous les pays, capture pour la vérification.

Peut être relancé sans risque. Ne soumet rien à Apple."""
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = os.environ["BUNDLE_ID"]
PRODUCT_ID = "plie.pass.complet"
PRICE_EUR = os.environ.get("PLUS_PRICE", "3.99")
LATER_EUR = ""
LATER_DATE = ""
SCREENSHOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "store_review", "pass_review.png")
LOCALES = {
    "en-US": ("Origamo Pass", "All 25 games, every level and duel, forever"),
    "fr-FR": ("Pass Origamo", "Les 25 jeux, tous les niveaux et duels, pour toujours"),
    "de-DE": ("Origamo-Pass", "Alle 25 Spiele, alle Level und Duelle, für immer"),
    "es-ES": ("Pase Origamo", "Los 25 juegos, todos los niveles y duelos, siempre"),
    "ja": ("Origamoパス", "25のゲーム、全レベルと全決闘がずっと遊べる"),
    "ko": ("Origamo 패스", "게임 25개, 모든 레벨과 대결을 영구히"),
    "zh-Hans": ("Origamo 通行证", "全部 25 款游戏、所有关卡和对决，永久解锁"),
}
REVIEW_NOTE = ("One-time purchase. The app is free: 7 games are open, and playing earns keys that unlock the others one by one. "
               "The Origamo Pass unlocks every game, level and mini-duel at once. Open it by tapping a locked game or the "
               "\"Origamo Pass\" button on the home screen. Restore Purchases is on the same screen and in Settings.")

token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
problems = []


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        try:
            detail = "; ".join(f"{x.get('code')}: {x.get('detail')}" for x in json.loads(text).get("errors", []))
        except Exception:
            detail = text[:400]
        return {"error": e.code, "detail": detail}


def step(label, result):
    if isinstance(result, dict) and "error" in result:
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
            print("lecture impossible", url, page)
            return out
        out += page.get("data", [])
        nxt = page.get("links", {}).get("next")
        url = nxt.replace(API, "") if nxt else None
    return out



apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")
if not apps.get("data"):
    print("app introuvable", apps)
    sys.exit(1)
app_id = apps["data"][0]["id"]
print("APP_ID", app_id)

# 1. L'achat
existing = [x for x in get_all(f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50") if x["attributes"].get("productId") == PRODUCT_ID]
if existing:
    iap = existing[0]
    print("ok     achat déjà créé, état", iap["attributes"].get("state"))
    step("nom de référence et note pour la vérification", call("PATCH", f"/v2/inAppPurchases/{iap['id']}", {"data": {
        "type": "inAppPurchases", "id": iap["id"], "attributes": {"name": "Pass Origamo", "reviewNote": REVIEW_NOTE}}}))
else:
    r = step("création de l'achat " + PRODUCT_ID, call("POST", "/v2/inAppPurchases", {"data": {"type": "inAppPurchases",
        "attributes": {"name": "Pass Origamo", "productId": PRODUCT_ID, "inAppPurchaseType": "NON_CONSUMABLE",
                       "reviewNote": REVIEW_NOTE, "familySharable": False},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
    if "error" in r:
        sys.exit(1)
    iap = r["data"]
iap_id = iap["id"]

# 2. Textes
locs = {l["attributes"]["locale"]: l for l in get_all(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")}
for locale, (name, desc) in LOCALES.items():
    assert len(desc) <= 55, desc
    if locale in locs:
        step(f"textes {locale}", call("PATCH", f"/v1/inAppPurchaseLocalizations/{locs[locale]['id']}",
             {"data": {"type": "inAppPurchaseLocalizations", "id": locs[locale]["id"], "attributes": {"name": name, "description": desc}}}))
    else:
        step(f"textes {locale}", call("POST", "/v1/inAppPurchaseLocalizations", {"data": {"type": "inAppPurchaseLocalizations",
             "attributes": {"locale": locale, "name": name, "description": desc},
             "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}}))

# 3. Prix : prix de lancement, puis prix normal à partir de LATER_DATE
points = get_all(f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=FRA&limit=200")
def find(eur):
    return next((p for p in points if float(p["attributes"].get("customerPrice") or 0) == float(eur)), None)
now_p, later_p = find(PRICE_EUR), (find(LATER_EUR) if LATER_EUR and LATER_DATE else None)
if not now_p or (LATER_EUR and LATER_DATE and not later_p):
    problems.append("prix")
    print("ÉCHEC  palier introuvable :", PRICE_EUR, LATER_EUR)
else:
    prices = [{"type": "inAppPurchasePrices", "id": "${p1}", "attributes": {"startDate": None, "endDate": LATER_DATE if later_p else None},
               "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": now_p["id"]}}}}]
    if later_p:
        prices.append({"type": "inAppPurchasePrices", "id": "${p2}", "attributes": {"startDate": LATER_DATE, "endDate": None},
                       "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": later_p["id"]}}}})
    label = f"prix {PRICE_EUR} €" + (f", puis {LATER_EUR} € dès le {LATER_DATE}" if later_p else "") + " (base France)"
    step(label, call("POST", "/v1/inAppPurchasePriceSchedules", {
        "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
            "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
            "baseTerritory": {"data": {"type": "territories", "id": "FRA"}},
            "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": x["id"]} for x in prices]}}},
        "included": prices}))
    print("       prix réglé :", [(x["attributes"].get("startDate"), x["attributes"].get("endDate")) for x in prices])

# 4. Disponibilité
territories = [t["id"] for t in get_all("/v1/territories?limit=200")]
step(f"disponibilité ({len(territories)} pays)", call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
    "type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
    "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                      "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}}))

# 5. Capture pour la vérification d'Apple
shot = call("GET", f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot") if os.path.exists(SCREENSHOT) else {}
if not os.path.exists(SCREENSHOT):
    print("       pas encore de capture pour la vérification (à ajouter avant la soumission)")
elif shot.get("data") and shot["data"].get("attributes", {}).get("assetDeliveryState", {}).get("state") in ("COMPLETE", "UPLOAD_COMPLETE"):
    print("ok     capture déjà envoyée")
else:
    if shot.get("data"):
        call("DELETE", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{shot['data']['id']}")
    data = open(SCREENSHOT, "rb").read()
    r = step("réservation de la capture", call("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", {"data": {
        "type": "inAppPurchaseAppStoreReviewScreenshots", "attributes": {"fileName": "pass_review.png", "fileSize": len(data)},
        "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}}))
    if "data" in r:
        sid = r["data"]["id"]
        ok = True
        for op in r["data"]["attributes"].get("uploadOperations", []):
            chunk = data[op["offset"]:op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], data=chunk, method=op["method"],
                                         headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
            try:
                urllib.request.urlopen(req).read()
            except urllib.error.HTTPError as e:
                ok = False
                print("ÉCHEC  envoi d'un morceau", e.code, e.read()[:200])
        step("capture envoyée", call("PATCH", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{sid}", {"data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots", "id": sid,
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}}) if ok else {"error": 0, "detail": "envoi"})

# Relecture
time.sleep(3)
a = call("GET", f"/v2/inAppPurchases/{iap_id}").get("data", {}).get("attributes", {})
print("\nachat", a.get("productId"), "|", a.get("name"), "| type", a.get("inAppPurchaseType"), "| état", a.get("state"))
for l in get_all(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations"):
    print("  ", l["attributes"].get("locale"), "|", l["attributes"].get("name"), "|", l["attributes"].get("description"))
print("\nPASS PRÊT" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
