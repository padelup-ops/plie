"""FOLDLY : lecture seule d'une route App Store Connect (GET), pour diagnostiquer."""
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
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:600]}
app = call("GET", "/v1/apps?filter[bundleId]=com.padelup.clapet")["data"][0]
for path in os.environ["ASC_PATHS"].split():
    path = path.replace("{app}", app["id"])
    r = call("GET", path)
    print("=====", path)
    for d in (r.get("data") if isinstance(r.get("data"), list) else [r.get("data") or r]):
        if isinstance(d, dict):
            print(d.get("type"), d.get("id"), json.dumps(d.get("attributes", d), ensure_ascii=False)[:600])
    for d in r.get("included", []) or []:
        print("inclus", d.get("type"), d.get("id"), json.dumps(d.get("attributes", {}), ensure_ascii=False)[:1500])
