"""Crée l'achat d'Allô Père Noël : « La magie complète », achat unique (non consommable) à 3,99 € (prix du brief).
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
BUNDLE = "com.padelup.allonoel"
PRICE_EUR = os.environ.get("PRICE", "3.99")
LATER_PRICE = ""
LATER_DATE = ""
SCREENSHOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "store", "iap-review.png")
NOTE = ("Unlocks the full magic: the four other Santa stories (secret, congratulations, silly Santa, Christmas Eve), one call "
        "for brothers and sisters together, a special moment and a Christmas wish that Santa mentions, and premium keepsake cards. "
        "The first story stays free. The purchase screen opens from a locked story or from Settings > Unlock the full magic, "
        "and asks a multiplication question for grown-ups before buying. Restore is on the same screen.")
PASS_NOTE = (
    "Christmas Pass, non-consumable, 6.99 EUR. Unlocks the full personalized Santa call (name, age, qualities, "
    "anecdote, wish, all stories, siblings), a printable letter, a good-child certificate, and the advent calendar. "
    "The free tier is a short preview of the magic call (greeting by name, age, qualities, goodbye) plus advent door 1. A multiplication question for grown-ups "
    "is required before the purchase and before the privacy-policy link. No ads, no account, no data collection. "
    "Restore is on the paywall and in Settings. Do not submit this product for review from this script."
)
PACK_NOTE = (
    "Consumable pack of 3 extra personalized messages for another child, 2.99 EUR. Bought from the paywall or Settings, "
    "behind the same grown-up multiplication question. Credits stay on the device. No ads, no data collection. "
    "Do not submit this product for review from this script."
)
PRODUCTS = [
    {"id": "com.padelup.allonoel.magie", "name": "Full magic", "price": PRICE_EUR, "type": "NON_CONSUMABLE",
     "locales": {"fr-FR": ("La magie complète", "Toutes les histoires, frères et sœurs, souvenirs"),
                 "en-US": ("The full magic", "All stories, siblings, special moments, cards"),
                 "es-ES": ("La magia completa", "Todas las historias, hermanos y recuerdos"),
                 "de-DE": ("Der volle Zauber", "Alle Geschichten, Geschwister, Erinnerungen"),
                 "it": ("La magia completa", "Tutte le storie, fratelli e ricordi"),
                 "pt-BR": ("A magia completa", "Todas as histórias, irmãos e lembranças")},
     "note": NOTE},
    {"id": "com.padelup.allonoel.pass", "name": "Christmas Pass", "price": "6.99", "type": "NON_CONSUMABLE",
     "locales": {"fr-FR": ("Pass Noël", "Appels, lettre, certificat, calendrier"),
                 "en-US": ("Christmas Pass", "Calls, letter, certificate, calendar"),
                 "es-ES": ("Pase de Navidad", "Llamadas, carta, diploma y calendario"),
                 "de-DE": ("Weihnachts-Pass", "Anrufe, Brief, Urkunde, Kalender"),
                 "it": ("Pass Natale", "Chiamate, lettera, diploma, calendario"),
                 "pt-BR": ("Passe de Natal", "Ligações, carta, diploma, calendário")},
     "note": PASS_NOTE},
    {"id": "com.padelup.allonoel.messages", "name": "Extra messages", "price": "2.99", "type": "CONSUMABLE",
     "locales": {"fr-FR": ("Messages en plus", "Trois messages pour un autre enfant"),
                 "en-US": ("Extra messages", "Three messages for another child"),
                 "es-ES": ("Mensajes extra", "Tres mensajes para otro niño"),
                 "de-DE": ("Extra-Botschaften", "Drei Botschaften für ein Kind mehr"),
                 "it": ("Messaggi extra", "Tre messaggi per un altro bambino"),
                 "pt-BR": ("Mensagens extra", "Três mensagens para outra criança")},
     "note": PACK_NOTE},
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
    print("app introuvable", apps)
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
            "attributes": {"name": prod["name"], "productId": pid, "inAppPurchaseType": prod["type"],
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
        if False and LATER_PRICE and LATER_DATE:
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
    # Capture pour la vérification d'Apple (la page « La magie complète »)
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



if problems:
    print("\nPROBLÈMES :", ", ".join(problems))
    sys.exit(1)
print("\nTOUT EST OK")
