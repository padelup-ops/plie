"""UNLOCKED sur App Store Connect : distribution TestFlight d'un build.

Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY, ORIGAMO_BUNDLE_ID, BUILD_NUMBER (facultatif),
NO_PUBLIC_BETA (1 = testeurs internes seulement).
Texte TestFlight, notes « À tester », mêmes testeurs internes qu'Origamo, puis testeurs externes s'il y a un groupe.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.padelup.unlocked"
BUILD = os.environ.get("BUILD_NUMBER", "").strip()

BETA_DESCRIPTION = {
    "fr-FR": "Unlocked : tu trouves un téléphone dans un train. Sa propriétaire, Nina, a disparu. Fouille ses messages, ses photos, ses notes et ses messages vocaux pour comprendre ce qui lui est arrivé.",
    "en-US": "Unlocked: you find a phone on a train. Its owner, Nina, has gone missing. Search her messages, photos, notes and voicemails to find out what happened to her.",
}
WHATS_NEW = {
    "fr-FR": """Premier chapitre du téléphone de Nina (environ 15 minutes).
1. Arrives-tu à déverrouiller le téléphone sans aide ? Avec combien d'indices ?
2. Y a-t-il un moment où tu ne savais plus quoi faire ?
3. Les messages qui arrivent en direct : trop lents, trop rapides ?
Réponds avec une capture d'écran si quelque chose cloche.""",
    "en-US": """First chapter of Nina's phone (about 15 minutes).
1. Can you unlock the phone without help? How many hints did you use?
2. Was there a moment where you didn't know what to do?
3. The live messages: too slow, too fast?
Send a screenshot if something looks wrong.""",
}

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


def upsert(kind, existing, locale, attrs, parent_rel, parent_type, parent_id, label):
    """Met à jour la localisation `locale` si elle existe, sinon la crée."""
    if locale in existing:
        lid = existing[locale]["id"]
        return step(label, call("PATCH", f"/v1/{kind}/{lid}", {"data": {"type": kind, "id": lid, "attributes": attrs}}))
    body = {"data": {"type": kind, "attributes": {"locale": locale, **attrs},
                     "relationships": {parent_rel: {"data": {"type": parent_type, "id": parent_id}}}}}
    return step(label, call("POST", f"/v1/{kind}", body))


apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}").get("data", [])
if not apps:
    print("FICHE  introuvable pour", BUNDLE)
    sys.exit(1)
app = apps[0]
app_id = app["id"]
print("APP", app_id, "|", app["attributes"]["name"], "| langue principale", app["attributes"].get("primaryLocale"))

# ------------------------------------------------------------ 3. Le texte TestFlight
existing = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/apps/{app_id}/betaAppLocalizations").get("data", [])}
for locale, text in BETA_DESCRIPTION.items():
    upsert("betaAppLocalizations", existing, locale, {"description": text}, "app", "apps", app_id, f"texte TestFlight {locale}")

# ------------------------------------------------------------ 4. Le build
build = None
for attempt in range(80):
    query = f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5"
    if BUILD:
        query += f"&filter[version]={BUILD}"
    found = call("GET", query).get("data", [])
    if found:
        b = found[0]
        state = b["attributes"].get("processingState")
        if state == "VALID":
            build = b
            break
        if state in ("FAILED", "INVALID"):
            print("ÉCHEC  traitement du build :", state)
            sys.exit(1)
        print("attente du traitement par Apple :", b["attributes"].get("version"), state)
    else:
        print("build pas encore visible")
    time.sleep(30)
if not build:
    print("ÉCHEC  le build n'est pas prêt après 40 minutes")
    sys.exit(1)
bid = build["id"]
print("build", build["attributes"].get("version"), "prêt")

locs = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/builds/{bid}/betaBuildLocalizations").get("data", [])}
if os.environ.get("SKIP_NOTES") != "1":
    for locale, text in WHATS_NEW.items():
        upsert("betaBuildLocalizations", locs, locale, {"whatsNew": text}, "build", "builds", bid, f"notes À tester {locale}")

# ------------------------------------------------------------ 5. Les testeurs internes (les mêmes qu'Origamo)
groups = call("GET", f"/v1/apps/{app_id}/betaGroups?limit=50").get("data", [])
internal = [g for g in groups if g["attributes"].get("isInternalGroup")]
if not internal:
    r = step("groupe interne créé", call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups",
             "attributes": {"name": "Unlocked interne", "isInternalGroup": True, "hasAccessToAllBuilds": True},
             "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
    internal = [r["data"]] if "data" in r else []
origamo = call("GET", "/v1/apps?filter[bundleId]=" + os.environ.get("ORIGAMO_BUNDLE_ID", "")).get("data", [])
wanted = {}
if origamo:
    for g in call("GET", f"/v1/apps/{origamo[0]['id']}/betaGroups?limit=50").get("data", []):
        if g["attributes"].get("isInternalGroup"):
            for t in call("GET", f"/v1/betaGroups/{g['id']}/betaTesters?limit=200").get("data", []):
                wanted[t["id"]] = t
print(f"{len(wanted)} testeur(s) interne(s) chez Origamo")
for g in internal:
    have = {t["id"] for t in call("GET", f"/v1/betaGroups/{g['id']}/betaTesters?limit=200").get("data", [])}
    missing = [tid for tid in wanted if tid not in have]
    if missing:
        step(f"{len(missing)} testeur(s) ajouté(s) au groupe « {g['attributes']['name']} »",
             call("POST", f"/v1/betaGroups/{g['id']}/relationships/betaTesters",
                  {"data": [{"type": "betaTesters", "id": tid} for tid in missing]}), tolerate=("already", "cannot be assigned"))
    if not g["attributes"].get("hasAccessToAllBuilds"):
        step(f"build ajouté au groupe « {g['attributes']['name']} »",
             call("POST", f"/v1/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": bid}]}),
             tolerate=("already",))
    count = len(call("GET", f"/v1/betaGroups/{g['id']}/betaTesters?limit=200").get("data", []))
    print(f"groupe « {g['attributes']['name']} » (interne) : {count} testeur(s)")

# Testeurs internes qui n'ont pas pu être ajoutés : on les réinvite par leur adresse.
if internal and wanted:
    count = len(call("GET", f"/v1/betaGroups/{internal[0]['id']}/betaTesters?limit=200").get("data", []))
    if count == 0:
        for t in wanted.values():
            at = t["attributes"]
            body = {"data": {"type": "betaTesters",
                             "attributes": {k: at.get(k) for k in ("email", "firstName", "lastName") if at.get(k)},
                             "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": internal[0]["id"]}]}}}}
            r = call("POST", "/v1/betaTesters", body)
            print("ok     testeur interne invité par adresse" if "data" in r else f"       testeur interne : {r.get('detail', '')[:200]}")

# ------------------------------------------------------------ 6. Les testeurs externes
external = [g for g in call(f"GET", f"/v1/apps/{app_id}/betaGroups?limit=50").get("data", []) if not g["attributes"].get("isInternalGroup")]
if external and os.environ.get("NO_PUBLIC_BETA") == "1":
    print("       testeurs externes : on n'envoie pas ce build (NO_PUBLIC_BETA=1)")
    external = []
if external:
    # Coordonnées pour la vérification bêta d'Apple : les mêmes que pour Origamo si elles manquent.
    mine = call("GET", f"/v1/apps/{app_id}/betaAppReviewDetail").get("data", {})
    if mine and not mine.get("attributes", {}).get("contactEmail") and origamo:
        src = call("GET", f"/v1/apps/{origamo[0]['id']}/betaAppReviewDetail").get("data", {}).get("attributes", {})
        keep = {k: src.get(k) for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail") if src.get(k)}
        if keep:
            keep["demoAccountRequired"] = False
            step("coordonnées pour la vérification bêta (reprises d'Origamo)",
                 call("PATCH", f"/v1/betaAppReviewDetails/{mine['id']}", {"data": {"type": "betaAppReviewDetails", "id": mine["id"], "attributes": keep}}))
        else:
            print("       Origamo n'a pas de coordonnées de vérification bêta à reprendre")
    # Adresse de retour des testeurs : celle d'Origamo si elle manque.
    if origamo:
        src_locs = {l["attributes"]["locale"]: l["attributes"] for l in call("GET", f"/v1/apps/{origamo[0]['id']}/betaAppLocalizations").get("data", [])}
        feedback = next((v.get("feedbackEmail") for v in src_locs.values() if v.get("feedbackEmail")), None)
        if feedback:
            for l in call("GET", f"/v1/apps/{app_id}/betaAppLocalizations").get("data", []):
                if not l["attributes"].get("feedbackEmail"):
                    step(f"adresse de retour {l['attributes']['locale']}", call("PATCH", f"/v1/betaAppLocalizations/{l['id']}",
                         {"data": {"type": "betaAppLocalizations", "id": l["id"], "attributes": {"feedbackEmail": feedback}}}))
    for g in external:
        if not g["attributes"].get("publicLinkEnabled"):
            r = step(f"lien public du groupe « {g['attributes'].get('name')} »", call("PATCH", f"/v1/betaGroups/{g['id']}",
                     {"data": {"type": "betaGroups", "id": g["id"], "attributes": {"publicLinkEnabled": True}}}))
            if "data" in r:
                g = r["data"]
        a = g["attributes"]
        n = len(call("GET", f"/v1/betaGroups/{g['id']}/betaTesters?limit=200").get("data", []))
        link = a.get("publicLink") if a.get("publicLinkEnabled") else None
        print(f"groupe « {a.get('name')} » (externe) : {n} testeur(s)" + (f" · lien public {link}" if link else " · pas de lien public"))
        r_ = call("POST", f"/v1/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": bid}]})
        if isinstance(r_, dict) and r_.get("error") == 404:
            # Autre chemin d'Apple pour la même chose (le premier répond parfois 404)
            r_ = call("POST", f"/v1/builds/{bid}/relationships/betaGroups", {"data": [{"type": "betaGroups", "id": g["id"]}]})
        step(f"build ajouté au groupe « {a.get('name')} »", r_, tolerate=("already",))
        in_group = [x["id"] for x in call("GET", f"/v1/builds/{bid}/betaGroups?limit=50").get("data", [])]
        print(f"       le build est dans le groupe : {'oui' if g['id'] in in_group else 'NON'}")
    detail = call("GET", f"/v1/builds/{bid}/buildBetaDetail").get("data", {})
    ext_state = detail.get("attributes", {}).get("externalBuildState")
    print("état pour les testeurs externes :", ext_state)
    if ext_state not in ("IN_BETA_TESTING", "READY_FOR_BETA_TESTING", "WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW", "BETA_APPROVED"):
        step("envoi à la vérification bêta d'Apple", call("POST", "/v1/betaAppReviewSubmissions",
             {"data": {"type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}}),
             tolerate=("already",))
    detail = call("GET", f"/v1/builds/{bid}/buildBetaDetail").get("data", {})
    print("état final pour les testeurs externes :", detail.get("attributes", {}).get("externalBuildState"))

detail = call("GET", f"/v1/builds/{bid}/buildBetaDetail").get("data", {})
print("état pour les testeurs internes :", detail.get("attributes", {}).get("internalBuildState"))
print("\nBUILD DISTRIBUÉ" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
