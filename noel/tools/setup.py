"""ALLÔ PÈRE NOËL : prépare App Store Connect (identifiant de l'app, groupe de test interne, testeurs internes).

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


APP = "com.padelup.allonoel"
existing = {b["attributes"]["identifier"]: b["id"] for b in call("GET", "/v1/bundleIds?limit=200&filter[platform]=IOS").get("data", [])}
for ident, label in ((APP, "Allo Pere Noel"),):
    if ident in existing:
        print("ok     identifiant déjà là :", ident)
    else:
        r = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": ident, "name": label, "platform": "IOS"}}})
        print("ok     identifiant créé :" if "data" in r else "ÉCHEC  identifiant :", ident, "" if "data" in r else r)

apps = call("GET", "/v1/apps?limit=200").get("data", [])
for a in apps:
    if "no" in a["attributes"]["name"].lower() and ("père" in a["attributes"]["name"].lower() or "pere" in a["attributes"]["name"].lower()):
        print("APP   ", a["id"], a["attributes"]["bundleId"], "«" + a["attributes"]["name"] + "»", a["attributes"].get("sku"))
mine = [a for a in apps if a["attributes"]["bundleId"] == APP]
if not mine:
    print("FICHE  à créer sur App Store Connect (nom Allô Père Noël, identifiant " + APP + ")")
    sys.exit(0)
cid = mine[0]["id"]
print("FICHE  ok", cid)

groups = call("GET", f"/v1/apps/{cid}/betaGroups?limit=50").get("data", [])
if not any(g["attributes"].get("isInternalGroup") for g in groups):
    r = call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": {"name": "Allô Père Noël interne", "isInternalGroup": True,
                                                                                        "hasAccessToAllBuilds": True},
                                                 "relationships": {"app": {"data": {"type": "apps", "id": cid}}}}})
    print("ok     groupe interne créé" if "data" in r else "ÉCHEC  groupe interne " + json.dumps(r)[:400])

# Les comptes du propriétaire (titulaire et administrateurs d'App Store Connect) testent chaque build sur TestFlight.
# Aucune adresse n'est écrite ici ni affichée dans le journal (le dépôt est public).
internal = [g for g in call("GET", f"/v1/apps/{cid}/betaGroups?limit=50").get("data", []) if g["attributes"].get("isInternalGroup")]
if internal:
    gid = internal[0]["id"]
    in_group = {t["attributes"].get("email", "").lower() for t in call("GET", f"/v1/betaGroups/{gid}/betaTesters?limit=200").get("data", [])}
    owners = [u for u in call("GET", "/v1/users?limit=50").get("data", [])
              if {"ACCOUNT_HOLDER", "ADMIN"} & set(u["attributes"].get("roles") or [])]
    for n, u in enumerate(owners, 1):
        email = (u["attributes"].get("username") or "").lower()
        if not email or email in in_group:
            print(f"ok     testeur interne {n} déjà là")
            continue
        found = call("GET", f"/v1/betaTesters?filter[email]={email}&limit=5").get("data", [])
        if found:
            r = call("POST", f"/v1/betaGroups/{gid}/relationships/betaTesters", {"data": [{"type": "betaTesters", "id": found[0]["id"]}]})
        else:
            r = call("POST", "/v1/betaTesters", {"data": {"type": "betaTesters", "attributes": {
                "email": email, "firstName": u["attributes"].get("firstName"), "lastName": u["attributes"].get("lastName")},
                "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": gid}]}}}})
        if isinstance(r, dict) and "error" in r:
            print(f"ÉCHEC  testeur interne {n} ({r.get('error')}) " + r.get("detail", "")[:400].replace(email, "<adresse>"))
        else:
            print(f"ok     testeur interne {n} ajouté")
