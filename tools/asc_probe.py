"""Sonde App Store Connect : types de captures acceptés et ceux des apps déjà publiées."""
import json, os, time, urllib.request, urllib.error
import jwt
API = "https://api.appstoreconnect.apple.com"
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 900,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
def call(m, p, b=None):
    req = urllib.request.Request(API + p, method=m, data=json.dumps(b).encode() if b else None,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read(); return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:3000]}
for bundle in ("com.padelup.clapet", "com.padelup.foldboard", os.environ.get("ORIGAMO", "")):
    if not bundle: continue
    a = call("GET", f"/v1/apps?filter[bundleId]={bundle}").get("data", [])
    if not a: continue
    print("==", bundle)
    for v in call("GET", f"/v1/apps/{a[0]['id']}/appStoreVersions?limit=3").get("data", []):
        print("  version", v["attributes"]["versionString"], v["attributes"].get("appVersionState") or v["attributes"].get("appStoreState"))
        locs = call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations").get("data", [])
        for l in locs[:1]:
            for s in call("GET", f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets").get("data", []):
                print("    ", l["attributes"]["locale"], s["attributes"]["screenshotDisplayType"])
        if bundle == "com.padelup.foldboard" and locs:
            r = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "XX_INVALID"},
                     "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": locs[0]["id"]}}}}})
            print("  sonde type invalide :", json.dumps(r)[:3000])
