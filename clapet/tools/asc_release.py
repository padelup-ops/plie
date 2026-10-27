"""DUO FOLDS : prépare la version 1.0 pour l'App Store, et l'envoie à la vérification d'Apple si SUBMIT=1.

Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY, ORIGAMO_BUNDLE_ID (pour reprendre les coordonnées),
RELEASE_BUILD (numéro du build), SITE_URL (pages d'assistance et de confidentialité), SUBMIT (1 = envoyer).
Fait : catégories, classification par âge, droits sur le contenu, copyright, sortie automatique après accord,
disponibilité dans tous les pays, coordonnées et notes pour la vérification, URL, captures, build.
"""
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.padelup.clapet"
HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.environ.get("RELEASE_BUILD", "").strip()
SITE = os.environ.get("SITE_URL", "").strip().rstrip("/")
SUBMIT = os.environ.get("SUBMIT") == "1"
SHOT_TYPE = os.environ.get("SHOT_TYPE", "APP_IPHONE_67")
LOCALES = {"en-US": "en", "fr-FR": "fr"}
REVIEW_NOTES = (
    "Duo Folds counts how many times the iPhone Duo is closed and opened, so people can keep that habit under control.\n\n"
    "On an iPhone Duo: keep Duo Folds on screen and fold the device. The app reads the hinge (SwiftUI onHingeChange) and "
    "the count goes up; the ring turns orange near the daily limit and red above it.\n"
    "On a device without a hinge: tap the Duo drawing on the main screen to add a fold.\n\n"
    "Optional automatic counting: the app's Shortcuts action \"Count a fold\" can be added to the personal automation "
    "\"When iPhone is Closed\" (Shortcuts > Automation). The app shows these steps under \"Count even when the app is closed\".\n\n"
    "Paid app: everything is included, there is no in-app purchase, no account, no ads and no data collection. "
    "Numbers stay on the device (shared with the widgets through the keychain).")

token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
problems = []


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path if path.startswith("/") else path, data=data, method=method,
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
            detail = text[:600]
        return {"error": e.code, "detail": detail}


def step(label, result, tolerate=()):
    if isinstance(result, dict) and "error" in result:
        if any(t in result["detail"] for t in tolerate):
            print(f"ok     {label} (déjà fait)")
            return result
        problems.append(label)
        print(f"ÉCHEC  {label} -> HTTP {result['error']} {result['detail']}")
    else:
        print(f"ok     {label}")
    return result


def get_all(path):
    out, url = [], path
    while url:
        page = call("GET", url)
        if "error" in page:
            return out
        out += page.get("data", [])
        url = page.get("links", {}).get("next")
    return out


app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}").get("data", [])
if not app:
    print("app introuvable")
    sys.exit(1)
app_id = app[0]["id"]
print("APP", app_id, app[0]["attributes"]["name"])

# ---------------------------------------------------------------- fiche de l'app
infos = call("GET", f"/v1/apps/{app_id}/appInfos").get("data", [])
info = next((i for i in infos if i["attributes"].get("appStoreState") not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION")), infos[0])
info_id = info["id"]
step("catégories (Santé et forme, Utilitaires)", call("PATCH", f"/v1/appInfos/{info_id}", {"data": {"type": "appInfos", "id": info_id, "relationships": {
    "primaryCategory": {"data": {"type": "appCategories", "id": "HEALTH_AND_FITNESS"}},
    "secondaryCategory": {"data": {"type": "appCategories", "id": "UTILITIES"}}}}}))

age = call("GET", f"/v1/appInfos/{info_id}/ageRatingDeclaration").get("data")
if age:
    BOOLS = {"advertising", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat", "parentalControls",
             "ageAssurance", "unrestrictedWebAccess", "userGeneratedContent", "socialMedia", "socialMediaAgeRestricted", "seventeenPlus"}
    LEVELS = {"alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
              "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity",
              "horrorOrFearThemes", "matureOrSuggestiveThemes", "violenceCartoonOrFantasy",
              "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic"}
    attrs = {}
    for k in age["attributes"]:
        if k in BOOLS:
            attrs[k] = False
        elif k in LEVELS:
            attrs[k] = "NONE"
    r = step("classification par âge (aucun contenu sensible)", call("PATCH", f"/v1/ageRatingDeclarations/{age['id']}",
             {"data": {"type": "ageRatingDeclarations", "id": age["id"], "attributes": attrs}}))
    if "error" in r:
        print("       attributs envoyés :", json.dumps(attrs)[:800])

step("droits sur le contenu (aucun contenu de tiers)", call("PATCH", f"/v1/apps/{app_id}", {"data": {"type": "apps", "id": app_id,
     "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}}))

# ---------------------------------------------------------------- disponibilité
avail = call("GET", f"/v1/apps/{app_id}/appAvailabilityV2")
if avail.get("data"):
    print("ok     disponibilité déjà définie")
else:
    territories = [t["id"] for t in get_all("/v1/territories?limit=200")]
    step(f"disponibilité ({len(territories)} pays)", call("POST", "/v2/appAvailabilities", {
        "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                 "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                                   "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": f"${{{t}}}"} for t in territories]}}},
        "included": [{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": True},
                      "relationships": {"territory": {"data": {"type": "territories", "id": t}}}} for t in territories]}))

# ---------------------------------------------------------------- version 1.0
versions = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10").get("data", [])
version = next((v for v in versions if v["attributes"].get("appStoreState") in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")), None)
if not version:
    print("aucune version modifiable :", [(v["attributes"].get("versionString"), v["attributes"].get("appStoreState")) for v in versions])
    sys.exit(1)
vid = version["id"]
print("VERSION", version["attributes"].get("versionString"), version["attributes"].get("appStoreState"))

origamo = call("GET", "/v1/apps?filter[bundleId]=" + os.environ.get("ORIGAMO_BUNDLE_ID", "")).get("data", [])
owner = "PadelUp"
if origamo:
    for v in call("GET", f"/v1/apps/{origamo[0]['id']}/appStoreVersions?limit=5").get("data", []):
        c = v["attributes"].get("copyright")
        if c:
            owner = c.split(" ", 1)[1] if c[:4].isdigit() and " " in c else c
            break
step(f"copyright « 2026 {owner} » et sortie dès l'accord d'Apple", call("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {
    "type": "appStoreVersions", "id": vid, "attributes": {"copyright": f"2026 {owner}", "releaseType": "AFTER_APPROVAL"}}}))

# Coordonnées pour la vérification : celles déjà données pour la bêta
contact = call("GET", f"/v1/apps/{app_id}/betaAppReviewDetail").get("data", {}).get("attributes", {})
attrs = {k: contact.get(k) for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail") if contact.get(k)}
attrs.update({"notes": REVIEW_NOTES, "demoAccountRequired": False})
detail = call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
if detail:
    step("coordonnées et notes pour la vérification", call("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}",
         {"data": {"type": "appStoreReviewDetails", "id": detail["id"], "attributes": attrs}}))
else:
    step("coordonnées et notes pour la vérification", call("POST", "/v1/appStoreReviewDetails", {"data": {
        "type": "appStoreReviewDetails", "attributes": attrs,
        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}))

# URL d'assistance et de confidentialité
if SITE:
    for path in ("fr/", "en/", "fr/privacy.html", "en/privacy.html"):
        try:
            code = urllib.request.urlopen(f"{SITE}/{path}", timeout=20).getcode()
        except Exception as e:
            code = str(e)
        print(f"       {SITE}/{path} -> {code}")
        if code != 200:
            problems.append(f"page {path}")
    for l in call("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations").get("data", []):
        lang = LOCALES.get(l["attributes"]["locale"], "en")
        step(f"confidentialité {l['attributes']['locale']}", call("PATCH", f"/v1/appInfoLocalizations/{l['id']}", {"data": {
            "type": "appInfoLocalizations", "id": l["id"], "attributes": {"privacyPolicyUrl": f"{SITE}/{lang}/privacy.html"}}}))
    for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", []):
        lang = LOCALES.get(l["attributes"]["locale"], "en")
        step(f"assistance {l['attributes']['locale']}", call("PATCH", f"/v1/appStoreVersionLocalizations/{l['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": l["id"], "attributes": {"supportUrl": f"{SITE}/{lang}/", "marketingUrl": f"{SITE}/{lang}/"}}}))
else:
    print("       pas encore de site (SITE_URL) : assistance et confidentialité à faire")

# Captures d'écran
for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", []):
    lang = LOCALES.get(l["attributes"]["locale"])
    if not lang:
        continue
    files = [os.path.join(HERE, "store", f"{lang}-{i}.png") for i in range(1, 6)]
    files = [f for f in files if os.path.exists(f)]
    sets = call("GET", f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets").get("data", [])
    s = next((x for x in sets if x["attributes"].get("screenshotDisplayType") == SHOT_TYPE), None)
    if not s:
        r = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": SHOT_TYPE},
                 "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": l["id"]}}}}})
        if "error" in r:
            step(f"jeu de captures {lang}", r)
            continue
        s = r["data"]
    for old in call("GET", f"/v1/appScreenshotSets/{s['id']}/appScreenshots").get("data", []):
        call("DELETE", f"/v1/appScreenshots/{old['id']}")
    ok_count = 0
    for f in files:
        data = open(f, "rb").read()
        r = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
                 "attributes": {"fileName": os.path.basename(f), "fileSize": len(data)},
                 "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": s["id"]}}}}})
        if "error" in r:
            step(f"capture {os.path.basename(f)}", r)
            continue
        sid = r["data"]["id"]
        for op in r["data"]["attributes"].get("uploadOperations", []):
            req = urllib.request.Request(op["url"], data=data[op["offset"]:op["offset"] + op["length"]], method=op["method"],
                                         headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
            urllib.request.urlopen(req).read()
        r = call("PATCH", f"/v1/appScreenshots/{sid}", {"data": {"type": "appScreenshots", "id": sid,
                 "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        if "error" in r:
            step(f"capture {os.path.basename(f)}", r)
        else:
            ok_count += 1
    print(f"ok     {ok_count} capture(s) {l['attributes']['locale']} ({SHOT_TYPE})")

# Build
if BUILD:
    builds = call("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={BUILD}&limit=5").get("data", [])
    build = next((b for b in builds if b["attributes"].get("processingState") == "VALID"), None)
    if build:
        step(f"build {BUILD} choisi pour la version 1.0", call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
             {"data": {"type": "builds", "id": build["id"]}}))
    else:
        problems.append("build")
        print(f"ÉCHEC  build {BUILD} pas prêt")

# ---------------------------------------------------------------- envoi à Apple
if SUBMIT:
    if problems:
        print("\nPAS ENVOYÉ : il reste des points à régler :", ", ".join(problems))
        sys.exit(1)
    time.sleep(20)   # le temps que les captures soient traitées
    open_subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW").get("data", [])
    if open_subs:
        sub_id = open_subs[0]["id"]
    else:
        r = step("demande de vérification créée", call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions",
                 "attributes": {"platform": "IOS"}, "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
        if "error" in r:
            sys.exit(1)
        sub_id = r["data"]["id"]
    step("version 1.0 ajoutée à la demande", call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
         "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                           "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}), tolerate=("already",))
    r = step("ENVOI À LA VÉRIFICATION D'APPLE", call("PATCH", f"/v1/reviewSubmissions/{sub_id}", {"data": {
         "type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}}))
    v = call("GET", f"/v1/appStoreVersions/{vid}").get("data", {}).get("attributes", {})
    print("état de la version :", v.get("appStoreState"))

print("\nPRÊT" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
