"""Vicefold : ajoute le lien Conditions d'utilisation (EULA) à chaque langue de la version
refusée ou en préparation, garde l'URL de confidentialité, vérifie, puis renvoie à Apple.

Ne touche qu'à com.padelup.vicefold. N'écrit ni clé, ni chiffre d'affaires, ni numéro de vendeur.
Ne répond au Centre de résolution que si l'API publique le permet.
"""
import os
import re
import sys
import time
import json
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.padelup.vicefold"
EULA_URL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
LINE = "Terms of Use (EULA): " + EULA_URL
PRIVACY = {
    "fr": "https://foldly.netlify.app/vicefold/fr/privacy.html",
    "en": "https://foldly.netlify.app/vicefold/en/privacy.html",
}
REPLY = (
    "Hello,\n\n"
    "The functional Terms of Use (EULA) link has been added to the App Description of every localization:\n\n"
    + LINE
    + "\n\nThe Vicefold Pro paywall already includes links to the Terms of Use and the Privacy Policy.\n\n"
    "Thank you."
)
# Version refusée, ou encore en préparation (pas une version déjà en ligne ou déjà en vérification).
PICK = {
    "REJECTED": 0,
    "METADATA_REJECTED": 0,
    "DEVELOPER_REJECTED": 1,
    "INVALID_BINARY": 1,
    "PREPARE_FOR_SUBMISSION": 1,
    "WAITING_FOR_REVIEW": 2,
    "IN_REVIEW": 2,
}
ALREADY_SUBMITTED = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_APPLE_RELEASE", "PENDING_DEVELOPER_RELEASE"}
LIVE = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "PROCESSING_FOR_APP_STORE"}
problems = []


def redact(text):
    text = "" if text is None else str(text)
    for key in ("ASC_PRIVATE_KEY", "ASC_KEY_ID", "ASC_ISSUER_ID"):
        val = os.environ.get(key) or ""
        if val and val in text:
            text = text.replace(val, "[redacted]")
    text = re.sub(r"-----BEGIN [^-]+-----.*?-----END [^-]+-----", "[redacted]", text, flags=re.S)
    text = re.sub(r"(?i)(vendorNumber|vendor_number)(\"?\s*[:=]\s*\"?)(\d+)", r"\1\2[redacted]", text)
    return text


def privacy_for(locale):
    return PRIVACY["fr"] if (locale or "").lower().startswith("fr") else PRIVACY["en"]


try:
    token = jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        os.environ["ASC_PRIVATE_KEY"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
except Exception:
    print("ÉCHEC authentification")
    sys.exit(1)


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    url = path if path.startswith("http") else API + path
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        text = e.read().decode(errors="replace")
        try:
            errs = json.loads(text).get("errors", [])
            detail = "; ".join(f"{x.get('code')}: {x.get('detail')}" for x in errs) or text[:500]
        except Exception:
            detail = text[:500]
        return {"error": e.code, "detail": redact(detail)}
    except Exception:
        return {"error": 0, "detail": "réseau"}


def get_all(path):
    out, url = [], path
    while url:
        page = call("GET", url)
        if "error" in page:
            print("lecture impossible", page.get("error"), redact(page.get("detail", ""))[:300])
            return out
        out += page.get("data") or []
        nxt = (page.get("links") or {}).get("next")
        url = nxt.replace(API, "") if nxt else None
    return out


def with_line(desc):
    desc = (desc or "").replace("\r\n", "\n").rstrip()
    if LINE in desc:
        return desc, False
    extra = ("\n\n" if desc else "") + LINE
    if len(desc) + len(extra) <= 4000:
        return desc + extra, True
    room = 4000 - len(extra)
    return desc[:room].rstrip() + extra, True


apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}&limit=5")
if "error" in apps or not apps.get("data"):
    print("ÉCHEC app introuvable", redact(apps.get("detail", ""))[:200] if isinstance(apps, dict) else "")
    sys.exit(1)
app = next((a for a in apps["data"] if a.get("attributes", {}).get("bundleId") == BUNDLE), None)
if not app:
    print("ÉCHEC app introuvable")
    sys.exit(1)
app_id = app["id"]
print("app", redact(app.get("attributes", {}).get("name") or "Vicefold"))

versions = [v for v in get_all(f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")
            if (v.get("attributes") or {}).get("platform") in (None, "IOS")]
for v in versions:
    a = v.get("attributes") or {}
    print("version", a.get("versionString"), a.get("appStoreState"))

chosen = []
for v in versions:
    st = (v.get("attributes") or {}).get("appStoreState") or ""
    if st in PICK:
        chosen.append((PICK[st], (v.get("attributes") or {}).get("createdDate") or "", v))
if not chosen:
    print("ÉCHEC aucune version refusée ou en préparation")
    sys.exit(1)
chosen.sort(key=lambda x: (x[0], x[1]))
best = chosen[0][0]
group = [x for x in chosen if x[0] == best]
group.sort(key=lambda x: x[1], reverse=True)
version = group[0][2]
vid = version["id"]
vstate = (version.get("attributes") or {}).get("appStoreState")
vstring = (version.get("attributes") or {}).get("versionString")
print("cible", vstring, vstate)

# --- descriptions
locs = get_all(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=200")
if not locs:
    print("ÉCHEC aucune langue sur la version")
    sys.exit(1)
for loc in sorted(locs, key=lambda x: (x.get("attributes") or {}).get("locale") or ""):
    a = loc.get("attributes") or {}
    locale = a.get("locale") or "?"
    new, changed = with_line(a.get("description"))
    if not changed:
        print(f"LOCALE {locale} description déjà")
        continue
    trimmed = LINE not in (a.get("description") or "") and len((a.get("description") or "")) + 2 + len(LINE) > 4000
    r = call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {
        "type": "appStoreVersionLocalizations", "id": loc["id"],
        "attributes": {"description": new}}})
    if "error" in r:
        problems.append(locale)
        print(f"ÉCHEC {locale} description HTTP {r.get('error')} {redact(r.get('detail', ''))[:300]}")
    else:
        print(f"LOCALE {locale} description ajoutée" + (" tronquée" if trimmed else ""))

# Relecture : chaque langue doit contenir la ligne exacte.
checked = get_all(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=200")
seen = []
for loc in sorted(checked, key=lambda x: (x.get("attributes") or {}).get("locale") or ""):
    a = loc.get("attributes") or {}
    locale = a.get("locale") or "?"
    desc = a.get("description") or ""
    ok = LINE in desc
    seen.append(locale)
    print(f"VERIF {locale} {'oui' if ok else 'NON'} caractères {len(desc)}")
    if not ok:
        problems.append("verif " + locale)
if not seen:
    problems.append("verif vide")

if problems:
    print("PAS ENVOYÉ :", ", ".join(problems))
    print("RESOLUTION_CENTER non")
    print("REPLY")
    print(REPLY)
    sys.exit(1)

AGREEMENT = ("This app is governed by Apple's Standard Licensed Application End User License Agreement: "
              "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

def app_territories():
    rows = get_all(f"/v1/apps/{app_id}/availableTerritories?limit=200")
    ids = [t["id"] for t in rows if t.get("id")]
    if not ids:
        ids = [t["id"] for t in get_all("/v1/territories?limit=200") if t.get("id")]
    return ids

def set_eula():
    terr = app_territories()
    if not terr:
        print("EULA ÉCHEC aucun territoire")
        return False
    print("EULA territoires", len(terr))
    links = [{"type": "territories", "id": t} for t in terr]
    existing = call("GET", f"/v1/apps/{app_id}/endUserLicenseAgreement")
    data = existing.get("data") if isinstance(existing, dict) else None
    if not isinstance(data, dict):
        r = call("POST", "/v1/endUserLicenseAgreements", {"data": {
            "type": "endUserLicenseAgreements", "attributes": {"agreementText": AGREEMENT},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                              "territories": {"data": links}}}})
        if "error" in r:
            print("EULA ÉCHEC création", r.get("error"), redact(r.get("detail", ""))[:400])
            return False
        print("EULA créée")
    else:
        r = call("PATCH", f"/v1/endUserLicenseAgreements/{data['id']}", {"data": {
            "type": "endUserLicenseAgreements", "id": data["id"],
            "attributes": {"agreementText": AGREEMENT},
            "relationships": {"territories": {"data": links}}}})
        if "error" in r:
            print("EULA ÉCHEC mise à jour", r.get("error"), redact(r.get("detail", ""))[:400])
            return False
        print("EULA mise à jour")
    check = call("GET", f"/v1/apps/{app_id}/endUserLicenseAgreement")
    text = (((check.get("data") or {}) if isinstance(check, dict) else {}).get("attributes") or {}).get("agreementText") or ""
    ok = EULA_URL in text
    print("EULA vérifiée", "oui" if ok else "non", "caractères", len(text))
    return ok

# --- retirer la demande en cours, poser l'EULA, renvoyer
def ios_subs():
    return [s for s in get_all(f"/v1/reviewSubmissions?filter[app]={app_id}&limit=20")
            if (s.get("attributes") or {}).get("platform") in (None, "IOS")]

open_now = [s for s in ios_subs() if (s.get("attributes") or {}).get("state") in ("WAITING_FOR_REVIEW", "IN_REVIEW")]
for s in open_now:
    call("PATCH", f"/v1/reviewSubmissions/{s['id']}", {"data": {
        "type": "reviewSubmissions", "id": s["id"], "attributes": {"canceled": True}}})
    print("retrait demandé", (s.get("attributes") or {}).get("state"))
if open_now:
    for _ in range(10):
        time.sleep(3)
        left = [((s.get("attributes") or {}).get("state")) for s in ios_subs()
                if (s.get("attributes") or {}).get("state") in ("WAITING_FOR_REVIEW", "IN_REVIEW", "CANCELING")]
        print("retrait", ",".join(left) or "terminé")
        if not left:
            break
eula_ok = set_eula()
checked = get_all(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=200")
seen = []
for loc in sorted(checked, key=lambda x: (x.get("attributes") or {}).get("locale") or ""):
    a = loc.get("attributes") or {}
    locale = a.get("locale") or "?"
    desc = a.get("description") or ""
    if LINE not in desc:
        new, _ = with_line(desc)
        call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"description": new}}})
        desc = (((call("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}").get("data") or {}).get("attributes") or {}).get("description") or "")
    ok = LINE in desc
    seen.append(locale)
    print(f"VERIF {locale} {'oui' if ok else 'NON'}")
    if not ok:
        problems.append("verif " + locale)
fresh = call("GET", f"/v1/appStoreVersions/{vid}")
vstate = ((fresh.get("data") or {}).get("attributes") or {}).get("appStoreState") or vstate
print("état après retrait", vstring, vstate, "eula", "oui" if eula_ok else "non", "langues", len(seen))
if problems or not eula_ok:
    print("PAS ENVOYÉ")
    sys.exit(1)
if vstate in ALREADY_SUBMITTED:
    print("PAS ENVOYÉ retrait incomplet", vstate)
    sys.exit(1)

subs = get_all(f"/v1/reviewSubmissions?filter[app]={app_id}&limit=20")
for s in subs:
    print("demande", (s.get("attributes") or {}).get("state"))

def submission_has_version(sub):
    items = get_all(f"/v1/reviewSubmissions/{sub['id']}/items?include=appStoreVersion&limit=50")
    for it in items:
        data = ((it.get("relationships") or {}).get("appStoreVersion") or {}).get("data")
        if isinstance(data, dict) and data.get("id") == vid:
            return True
    return False

def newest(cands):
    return sorted(cands, key=lambda s: ((s.get("attributes") or {}).get("submittedDate") or ""), reverse=True)[0]

ios_subs = [s for s in subs if (s.get("attributes") or {}).get("platform") in (None, "IOS")]
unresolved = [s for s in ios_subs if (s.get("attributes") or {}).get("state") == "UNRESOLVED_ISSUES"]
ready = [s for s in ios_subs if (s.get("attributes") or {}).get("state") == "READY_FOR_REVIEW"]
open_sub = next((s for s in unresolved if submission_has_version(s)), None)
if not open_sub and unresolved:
    open_sub = newest(unresolved)
if not open_sub:
    open_sub = next((s for s in ready if submission_has_version(s)), None)
if not open_sub and ready:
    open_sub = newest(ready)
if open_sub:
    sub_id = open_sub["id"]
    print("demande reprise", (open_sub.get("attributes") or {}).get("state"))
else:
    made = call("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    if "error" in made or not (made.get("data") or {}).get("id"):
        print("ÉCHEC création de la demande", redact((made or {}).get("detail", ""))[:400])
        sys.exit(1)
    sub_id = made["data"]["id"]
    print("demande créée", (made["data"].get("attributes") or {}).get("state"))

items = get_all(f"/v1/reviewSubmissions/{sub_id}/items?include=appStoreVersion&limit=50")
has_version = False
for it in items:
    data = ((it.get("relationships") or {}).get("appStoreVersion") or {}).get("data")
    if isinstance(data, dict) and data.get("id") == vid:
        has_version = True
if has_version:
    print("version déjà dans la demande")
else:
    added = call("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    detail = (added.get("detail") or "") if isinstance(added, dict) else ""
    if "error" in added and not any(w in detail.lower() for w in ("already", "duplicate")):
        print("ÉCHEC version non ajoutée", redact(detail)[:400])
        sys.exit(1)
    print("version ajoutée à la demande" if "error" not in added else "version déjà dans la demande")

def item_lines(sid):
    for it in get_all(f"/v1/reviewSubmissions/{sid}/items?limit=50"):
        rels = it.get("relationships") or {}
        kind = next((k for k, rel in rels.items() if k != "reviewSubmission" and isinstance(rel, dict) and rel.get("data")), "?")
        print("item", kind, (it.get("attributes") or {}).get("state"))

def submit(sid):
    return call("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {
        "type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})

sent = submit(sub_id)
if "error" in sent:
    print("ÉCHEC envoi", redact(sent.get("detail", ""))[:400])
    item_lines(sub_id)
    b = call("GET", f"/v1/appStoreVersions/{vid}/build")
    ba = (b.get("data") or {}).get("attributes") or {}
    print("build", ba.get("version"), ba.get("processingState"))
    # La demande refusée reste bloquée : on la retire et on en ouvre une neuve avec la même version.
    call("PATCH", f"/v1/reviewSubmissions/{sub_id}", {"data": {
        "type": "reviewSubmissions", "id": sub_id, "attributes": {"canceled": True}}})
    for _ in range(8):
        time.sleep(3)
        st = ((call("GET", f"/v1/reviewSubmissions/{sub_id}").get("data") or {}).get("attributes") or {}).get("state")
        print("retrait", st)
        if st not in ("UNRESOLVED_ISSUES", "CANCELING", "READY_FOR_REVIEW"):
            break
    made = call("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    if "error" in made or not (made.get("data") or {}).get("id"):
        print("ÉCHEC nouvelle demande", redact(made.get("detail", ""))[:400])
        sys.exit(1)
    sub_id = made["data"]["id"]
    added = call("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    if "error" in added and not any(w in (added.get("detail") or "").lower() for w in ("already", "duplicate")):
        print("ÉCHEC version non ajoutée", redact(added.get("detail", ""))[:400])
        sys.exit(1)
    sent = submit(sub_id)
    if "error" in sent:
        print("ÉCHEC second envoi", redact(sent.get("detail", ""))[:400])
        item_lines(sub_id)
        sys.exit(1)

sub_state = ((sent.get("data") or {}).get("attributes") or {}).get("state")
ver_state = vstate
for _ in range(6):
    time.sleep(3)
    ver_state = ((call("GET", f"/v1/appStoreVersions/{vid}").get("data") or {}).get("attributes") or {}).get("appStoreState")
    sub_state = ((call("GET", f"/v1/reviewSubmissions/{sub_id}").get("data") or {}).get("attributes") or {}).get("state")
    print("READBACK version", vstring, ver_state)
    print("READBACK submission", sub_state)
    if sub_state in ALREADY_SUBMITTED or ver_state in ALREADY_SUBMITTED:
        break

# Centre de résolution : l'API publique n'a pas d'écriture. On sonde une fois, sans rien poster au hasard.
probe = call("GET", f"/v1/resolutionCenterThreads?filter[reviewSubmission]={sub_id}&limit=5")
sent_reply = False
if "error" not in probe and isinstance(probe.get("data"), list):
    print("RESOLUTION_CENTER fils", len(probe["data"]), "sans méthode d'envoi publique")
else:
    print("RESOLUTION_CENTER non", probe.get("error") or "absent")
print("REPLY")
print(REPLY)
ok = sub_state in ALREADY_SUBMITTED or ver_state in ALREADY_SUBMITTED
print(f"SUMMARY locales={len(seen)} verified={len(seen)} version={vstring} versionState={ver_state} submissionState={sub_state} resolutionCenter={'yes' if sent_reply else 'no'}")
sys.exit(0 if ok else 1)
