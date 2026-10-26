"""CLAPET : prépare App Store Connect (identifiants de l'app et du widget, fiche, groupe de testeurs).

Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY, BUNDLE_ID (celui d'Origamo, pour trouver le préfixe).
Écrit le rapport sur la sortie standard. N'invente rien : la fiche de l'app doit être créée à la main
sur App Store Connect (l'API d'Apple ne le permet pas).
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


base = os.environ["BUNDLE_ID"].rsplit(".", 1)[0]
app_id = base + ".clapet"
widget_id = app_id + ".widget"
print("BUNDLE_APP", app_id)
print("BUNDLE_WIDGET", widget_id)

existing = {b["attributes"]["identifier"]: b["id"] for b in call("GET", "/v1/bundleIds?limit=200&filter[platform]=IOS").get("data", [])}
for ident, name in [(app_id, "Clapet"), (widget_id, "Clapet Widget")]:
    if ident in existing:
        print("ok     identifiant déjà là :", ident)
        continue
    r = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": ident, "name": name, "platform": "IOS"}}})
    print("ok     identifiant créé :" if "data" in r else "ÉCHEC  identifiant :", ident, "" if "data" in r else r)

apps = call("GET", "/v1/apps?limit=200").get("data", [])
for a in apps:
    print("APP", a["id"], "|", a["attributes"]["name"], "|", a["attributes"]["bundleId"], "| sku", a["attributes"].get("sku"))
mine = [a for a in apps if a["attributes"]["bundleId"] == app_id]
if not mine:
    print("FICHE  à créer sur App Store Connect")
    sys.exit(0)
cid = mine[0]["id"]
print("FICHE  ok", cid)

# Un groupe de testeurs internes qui reçoit tous les builds
groups = call("GET", f"/v1/apps/{cid}/betaGroups?limit=50").get("data", [])
for g in groups:
    print("GROUPE", g["attributes"]["name"], "| interne" if g["attributes"].get("isInternalGroup") else "| externe")
if not any(g["attributes"].get("isInternalGroup") for g in groups):
    r = call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": {"name": "Clapet interne", "isInternalGroup": True,
                                                                                        "hasAccessToAllBuilds": True},
                                                 "relationships": {"app": {"data": {"type": "apps", "id": cid}}}}})
    print("ok     groupe interne créé" if "data" in r else "ÉCHEC  groupe interne " + json.dumps(r)[:400])
