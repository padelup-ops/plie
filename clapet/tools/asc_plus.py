"""Crée l'achat intégré « Duo Folds+ » (non consommable) de l'app Duo Folds (projet Clapet).

Nom et description en anglais et en français, 2,99 € (base France), tous les pays, capture pour la vérification.
Peut être relancé sans risque : ce qui existe déjà est conservé et complété. Ne soumet rien à Apple.
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
BUNDLE = "com.padelup.clapet"
PRODUCT_ID = "com.padelup.clapet.plus"
PRICE_EUR = os.environ.get("PLUS_PRICE", "2.99")
SCREENSHOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "review", "plus_review.png")
LOCALES = {
    "en-US": ("Duo Folds+", "Every widget, limit alerts, full history"),
    "fr-FR": ("Duo Folds+", "Tous les widgets, alertes, tout l'historique"),
}
REVIEW_NOTE = ("One-time purchase. Unlocks the medium, large and Lock Screen widgets (without it they are blurred with a "
               "\"Tap to unlock\" message), limit alerts (notifications at 80% and 100% of the daily limit), the full history "
               "and records, widget colors and CSV export. Open it from the \"Plus\" button at the top of the main screen. "
               "Restore is in Settings.")

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
else:
    r = step("création de l'achat " + PRODUCT_ID, call("POST", "/v2/inAppPurchases", {"data": {"type": "inAppPurchases",
        "attributes": {"name": "Duo Folds+", "productId": PRODUCT_ID, "inAppPurchaseType": "NON_CONSUMABLE",
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

# 3. Prix
points = get_all(f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=FRA&limit=200")
point = next((p for p in points if p["attributes"].get("customerPrice") == PRICE_EUR), None)
if not point:
    problems.append("prix")
    print("ÉCHEC  aucun palier à", PRICE_EUR, "€")
else:
    step(f"prix {PRICE_EUR} € (base France)", call("POST", "/v1/inAppPurchasePriceSchedules", {
        "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
            "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
            "baseTerritory": {"data": {"type": "territories", "id": "FRA"}},
            "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${prix}"}]}}},
        "included": [{"type": "inAppPurchasePrices", "id": "${prix}", "attributes": {"startDate": None},
                      "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": point["id"]}}}}]}))

# 4. Disponibilité
territories = [t["id"] for t in get_all("/v1/territories?limit=200")]
step(f"disponibilité ({len(territories)} pays)", call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
    "type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
    "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                      "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}}))

# 5. Capture pour la vérification d'Apple
shot = call("GET", f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot")
if shot.get("data") and shot["data"].get("attributes", {}).get("assetDeliveryState", {}).get("state") in ("COMPLETE", "UPLOAD_COMPLETE"):
    print("ok     capture déjà envoyée")
else:
    if shot.get("data"):
        call("DELETE", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{shot['data']['id']}")
    data = open(SCREENSHOT, "rb").read()
    r = step("réservation de la capture", call("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", {"data": {
        "type": "inAppPurchaseAppStoreReviewScreenshots", "attributes": {"fileName": "plus_review.png", "fileSize": len(data)},
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
print("\nDUO FOLDS+ PRÊT" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
