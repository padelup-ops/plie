"""Sonde App Store Connect : état de Foldboard (version, build, demande de vérification, achats)."""
import json, os, time, urllib.request, urllib.error
import jwt
API = "https://api.appstoreconnect.apple.com"
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 900,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
def call(m, p):
    req = urllib.request.Request(API + p, method=m, headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req) as r: return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:800]}
app = call("GET", "/v1/apps?filter[bundleId]=com.padelup.foldboard")["data"][0]
for v in call("GET", f"/v1/apps/{app['id']}/appStoreVersions?limit=3").get("data", []):
    b = call("GET", f"/v1/appStoreVersions/{v['id']}/build").get("data") or {}
    print("version", v["attributes"]["versionString"], v["attributes"].get("appStoreState"), "build", (b.get("attributes") or {}).get("version"))
for s in call("GET", f"/v1/reviewSubmissions?filter[app]={app['id']}&limit=10").get("data", []):
    print("demande", s["id"][:8], s["attributes"].get("state"), s["attributes"].get("submittedDate"))
    for it in call("GET", f"/v1/reviewSubmissions/{s['id']}/items?include=appStoreVersion").get("data", []):
        rel = [k for k, x in it.get("relationships", {}).items() if isinstance(x, dict) and x.get("data")]
        print("   élément", it["attributes"].get("state"), rel)
for x in call("GET", f"/v1/apps/{app['id']}/inAppPurchasesV2?limit=10").get("data", []):
    print("achat", x["attributes"].get("productId"), x["attributes"].get("state"))
