"""TWINFOLD : prépare App Store Connect (identifiant de l'app, groupe de test interne).

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
        return {"error": e.code, "detail": e.read().decode()[:2000]}


APP = "com.padelup.twinfold"
existing = {b["attributes"]["identifier"]: b["id"] for b in call("GET", "/v1/bundleIds?limit=200&filter[platform]=IOS").get("data", [])}
if APP in existing:
    print("ok     identifiant déjà là :", APP)
else:
    r = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": APP, "name": "Twinfold", "platform": "IOS"}}})
    print("ok     identifiant créé :" if "data" in r else "ÉCHEC  identifiant :", APP, "" if "data" in r else r)

apps = call("GET", "/v1/apps?limit=200").get("data", [])
mine = [a for a in apps if a["attributes"]["bundleId"] == APP]
if not mine:
    print("FICHE  à créer sur App Store Connect (nom Twinfold, identifiant " + APP + ")")
    sys.exit(0)
cid = mine[0]["id"]
print("FICHE  ok", cid)

groups = call("GET", f"/v1/apps/{cid}/betaGroups?limit=50").get("data", [])
if not any(g["attributes"].get("isInternalGroup") for g in groups):
    r = call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": {"name": "Twinfold interne", "isInternalGroup": True,
                                                                                        "hasAccessToAllBuilds": True},
                                                 "relationships": {"app": {"data": {"type": "apps", "id": cid}}}}})
    print("ok     groupe interne créé" if "data" in r else "ÉCHEC  groupe interne " + json.dumps(r)[:400])
