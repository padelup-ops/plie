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
# PRICE : prix réduit en euros (ex. "1.99") ; vide = gratuit. CUSTOM : un code réutilisable (ex. ORIGAMO199) au lieu de codes uniques.
PRICE = os.environ.get("PRICE", "").strip()
CUSTOM = os.environ.get("CUSTOM", "").strip().upper()
COUNT = int(os.environ.get("COUNT", "50"))
DAYS = int(os.environ.get("DAYS", "60"))

token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None, raw=False):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json",
                                          "Accept": "text/csv" if raw else "application/json"})
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
    for o in offers.get("data", [])[:6]:
        oid = o["id"]
        show("offre + prix", call("GET", f"/v1/inAppPurchaseOfferCodes/{oid}?include=prices"))
        show("prix", call("GET", f"/v1/inAppPurchaseOfferCodes/{oid}/prices?limit=3&include=territory,pricePoint"))
        show("codes à usage unique", call("GET", f"/v1/inAppPurchaseOfferCodes/{oid}/oneTimeUseCodes?limit=5"))
        cc = call("GET", f"/v1/inAppPurchaseOfferCodes/{oid}/customCodes?limit=10")
        for c in cc.get("data", []):
            a = c["attributes"]
            print(f"CODE PERSO {o['attributes'].get('name')!r}: {a.get('customCode')} · {a.get('numberOfCodes')} utilisations · expire {a.get('expirationDate')} · actif {a.get('active')}")
        fr = call("GET", f"/v1/inAppPurchaseOfferCodes/{oid}/prices?filter[territory]=FRA&include=pricePoint&limit=1")
        for x in fr.get("included", []):
            print(f"PRIX FRANCE {o['attributes'].get('name')!r}: {x['attributes'].get('customerPrice')} €")
    mp = call("GET", f"/v1/inAppPurchasePriceSchedules/{iap_id}/manualPrices?include=inAppPurchasePricePoint&filter[territory]=FRA&limit=50")
    pts = {x["id"]: x for x in mp.get("included", []) if x["type"] == "inAppPurchasePricePoints"}
    for p in mp.get("data", []):
        pid = p["relationships"]["inAppPurchasePricePoint"]["data"]["id"]
        print(f"PRIX DU PASS (France) {pts.get(pid, {}).get('attributes', {}).get('customerPrice')} € du {p['attributes'].get('startDate')} au {p['attributes'].get('endDate')}")
    show("points de prix (extrait)", call("GET", f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=FRA&limit=3"))
    sys.exit(0)

if MODE == "fetch":
    ex = [o for o in offers.get("data", []) if o["attributes"].get("name") == NAME]
    if not ex: sys.exit("ÉCHEC offre introuvable : " + NAME)
    batches = call("GET", f"/v1/inAppPurchaseOfferCodes/{ex[0]['id']}/oneTimeUseCodes?limit=50").get("data", [])
    out = []
    for b in batches:
        if not b["attributes"].get("active"): continue
        v = call("GET", f"/v1/inAppPurchaseOfferCodeOneTimeUseCodes/{b['id']}/values", raw=True)
        if isinstance(v, str):
            out += [l.strip().split(",")[0] for l in v.splitlines() if len(l.strip().split(",")[0]) >= 8 and l.strip().lower() != "code"]
    with open("codes.csv", "w") as f:
        f.write("code,lien\n")
        for c in out: f.write(f"{c},https://apps.apple.com/redeem?ctx=offercodes&id={app_id}&code={c}\n")
    print(len(out), "CODES LUS", [(b["attributes"].get("numberOfCodes"), b["attributes"].get("expirationDate"), b["attributes"].get("active")) for b in batches])
    sys.exit(0)

# PRICE=half : moitié du prix actuel (France), arrondie au point de prix juste en dessous.
if PRICE.lower() == "half":
    mp = call("GET", f"/v1/inAppPurchasePriceSchedules/{iap_id}/manualPrices?include=inAppPurchasePricePoint&filter[territory]=FRA&limit=50")
    pts = {x["id"]: x for x in mp.get("included", []) if x["type"] == "inAppPurchasePricePoints"}
    base = None
    for p in mp.get("data", []):
        if not p["attributes"].get("endDate"):
            base = float(pts[p["relationships"]["inAppPurchasePricePoint"]["data"]["id"]]["attributes"]["customerPrice"])
    if base is None: sys.exit("ÉCHEC prix actuel introuvable")
    target, best = base / 2, None
    url = f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=FRA&limit=200"
    while url:
        page = call("GET", url)
        for pp in page.get("data", []):
            c = float(pp["attributes"].get("customerPrice", "0"))
            if 0 < c <= target + 0.001 and (best is None or c > best): best = c
        nxt = page.get("links", {}).get("next")
        url = nxt.replace(API, "") if nxt else None
    PRICE = f"{best:.2f}"
    print(f"PRIX ACTUEL {base:.2f} € -> PRIX OFFRE {PRICE} €")

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
    # Prix réduit : le point de prix français, puis ses équivalents dans chaque pays.
    points = {}
    if PRICE:
        url = f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=FRA&limit=200"
        fra = None
        while url and not fra:
            page = call("GET", url)
            for pp in page.get("data", []):
                if abs(float(pp["attributes"].get("customerPrice", "0")) - float(PRICE)) < 0.001: fra = pp["id"]; break
            nxt = page.get("links", {}).get("next")
            url = nxt.replace(API, "") if nxt else None
        if not fra: sys.exit(f"ÉCHEC point de prix {PRICE} € introuvable")
        points["FRA"] = fra
        url = f"/v1/inAppPurchasePricePoints/{fra}/equalizations?limit=200&include=territory"
        while url:
            page = call("GET", url)
            for pp in page.get("data", []):
                t = (pp.get("relationships", {}).get("territory", {}).get("data") or {}).get("id")
                if t: points[t] = pp["id"]
            nxt = page.get("links", {}).get("next")
            url = nxt.replace(API, "") if nxt else None
        terr = [t for t in terr if t in points]
        print(len(points), "points de prix,", len(terr), "territoires gardés")
    prices, included = [], []
    for k, t in enumerate(terr):
        lid = f"${{p{k}}}"
        prices.append({"type": "inAppPurchaseOfferPrices", "id": lid})
        included.append({"type": "inAppPurchaseOfferPrices", "id": lid, "attributes": {},
                         "relationships": {"territory": {"data": {"type": "territories", "id": t}},
                                           "pricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": points[t]} if PRICE else None}}})
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
if CUSTOM:
    r = call("POST", "/v1/inAppPurchaseOfferCodeCustomCodes", {"data": {"type": "inAppPurchaseOfferCodeCustomCodes",
             "attributes": {"customCode": CUSTOM, "numberOfCodes": COUNT, "expirationDate": exp},
             "relationships": {"offerCode": {"data": {"type": "inAppPurchaseOfferCodes", "id": oid}}}}})
    show("code personnalisé", r)
    if "error" in r: sys.exit("ÉCHEC code personnalisé")
    print(f"\nCODE {CUSTOM} : {COUNT} utilisations, valable jusqu'au {exp}")
    print(f"LIEN https://apps.apple.com/redeem?ctx=offercodes&id={app['id']}&code={CUSTOM}")
    sys.exit(0)
if MODE == "fetch":
    lots = call("GET", f"/v1/inAppPurchaseOfferCodes/{oid}/oneTimeUseCodes?limit=20").get("data", [])
    show("lots", lots)
    r = {"data": lots[-1]} if lots else {"error": 0, "detail": "aucun lot"}
else:
  r = call("POST", "/v1/inAppPurchaseOfferCodeOneTimeUseCodes", {"data": {"type": "inAppPurchaseOfferCodeOneTimeUseCodes",
         "attributes": {"numberOfCodes": COUNT, "expirationDate": exp},
         "relationships": {"offerCode": {"data": {"type": "inAppPurchaseOfferCodes", "id": oid}}}}})
  show("création des codes", r)
if "error" in r:
    sys.exit("ÉCHEC création des codes")
cid = r["data"]["id"]
values = ""
for _ in range(6):
    values = call("GET", f"/v1/inAppPurchaseOfferCodeOneTimeUseCodes/{cid}/values", raw=True)
    if isinstance(values, str) and values.strip():
        break
    print("valeurs pas encore prêtes :", str(values)[:300])
    time.sleep(20)
values = values if isinstance(values, str) else ""
codes = [l.strip().split(",")[0] for l in values.splitlines() if l.strip()]
codes = [c for c in codes if c and c.lower() != "code" and len(c) >= 8]
apple_id = app["id"]
with open("codes.csv", "w") as f:
    f.write("code,lien\n")
    for c in codes:
        f.write(f"{c},https://apps.apple.com/redeem?ctx=offercodes&id={apple_id}&code={c}\n")
print(f"\n{len(codes)} CODES ÉCRITS (valables jusqu'au {exp})")
