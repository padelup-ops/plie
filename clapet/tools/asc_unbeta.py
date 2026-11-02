"""FOLDLY : retire un build des groupes de testeurs externes (il reste chez les testeurs internes)."""
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
BUILD = os.environ["BUILD_NUMBER"].strip()
b = call("GET", f"/v1/builds?filter[app]={app['id']}&filter[version]={BUILD}&limit=5").get("data", [])
if not b:
    sys.exit("build introuvable")
bid = b[0]["id"]
d = call("GET", f"/v1/builds/{bid}/buildBetaDetail").get("data", {}).get("attributes", {})
print("build", BUILD, "| externe", d.get("externalBuildState"))
for g in call("GET", f"/v1/apps/{app['id']}/betaGroups?limit=50").get("data", []):
    if g["attributes"].get("isInternalGroup"):
        continue
    r = call("DELETE", f"/v1/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": bid}]})
    print("retiré du groupe", g["attributes"]["name"], "->", "ok" if "error" not in r else f"ÉCHEC {r['error']} {r['detail'][:300]}")
time.sleep(5)
d = call("GET", f"/v1/builds/{bid}/buildBetaDetail").get("data", {}).get("attributes", {})
print("après : externe", d.get("externalBuildState"))
for g in call("GET", f"/v1/apps/{app['id']}/betaGroups?limit=50").get("data", []):
    ids = [x["attributes"]["version"] for x in call("GET", f"/v1/betaGroups/{g['id']}/builds?limit=10").get("data", [])]
    print("groupe", g["attributes"]["name"], ": builds", ids)
