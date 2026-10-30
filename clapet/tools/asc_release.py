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
BUNDLE = os.environ.get("APP_BUNDLE") or "com.padelup.clapet"
HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.environ.get("RELEASE_BUILD", "").strip()
SITE = os.environ.get("SITE_URL", "").strip().rstrip("/")
SUBMIT = os.environ.get("SUBMIT") == "1"
SHOT_TYPE = os.environ.get("SHOT_TYPE", "APP_IPHONE_67")
SHOTS_DIR = os.environ.get("SHOTS_DIR") or os.path.join(HERE, "store")
CATEGORIES = (os.environ.get("CATEGORIES") or "HEALTH_AND_FITNESS,UTILITIES").split(",")
PRICE_EUR = os.environ.get("APP_PRICE", "").strip()
LOCALES = {"en-US": "en", "fr-FR": "fr"}
REVIEW_NOTES = (
    "Foldly counts how many times a foldable iPhone (iPhone Duo) is closed and opened, so people can keep that habit under control.\n\n"
    "On an iPhone Duo: keep Foldly on screen and fold the device. The app reads the hinge (SwiftUI onHingeChange) and "
    "the count goes up; the ring turns orange near the daily limit and red above it.\n"
    "On a device without a hinge (like an iPad): tap the hinge drawing on the main screen to add a fold.\n\n"
    "Optional automatic counting: the app's Shortcuts action \"Count a fold\" can be added to the personal automation "
    "\"When iPhone is Closed\" (Shortcuts > Automation). The app shows these steps under \"Count even when the app is closed\".\n\n"
    "Following Guideline 5.2.5, the app was renamed from DUO FOLDS to Foldly: the Apple product name is no longer used "
    "in the app name, the name shown on the device or the metadata.\n\n"
    "Paid app: everything is included, there is no in-app purchase, no account, no ads and no data collection. "
    "Numbers stay on the device (shared with the widgets through the keychain).")

if os.environ.get("LISTING_JSON"):
    REVIEW_NOTES = json.load(open(os.environ["LISTING_JSON"], encoding="utf-8"))["reviewNotes"]

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
            errs = json.loads(text).get("errors", [])
            detail = "; ".join(f"{x.get('code')}: {x.get('detail')}" for x in errs)
            for x in errs:
                assoc = (x.get("meta") or {}).get("associatedErrors") or {}
                for where, items in assoc.items():
                    for it in items:
                        detail += f"\n         -> {it.get('code')}: {it.get('detail') or it.get('title')}"
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

# ---------------------------------------------------------------- retrait de la vérification (WITHDRAW=1)
if os.environ.get("WITHDRAW") == "1":
    subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&limit=20").get("data", [])
    open_states = ("WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES", "READY_FOR_REVIEW")
    found = False
    for sub in subs:
        state = sub["attributes"].get("state")
        print("demande de vérification", sub["id"], state)
        if state in open_states:
            found = True
            step(f"demande {sub['id']} retirée de la vérification",
                 call("PATCH", f"/v1/reviewSubmissions/{sub['id']}",
                      {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"canceled": True}}}))
    if not found:
        print("aucune demande en cours à retirer")
    time.sleep(8)
    for v in call("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=5").get("data", []):
        print("VERSION", v["attributes"].get("versionString"), v["attributes"].get("appStoreState"))
    sys.exit(1 if problems else 0)

# ---------------------------------------------------------------- fiche de l'app
infos = call("GET", f"/v1/apps/{app_id}/appInfos").get("data", [])
info = next((i for i in infos if i["attributes"].get("appStoreState") not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION")), infos[0])
info_id = info["id"]
if CATEGORIES[0] == "GAMES":
    rel = {"primaryCategory": {"data": {"type": "appCategories", "id": "GAMES"}}}
    for key, cid in zip(("primarySubcategoryOne", "primarySubcategoryTwo"), CATEGORIES[1:3]):
        rel[key] = {"data": {"type": "appCategories", "id": cid}}
else:
    rel = {"primaryCategory": {"data": {"type": "appCategories", "id": CATEGORIES[0]}}}
    if len(CATEGORIES) > 1:
        rel["secondaryCategory"] = {"data": {"type": "appCategories", "id": CATEGORIES[1]}}
step("catégories " + " / ".join(CATEGORIES), call("PATCH", f"/v1/appInfos/{info_id}", {"data": {"type": "appInfos", "id": info_id, "relationships": rel}}))

# Prix de l'app (base France)
if PRICE_EUR:
    current = call("GET", f"/v1/apps/{app_id}/appPriceSchedule?include=manualPrices")
    have = [x for x in current.get("included", []) if x["type"] == "appPrices"]
    point, url = None, f"/v1/apps/{app_id}/appPricePoints?filter[territory]=FRA&limit=200"
    while url and not point:
        page = call("GET", url)
        point = next((p for p in page.get("data", []) if p["attributes"].get("customerPrice") == PRICE_EUR), None)
        url = page.get("links", {}).get("next")
    if not point:
        problems.append("prix")
        print("ÉCHEC  aucun palier à", PRICE_EUR, "€")
    elif any(x.get("relationships", {}).get("appPricePoint", {}).get("data", {}).get("id") == point["id"] for x in have):
        print(f"ok     prix {PRICE_EUR} € (déjà en place)")
    else:
        step(f"prix {PRICE_EUR} € (base France)", call("POST", "/v1/appPriceSchedules", {
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "FRA"}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${prix}"}]}}},
            "included": [{"type": "appPrices", "id": "${prix}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": point["id"]}}}}]}))

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

# ---------------------------------------------------------------- nouvelle version (NEW_VERSION=1.0.1…)
# Les nouveautés affichées sur l'App Store, par version.
RELEASE_NOTES = {
    "1.0.1": {
        "en-US": "• Foldly is now free. Foldly+ is a one-time purchase, and it's already yours if you bought Foldly before.\n"
                 "• All about your numbers: each day is compared with your own average. The daily limit is optional.\n"
                 "• NEW Weekly recap: your week compared with the week before, your busiest and calmest days, and a card to share.\n"
                 "• NEW Desk mode: stand your phone in an L to see the time and your numbers, big.\n"
                 "• NEW Minimal theme, a new Open & closed widget, and widgets that look great in StandBy.",
        "fr-FR": "• Foldly est maintenant gratuit. Foldly+ est un achat unique, et il est déjà à toi si tu avais acheté Foldly.\n"
                 "• Tout pour tes chiffres : chaque journée est comparée à ta propre moyenne. La limite du jour est facultative.\n"
                 "• NOUVEAU Bilan de la semaine : ta semaine comparée à la précédente, ton jour le plus chargé et le plus calme, et une image à partager.\n"
                 "• NOUVEAU Mode bureau : pose ton téléphone plié en L pour voir l'heure et tes chiffres en grand.\n"
                 "• NOUVEAU thème Épuré, un nouveau widget Ouvert / fermé, et des widgets qui s'affichent en grand en mode veille.",
    },
}
NEW_VERSION = os.environ.get("NEW_VERSION", "").strip()
if NEW_VERSION:
    existing = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&filter[versionString]={NEW_VERSION}").get("data", [])
    if existing:
        print(f"ok     version {NEW_VERSION} déjà créée ({existing[0]['attributes'].get('appStoreState')})")
        new_vid = existing[0]["id"]
    else:
        r = step(f"version {NEW_VERSION} créée", call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions",
                 "attributes": {"platform": "IOS", "versionString": NEW_VERSION, "releaseType": "AFTER_APPROVAL"},
                 "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
        new_vid = r.get("data", {}).get("id")
    notes = RELEASE_NOTES.get(NEW_VERSION, {})
    if new_vid and notes:
        for l in call("GET", f"/v1/appStoreVersions/{new_vid}/appStoreVersionLocalizations").get("data", []):
            text = notes.get(l["attributes"]["locale"])
            if text:
                step(f"nouveautés {l['attributes']['locale']}", call("PATCH", f"/v1/appStoreVersionLocalizations/{l['id']}", {"data": {
                     "type": "appStoreVersionLocalizations", "id": l["id"], "attributes": {"whatsNew": text}}}))

# ---------------------------------------------------------------- version 1.0
versions = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10").get("data", [])
version = next((v for v in versions if v["attributes"].get("appStoreState") in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")), None)
if not version:
    print("aucune version modifiable :", [(v["attributes"].get("versionString"), v["attributes"].get("appStoreState")) for v in versions])
    ready = next((v for v in versions if v["attributes"].get("appStoreState") == "READY_FOR_REVIEW"), None)
    if ready and SUBMIT:
        # La version est déjà dans une demande de vérification pas encore envoyée : on l'envoie.
        subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW,UNRESOLVED_ISSUES").get("data", [])
        print("demandes ouvertes :", [(x["id"], x["attributes"].get("state")) for x in subs])
        for sub in subs:
            items = call("GET", f"/v1/reviewSubmissions/{sub['id']}/items").get("data", [])
            print("  éléments :", len(items))
            if items:
                step("ENVOI À LA VÉRIFICATION D'APPLE", call("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {
                     "type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}}))
                break
        v = call("GET", f"/v1/appStoreVersions/{ready['id']}").get("data", {}).get("attributes", {})
        print("état de la version :", v.get("appStoreState"))
        print("\nENVOYÉ" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
    sys.exit(0 if not problems else 1)
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

# Captures d'écran : iPhone 6,7" et iPhone Duo (le badge « conçu pour l'iPhone Duo » demande ces dernières)
SHOT_SETS = [(SHOT_TYPE, ""), ("APP_IPHONE_DUO", "duo-")]
for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", []):
    lang = LOCALES.get(l["attributes"]["locale"])
    if not lang:
        continue
    sets = call("GET", f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets").get("data", [])
    for shot_type, prefix in SHOT_SETS:
        files = [os.path.join(SHOTS_DIR, f"{prefix}{lang}-{i}.png") for i in range(1, 11)]
        files = [f for f in files if os.path.exists(f)]
        if not files:
            continue
        s_ = next((x for x in sets if x["attributes"].get("screenshotDisplayType") == shot_type), None)
        if not s_:
            r = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": shot_type},
                     "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": l["id"]}}}}})
            if "error" in r:
                step(f"jeu de captures {shot_type} {lang}", r)
                continue
            s_ = r["data"]
        existing_shots = call("GET", f"/v1/appScreenshotSets/{s_['id']}/appScreenshots").get("data", [])
        wanted = sorted(hashlib.md5(open(f, "rb").read()).hexdigest() for f in files)
        have = sorted((x["attributes"].get("sourceFileChecksum") or "") for x in existing_shots)
        if wanted == have:
            print(f"ok     {len(files)} capture(s) {l['attributes']['locale']} ({shot_type}) déjà à jour")
            continue
        for old in existing_shots:
            call("DELETE", f"/v1/appScreenshots/{old['id']}")
        ok_count = 0
        for f in files:
            data = open(f, "rb").read()
            r = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
                     "attributes": {"fileName": os.path.basename(f), "fileSize": len(data)},
                     "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": s_["id"]}}}}})
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
        print(f"ok     {ok_count} capture(s) {l['attributes']['locale']} ({shot_type})")

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

# Les vidéos d'en-tête et de recherche (iOS 27), déjà dans la bibliothèque : placées sur cette version, par langue.
ASSETS_DIR = os.environ.get("ASSETS_DIR", "")
if ASSETS_DIR and os.path.isdir(ASSETS_DIR):
    import subprocess
    r = subprocess.run([sys.executable, os.path.join(HERE, "asc_assets.py")], env={**os.environ, "MODE": "place"},
                       capture_output=True, text=True)
    print("\n".join("       " + x for x in (r.stdout + r.stderr).strip().splitlines()[-12:]))

# Les captures doivent être traitées par Apple avant l'envoi
if os.environ.get("SUBMIT") == "1":
    for attempt in range(30):
        pending = 0
        for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", []):
            for s_ in call("GET", f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets").get("data", []):
                for x in call("GET", f"/v1/appScreenshotSets/{s_['id']}/appScreenshots").get("data", []):
                    st = ((x["attributes"].get("assetDeliveryState") or {}).get("state"))
                    if st not in ("COMPLETE",):
                        pending += 1
        if not pending:
            print("ok     captures traitées par Apple")
            break
        print(f"       {pending} capture(s) encore en traitement chez Apple")
        time.sleep(15)

# ---------------------------------------------------------------- envoi à Apple
# Foldly devenue gratuite (1.0.1) : les acheteurs de la 1.0 doivent garder Foldly+, ce qui demande le premier build gratuit.
if SUBMIT and "com.padelup.clapet" in BUNDLE:
    flags = open(os.path.join(HERE, "..", "Shared", "Flags.swift")).read()
    if "paidApp = false" in flags and "firstFreeBuild = 0" in flags:
        problems.append("firstFreeBuild")
        print("ÉCHEC  Flags.swift : firstFreeBuild vaut 0. Le fixer au numéro du build de la 1.0.1 (les acheteurs de la 1.0 gardent Foldly+).")
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
    # Les vidéos d'en-tête et de recherche (iOS 27) placées sur cette version partent avec elle.
    for v_ in call("GET", f"/v1/appAssetLibraries/{app_id}/videos?limit=50").get("data", []):
        st = str(v_["attributes"].get("state") or "")
        if "APPROVED" in st or "REVIEW" in st or "REJECTED" in st:
            continue
        step(f"vidéo d'en-tête {v_['attributes'].get('referenceName')} ajoutée à la demande", call("POST", "/v1/reviewSubmissionItems", {"data": {
             "type": "reviewSubmissionItems", "relationships": {
                 "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                 "appAssetLibraryVideo": {"data": {"type": "appAssetLibraryVideos", "id": v_["id"]}}}}}),
             tolerate=("already", "ENTITY_ERROR", "STATE_ERROR"))
    r = step("ENVOI À LA VÉRIFICATION D'APPLE", call("PATCH", f"/v1/reviewSubmissions/{sub_id}", {"data": {
         "type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}}))
    v = call("GET", f"/v1/appStoreVersions/{vid}").get("data", {}).get("attributes", {})
    print("état de la version :", v.get("appStoreState"))

print("\nPRÊT" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
