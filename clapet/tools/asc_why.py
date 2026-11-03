"""FOLDLY : pourquoi Apple refuse la version dans la demande de vérification (erreurs détaillées)."""
import json, os, sys, time, urllib.request, urllib.error
import jwt
API = "https://api.appstoreconnect.apple.com"
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 600,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read(); return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()}
app = call("GET", "/v1/apps?filter[bundleId]=com.padelup.clapet")["data"][0]
v = [x for x in call("GET", f"/v1/apps/{app['id']}/appStoreVersions?filter[versionString]=1.0.3").get("data", [])][0]
print("version", v["id"], v["attributes"].get("appStoreState"))
subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app['id']}&limit=10").get("data", [])
for s in subs:
    print("demande", s["id"], s["attributes"])
# La demande partie sans la version (vidéos seules) : on l'annule pour tout renvoyer ensemble.
for x in subs:
    if x["attributes"]["state"] == "WAITING_FOR_REVIEW":
        r = call("PATCH", f"/v1/reviewSubmissions/{x['id']}", {"data": {"type": "reviewSubmissions", "id": x["id"], "attributes": {"canceled": True}}})
        print("annulation", x["id"], r.get("data", {}).get("attributes", r.get("detail", "")[:300]))
time.sleep(10)
subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app['id']}&limit=10").get("data", [])
open_ = [s for s in subs if s["attributes"]["state"] in ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES")]
sid = open_[0]["id"] if open_ else None
if not sid:
    r = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
             "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})
    sid = r.get("data", {}).get("id"); print("nouvelle demande", sid, r.get("detail", "")[:300])
r = call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
print(json.dumps(r, indent=1, ensure_ascii=False)[:6000])
b = call("GET", f"/v1/appStoreVersions/{v['id']}/build").get("data") or {}
print("build", b.get("attributes", {}).get("version"), "chiffrement:", b.get("attributes", {}).get("usesNonExemptEncryption"))
