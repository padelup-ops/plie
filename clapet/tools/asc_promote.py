"""Achat mis en avant (Promoted In-App Purchase) : Foldly+ sur la fiche App Store de Foldly.

Envoie l'image de promotion (1024 x 1024) de l'achat, puis l'ajoute aux achats mis en avant, visible par tous.
Peut être relancé : ce qui existe déjà est gardé. L'image passe en revue avec la prochaine version.
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
PRICE_EUR = os.environ.get("PLUS_PRICE", "2.99")        # prix de lancement
LATER_EUR = os.environ.get("PLUS_PRICE_LATER", "3.99")  # prix normal...
LATER_DATE = os.environ.get("PLUS_LATER_DATE", "2026-11-13")  # ...à partir de cette date
IMAGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "review", "plus_promo.png")
LOCALES = {
    "en-US": ("Foldly+", "Every widget, limit alerts, full history"),
    "fr-FR": ("Foldly+", "Tous les widgets, alertes, tout l'historique"),
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



def upload(ops, data):
    for op in ops:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"],
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
        try:
            urllib.request.urlopen(req).read()
        except urllib.error.HTTPError as e:
            print("ÉCHEC  envoi d'un morceau", e.code, e.read()[:200])
            return False
    return True


app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]
app_id = app["id"]
iaps = call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?filter[productId]={PRODUCT_ID}").get("data", [])
if not iaps:
    sys.exit("Foldly+ introuvable")
iap_id = iaps[0]["id"]
print("achat", iap_id, iaps[0]["attributes"].get("state"))

# 1. Image de promotion
imgs = call("GET", f"/v2/inAppPurchases/{iap_id}/images")
print("images :", json.dumps(imgs)[:600])
have = [i for i in imgs.get("data", []) if i["attributes"].get("state") not in ("FAILED", "UPLOAD_FAILED")]
if have:
    print("ok     image déjà là :", have[0]["attributes"].get("state"))
else:
    data = open(IMAGE, "rb").read()
    r = step("réservation de l'image", call("POST", "/v1/inAppPurchaseImages", {"data": {
        "type": "inAppPurchaseImages", "attributes": {"fileName": "plus_promo.png", "fileSize": len(data)},
        "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}}}}}))
    if "data" in r:
        iid = r["data"]["id"]
        ok = upload(r["data"]["attributes"].get("uploadOperations", []), data)
        step("image envoyée", call("PATCH", f"/v1/inAppPurchaseImages/{iid}", {"data": {
            "type": "inAppPurchaseImages", "id": iid,
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}}) if ok else {"error": 0, "detail": "envoi"})

# 2. Achat mis en avant
promos = call("GET", f"/v1/apps/{app_id}/promotedPurchases?include=inAppPurchaseV2")
print("mis en avant :", json.dumps(promos)[:600])
mine = [p for p in promos.get("data", []) if (p.get("relationships", {}).get("inAppPurchaseV2", {}).get("data") or {}).get("id") == iap_id]
if mine:
    pid = mine[0]["id"]
    step("achat mis en avant (mise à jour)", call("PATCH", f"/v1/promotedPurchases/{pid}", {"data": {
        "type": "promotedPurchases", "id": pid, "attributes": {"visibleForAllUsers": True, "enabled": True}}}))
else:
    r = step("achat mis en avant (création)", call("POST", "/v1/promotedPurchases", {"data": {
        "type": "promotedPurchases", "attributes": {"visibleForAllUsers": True, "enabled": True},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                          "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}}))
    if "data" in r:
        pid = r["data"]["id"]
        step("ordre des achats mis en avant", call("PATCH", f"/v1/apps/{app_id}/relationships/promotedPurchases", {
            "data": [{"type": "promotedPurchases", "id": pid}]}))

time.sleep(3)
for p in call("GET", f"/v1/apps/{app_id}/promotedPurchases").get("data", []):
    print("  promo", p["id"], json.dumps(p["attributes"]))
print("\nMISE EN AVANT PRÊTE" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
