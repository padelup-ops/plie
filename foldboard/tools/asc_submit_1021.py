"""Envoie Foldboard 1.0.21 (build 149) à la vérification, sortie automatique après accord.

Ne change que les nouveautés, le type de sortie, le chiffrement (comme les versions
précédentes : pas de chiffrement exempté) et le build joint. Pas le prix, pas les
captures, pas les catégories. Ne touche pas aux autres apps.
"""
import json
import os
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.padelup.foldboard"
VERSION = "1.0.21"
BUILD = os.environ.get("RELEASE_BUILD", "149").strip()

notes_path = os.path.join(os.path.dirname(__file__), "..", "..", "tools", "meta", "foldboard.json")
with open(notes_path, encoding="utf-8") as f:
    NOTES = {loc: entry["whatsNew"] for loc, entry in json.load(f)["locales"].items() if entry.get("whatsNew")}

token = jwt.encode(
    {"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
    os.environ["ASC_PRIVATE_KEY"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
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
            detail = "; ".join(f"{x.get('code')}: {x.get('detail')}" for x in errs) or text[:800]
        except Exception:
            detail = text[:800]
        return {"error": e.code, "detail": detail}


def step(label, result, tolerate=()):
    if isinstance(result, dict) and "error" in result:
        if any(t in result["detail"] for t in tolerate):
            print(f"ok     {label} (déjà fait)")
            return result
        problems.append(label)
        print(f"ÉCHEC  {label} -> HTTP {result['error']} {result['detail'][:500]}")
    else:
        print(f"ok     {label}")
    return result


def note_for(locale):
    if locale in NOTES:
        return NOTES[locale]
    lang = locale.split("-")[0]
    for key, text in NOTES.items():
        if key == lang or key.startswith(lang + "-"):
            return text
    return NOTES.get("en-US")


apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}&limit=5").get("data", [])
if not apps:
    print("app introuvable")
    raise SystemExit(1)
app_id = apps[0]["id"]
print("APP", app_id, apps[0]["attributes"].get("name"))

existing = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&filter[versionString]={VERSION}&limit=5").get("data", [])
if existing:
    version = existing[0]
    print("version déjà là", version["attributes"].get("appStoreState"), version["attributes"].get("releaseType"))
else:
    all_v = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10").get("data", [])
    print("versions", [(v["attributes"].get("versionString"), v["attributes"].get("appStoreState")) for v in all_v])
    editable = [v for v in all_v if v["attributes"].get("appStoreState") in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")]
    if editable and editable[0]["attributes"].get("versionString") != VERSION:
        ev = editable[0]
        renamed = step(f"version {ev['attributes'].get('versionString')} renommée en {VERSION}",
                       call("PATCH", f"/v1/appStoreVersions/{ev['id']}", {"data": {
                           "type": "appStoreVersions", "id": ev["id"],
                           "attributes": {"versionString": VERSION, "releaseType": "AFTER_APPROVAL"}}}))
        version = ev if "error" not in renamed else None
    else:
        created = step(f"version {VERSION} créée", call("POST", "/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": VERSION, "releaseType": "AFTER_APPROVAL"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
        version = created.get("data")
if not version:
    raise SystemExit(1)
vid = version["id"]
step("sortie automatique après accord", call("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {
    "type": "appStoreVersions", "id": vid, "attributes": {"releaseType": "AFTER_APPROVAL"}}}))

for loc in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=50").get("data", []):
    locale = loc["attributes"]["locale"]
    text = note_for(locale)
    if not text:
        problems.append(f"nouveautés {locale}")
        print(f"ÉCHEC  nouveautés {locale} : pas de texte")
        continue
    step(f"nouveautés {locale}", call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {
        "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"whatsNew": text}}}))

build = None
states = []
for attempt in range(40):
    builds = call("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={BUILD}&limit=5").get("data", [])
    states = [b["attributes"].get("processingState") for b in builds]
    build = next((b for b in builds if b["attributes"].get("processingState") == "VALID"), None)
    print(f"build {BUILD}", states or "introuvable", f"essai {attempt + 1}")
    if build or any(s in ("FAILED", "INVALID") for s in states):
        break
    time.sleep(30)
if not build:
    print("ÉCHEC build pas prêt")
    raise SystemExit(1)
bid = build["id"]
enc = build["attributes"].get("usesNonExemptEncryption")
print("chiffrement", enc)
if enc is None:
    step("chiffrement : aucun, comme les versions précédentes", call("PATCH", f"/v1/builds/{bid}", {"data": {
        "type": "builds", "id": bid, "attributes": {"usesNonExemptEncryption": False}}}))
elif enc is False:
    print("ok     chiffrement déjà à non")
else:
    problems.append("chiffrement")
    print("ÉCHEC  chiffrement inattendu", enc)

step(f"build {BUILD} joint", call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
     {"data": {"type": "builds", "id": bid}}))

subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW,UNRESOLVED_ISSUES,WAITING_FOR_REVIEW&limit=10").get("data", [])
open_sub = next((s for s in subs if s["attributes"].get("state") in ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES")), None)
if open_sub:
    sub_id = open_sub["id"]
    print("demande ouverte", sub_id, open_sub["attributes"].get("state"))
else:
    made = step("demande de vérification créée", call("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
    if "error" in made:
        raise SystemExit(1)
    sub_id = made["data"]["id"]
step("version ajoutée à la demande", call("POST", "/v1/reviewSubmissionItems", {"data": {
    "type": "reviewSubmissionItems", "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}),
     tolerate=("already", "ENTITY_ERROR"))
step("ENVOI À LA VÉRIFICATION", call("PATCH", f"/v1/reviewSubmissions/{sub_id}", {"data": {
    "type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}}))

time.sleep(5)
final = call("GET", f"/v1/appStoreVersions/{vid}").get("data", {}).get("attributes", {})
attached = call("GET", f"/v1/appStoreVersions/{vid}/build").get("data") or {}
batts = attached.get("attributes") or {}
sub_now = call("GET", f"/v1/reviewSubmissions/{sub_id}").get("data", {}).get("attributes", {})
locs = call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=50").get("data", [])
print("READBACK versionState", final.get("appStoreState"))
print("READBACK releaseType", final.get("releaseType"))
print("READBACK version", final.get("versionString"))
print("READBACK build", batts.get("version"), batts.get("processingState"), "encryption", batts.get("usesNonExemptEncryption"))
print("READBACK submissionId", sub_id)
print("READBACK submissionState", sub_now.get("state"))
for loc in locs:
    text = (loc["attributes"].get("whatsNew") or "").replace("\n", " ")
    print("READBACK whatsNew", loc["attributes"].get("locale"), text[:90])
if problems:
    print("À REVOIR", ", ".join(problems))
    raise SystemExit(1)
print("SOUMIS")
