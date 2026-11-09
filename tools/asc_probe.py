"""Sonde : prix et état des achats Foldboard."""
import json, os, time, urllib.request, urllib.error
import jwt
API = "https://api.appstoreconnect.apple.com"
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 900,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
def call(p):
    req = urllib.request.Request(API + p, headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req) as r: return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:600]}
app = call("/v1/apps?filter[bundleId]=com.padelup.foldboard")["data"][0]
for x in call(f"/v1/apps/{app['id']}/inAppPurchasesV2?limit=10").get("data", []):
    a = x["attributes"]
    print("ACHAT", a.get("productId"), a.get("state"), a.get("inAppPurchaseType"), a.get("name"))
    for l in call(f"/v2/inAppPurchases/{x['id']}/inAppPurchaseLocalizations").get("data", []):
        print("   texte", l["attributes"].get("locale"), "|", l["attributes"].get("name"), "|", l["attributes"].get("description"))
    r = call(f"/v1/inAppPurchasePriceSchedules/{x['id']}/manualPrices?filter[territory]=FRA&include=inAppPurchasePricePoint&limit=20")
    pts = {i["id"]: i["attributes"].get("customerPrice") for i in r.get("included", [])}
    for p in r.get("data", []):
        pp = p["relationships"]["inAppPurchasePricePoint"]["data"]["id"]
        print("   prix France", pts.get(pp), "du", p["attributes"].get("startDate"), "au", p["attributes"].get("endDate"))
    if "error" in r: print("   ", r)
for v in call(f"/v1/apps/{app['id']}/appStoreVersions?limit=3").get("data", []):
    b = call(f"/v1/appStoreVersions/{v['id']}/build").get("data") or {}
    print("VERSION", v["attributes"]["versionString"], v["attributes"].get("appStoreState"), "build", (b.get("attributes") or {}).get("version"))
for s in call(f"/v1/reviewSubmissions?filter[app]={app['id']}&limit=10").get("data", []):
    print("DEMANDE", s["id"][:8], s["attributes"].get("state"))
    for it in call(f"/v1/reviewSubmissions/{s['id']}/items").get("data", []):
        rel = [k for k, x in it.get("relationships", {}).items() if isinstance(x, dict) and x.get("data")]
        print("   élément", it["attributes"].get("state"), rel)
print("CONFIDENTIALITE", json.dumps(call(f"/v1/apps/{app['id']}/appDataUsages"))[:300])
