"""Prix temporaire d'un achat intégré (ex. Foldly+ à 0,99 € pendant 48 h), puis retour automatique au prix habituel.

MODE=probe : montre le calendrier de prix actuel.
MODE=apply : garde le prix habituel et ajoute PROMO_PRICE (euros, France ; les autres pays suivent)
             du START au END (dates AAAA-MM-JJ).
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
PRODUCT_ID = os.environ["PRODUCT_ID"]
MODE = os.environ.get("MODE", "probe")
PROMO = os.environ.get("PROMO_PRICE", "0.99")
START = os.environ.get("START", "")
END = os.environ.get("END", "")

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
        return {"error": e.code, "detail": e.read().decode()[:2000]}


def show(label, x):
    print(f"--- {label}\n{json.dumps(x, ensure_ascii=False)[:3000]}\n")


app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]
iaps = [x for x in call("GET", f"/v1/apps/{app['id']}/inAppPurchasesV2?limit=50").get("data", [])
        if x["attributes"].get("productId") == PRODUCT_ID]
if not iaps:
    sys.exit("achat introuvable : " + PRODUCT_ID)
iap_id = iaps[0]["id"]
print("achat", PRODUCT_ID, iap_id)

prices = call("GET", f"/v1/inAppPurchasePriceSchedules/{iap_id}/manualPrices?include=inAppPurchasePricePoint,territory&filter[territory]=FRA&limit=50")
show("prix manuels (France)", prices)
points = {x["id"]: x for x in prices.get("included", []) if x["type"] == "inAppPurchasePricePoints"}
current = None
for p in prices.get("data", []):
    a = p["attributes"]
    pp = p["relationships"]["inAppPurchasePricePoint"]["data"]["id"]
    cp = points.get(pp, {}).get("attributes", {}).get("customerPrice")
    print("  prix", cp, "€ du", a.get("startDate"), "au", a.get("endDate"))
    if not a.get("startDate") and not a.get("endDate"):
        current = (pp, cp)
    elif current is None and not a.get("endDate"):
        current = (pp, cp)
print("prix habituel :", current)

if MODE == "probe":
    sys.exit(0)
if not current:
    sys.exit("ÉCHEC : prix habituel introuvable")
if not START or not END:
    sys.exit("ÉCHEC : START et END requis")

# Le point de prix à 0,99 € en France
promo_pp = None
url = f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=FRA&limit=200"
while url and not promo_pp:
    page = call("GET", url)
    for pp in page.get("data", []):
        if abs(float(pp["attributes"].get("customerPrice", "0")) - float(PROMO)) < 0.001:
            promo_pp = pp["id"]
            break
    nxt = page.get("links", {}).get("next")
    url = nxt.replace(API, "") if nxt else None
if not promo_pp:
    sys.exit(f"ÉCHEC : point de prix {PROMO} € introuvable")

body = {
    "data": {"type": "inAppPurchasePriceSchedules",
             "relationships": {
                 "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                 "baseTerritory": {"data": {"type": "territories", "id": "FRA"}},
                 "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${base}"},
                                           {"type": "inAppPurchasePrices", "id": "${promo}"}]}}},
    "included": [
        {"type": "inAppPurchasePrices", "id": "${base}", "attributes": {"startDate": None},
         "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": current[0]}}}},
        {"type": "inAppPurchasePrices", "id": "${promo}", "attributes": {"startDate": START, "endDate": END},
         "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": promo_pp}}}},
    ],
}
r = call("POST", "/v1/inAppPurchasePriceSchedules", body)
show("nouveau calendrier", r)
if "error" in r:
    sys.exit("ÉCHEC calendrier de prix")
print(f"\nPROMO OK : {PROMO} € du {START} au {END}, puis retour à {current[1]} €")
