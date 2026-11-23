"""Crée les achats de Vicefold : Pro à vie (5,99 €), et l'abonnement Pro (2,99 €/an, 0,99 €/mois), validés le 23/11.
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
BUNDLE = "com.padelup.vicefold"
PRO_EUR = os.environ.get("PRO_PRICE", "5.99")
YEAR_EUR = os.environ.get("YEAR_PRICE", "2.99")
MONTH_EUR = os.environ.get("MONTH_PRICE", "0.99")
# Prix de lancement puis prix normal : à partir de LATER_DATE (AAAA-MM-JJ), le prix passe à LATER_PRICE.
LATER_PRICE = os.environ.get("LATER_PRICE", "").strip()
LATER_DATE = os.environ.get("LATER_DATE", "").strip()
SCREENSHOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "store", "iap-review.png")
NOTE = ("Unlocks Pro: unlimited pins on the map, the collectible/activity/random event map layers, importing your own map picture, "
        "iCloud sync, progress widgets and PlayStation play time. All guides stay free. More > Vicefold Pro opens the purchase screen "
        "with the three options and Restore.")
PRODUCTS = [
    {"id": "com.padelup.vicefold.pro.lifetime", "name": "Vicefold Pro (lifetime)", "price": PRO_EUR,
     "locales": {"en-US": ("Vicefold Pro, forever", "Pro once, for good: pins, layers, your map, iCloud"),
                 "fr-FR": ("Vicefold Pro, à vie", "Pro pour toujours : épingles, calques, ta carte")},
     "note": NOTE},
]
SUBS = [
    {"id": "com.padelup.vicefold.pro.yearly", "name": "Vicefold Pro yearly", "period": "ONE_YEAR", "price": YEAR_EUR, "level": 1,
     "locales": {"en-US": ("Vicefold Pro, yearly", "Pins, layers, your map, iCloud, widgets"),
                 "fr-FR": ("Vicefold Pro, à l'année", "Épingles, calques, ta carte, iCloud, widgets")}},
    {"id": "com.padelup.vicefold.pro.monthly", "name": "Vicefold Pro monthly", "period": "ONE_MONTH", "price": MONTH_EUR, "level": 2,
     "locales": {"en-US": ("Vicefold Pro, monthly", "Pins, layers, your map, iCloud, widgets"),
                 "fr-FR": ("Vicefold Pro, au mois", "Épingles, calques, ta carte, iCloud, widgets")}},
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


# ---------------------------------------------------------------- Abonnements (un groupe, deux durées)
def upload_shot(kind_path, rel_type, rel_id, rel_key):
    if not os.path.exists(SCREENSHOT):
        print("       pas de capture pour la vérification :", SCREENSHOT)
        return
    data = open(SCREENSHOT, "rb").read()
    r = step("réservation de la capture", call("POST", "/v1/subscriptionAppStoreReviewScreenshots", {"data": {
        "type": "subscriptionAppStoreReviewScreenshots", "attributes": {"fileName": "iap-review.png", "fileSize": len(data)},
        "relationships": {"subscription": {"data": {"type": "subscriptions", "id": rel_id}}}}}))
    if "data" in r:
        sid = r["data"]["id"]
        for op in r["data"]["attributes"].get("uploadOperations", []):
            req = urllib.request.Request(op["url"], data=data[op["offset"]:op["offset"] + op["length"]], method=op["method"],
                                         headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
            urllib.request.urlopen(req).read()
        step("capture envoyée", call("PATCH", f"/v1/subscriptionAppStoreReviewScreenshots/{sid}", {"data": {
            "type": "subscriptionAppStoreReviewScreenshots", "id": sid,
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}}))

groups = get_all(f"/v1/apps/{app_id}/subscriptionGroups?limit=50")
group = next((g for g in groups if g["attributes"].get("referenceName") == "Vicefold Pro"), None)
if not group:
    r = step("groupe d'abonnements", call("POST", "/v1/subscriptionGroups", {"data": {"type": "subscriptionGroups",
        "attributes": {"referenceName": "Vicefold Pro"}, "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
    group = r.get("data")
if group:
    gid = group["id"]
    glocs = {l["attributes"]["locale"]: l for l in get_all(f"/v1/subscriptionGroups/{gid}/subscriptionGroupLocalizations")}
    for locale, name in (("en-US", "Vicefold Pro"), ("fr-FR", "Vicefold Pro")):
        if locale not in glocs:
            step(f"nom du groupe {locale}", call("POST", "/v1/subscriptionGroupLocalizations", {"data": {"type": "subscriptionGroupLocalizations",
                 "attributes": {"locale": locale, "name": name}, "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": gid}}}}}))
    existing_subs = get_all(f"/v1/subscriptionGroups/{gid}/subscriptions?limit=50")
    for sub in SUBS:
        print("\n==", sub["id"])
        cur = next((x for x in existing_subs if x["attributes"].get("productId") == sub["id"]), None)
        if not cur:
            r = step("abonnement " + sub["id"], call("POST", "/v1/subscriptions", {"data": {"type": "subscriptions",
                "attributes": {"name": sub["name"], "productId": sub["id"], "subscriptionPeriod": sub["period"], "familySharable": False,
                               "reviewNote": NOTE, "groupLevel": sub["level"]},
                "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": gid}}}}}))
            cur = r.get("data")
        if not cur:
            continue
        sid = cur["id"]
        slocs = {l["attributes"]["locale"]: l for l in get_all(f"/v1/subscriptions/{sid}/subscriptionLocalizations")}
        for locale, (name, desc) in sub["locales"].items():
            assert len(desc) <= 55 and len(name) <= 30, (name, desc)
            if locale in slocs:
                step(f"textes {locale}", call("PATCH", f"/v1/subscriptionLocalizations/{slocs[locale]['id']}", {"data": {
                     "type": "subscriptionLocalizations", "id": slocs[locale]["id"], "attributes": {"name": name, "description": desc}}}))
            else:
                step(f"textes {locale}", call("POST", "/v1/subscriptionLocalizations", {"data": {"type": "subscriptionLocalizations",
                     "attributes": {"locale": locale, "name": name, "description": desc},
                     "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}}}}))
        have_prices = get_all(f"/v1/subscriptions/{sid}/prices?limit=200")
        if have_prices:
            print(f"ok     prix déjà posés ({len(have_prices)} pays)")
        else:
            pts = get_all(f"/v1/subscriptions/{sid}/pricePoints?filter[territory]=FRA&limit=200")
            base = next((p for p in pts if abs(float(p["attributes"].get("customerPrice") or 0) - float(sub["price"])) < 0.001), None)
            if not base:
                problems.append("prix " + sub["id"]); print("ÉCHEC  palier introuvable :", sub["price"])
            else:
                eq = [base] + get_all(f"/v1/subscriptionPricePoints/{base['id']}/equalizations?limit=200")
                ok = 0
                for p in eq:
                    terr = p.get("relationships", {}).get("territory", {}).get("data", {}).get("id") or "FRA"
                    r = call("POST", "/v1/subscriptionPrices", {"data": {"type": "subscriptionPrices",
                        "attributes": {"startDate": None, "preserveCurrentPrice": False},
                        "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                                          "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": p["id"]}},
                                          "territory": {"data": {"type": "territories", "id": terr}}}}})
                    ok += 0 if "error" in r else 1
                print(f"ok     prix {sub['price']} € posé dans {ok} pays sur {len(eq)}")
        step(f"disponibilité ({len(territories)} pays)", call("POST", "/v1/subscriptionAvailabilities", {"data": {
            "type": "subscriptionAvailabilities", "attributes": {"availableInNewTerritories": True},
            "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                              "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}}))
        shot = call("GET", f"/v1/subscriptions/{sid}/appStoreReviewScreenshot")
        if (shot.get("data") or {}).get("attributes", {}).get("assetDeliveryState", {}).get("state") in ("COMPLETE", "UPLOAD_COMPLETE"):
            print("ok     capture déjà envoyée")
        else:
            upload_shot(None, None, sid, None)
        a = call("GET", f"/v1/subscriptions/{sid}").get("data", {}).get("attributes", {})
        print("abonnement", a.get("productId"), "| état", a.get("state"))

print("\nACHATS PRÊTS (capture pour la vérification à ajouter avant la soumission)" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
