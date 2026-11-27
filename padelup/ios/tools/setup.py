"""PADELUP NEO (iOS) : prépare App Store Connect (identifiant, fiche, groupe de test interne, testeurs internes).

Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY (et PADELUP_BUNDLE pour imposer un autre identifiant).
App séparée de « PADELUP (FR) » (com.padelup.padelup-new), qui n'est jamais touchée ici.
Écrit « BUNDLE=<identifiant> » pour le workflow TestFlight. Si l'API d'Apple refuse de créer la fiche,
elle se crée à la main : App Store Connect > Apps > + > Nouvelle app (nom PadelUp Neo, identifiant ci-dessous).
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


apps = call("GET", "/v1/apps?limit=200").get("data", [])
for a in apps:
    if "padel" in a["attributes"]["name"].lower() or "padel" in a["attributes"]["bundleId"].lower():
        print("APP   ", a["id"], a["attributes"]["bundleId"], "«" + a["attributes"]["name"] + "»", a["attributes"].get("sku"))

existing = {b["attributes"]["identifier"]: b["id"] for b in call("GET", "/v1/bundleIds?limit=200&filter[platform]=IOS").get("data", [])}
for ident in sorted(existing):
    if "padel" in ident.split(".", 2)[-1] or ident.endswith(".app"):
        print("IDENT ", ident)

wanted = os.environ.get("PADELUP_BUNDLE", "").strip() or "com.padelup.neo"
if wanted == "com.padelup.padelup-new":
    sys.exit("Refus : l'app PadelUp Neo ne doit pas partir dans la fiche PADELUP (FR).")

if wanted not in existing:
    r = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": wanted, "name": "PadelUp Neo", "platform": "IOS"}}})
    print("ok     identifiant créé :" if "data" in r else "ÉCHEC  identifiant :", wanted, "" if "data" in r else json.dumps(r)[:600])
    existing = {b["attributes"]["identifier"]: b["id"] for b in call("GET", "/v1/bundleIds?limit=200&filter[platform]=IOS").get("data", [])}
else:
    print("ok     identifiant déjà là :", wanted)
print("BUNDLE=" + wanted)

# Capacité « Se connecter avec Apple » sur l'identifiant (l'app la propose pour le compte PadelUp).
if wanted in existing:
    caps = call("GET", f"/v1/bundleIds/{existing[wanted]}/bundleIdCapabilities").get("data", [])
    if not any(c["attributes"].get("capabilityType") == "APPLE_ID_AUTH" for c in caps):
        r = call("POST", "/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities",
                 "attributes": {"capabilityType": "APPLE_ID_AUTH", "settings": [{"key": "APPLE_ID_AUTH_APP_CONSENT",
                                "options": [{"key": "PRIMARY_APP_CONSENT"}]}]},
                 "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": existing[wanted]}}}}})
        print("ok     Se connecter avec Apple activé" if "data" in r else "ÉCHEC  Se connecter avec Apple " + json.dumps(r)[:300])

if not any(a["attributes"]["bundleId"] == wanted for a in apps) and wanted in existing:
    # Essai de création de la fiche par l'API (Apple ne l'a longtemps pas permis : dans ce cas, création à la main).
    r = call("POST", "/v1/apps", {"data": {"type": "apps", "attributes": {
        "name": "PadelUp Neo", "primaryLocale": "fr-FR", "sku": "padelup-neo", "bundleId": wanted},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": existing[wanted]}}}}})
    if "data" in r:
        print("ok     fiche créée par l'API :", r["data"]["id"])
        apps = call("GET", "/v1/apps?limit=200").get("data", [])
    else:
        print("INFO   création de fiche par l'API refusée (" + str(r.get("error")) + ")")

mine = [a for a in apps if a["attributes"]["bundleId"] == wanted]
if not mine:
    print("FICHE  à créer sur App Store Connect (Nouvelle app, nom PadelUp Neo, langue Français, identifiant " + wanted + ", SKU padelup-neo)")
    sys.exit(0)
cid = mine[0]["id"]
print("FICHE  ok", cid)

groups = call("GET", f"/v1/apps/{cid}/betaGroups?limit=50").get("data", [])
if not any(g["attributes"].get("isInternalGroup") for g in groups):
    r = call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": {"name": "PadelUp Neo interne", "isInternalGroup": True,
                                                                                        "hasAccessToAllBuilds": True},
                                                 "relationships": {"app": {"data": {"type": "apps", "id": cid}}}}})
    print("ok     groupe interne créé" if "data" in r else "ÉCHEC  groupe interne " + json.dumps(r)[:400])

# Les comptes du propriétaire (titulaire et administrateurs) testent chaque build. Aucune adresse n'est affichée (dépôt public).
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

for b in call("GET", f"/v1/builds?filter[app]={cid}&sort=-uploadedDate&limit=5").get("data", []):
    a = b["attributes"]
    print("BUILD ", a.get("version"), a.get("processingState"), (a.get("uploadedDate") or "")[:16])
