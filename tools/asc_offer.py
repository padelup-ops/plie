"""Codes d'offre à usage unique pour un achat intégré (ex. le Pass Origamo offert).

MODE=probe  : montre les codes d'offre existants d'un achat (pour comprendre leur forme).
MODE=create : crée une offre gratuite « NAME » sur l'achat, puis COUNT codes à usage unique valables DAYS jours,
              et écrit codes.csv (code + lien de rachat).
"""
import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = os.environ["BUNDLE_ID"]
PRODUCT_ID = os.environ.get("PRODUCT_ID", "plie.pass.complet")
MODE = os.environ.get("MODE", "probe")
NAME = os.environ.get("NAME", "Launch giveaway")
COUNT = int(os.environ.get("COUNT", "50"))
DAYS = int(os.environ.get("DAYS", "60"))

token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None, raw=False):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            b = r.read()
            if raw: return b.decode()
            return json.loads(b) if b else {}
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        return {"error": e.code, "detail": text[:1500]}


def show(label, x):
    print(f"--- {label}\n{json.dumps(x, ensure_ascii=False)[:3000]}\n")


app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]
app_id = app["id"]
iaps = [x for x in call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50").get("data", []) if x["attributes"].get("productId") == PRODUCT_ID]
if not iaps:
    sys.exit("achat introuvable : " + PRODUCT_ID)
iap = iaps[0]
iap_id = iap["id"]
print("achat", iap_id, iap["attributes"].get("state"))

offers = call("GET", f"/v2/inAppPurchases/{iap_id}/offerCodes?limit=50")
show("offres existantes", offers)

if MODE == "probe":
    for o in offers.get("data", [])[:2]:
        oid = o["id"]
        show("offre + prix", call("GET", f"/v1/inAppPurchaseOfferCodes/{oid}?include=prices"))
        show("prix", call("GET", f"/v1/inAppPurchaseOfferCodes/{oid}/prices?limit=3&include=territory,pricePoint"))
        show("codes à usage unique", call("GET", f"/v1/inAppPurchaseOfferCodes/{oid}/oneTimeUseCodes?limit=5"))
    show("points de prix (extrait)", call("GET", f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=FRA&limit=3"))
    sys.exit(0)

# --- MODE create
# Territoires où l'achat est vendu
terr = []
url = f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule"
avail = call("GET", f"/v2/inAppPurchases/{iap_id}/inAppPurchaseAvailability?include=availableTerritories&limit[availableTerritories]=200")
for t in avail.get("included", []):
    if t["type"] == "territories": terr.append(t["id"])
if not terr:
    terr = [t["id"] for t in call("GET", "/v1/territories?limit=200").get("data", [])]
print(len(terr), "territoires")

existing = [o for o in offers.get("data", []) if o["attributes"].get("name") == NAME]
if existing:
    oid = existing[0]["id"]
    print("offre déjà là", oid)
else:
    prices, included = [], []
    for k, t in enumerate(terr):
        lid = f"${{p{k}}}"
        prices.append({"type": "inAppPurchaseOfferPrices", "id": lid})
        included.append({"type": "inAppPurchaseOfferPrices", "id": lid, "attributes": {},
                         "relationships": {"territory": {"data": {"type": "territories", "id": t}},
                                           "pricePoint": {"data": None}}})
    body = {"data": {"type": "inAppPurchaseOfferCodes",
                     "attributes": {"name": NAME, "customerEligibilities": ["NON_SPENDER"]},
                     "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                                       "prices": {"data": prices}}},
            "included": included}
    r = call("POST", "/v1/inAppPurchaseOfferCodes", body)
    show("création de l'offre", r)
    if "error" in r:
        # deuxième forme : sans pricePoint (gratuit)
        for x in included: x["relationships"].pop("pricePoint", None)
        r = call("POST", "/v1/inAppPurchaseOfferCodes", body)
        show("création de l'offre (sans point de prix)", r)
    if "error" in r:
        sys.exit("ÉCHEC création de l'offre")
    oid = r["data"]["id"]

exp = (datetime.date.today() + datetime.timedelta(days=DAYS)).isoformat()
r = call("POST", "/v1/inAppPurchaseOfferCodeOneTimeUseCodes", {"data": {"type": "inAppPurchaseOfferCodeOneTimeUseCodes",
         "attributes": {"numberOfCodes": COUNT, "expirationDate": exp},
         "relationships": {"offerCode": {"data": {"type": "inAppPurchaseOfferCodes", "id": oid}}}}})
show("création des codes", r)
if "error" in r:
    sys.exit("ÉCHEC création des codes")
cid = r["data"]["id"]
values = ""
for _ in range(30):
    values = call("GET", f"/v1/inAppPurchaseOfferCodeOneTimeUseCodes/{cid}/values", raw=True)
    if isinstance(values, str) and values.strip() and "error" not in values[:20]:
        break
    time.sleep(20)
codes = [l.strip().split(",")[0] for l in values.splitlines() if l.strip()]
codes = [c for c in codes if c and c.lower() != "code" and len(c) >= 8]
apple_id = app["id"]
with open("codes.csv", "w") as f:
    f.write("code,lien\n")
    for c in codes:
        f.write(f"{c},https://apps.apple.com/redeem?ctx=offercodes&id={apple_id}&code={c}\n")
print(f"\n{len(codes)} CODES ÉCRITS (valables jusqu'au {exp})")
