"""Foldly (projet Clapet) sur App Store Connect : fiche en anglais et en français, puis distribution TestFlight d'un build.

Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY, ORIGAMO_BUNDLE_ID, BUILD_NUMBER (facultatif).
1. Nom, sous-titre (fiche) et description, mots-clés (version) en en-US et fr-FR, texte TestFlight.
2. Attend que le build soit traité, écrit « À tester », et donne au groupe interne de Clapet
   les mêmes testeurs internes qu'Origamo.
Rien n'est soumis à Apple : la fiche reste en préparation.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.padelup.clapet"
BUILD = os.environ.get("BUILD_NUMBER", "").strip()

NAMES = {
    "en-US": ["Foldly: Fold Counter", "Foldly - Fold Counter", "Foldly: Hinge Counter", "Foldly: Fold Tracker"],
    "fr-FR": ["Foldly : compteur de plis", "Foldly - compteur de plis", "Foldly : compteur de pliages"],
}
SUBTITLE = {"en-US": "Keep your folds under control", "fr-FR": "Garde tes plis sous contrôle"}
KEYWORDS = {
    "en-US": "fold,hinge,counter,foldable,folding,widget,limit,habit,screen time,tracker,stats,digital wellbeing",
    "fr-FR": "pli,charnière,compteur,pliable,pliant,widget,limite,habitude,temps d'écran,suivi,statistiques",
}
PROMO = {
    "en-US": "How many times a day do you open your phone? Set a daily limit and keep an eye on your folds, right from your Home Screen.",
    "fr-FR": "Combien de fois par jour ouvres-tu ton téléphone ? Fixe une limite et garde un œil sur tes plis, directement sur ton écran d'accueil.",
}
PRICE_EUR = os.environ.get("APP_PRICE", "2.99")
DESCRIPTION = {
    "en-US": """Every time you unfold your phone, you glance at it. Foldly counts your folds, so you can see your habits and keep them under control.

Keep Foldly on screen, on the inner or the outer display: every time you close your phone, it counts. Set a daily limit and watch the ring: green while you're under it, orange when you get close, red when you're over.

• Folds and opens today, the last 7 days and your total
• Time open: how long your phone stays open each day
• A daily limit, and how many folds you have left
• Limit alerts: a notification at 80 % and at 100 % of your limit
• Today hour by hour, and your lifetime milestones
• Widgets for the Home Screen and the Lock Screen, including a big Health-style widget
• Your full history: 30 days, 12 months, the calendar of days under your limit, your trends and records
• Five widget colors, and your history as a spreadsheet (CSV)
• Shortcuts actions "Count a fold" and "Count an opening", to count automatically, even when the app is closed

One purchase, everything included. No subscription, no ads, no account.

Counting all day: on screen, Foldly reads the hinge itself. To count when it isn't on screen, plug its "Count a fold" action into the Shortcuts automation "When iPhone is Closed": the app shows you how, step by step. Your numbers stay on your iPhone.""",
    "fr-FR": """Chaque fois que tu déplies ton téléphone, tu y jettes un œil. Foldly compte tes plis, pour que tu voies tes habitudes et que tu les gardes sous contrôle.

Garde Foldly à l'écran, sur l'écran intérieur ou extérieur : chaque fois que tu fermes ton téléphone, il compte. Fixe une limite par jour et regarde l'anneau : vert tant que tu es en dessous, orange quand tu t'en approches, rouge quand tu la dépasses.

• Fermetures et ouvertures du jour, les 7 derniers jours et ton total
• Le temps ouvert : combien de temps ton téléphone reste ouvert chaque jour
• Une limite par jour, et combien de plis il te reste
• Des alertes de limite : une notification à 80 % et à 100 % de ta limite
• Ta journée heure par heure, et tes paliers depuis le début
• Des widgets pour l'écran d'accueil et l'écran verrouillé, dont un grand widget façon Santé
• Tout l'historique : 30 jours, 12 mois, le calendrier des jours sous ta limite, tes tendances et tes records
• Cinq couleurs de widgets, et ton historique en tableur (CSV)
• Des actions Raccourcis « Compter un pli » et « Compter une ouverture », pour compter automatiquement, même app fermée

Un seul achat, tout est inclus. Sans abonnement, sans pub, sans compte.

Compter toute la journée : à l'écran, Foldly lit lui-même la charnière. Pour compter quand il n'est pas à l'écran, branche son action « Compter un pli » sur l'automatisation Raccourcis « iPhone fermé » : l'app te montre comment, pas à pas. Tes chiffres restent sur ton iPhone.""",
}
BETA_DESCRIPTION = {
    "en-US": "Foldly counts how many times you close and open your foldable phone, with a daily limit and widgets like the steps in Health.",
    "fr-FR": "Foldly compte combien de fois tu fermes et ouvres ton téléphone pliable, avec une limite par jour et des widgets comme les pas dans Santé.",
}
WHATS_NEW = {
    "en-US": """New in this build:

• Foldly is now all about your numbers: no more plants, and no limit by default. Each day is compared with your own average.
• NEW Weekly recap: at the end of each week, your folds compared with the week before, time open and closed, your busiest and calmest days, and a card to share.
• NEW Minimal theme: just your numbers, black on white (or white on black). Settings > Theme.
• The "Phone down" widget becomes "Open & closed": time open and closed today, with a timer on the Lock Screen.
• The daily limit is still there if you want one: Settings > Daily limit.

Please test: try the Minimal theme, and open your weekly recap (Weekly recap in the menu).""",
    "fr-FR": """Nouveautés de ce build :

• Foldly se concentre sur tes chiffres : plus de plantes, et plus de limite par défaut. Chaque journée est comparée à ta propre moyenne.
• NOUVEAU Bilan de la semaine : à la fin de chaque semaine, tes plis comparés à la semaine d'avant, ton temps ouvert et fermé, ton jour le plus chargé et le plus calme, et une carte à partager.
• NOUVEAU thème Épuré : juste tes chiffres, noir sur blanc (ou blanc sur noir). Réglages > Thème.
• Le widget « Téléphone posé » devient « Ouvert / fermé » : ton temps ouvert et fermé aujourd'hui, avec un chrono sur l'écran verrouillé.
• La limite du jour existe toujours si tu en veux une : Réglages > Limite du jour.

À tester : essaie le thème Épuré, et ouvre ton bilan de la semaine (Bilan de la semaine dans le menu).""",
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

# ------------------------------------------------------------ 1. La fiche (nom, sous-titre)
infos = call("GET", f"/v1/apps/{app_id}/appInfos").get("data", [])
editable = [i for i in infos if i["attributes"].get("appStoreState") not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION")] or infos
if editable:
    info_id = editable[0]["id"]
    existing = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations").get("data", [])}
    for locale, names in NAMES.items():
        for i, name in enumerate(names):
            r = upsert("appInfoLocalizations", existing, locale, {"name": name, "subtitle": SUBTITLE[locale]},
                       "appInfo", "appInfos", info_id, f"nom {locale} « {name} »")
            if "error" not in r or i == len(names) - 1:
                break
            problems.pop()
            print("       on essaie le nom suivant")
    for l in call("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations").get("data", []):
        print("FICHE ", l["attributes"]["locale"], "|", l["attributes"].get("name"), "|", l["attributes"].get("subtitle"))

# ------------------------------------------------------------ 2. La version (description, mots-clés)
versions = call("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=5").get("data", [])
for v in versions:
    print("VERSION", v["attributes"].get("versionString"), v["attributes"].get("appStoreState"))
editable_versions = [v for v in versions if v["attributes"].get("appStoreState") in
                     ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
if editable_versions:
    vid = editable_versions[0]["id"]
    existing = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", [])}
    for locale in DESCRIPTION:
        upsert("appStoreVersionLocalizations", existing, locale,
               {"description": DESCRIPTION[locale], "keywords": KEYWORDS[locale], "promotionalText": PROMO[locale]},
               "appStoreVersion", "appStoreVersions", vid, f"description {locale}")
else:
    print("pas de version modifiable pour la description")

# ------------------------------------------------------------ 2 bis. Le prix de l'app (base France)
current = call("GET", f"/v1/apps/{app_id}/appPriceSchedule?include=manualPrices,baseTerritory")
have = [x for x in current.get("included", []) if x["type"] == "appPrices"]
point = None
url = f"/v1/apps/{app_id}/appPricePoints?filter[territory]=FRA&limit=200"
while url and not point:
    page = call("GET", url)
    point = next((p for p in page.get("data", []) if p["attributes"].get("customerPrice") == PRICE_EUR), None)
    nxt = page.get("links", {}).get("next")
    url = nxt.replace(API, "") if nxt else None
if not point:
    problems.append("prix")
    print("ÉCHEC  aucun palier à", PRICE_EUR, "€ pour l'app")
else:
    already = any(x.get("relationships", {}).get("appPricePoint", {}).get("data", {}).get("id") == point["id"] for x in have)
    if already:
        print(f"ok     prix de l'app {PRICE_EUR} € (déjà en place)")
    else:
        step(f"prix de l'app {PRICE_EUR} € (base France)", call("POST", "/v1/appPriceSchedules", {
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "FRA"}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${prix}"}]}}},
            "included": [{"type": "appPrices", "id": "${prix}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": point["id"]}}}}]}))

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
             "attributes": {"name": "Clapet interne", "isInternalGroup": True, "hasAccessToAllBuilds": True},
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
        step(f"build ajouté au groupe « {a.get('name')} »",
             call("POST", f"/v1/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": bid}]}),
             tolerate=("already",))
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
