"""Distribue un build TestFlight aux bêta-testeurs.

Attend que le build soit traité par Apple, écrit les notes « À tester » (FR et EN),
l'ajoute à tous les groupes de testeurs externes et l'envoie à la vérification bêta d'Apple
si elle est nécessaire. Les groupes internes qui reçoivent tous les builds l'ont automatiquement.
Lancé par .github/workflows/asc-beta.yml (entrée : numéro du build).
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUILD = os.environ.get("BUILD_NUMBER", "").strip()

INTERNAL_ONLY = os.environ.get("INTERNAL_ONLY", "").strip() in ("1", "true", "yes")
# RESEND : renvoie l'invitation TestFlight (e-mail) aux testeurs des groupes concernés, et le mail « nouveau build ».
RESEND = os.environ.get("RESEND", "").strip() in ("1", "true", "yes")

WHATS_NEW = {
    "fr-FR": """Origamo 1.1 : tout nouveau look, en papier et origami.

• Accueil refait : fond de papier, jeux à la une en feuilles qu'on fait glisser, « Reprendre », et tous les jeux en cartes pliées, triés d'un geste (à deux, en soirée, la magie du Duo, seul, enfants).
• Réglages, modes d'emploi et Pass en papier.
• Dans les jeux : boutons en papier, conseils en pense-bête, cartes de fin de partie et de pause collées sur le jeu.

À tester en priorité : l'accueil, les filtres, et les écrans de fin de partie. Dites-nous ce qui vous plaît ou pas !""",
    "en-US": """Origamo 1.1: a brand-new paper and origami look.

• New home screen: paper background, featured games as sheets you swipe, "Resume", and every game as a folded card, sorted in one tap (for two, party, Duo magic, solo, kids).
• Settings, how-to-play screens and the Pass on paper.
• In the games: paper buttons, tips as sticky notes, end-of-game and pause cards taped onto the game.

Please test first: the home screen, the filters and the end-of-game screens. Tell us what you like and what you don't!""",
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


apps = call("GET", "/v1/apps?filter[bundleId]=" + os.environ["BUNDLE_ID"])
if not apps.get("data"):
    print("app introuvable", apps)
    sys.exit(1)
app_id = apps["data"][0]["id"]
print("APP_ID", app_id)

# 1. Le build, une fois traité par Apple (jusqu'à 40 minutes)
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

# 2. Notes « À tester »
locs = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/builds/{bid}/betaBuildLocalizations").get("data", [])}
for locale, text in WHATS_NEW.items():
    if locale in locs:
        step(f"notes À tester {locale}", call("PATCH", f"/v1/betaBuildLocalizations/{locs[locale]['id']}",
             {"data": {"type": "betaBuildLocalizations", "id": locs[locale]["id"], "attributes": {"whatsNew": text}}}))
    else:
        step(f"notes À tester {locale}", call("POST", "/v1/betaBuildLocalizations",
             {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": locale, "whatsNew": text},
                       "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}}))

# 3. Groupes de testeurs (INTERNAL_ONLY : seulement les testeurs internes, pour vérifier avant tout le monde)
groups = []
for attempt in range(5):
    reply = call("GET", f"/v1/apps/{app_id}/betaGroups?limit=50")
    if "error" not in reply:
        groups = reply.get("data", [])
        break
    print("lecture des groupes impossible :", reply.get("error"), reply.get("detail"), "· nouvel essai")
    time.sleep(20)
if not groups:
    print("ÉCHEC  aucun groupe de testeurs lu")
    problems.append("groupes de testeurs")
if INTERNAL_ONLY:
    groups = [g for g in groups if g["attributes"].get("isInternalGroup")]
    print("testeurs internes seulement")
external = [g for g in groups if not g["attributes"].get("isInternalGroup")]
for g in groups:
    a = g["attributes"]
    testers = call("GET", f"/v1/betaGroups/{g['id']}/betaTesters?limit=200").get("data", [])
    kind = "interne" if a.get("isInternalGroup") else "externe"
    link = a.get("publicLink") if a.get("publicLinkEnabled") else None
    print(f"groupe « {a.get('name')} » ({kind}) : {len(testers)} testeur(s)" + (f" · lien public {link}" if link else "")
          + (" · reçoit tous les builds" if a.get("hasAccessToAllBuilds") else ""))
    if not a.get("isInternalGroup") or not a.get("hasAccessToAllBuilds"):
        step(f"build ajouté au groupe « {a.get('name')} »",
             call("POST", f"/v1/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": bid}]}),
             tolerate=("already", "ENTITY_ERROR.RELATIONSHIP"))
    if RESEND:
        for t in testers:
            ta = t["attributes"]
            mail = ta.get("email") or ""
            hidden = (mail[:2] + "***" + mail[mail.find("@"):]) if "@" in mail else "?"
            print(f"   testeur {hidden} · état {ta.get('state')} · invitation {ta.get('inviteType')}")
            step(f"invitation renvoyée à {hidden}", call("POST", "/v1/betaTesterInvitations", {"data": {
                "type": "betaTesterInvitations",
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}},
                                  "betaTester": {"data": {"type": "betaTesters", "id": t["id"]}}}}}))

# 4. Vérification bêta d'Apple (obligatoire pour les testeurs externes)
if external:
    detail = call("GET", f"/v1/builds/{bid}/buildBetaDetail").get("data", {})
    ext_state = detail.get("attributes", {}).get("externalBuildState")
    print("état pour les testeurs externes :", ext_state)
    if ext_state not in ("IN_BETA_TESTING", "READY_FOR_BETA_TESTING", "WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW", "BETA_APPROVED"):
        step("envoi à la vérification bêta d'Apple", call("POST", "/v1/betaAppReviewSubmissions",
             {"data": {"type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}}),
             tolerate=("already",))
    detail = call("GET", f"/v1/builds/{bid}/buildBetaDetail").get("data", {})
    print("état final pour les testeurs externes :", detail.get("attributes", {}).get("externalBuildState"))
    print("état pour les testeurs internes :", detail.get("attributes", {}).get("internalBuildState"))
else:
    print("aucun groupe externe : seuls les testeurs internes reçoivent le build")
    detail = call("GET", f"/v1/builds/{bid}/buildBetaDetail").get("data", {})
    print("état pour les testeurs internes :", detail.get("attributes", {}).get("internalBuildState"))

if RESEND:
    step("mail « nouveau build » envoyé aux testeurs", call("POST", "/v1/buildBetaNotifications",
         {"data": {"type": "buildBetaNotifications", "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}}),
         tolerate=("already",))

print("\nBUILD DISTRIBUÉ" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
