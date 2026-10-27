"""DUO FOLDS : invite un testeur externe (par e-mail) dans le groupe externe TestFlight."""
import json, os, sys, time, urllib.request, urllib.error
import jwt
API = "https://api.appstoreconnect.apple.com"
EMAIL = os.environ["TESTER_EMAIL"].strip()
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
groups = [g for g in call("GET", f"/v1/apps/{app['id']}/betaGroups?limit=50").get("data", []) if not g["attributes"].get("isInternalGroup")]
if not groups:
    print("aucun groupe externe"); sys.exit(1)
g = groups[0]
existing = call("GET", f"/v1/betaTesters?filter[email]={EMAIL}&limit=5").get("data", [])
if existing:
    r = call("POST", f"/v1/betaGroups/{g['id']}/relationships/betaTesters", {"data": [{"type": "betaTesters", "id": existing[0]["id"]}]})
    print("testeur déjà connu, ajouté au groupe" if "error" not in r else f"ajout au groupe : {r}")
    tid = existing[0]["id"]
else:
    r = call("POST", "/v1/betaTesters", {"data": {"type": "betaTesters", "attributes": {"email": EMAIL},
             "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": g["id"]}]}}}})
    if "error" in r:
        print("ÉCHEC", r); sys.exit(1)
    tid = r["data"]["id"]
    print(f"ok     {EMAIL} ajouté au groupe « {g['attributes']['name']} »")
# Envoie l'invitation TestFlight (si un build est disponible pour le groupe)
r = call("POST", "/v1/betaTesterInvitations", {"data": {"type": "betaTesterInvitations", "relationships": {
         "app": {"data": {"type": "apps", "id": app["id"]}}, "betaTester": {"data": {"type": "betaTesters", "id": tid}}}}})
print("ok     invitation envoyée" if "error" not in r else f"       invitation : {r.get('detail', '')[:300]}")
print("testeurs du groupe :", len(call("GET", f"/v1/betaGroups/{g['id']}/betaTesters?limit=200").get("data", [])))
