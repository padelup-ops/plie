"""FOLDBOARD : prépare App Store Connect (identifiants de l'app et du clavier, groupe de testeurs).

Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY.
La fiche de l'app doit être créée à la main sur App Store Connect (l'API d'Apple ne le permet pas).
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
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


APP = "com.padelup.foldboard"
existing = {b["attributes"]["identifier"]: b["id"] for b in call("GET", "/v1/bundleIds?limit=200&filter[platform]=IOS").get("data", [])}
for ident, name in [(APP, "Foldboard"), (APP + ".keyboard", "Foldboard Keyboard")]:
    if ident in existing:
        print("ok     identifiant déjà là :", ident)
        continue
    r = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": ident, "name": name, "platform": "IOS"}}})
    print("ok     identifiant créé :" if "data" in r else "ÉCHEC  identifiant :", ident, "" if "data" in r else r)

apps = call("GET", "/v1/apps?limit=200").get("data", [])
mine = [a for a in apps if a["attributes"]["bundleId"] == APP]
if not mine:
    print("FICHE  à créer sur App Store Connect (nom Foldboard, identifiant " + APP + ")")
    sys.exit(0)
cid = mine[0]["id"]
print("FICHE  ok", cid)

groups = call("GET", f"/v1/apps/{cid}/betaGroups?limit=50").get("data", [])
for g in groups:
    print("GROUPE", g["attributes"]["name"], "| interne" if g["attributes"].get("isInternalGroup") else "| externe")
if not any(g["attributes"].get("isInternalGroup") for g in groups):
    r = call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": {"name": "Foldboard interne", "isInternalGroup": True,
                                                                                        "hasAccessToAllBuilds": True},
                                                 "relationships": {"app": {"data": {"type": "apps", "id": cid}}}}})
    print("ok     groupe interne créé" if "data" in r else "ÉCHEC  groupe interne " + json.dumps(r)[:400])

# Les utilisateurs du compte App Store Connect deviennent testeurs internes (TestFlight).
internal = [g for g in call("GET", f"/v1/apps/{cid}/betaGroups?limit=50").get("data", []) if g["attributes"].get("isInternalGroup")]
if internal:
    gid = internal[0]["id"]
    in_group = {t["attributes"].get("email", "").lower() for t in call("GET", f"/v1/betaGroups/{gid}/betaTesters?limit=200").get("data", [])}
    for u in call("GET", "/v1/users?limit=50").get("data", []):
        email = (u["attributes"].get("username") or "").strip()
        if not email or email.lower() in in_group:
            print("ok     testeur interne déjà là :", email)
            continue
        found = call("GET", f"/v1/betaTesters?filter[email]={email}&limit=5").get("data", [])
        if found:
            r = call("POST", f"/v1/betaGroups/{gid}/relationships/betaTesters", {"data": [{"type": "betaTesters", "id": found[0]["id"]}]})
        else:
            r = call("POST", "/v1/betaTesters", {"data": {"type": "betaTesters", "attributes": {
                "email": email, "firstName": u["attributes"].get("firstName"), "lastName": u["attributes"].get("lastName")},
                "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": gid}]}}}})
        print(("ÉCHEC  testeur " + email + " " + json.dumps(r)[:300]) if isinstance(r, dict) and "error" in r else "ok     testeur interne ajouté : " + email)
