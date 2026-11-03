"""FOLDLY : active la capacité Game Center sur l'identifiant de l'app (com.padelup.clapet) et affiche les capacités."""
import json, os, time, urllib.request, urllib.error
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
        return {"error": e.code, "detail": e.read().decode()[:1500]}
b = call("GET", "/v1/bundleIds?filter[identifier]=com.padelup.clapet")["data"]
bid = [x for x in b if x["attributes"]["identifier"] == "com.padelup.clapet"][0]["id"]
caps = call("GET", f"/v1/bundleIds/{bid}/bundleIdCapabilities").get("data", [])
print("avant :", [c["attributes"].get("capabilityType") for c in caps])
if not any(c["attributes"].get("capabilityType") == "GAME_CENTER" for c in caps):
    r = call("POST", "/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": "GAME_CENTER"},
             "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}})
    print("activation :", r.get("data", {}).get("attributes") or r)
caps = call("GET", f"/v1/bundleIds/{bid}/bundleIdCapabilities").get("data", [])
print("après :", [c["attributes"].get("capabilityType") for c in caps])
# Le build choisi pour la 1.0.3
app = call("GET", "/v1/apps?filter[bundleId]=com.padelup.clapet")["data"][0]
v = call("GET", f"/v1/apps/{app['id']}/appStoreVersions?filter[versionString]=1.0.3")["data"][0]
bd = call("GET", f"/v1/appStoreVersions/{v['id']}/build").get("data") or {}
print("build de la 1.0.3 :", bd.get("id"), bd.get("attributes", {}).get("version"))
