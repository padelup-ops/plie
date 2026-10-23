"""Remplit la fiche App Store de la version en préparation à partir de tools/store_listing.json.

Ne soumet rien à Apple et ne crée aucun achat : nom, sous-titre, description, mots-clés,
texte promotionnel, catégories, notes pour la vérification et choix du build.
Lancé par .github/workflows/asc-fiche.yml.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
listing = json.load(open(os.path.join(os.path.dirname(__file__), "store_listing.json"), encoding="utf-8"))
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
problems = []


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        try:
            detail = "; ".join(f"{x.get('code')}: {x.get('detail')}" for x in json.loads(text).get("errors", []))
        except Exception:
            detail = text[:400]
        return {"error": e.code, "detail": detail}


def step(label, result):
    if isinstance(result, dict) and "error" in result:
        problems.append(label)
        print(f"ÉCHEC  {label} -> HTTP {result['error']} {result['detail']}")
    else:
        print(f"ok     {label}")
    return result


apps = call("GET", "/v1/apps?filter[bundleId]=" + os.environ["BUNDLE_ID"])
if not apps.get("data"):
    print("app introuvable", apps)
    sys.exit(1)
app_id = apps["data"][0]["id"]
print("APP_ID", app_id)

# 1. Nom et sous-titre (fiche « Informations sur l'app »)
infos = call("GET", f"/v1/apps/{app_id}/appInfos").get("data", [])
editable = [x for x in infos if (x["attributes"].get("appStoreState") or x["attributes"].get("state")) not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION")]
info = (editable or infos)[0]
info_locs = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations").get("data", [])}
for locale, v in listing["locales"].items():
    attrs = {"name": v["name"], "subtitle": v["subtitle"]}
    if locale in info_locs:
        step(f"nom et sous-titre {locale}", call("PATCH", f"/v1/appInfoLocalizations/{info_locs[locale]['id']}",
             {"data": {"type": "appInfoLocalizations", "id": info_locs[locale]["id"], "attributes": attrs}}))
    else:
        step(f"nom et sous-titre {locale} (nouvelle langue)", call("POST", "/v1/appInfoLocalizations",
             {"data": {"type": "appInfoLocalizations", "attributes": {"locale": locale, **attrs},
                       "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}}))

# 2. Catégories
c = listing["categories"]
step("catégories", call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
    "primaryCategory": {"data": {"type": "appCategories", "id": c["primary"]}},
    "primarySubcategoryOne": {"data": {"type": "appCategories", "id": c["sub1"]}},
    "primarySubcategoryTwo": {"data": {"type": "appCategories", "id": c["sub2"]}}}}}))

# 3. Version en préparation : description, mots-clés, texte promotionnel
versions = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10").get("data", [])
version = next((x for x in versions if x["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION"), None)
if not version:
    print("aucune version en préparation :", [(x["attributes"].get("versionString"), x["attributes"].get("appStoreState")) for x in versions])
    sys.exit(1)
vid = version["id"]
print("version", version["attributes"].get("versionString"), vid)
ver_locs = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", [])}
for locale, v in listing["locales"].items():
    attrs = {"description": v["description"], "keywords": v["keywords"], "promotionalText": v["promotionalText"]}
    if locale in ver_locs:
        step(f"description {locale}", call("PATCH", f"/v1/appStoreVersionLocalizations/{ver_locs[locale]['id']}",
             {"data": {"type": "appStoreVersionLocalizations", "id": ver_locs[locale]["id"], "attributes": attrs}}))
    else:
        step(f"description {locale} (nouvelle langue)", call("POST", "/v1/appStoreVersionLocalizations",
             {"data": {"type": "appStoreVersionLocalizations", "attributes": {"locale": locale, **attrs},
                       "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}))

# 4. Build
builds = call("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={listing['build']}&limit=5").get("data", [])
build = next((b for b in builds if b["attributes"].get("processingState") == "VALID"), None)
if build:
    step(f"build {listing['build']} choisi pour la version", call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
         {"data": {"type": "builds", "id": build["id"]}}))
else:
    problems.append("build")
    print(f"ÉCHEC  build {listing['build']} pas encore prêt :", [(b["attributes"].get("version"), b["attributes"].get("processingState")) for b in builds])

# 5. Notes pour la vérification
detail = call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
attrs = {"notes": listing["reviewNotes"], "demoAccountRequired": False}
if detail.get("data"):
    step("notes pour App Review", call("PATCH", f"/v1/appStoreReviewDetails/{detail['data']['id']}",
         {"data": {"type": "appStoreReviewDetails", "id": detail["data"]["id"], "attributes": attrs}}))
else:
    step("notes pour App Review", call("POST", "/v1/appStoreReviewDetails",
         {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
                   "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}))

# Relecture
print()
for l in call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations").get("data", []):
    a = l["attributes"]
    print("fiche", a.get("locale"), "|", a.get("name"), "|", a.get("subtitle"))
for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", []):
    a = l["attributes"]
    print("version", a.get("locale"), "| description", len(a.get("description") or ""), "car. | mots-clés", a.get("keywords"))
b = call("GET", f"/v1/appStoreVersions/{vid}/build").get("data")
print("build choisi :", b["attributes"].get("version") if b else "aucun")
print("\nTOUT EST À JOUR" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
