"""Vicefold : envoie un build à la vérification d'Apple, avec les conditions d'utilisation (EULA).

- retire d'abord une demande encore en attente (pour remplacer le build) ;
- remet la description de chaque langue (tools/meta/vicefold.json), qui finit par le lien EULA ;
- pose l'EULA propre à l'app dans App Store Connect (le contrat standard d'Apple) ;
- joint le build, écrit la note pour Apple, envoie, puis relit tout.
Ne touche qu'à com.padelup.vicefold. Ne change ni prix ni achats. N'écrit ni clé ni adresse.
RELEASE_BUILD : numéro du build. RELEASE_VERSION : seulement s'il faut créer une nouvelle version (ignorée sinon).
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.padelup.vicefold"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BUILD = os.environ.get("RELEASE_BUILD", "").strip()
NEW_VERSION = os.environ.get("RELEASE_VERSION", "").strip()
DRY = os.environ.get("DRY_RUN") == "1"
EULA_URL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
LINE = "Terms of Use (EULA): " + EULA_URL
AGREEMENT = ("This app is governed by Apple's Standard Licensed Application End User License Agreement: " + EULA_URL)
NOTES = (
    "Terms of Use (EULA), as requested in the previous review:\n"
    "- A functional link to the Terms of Use (EULA) is at the end of the App Description of every localization: "
    + EULA_URL + "\n"
    "- The EULA field of the app in App Store Connect is filled in as well.\n"
    "- In the app, the Vicefold Pro screen (More > Profile and play time > Vicefold Pro, or any Pro badge) shows the "
    "price and length of the subscription with working \"Terms\" and \"Privacy\" links under the purchase buttons.\n"
    "- The Privacy Policy URL is set in App Information.\n\n"
    "Vicefold is an unofficial fan companion: no account, no ads, no tracking. Every guide is free; "
    "Vicefold Pro (one-time purchase or yearly subscription) unlocks map layers, iCloud sync and widgets."
)
EDITABLE = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")
PENDING = ("WAITING_FOR_REVIEW", "IN_REVIEW")
problems = []

with open(os.path.join(ROOT, "tools/meta/vicefold.json"), encoding="utf-8") as f:
    LOCALES = json.load(f)["locales"]

token = jwt.encode(
    {"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
    os.environ["ASC_PRIVATE_KEY"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        text = e.read().decode(errors="replace")
        try:
            errs = json.loads(text).get("errors", [])
            parts = []
            for x in errs:
                parts.append(f"{x.get('code')}: {x.get('detail')}")
                # Apple range la vraie raison dans les erreurs associées (par ressource).
                for where, subs in ((x.get("meta") or {}).get("associatedErrors") or {}).items():
                    for one in subs:
                        parts.append(f"[{where}] {one.get('code')}: {one.get('detail')}")
            detail = "; ".join(parts) or text[:600]
        except Exception:
            detail = text[:600]
        return {"error": e.code, "detail": detail}


def write(method, path, body):
    if DRY and method != "GET":
        print("   (essai à blanc)", method, path.split("?")[0])
        return {}
    return call(method, path, body)


def step(label, result, tolerate=()):
    if isinstance(result, dict) and "error" in result:
        if any(t in result["detail"] for t in tolerate):
            print(f"ok     {label} (déjà fait)")
            return result
        problems.append(label)
        print(f"ÉCHEC  {label} -> HTTP {result['error']} {result['detail'][:3000]}")
    else:
        print(f"ok     {label}")
    return result


def attrs(x):
    return (x or {}).get("attributes") or {}


def meta_for(locale):
    return LOCALES.get(locale) or next((v for k, v in LOCALES.items() if k.split("-")[0] == locale.split("-")[0]), None) \
        or LOCALES.get("en-US")


if not BUILD:
    print("RELEASE_BUILD manquant")
    sys.exit(1)
apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}&limit=5").get("data", [])
app = next((a for a in apps if attrs(a).get("bundleId") == BUNDLE), None)
if not app:
    print("app introuvable")
    sys.exit(1)
app_id = app["id"]
print("APP", app_id, attrs(app).get("name"))


def versions():
    return call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10").get("data", [])


all_v = versions()
print("versions", [(attrs(v).get("versionString"), attrs(v).get("appStoreState")) for v in all_v])

if os.environ.get("DRY_RUN") == "iap":
    # Diagnostic en lecture seule : de quoi est faite la demande ouverte, et quelles relations Apple expose
    # pour les achats et les abonnements (leurs « versions »).
    def show(label, r, n=1800):
        print(label, json.dumps(r, ensure_ascii=False)[:n])

    def rels(label, path):
        r = call("GET", path)
        d = r.get("data") if isinstance(r, dict) else None
        if isinstance(d, dict):
            print(label, "état", attrs(d).get("state"), "relations", sorted((d.get("relationships") or {}).keys()))
        else:
            show(label, r, 400)
        return d

    for sub in call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW,UNRESOLVED_ISSUES,WAITING_FOR_REVIEW&limit=5").get("data", []):
        print("DEMANDE", sub["id"], attrs(sub).get("state"))
        for it in call("GET", f"/v1/reviewSubmissions/{sub['id']}/items?limit=20").get("data", []):
            print("  élément", it["id"], attrs(it).get("state"), "relations", sorted((it.get("relationships") or {}).keys()))
            for k in (it.get("relationships") or {}):
                if k == "reviewSubmission":
                    continue
                rr = call("GET", f"/v1/reviewSubmissionItems/{it['id']}/relationships/{k}")
                if "error" not in rr and rr.get("data"):
                    print("     ->", k, rr["data"])
    for x in call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50").get("data", []):
        d = rels(f"ACHAT {attrs(x).get('productId')}", f"/v2/inAppPurchases/{x['id']}")
        for k in sorted((d or {}).get("relationships") or {}):
            if "ersion" in k or "ubmission" in k:
                show(f"   {k}", call("GET", f"/v2/inAppPurchases/{x['id']}/{k}"), 700)
    for g in call("GET", f"/v1/apps/{app_id}/subscriptionGroups?limit=20").get("data", []):
        d = rels(f"GROUPE {attrs(g).get('referenceName')}", f"/v1/subscriptionGroups/{g['id']}")
        for k in sorted((d or {}).get("relationships") or {}):
            if "ersion" in k or "ubmission" in k:
                show(f"   {k}", call("GET", f"/v1/subscriptionGroups/{g['id']}/{k}"), 700)
        for sx in call("GET", f"/v1/subscriptionGroups/{g['id']}/subscriptions?limit=50").get("data", []):
            d = rels(f"ABONNEMENT {attrs(sx).get('productId')}", f"/v1/subscriptions/{sx['id']}")
            for k in sorted((d or {}).get("relationships") or {}):
                if "ersion" in k or "ubmission" in k:
                    show(f"   {k}", call("GET", f"/v1/subscriptions/{sx['id']}/{k}"), 700)
    sys.exit(0)

# 1. Une demande encore chez Apple : on la retire, sinon ni la fiche ni le build ne peuvent changer.
if any(attrs(v).get("appStoreState") in PENDING for v in all_v):
    waiting = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=WAITING_FOR_REVIEW,IN_REVIEW&limit=10").get("data", [])
    for sub in waiting:
        step(f"demande {sub['id'][:8]} retirée", write("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {
            "type": "reviewSubmissions", "id": sub["id"], "attributes": {"canceled": True}}}))
    for _ in range(30):
        if DRY:
            break
        left = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=WAITING_FOR_REVIEW,IN_REVIEW,CANCELING&limit=10").get("data", [])
        if not left:
            break
        print("retrait en cours", [attrs(x).get("state") for x in left])
        time.sleep(10)
    all_v = versions()
    print("versions", [(attrs(v).get("versionString"), attrs(v).get("appStoreState")) for v in all_v])

# 2. La version à envoyer : celle qui est modifiable, sinon une nouvelle (RELEASE_VERSION).
first_release = not any(attrs(v).get("appStoreState") in ("READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION", "PENDING_DEVELOPER_RELEASE",
                                                         "PENDING_APPLE_RELEASE", "PROCESSING_FOR_APP_STORE", "REMOVED_FROM_SALE",
                                                         "DEVELOPER_REMOVED_FROM_SALE") for v in all_v)
version = next((v for v in all_v if attrs(v).get("appStoreState") in EDITABLE), None)
# Déjà rangée dans une demande ouverte (un envoi précédent s'est arrêté juste avant de partir) : fiche, EULA, note et
# build sont posés, il ne reste qu'à envoyer.
staged = False
if not version:
    version = next((v for v in all_v if attrs(v).get("appStoreState") == "READY_FOR_REVIEW"), None)
    staged = version is not None
if DRY and not version:
    version = next((v for v in all_v if attrs(v).get("appStoreState") in PENDING), None)
if not version:
    if not NEW_VERSION:
        print("ÉCHEC aucune version modifiable : donner RELEASE_VERSION pour en créer une")
        sys.exit(1)
    created = step(f"version {NEW_VERSION} créée", write("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": NEW_VERSION, "releaseType": "AFTER_APPROVAL"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
    version = created.get("data")
    if not version:
        sys.exit(1)
vid = version["id"]
vstring = attrs(version).get("versionString")
print("cible", vstring, attrs(version).get("appStoreState"), "première sortie" if first_release else "mise à jour")
if staged:
    print("version déjà dans une demande ouverte : on passe directement à l'envoi")
else:
    step("sortie automatique après accord", write("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {
        "type": "appStoreVersions", "id": vid, "attributes": {"releaseType": "AFTER_APPROVAL"}}}))

    # 3. La fiche de chaque langue, avec le lien EULA à la fin de la description.
    for loc in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=50").get("data", []):
        locale = attrs(loc).get("locale")
        meta = meta_for(locale) or {}
        desc = (meta.get("description") or attrs(loc).get("description") or "").rstrip()
        if LINE not in desc:
            desc = desc[:4000 - len(LINE) - 2].rstrip() + "\n\n" + LINE
        new = {"description": desc}
        for src, dst in (("keywords", "keywords"), ("promo", "promotionalText")):
            if meta.get(src):
                new[dst] = meta[src]
        if not first_release and meta.get("whatsNew"):
            new["whatsNew"] = meta["whatsNew"]
        step(f"fiche {locale}", write("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": new}}))

    # 4. L'EULA propre à l'app (le contrat standard d'Apple), sur tous les pays.
    terr = []
    path = "/v1/territories?limit=200"
    while path:
        page = call("GET", path)
        terr += [t["id"] for t in page.get("data", [])]
        nxt = (page.get("links") or {}).get("next")
        path = nxt.replace(API, "") if nxt else None
    links = [{"type": "territories", "id": t} for t in terr]
    existing = call("GET", f"/v1/apps/{app_id}/endUserLicenseAgreement").get("data")
    if isinstance(existing, dict) and EULA_URL in (attrs(existing).get("agreementText") or ""):
        print("ok     EULA déjà posée,", len(attrs(existing).get("agreementText") or ""), "caractères")
    elif isinstance(existing, dict):
        step("EULA mise à jour", write("PATCH", f"/v1/endUserLicenseAgreements/{existing['id']}", {"data": {
            "type": "endUserLicenseAgreements", "id": existing["id"], "attributes": {"agreementText": AGREEMENT},
            "relationships": {"territories": {"data": links}}}}))
    else:
        step(f"EULA créée ({len(terr)} pays)", write("POST", "/v1/endUserLicenseAgreements", {"data": {
            "type": "endUserLicenseAgreements", "attributes": {"agreementText": AGREEMENT},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}, "territories": {"data": links}}}}))

    # 5. La note pour Apple : où trouver les conditions.
    det = call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
    if det:
        old = (attrs(det).get("notes") or "").strip()
        keep = old.split("Terms of Use (EULA), as requested")[0].strip()
        notes = (NOTES + ("\n\n" + keep if keep else ""))[:4000]
        step("note pour Apple", write("PATCH", f"/v1/appStoreReviewDetails/{det['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": det["id"], "attributes": {"notes": notes}}}))
    else:
        step("note pour Apple", write("POST", "/v1/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": {"notes": NOTES},
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}))

    # 6. Le build.
    build, states = None, []
    for attempt in range(40):
        builds = call("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={BUILD}&limit=5").get("data", [])
        states = [attrs(b).get("processingState") for b in builds]
        build = next((b for b in builds if attrs(b).get("processingState") == "VALID"), None)
        print(f"build {BUILD}", states or "introuvable", f"essai {attempt + 1}")
        if build or any(s in ("FAILED", "INVALID") for s in states) or DRY:
            break
        time.sleep(30)
    if not build:
        print("ÉCHEC build pas prêt")
        sys.exit(1)
    bid = build["id"]
    pre = attrs(call("GET", f"/v1/builds/{bid}/preReleaseVersion").get("data")).get("version")
    print("build", BUILD, "version du build", pre)
    enc = attrs(build).get("usesNonExemptEncryption")
    if enc is None:
        step("chiffrement : aucun", write("PATCH", f"/v1/builds/{bid}", {"data": {
            "type": "builds", "id": bid, "attributes": {"usesNonExemptEncryption": False}}}))
    elif enc is not False:
        problems.append("chiffrement")
        print("ÉCHEC  chiffrement inattendu", enc)
    step(f"build {BUILD} joint", write("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
         {"data": {"type": "builds", "id": bid}}))

if problems:
    print("PAS ENVOYÉ :", ", ".join(problems))
    sys.exit(1)
if DRY:
    print("ESSAI À BLANC terminé, rien n'a été écrit")
    sys.exit(0)

# 7. La demande de vérification.
subs = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW,UNRESOLVED_ISSUES&limit=10").get("data", [])
sub_id = None
for s in subs:
    if attrs(s).get("state") == "READY_FOR_REVIEW":
        sub_id = s["id"]
        print("demande ouverte reprise", sub_id[:8])
        break
if not sub_id:
    for s in subs:
        # Une demande refusée reste bloquée sur l'ancien build : on la referme pour en ouvrir une neuve.
        step(f"ancienne demande {s['id'][:8]} refermée", write("PATCH", f"/v1/reviewSubmissions/{s['id']}", {"data": {
            "type": "reviewSubmissions", "id": s["id"], "attributes": {"canceled": True}}}), tolerate=("STATE_ERROR",))
    for _ in range(12):
        left = call("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=CANCELING&limit=10").get("data", [])
        if not left:
            break
        time.sleep(5)
    made = step("demande de vérification créée", write("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
    if "error" in made:
        sys.exit(1)
    sub_id = made["data"]["id"]
step("version ajoutée à la demande", write("POST", "/v1/reviewSubmissionItems", {"data": {
    "type": "reviewSubmissionItems", "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}),
     tolerate=("already", "ENTITY_ERROR"))

# Les achats de Vicefold Pro partent avec la version (première fois) : sans eux, Apple ne peut pas vérifier l'écran Pro.
# Chez Apple, un achat, un abonnement et un groupe ont chacun une « version » ; c'est elle qu'on range dans la demande.
# Un nouveau groupe ne part que si au moins un de ses abonnements part avec lui.
IN_SUBMISSION = ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW")
DONE = ("APPROVED", "ACCEPTED", "READY_FOR_SALE", "READY_FOR_DISTRIBUTION")
warnings = []
learned = False


def attach(label, versions_path, kind, rel_names):
    global learned
    vs = call("GET", versions_path).get("data", [])
    if not vs:
        warnings.append(label)
        print(f"ATTENTION {label} : aucune version côté Apple")
        return
    v = sorted(vs, key=lambda x: attrs(x).get("version") or 0)[-1]
    st = attrs(v).get("state")
    if st in IN_SUBMISSION or st in DONE:
        print(f"ok     {label} déjà dans la demande ou accepté ({st})")
        return
    for rel in rel_names:
        r = write("POST", "/v1/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                rel: {"data": {"type": kind, "id": v["id"]}}}}})
        if "error" not in r or "already" in r.get("detail", ""):
            print(f"ok     {label} ajouté à la demande (était {st})")
            return
        print(f"       {label} ({st}) : {rel} refusé -> HTTP {r['error']} {r['detail'][:400]}")
    if not learned:
        learned = True
        probe = call("GET", f"/v1/reviewSubmissions/{sub_id}/items?include=zzz&limit=1")
        print("       relations connues d'Apple :", (probe.get("detail") or "")[:900])
    warnings.append(label)


for x in call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50").get("data", []):
    attach(f"achat {attrs(x).get('productId')}", f"/v2/inAppPurchases/{x['id']}/versions",
           "inAppPurchaseVersions", ("inAppPurchaseVersion",))
for g in call("GET", f"/v1/apps/{app_id}/subscriptionGroups?limit=20").get("data", []):
    for sx in call("GET", f"/v1/subscriptionGroups/{g['id']}/subscriptions?limit=50").get("data", []):
        attach(f"abonnement {attrs(sx).get('productId')}", f"/v1/subscriptions/{sx['id']}/versions",
               "subscriptionVersions", ("subscriptionVersion",))
    attach(f"groupe {attrs(g).get('referenceName')}", f"/v1/subscriptionGroups/{g['id']}/versions",
           "subscriptionGroupVersions", ("subscriptionGroupVersion",))

step("ENVOI À LA VÉRIFICATION", write("PATCH", f"/v1/reviewSubmissions/{sub_id}", {"data": {
    "type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}}))

# 8. Relecture.
time.sleep(6)
final = attrs(call("GET", f"/v1/appStoreVersions/{vid}").get("data"))
batts = attrs(call("GET", f"/v1/appStoreVersions/{vid}/build").get("data"))
sub_now = attrs(call("GET", f"/v1/reviewSubmissions/{sub_id}").get("data"))
print("READBACK version", final.get("versionString"), final.get("appStoreState"), "sortie", final.get("releaseType"))
print("READBACK build", batts.get("version"), batts.get("processingState"))
print("READBACK demande", sub_id[:8], sub_now.get("state"))
for it in call("GET", f"/v1/reviewSubmissions/{sub_id}/items?limit=20").get("data", []):
    kinds = [k for k, x in (it.get("relationships") or {}).items()
             if k != "reviewSubmission" and isinstance(x, dict) and x.get("data")]
    if not kinds:
        # Relations non renvoyées d'office : on les demande une à une.
        for k in (it.get("relationships") or {}):
            if k == "reviewSubmission":
                continue
            rr = call("GET", f"/v1/reviewSubmissionItems/{it['id']}/relationships/{k}")
            if "error" not in rr and rr.get("data"):
                kinds.append(k)
    print("READBACK élément", attrs(it).get("state"), ",".join(kinds) or "(genre non indiqué)")
for loc in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=50").get("data", []):
    d = attrs(loc).get("description") or ""
    ok = LINE in d
    print("READBACK fiche", attrs(loc).get("locale"), "lien EULA", "oui" if ok else "NON", len(d), "caractères")
    if not ok:
        problems.append("lien EULA " + str(attrs(loc).get("locale")))
for x in call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50").get("data", []):
    print("READBACK achat", attrs(x).get("productId"), attrs(x).get("state"))
for g in call("GET", f"/v1/apps/{app_id}/subscriptionGroups?limit=20").get("data", []):
    for sx in call("GET", f"/v1/subscriptionGroups/{g['id']}/subscriptions?limit=50").get("data", []):
        print("READBACK abonnement", attrs(sx).get("productId"), attrs(sx).get("state"))
if warnings:
    print("ACHATS À JOINDRE À LA MAIN dans App Store Connect :", ", ".join(warnings))
e = attrs(call("GET", f"/v1/apps/{app_id}/endUserLicenseAgreement").get("data"))
eula_ok = EULA_URL in (e.get("agreementText") or "")
print("READBACK EULA de l'app", "oui" if eula_ok else "NON")
if not eula_ok:
    problems.append("EULA de l'app")
if problems or sub_now.get("state") not in ("WAITING_FOR_REVIEW", "IN_REVIEW"):
    print("À REVOIR", ", ".join(problems) or sub_now.get("state"))
    sys.exit(1)
print("SOUMIS")
