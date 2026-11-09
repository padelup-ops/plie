"""Crée les deux achats de Foldboard : l'essai gratuit de 3 jours (0 €) et Foldboard Pro (achat unique).

Apple demande, pour un essai sans abonnement, un achat non consommable à 0 € nommé « 3-day Trial ».
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
BUNDLE = "com.padelup.foldboard"
PRO_EUR = os.environ.get("PRO_PRICE", "2.99")
# Prix de lancement puis prix normal : à partir de LATER_DATE (AAAA-MM-JJ), le prix passe à LATER_PRICE.
LATER_PRICE = os.environ.get("LATER_PRICE", "").strip()
LATER_DATE = os.environ.get("LATER_DATE", "").strip()
SCREENSHOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "store", "iap-review.png")
PRODUCTS = [
    {"id": "com.padelup.foldboard.trial3", "name": "3-day Trial", "price": "0",
     "locales": {"en-US": ("3-day Trial", "Try every Foldboard Pro feature free"),
                 "fr-FR": ("Essai de 3 jours", "Toutes les options Pro gratuites 3 jours")},
     "note": "Free 3-day trial, as allowed for non-subscription apps (guideline 3.1.1). Starts from the Foldboard Pro screen in the app. Nothing renews."},
    {"id": "com.padelup.foldboard.pro", "name": "Foldboard Pro", "price": PRO_EUR,
     "locales": {"en-US": ("Foldboard Pro", "Two hands, colors, phrases, sounds"),
                 "fr-FR": ("Foldboard Pro", "Deux mains, couleurs, phrases, sons")},
     "note": "One-time purchase that unlocks the two-hand keyboard, the follow-your-hand mode, color themes, fonts, sounds and custom phrases. Buy and Restore buttons are on the Foldboard Pro screen of the app."},
]

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
    print("app introuvable : crée d'abord la fiche Foldboard sur App Store Connect", apps)
    sys.exit(1)
app_id = apps["data"][0]["id"]
print("APP_ID", app_id)
territories = [t["id"] for t in get_all("/v1/territories?limit=200")]
all_iaps = get_all(f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50")

for prod in PRODUCTS:
    pid = prod["id"]
    print("\n==", pid)
    existing = [x for x in all_iaps if x["attributes"].get("productId") == pid]
    if existing:
        iap = existing[0]
        print("ok     achat déjà créé, état", iap["attributes"].get("state"))
    else:
        r = step("création de l'achat " + pid, call("POST", "/v2/inAppPurchases", {"data": {"type": "inAppPurchases",
            "attributes": {"name": prod["name"], "productId": pid, "inAppPurchaseType": "NON_CONSUMABLE",
                           "reviewNote": prod["note"], "familySharable": False},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
        if "error" in r:
            continue
        iap = r["data"]
    iap_id = iap["id"]

    locs = {l["attributes"]["locale"]: l for l in get_all(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")}
    for locale, (name, desc) in prod["locales"].items():
        assert len(desc) <= 55 and len(name) <= 30, (name, desc)
        if locale in locs:
            step(f"textes {locale}", call("PATCH", f"/v1/inAppPurchaseLocalizations/{locs[locale]['id']}",
                 {"data": {"type": "inAppPurchaseLocalizations", "id": locs[locale]["id"], "attributes": {"name": name, "description": desc}}}))
        else:
            step(f"textes {locale}", call("POST", "/v1/inAppPurchaseLocalizations", {"data": {"type": "inAppPurchaseLocalizations",
                 "attributes": {"locale": locale, "name": name, "description": desc},
                 "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}}))

    points = get_all(f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=FRA&limit=200")
    point = next((p for p in points if abs(float(p["attributes"].get("customerPrice") or 0) - float(prod["price"])) < 0.001), None)
    if not point:
        problems.append("prix " + pid)
        print("ÉCHEC  palier introuvable :", prod["price"])
    else:
        later = None
        if pid.endswith(".pro") and LATER_PRICE and LATER_DATE:
            later = next((p for p in points if abs(float(p["attributes"].get("customerPrice") or 0) - float(LATER_PRICE)) < 0.001), None)
            if not later:
                print("ÉCHEC  palier introuvable :", LATER_PRICE)
        def schedule(with_end):
            prices = [{"type": "inAppPurchasePrices", "id": "${p1}",
                       "attributes": {"startDate": None, "endDate": LATER_DATE if (later and with_end) else None},
                       "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": point["id"]}}}}]
            refs = [{"type": "inAppPurchasePrices", "id": "${p1}"}]
            if later:
                prices.append({"type": "inAppPurchasePrices", "id": "${p2}", "attributes": {"startDate": LATER_DATE, "endDate": None},
                               "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": later["id"]}}}})
                refs.append({"type": "inAppPurchasePrices", "id": "${p2}"})
            return call("POST", "/v1/inAppPurchasePriceSchedules", {
                "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                    "baseTerritory": {"data": {"type": "territories", "id": "FRA"}},
                    "manualPrices": {"data": refs}}},
                "included": prices})
        r = schedule(True)
        if later and isinstance(r, dict) and "error" in r:
            print("       essai sans date de fin :", r.get("detail", "")[:300])
            r = schedule(False)
        label = f"prix {prod['price']} € (base France)" + (f", puis {LATER_PRICE} € dès le {LATER_DATE}" if later else "")
        step(label, r)

    step(f"disponibilité ({len(territories)} pays)", call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
        "type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
        "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                          "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}}))
    # Capture pour la vérification d'Apple (l'écran Foldboard Pro)
    if os.path.exists(SCREENSHOT):
        shot = call("GET", f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot")
        state = (shot.get("data") or {}).get("attributes", {}).get("assetDeliveryState", {}).get("state")
        if state in ("COMPLETE", "UPLOAD_COMPLETE"):
            print("ok     capture déjà envoyée")
        else:
            if shot.get("data"):
                call("DELETE", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{shot['data']['id']}")
            data = open(SCREENSHOT, "rb").read()
            r = step("réservation de la capture", call("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", {"data": {
                "type": "inAppPurchaseAppStoreReviewScreenshots", "attributes": {"fileName": "iap-review.png", "fileSize": len(data)},
                "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}}))
            if "data" in r:
                sid = r["data"]["id"]
                for op in r["data"]["attributes"].get("uploadOperations", []):
                    req = urllib.request.Request(op["url"], data=data[op["offset"]:op["offset"] + op["length"]], method=op["method"],
                                                 headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
                    urllib.request.urlopen(req).read()
                step("capture envoyée", call("PATCH", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{sid}", {"data": {
                    "type": "inAppPurchaseAppStoreReviewScreenshots", "id": sid,
                    "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}}))
    else:
        print("       pas de capture pour la vérification :", SCREENSHOT)
    time.sleep(2)
    a = call("GET", f"/v2/inAppPurchases/{iap_id}").get("data", {}).get("attributes", {})
    print("achat", a.get("productId"), "|", a.get("name"), "| état", a.get("state"))

print("\nACHATS PRÊTS (capture pour la vérification à ajouter avant la soumission)" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
