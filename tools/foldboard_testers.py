"""FOLDBOARD : invite des testeurs externes (par e-mail) dans un groupe TestFlight et leur envoie un build.

Entrées (variables d'environnement) :
  EMAILS        adresses séparées par des virgules ou des espaces
  BUILD_NUMBER  le build à leur envoyer
  GROUP         nom du groupe externe (créé s'il n'existe pas)
Écrit le message « À tester » (FR et EN), reprend les coordonnées de vérification bêta de Foldly si besoin,
ajoute le build au groupe, l'envoie à la vérification bêta d'Apple et invite les testeurs.
"""
import json, os, re, sys, time, urllib.request, urllib.error
import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.padelup.foldboard"
SOURCE_BUNDLE = "com.padelup.clapet"
EMAILS = [e.strip().lower().removeprefix("mailto:") for e in re.split(r"[,\s]+", os.environ.get("EMAILS", "")) if e.strip()]
BUILD = os.environ.get("BUILD_NUMBER", "").strip()
GROUP = os.environ.get("GROUP", "").strip() or "Premiers testeurs"

WHATS_NEW = {
    "fr-FR": """Tu as l'honneur de faire partie des tout premiers testeurs de Foldboard, le clavier pensé pour l'iPhone Duo !

Tu as été choisi parmi les meilleurs utilisateurs de Foldly. Merci !

À essayer :
• Ouvre l'app et fais « Comment ça marche » : 3 appuis sous le pouce droit, 3 sous le pouce gauche.
• Écris dans n'importe quelle app : le clavier vient du côté de la main qui tient le téléphone.
• Duo ouvert : clavier entier en paysage ; en portrait, petit clavier qui suit la main, en grand ou en deux moitiés.

Un souci, une idée ? Fais une capture d'écran : TestFlight te propose de l'envoyer avec un commentaire.""",
    "en-US": """You are one of the very first testers of Foldboard, the keyboard made for iPhone Duo!

You were picked among the best Foldly users. Thank you!

Things to try:
• Open the app and do "How it works": 3 presses under your right thumb, 3 under your left.
• Type in any app: the keyboard comes to the side of the hand holding the phone.
• Duo open: full keyboard in landscape; in portrait, a small keyboard that follows your hand, full width or split.

A problem or an idea? Take a screenshot: TestFlight lets you send it with a comment.""",
}
DESCRIPTION = {
    "fr-FR": "Foldboard : le clavier de l'iPhone Duo qui vient du côté de la main qui tient le téléphone.",
    "en-US": "Foldboard: the iPhone Duo keyboard that comes to the side of the hand holding the phone.",
}

token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1100,
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
        return {"error": e.code, "detail": e.read().decode()[:700]}


def step(label, r):
    if isinstance(r, dict) and "error" in r:
        print(f"ÉCHEC  {label} : {r['error']} {r['detail']}")
    else:
        print(f"ok     {label}")
    return r


app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]
app_id = app["id"]
src = (call("GET", f"/v1/apps?filter[bundleId]={SOURCE_BUNDLE}").get("data") or [None])[0]

# Le build
build = None
for _ in range(40):
    bs = call("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={BUILD}&limit=5").get("data", [])
    if bs and bs[0]["attributes"].get("processingState") == "VALID":
        build = bs[0]
        break
    print("       attente du traitement du build", BUILD)
    time.sleep(30)
if not build:
    sys.exit(f"ÉCHEC  build {BUILD} introuvable ou pas prêt")
bid = build["id"]
print(f"ok     build {BUILD} prêt")
if build["attributes"].get("usesNonExemptEncryption") is None:
    step("chiffrement : aucun", call("PATCH", f"/v1/builds/{bid}", {"data": {"type": "builds", "id": bid, "attributes": {"usesNonExemptEncryption": False}}}))

# Description TestFlight et adresse de retour (reprise de Foldly)
feedback = None
if src:
    for l in call("GET", f"/v1/apps/{src['id']}/betaAppLocalizations").get("data", []):
        feedback = feedback or l["attributes"].get("feedbackEmail")
primary = app["attributes"].get("primaryLocale", "en-US")
print("       langue principale :", primary)
if primary not in DESCRIPTION:
    DESCRIPTION[primary] = DESCRIPTION["fr-FR" if primary.startswith("fr") else "en-US"]
existing = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/apps/{app_id}/betaAppLocalizations").get("data", [])}
print("       textes TestFlight existants :", {k: (v["attributes"].get("description") or "")[:30] for k, v in existing.items()})
for loc, text in DESCRIPTION.items():
    attrs = {"description": text}
    if feedback:
        attrs["feedbackEmail"] = feedback
    if loc in existing:
        step(f"texte TestFlight {loc}", call("PATCH", f"/v1/betaAppLocalizations/{existing[loc]['id']}",
             {"data": {"type": "betaAppLocalizations", "id": existing[loc]["id"], "attributes": attrs}}))
    else:
        step(f"texte TestFlight {loc}", call("POST", "/v1/betaAppLocalizations",
             {"data": {"type": "betaAppLocalizations", "attributes": {"locale": loc, **attrs},
                       "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))

# Coordonnées pour la vérification bêta (reprises de Foldly)
mine = call("GET", f"/v1/apps/{app_id}/betaAppReviewDetail").get("data", {})
if mine and not mine.get("attributes", {}).get("contactEmail") and src:
    s = call("GET", f"/v1/apps/{src['id']}/betaAppReviewDetail").get("data", {}).get("attributes", {})
    keep = {k: s.get(k) for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail") if s.get(k)}
    keep["demoAccountRequired"] = False
    step("coordonnées de vérification bêta (reprises de Foldly)",
         call("PATCH", f"/v1/betaAppReviewDetails/{mine['id']}", {"data": {"type": "betaAppReviewDetails", "id": mine["id"], "attributes": keep}}))

# « À tester »
locs = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/builds/{bid}/betaBuildLocalizations").get("data", [])}
for loc, text in WHATS_NEW.items():
    if loc in locs:
        step(f"« À tester » {loc}", call("PATCH", f"/v1/betaBuildLocalizations/{locs[loc]['id']}",
             {"data": {"type": "betaBuildLocalizations", "id": locs[loc]["id"], "attributes": {"whatsNew": text}}}))
    else:
        step(f"« À tester » {loc}", call("POST", "/v1/betaBuildLocalizations",
             {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": loc, "whatsNew": text},
                       "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}}))

# Le groupe externe
groups = call("GET", f"/v1/apps/{app_id}/betaGroups?limit=50").get("data", [])
group = next((g for g in groups if g["attributes"].get("name") == GROUP and not g["attributes"].get("isInternalGroup")), None)
if not group:
    r = step(f"groupe « {GROUP} » créé", call("POST", "/v1/betaGroups",
             {"data": {"type": "betaGroups", "attributes": {"name": GROUP, "publicLinkEnabled": False, "feedbackEnabled": True},
                       "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
    group = r.get("data")
    if not group:
        sys.exit(1)
gid = group["id"]
step(f"build {BUILD} ajouté au groupe", call("POST", f"/v1/betaGroups/{gid}/relationships/builds", {"data": [{"type": "builds", "id": bid}]}))

# Vérification bêta d'Apple (obligatoire pour le premier build envoyé à des testeurs externes)
state = call("GET", f"/v1/builds/{bid}/buildBetaDetail").get("data", {}).get("attributes", {}).get("externalBuildState")
print("       état bêta externe :", state)
if state in ("READY_FOR_BETA_SUBMISSION", None):
    time.sleep(20)
    step("envoyé à la vérification bêta d'Apple", call("POST", "/v1/betaAppReviewSubmissions",
         {"data": {"type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}}))

# Les testeurs
for email in EMAILS:
    found = call("GET", f"/v1/betaTesters?filter[email]={email}&filter[apps]={app_id}&limit=5").get("data", [])
    if found:
        tid = found[0]["id"]
        step(f"{email} ajouté au groupe", call("POST", f"/v1/betaGroups/{gid}/relationships/betaTesters", {"data": [{"type": "betaTesters", "id": tid}]}))
    else:
        r = step(f"{email} invité", call("POST", "/v1/betaTesters",
                 {"data": {"type": "betaTesters", "attributes": {"email": email},
                           "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": gid}]}}}}))
        tid = (r.get("data") or {}).get("id")
    if tid:
        step(f"invitation TestFlight envoyée à {email}", call("POST", "/v1/betaTesterInvitations",
             {"data": {"type": "betaTesterInvitations", "relationships": {
                 "app": {"data": {"type": "apps", "id": app_id}},
                 "betaTester": {"data": {"type": "betaTesters", "id": tid}}}}}))
print("Fini. Les testeurs reçoivent l'e-mail de TestFlight dès qu'Apple a validé le build pour les tests externes.")
