"""Crée l'achat intégré « Pass Origamo » (non consommable) dans App Store Connect.

Nom et description en français et en anglais, prix de base en France, disponible dans tous les pays.
Peut être relancé sans risque : ce qui existe déjà est conservé et seulement complété.
Ne soumet rien à Apple. Lancé par .github/workflows/asc-pass.yml.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
PRODUCT_ID = "plie.pass.complet"
PRICE_EUR = os.environ.get("PASS_PRICE", "2.99")
LOCALES = {
    "fr-FR": ("Pass Origamo", "Tous les niveaux, pour toujours"),
    "en-US": ("Origamo Pass", "Every level, forever"),
}
REVIEW_NOTE = ("One-time purchase that unlocks the extra levels in Beam, Inkfold, Ramp and The Safe, the Champion opponent "
               "in Ping Pong, the Hard computer in Chess and Checkers, and every plant in Focus. Open it from the home screen, "
               "\"Origamo Pass\" button. Restore is in Settings.")

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


apps = call("GET", "/v1/apps?filter[bundleId]=" + os.environ["BUNDLE_ID"])
if not apps.get("data"):
    print("app introuvable", apps)
    sys.exit(1)
app_id = apps["data"][0]["id"]
print("APP_ID", app_id)

# 1. L'achat lui-même
existing = [x for x in get_all(f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50") if x["attributes"].get("productId") == PRODUCT_ID]
if existing:
    iap = existing[0]
    print("ok     achat déjà créé, état", iap["attributes"].get("state"))
else:
    r = step("création de l'achat " + PRODUCT_ID, call("POST", "/v2/inAppPurchases", {"data": {"type": "inAppPurchases",
        "attributes": {"name": "Pass Origamo", "productId": PRODUCT_ID, "inAppPurchaseType": "NON_CONSUMABLE",
                       "reviewNote": REVIEW_NOTE, "familySharable": False},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
    if "error" in r:
        sys.exit(1)
    iap = r["data"]
iap_id = iap["id"]

# 2. Nom et description affichés dans chaque langue
locs = {l["attributes"]["locale"]: l for l in get_all(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")}
for locale, (name, desc) in LOCALES.items():
    if locale in locs:
        step(f"textes {locale}", call("PATCH", f"/v1/inAppPurchaseLocalizations/{locs[locale]['id']}",
             {"data": {"type": "inAppPurchaseLocalizations", "id": locs[locale]["id"], "attributes": {"name": name, "description": desc}}}))
    else:
        step(f"textes {locale}", call("POST", "/v1/inAppPurchaseLocalizations", {"data": {"type": "inAppPurchaseLocalizations",
             "attributes": {"locale": locale, "name": name, "description": desc},
             "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}}))

# 3. Prix : palier français à PRICE_EUR, les autres pays suivent la grille d'Apple
points = get_all(f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=FRA&limit=200")
point = next((p for p in points if p["attributes"].get("customerPrice") == PRICE_EUR), None)
if not point:
    problems.append("prix")
    print("ÉCHEC  aucun palier à", PRICE_EUR, "€ ; paliers proches :",
          sorted({p["attributes"].get("customerPrice") for p in points}, key=float)[:40])
else:
    step(f"prix {PRICE_EUR} € (base France)", call("POST", "/v1/inAppPurchasePriceSchedules", {
        "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
            "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
            "baseTerritory": {"data": {"type": "territories", "id": "FRA"}},
            "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${prix}"}]}}},
        "included": [{"type": "inAppPurchasePrices", "id": "${prix}", "attributes": {"startDate": None},
                      "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": point["id"]}}}}]}))

# 4. Disponible partout où l'app l'est
territories = [t["id"] for t in get_all("/v1/territories?limit=200")]
step(f"disponibilité ({len(territories)} pays)", call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
    "type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
    "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                      "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}}))

# Relecture
print()
again = call("GET", f"/v2/inAppPurchases/{iap_id}")
a = again.get("data", {}).get("attributes", {})
print("achat", a.get("productId"), "|", a.get("name"), "| type", a.get("inAppPurchaseType"), "| état", a.get("state"))
for l in get_all(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations"):
    print("  ", l["attributes"].get("locale"), "|", l["attributes"].get("name"), "|", l["attributes"].get("description"))
sched = call("GET", f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule?include=manualPrices,baseTerritory")
print("  prix de base :", ", ".join(x["id"] for x in sched.get("included", []) if x["type"] == "territories") or "?")
print("\nPASS CRÉÉ" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
print("Il reste à ajouter une capture de l'écran du Pass, puis à cocher l'achat sur la page de la version 1.0.")
