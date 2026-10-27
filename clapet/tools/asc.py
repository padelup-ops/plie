"""DUO FOLDS (projet Clapet) sur App Store Connect : fiche en anglais et en français, puis distribution TestFlight d'un build.

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
    "en-US": ["DUO FOLDS: Fold Counter", "DUO FOLDS - Fold Counter", "DUO FOLDS: Hinge Counter"],
    "fr-FR": ["DUO FOLDS : compteur de plis"],
}
SUBTITLE = {"en-US": "Keep your folds under control", "fr-FR": "Garde tes plis sous contrôle"}
KEYWORDS = {
    "en-US": "duo,fold,hinge,counter,foldable,widget,limit,habit,screen time,tracker,stats,digital wellbeing",
    "fr-FR": "duo,pli,charnière,compteur,pliable,widget,limite,habitude,temps d'écran,suivi,statistiques",
}
PROMO = {
    "en-US": "How many times a day do you open your Duo? Set a daily limit and keep an eye on your folds, right from your Home Screen.",
    "fr-FR": "Combien de fois par jour ouvres-tu ton Duo ? Fixe une limite et garde un œil sur tes plis, directement sur ton écran d'accueil.",
}
DESCRIPTION = {
    "en-US": """Every fold of your iPhone Duo is a glance at your phone. Duo Folds counts them, so you can see your habits and keep them under control.

Keep Duo Folds on screen, on the inner or the outer display: every time you close your Duo, it counts. Set a daily limit and watch the ring: mint while you're under it, yellow when you get close, pink when you're over.

FREE
• Folds and opens today, the last 7 days and your total
• A daily limit, and how many folds you have left
• Today hour by hour, and your hinge level
• The small Home Screen widget and the Lock Screen line
• A Shortcuts action, "Count a fold", to count from an automation

DUO FOLDS+ (one-time purchase, no subscription)
• Every widget: the big Health-style widget, the medium one and the Lock Screen ones
• Limit alerts: a notification at 80 % and at 100 % of your limit
• Your full history: 30 days, 12 months, the calendar of days under your limit, your trends and records
• Five widget colors
• Export your history as a spreadsheet (CSV)

Good to know: iOS only tells an app about the hinge while that app is on screen, so Duo Folds counts while it is open. Your numbers stay on your iPhone.""",
    "fr-FR": """Chaque pli de ton iPhone Duo, c'est un coup d'œil à ton téléphone. Duo Folds les compte, pour que tu voies tes habitudes et que tu les gardes sous contrôle.

Garde Duo Folds à l'écran, sur l'écran intérieur ou extérieur : chaque fois que tu fermes ton Duo, il compte. Fixe une limite par jour et regarde l'anneau : menthe tant que tu es en dessous, jaune quand tu t'en approches, rose quand tu la dépasses.

GRATUIT
• Fermetures et ouvertures du jour, les 7 derniers jours et ton total
• Une limite par jour, et combien de plis il te reste
• Ta journée heure par heure, et le niveau de ta charnière
• Le petit widget de l'écran d'accueil et la ligne de l'écran verrouillé
• Une action Raccourcis, « Compter un pli », pour compter depuis une automatisation

DUO FOLDS+ (achat unique, sans abonnement)
• Tous les widgets : le grand widget façon Santé, le moyen et ceux de l'écran verrouillé
• Les alertes de limite : une notification à 80 % et à 100 % de ta limite
• Tout l'historique : 30 jours, 12 mois, le calendrier des jours sous ta limite, tes tendances et tes records
• Cinq couleurs de widgets
• L'export de ton historique en tableur (CSV)

Bon à savoir : iOS ne prévient une app des mouvements de la charnière que quand elle est à l'écran ; Duo Folds compte donc tant qu'il est ouvert. Tes chiffres restent sur ton iPhone.""",
}
BETA_DESCRIPTION = {
    "en-US": "Duo Folds counts how many times you close and open your iPhone Duo, with a daily limit and widgets like the steps in Health.",
    "fr-FR": "Duo Folds compte combien de fois tu fermes et ouvres ton iPhone Duo, avec une limite par jour et des widgets comme les pas dans Santé.",
}
WHATS_NEW = {
    "en-US": """New in this build:

• The app is now called Duo Folds.
• A daily LIMIT instead of a goal: the ring turns yellow near your limit and pink above it.
• Duo Folds+ (one-time purchase): every widget, limit alerts, full history and records, widget colors, CSV export. In TestFlight the purchase is free (Apple's test mode). Settings > Test version > "Simulate Duo Folds+" shows both modes.
• Without Duo Folds+, the big widgets are blurred: tap them to see the offer.

Please test: does every fold count once? Do the widgets show the same numbers as the app? Does the purchase unlock the widgets right away?""",
    "fr-FR": """Nouveautés de ce build :

• L'app s'appelle maintenant Duo Folds.
• Une LIMITE par jour au lieu d'un objectif : l'anneau devient jaune près de la limite et rose au-dessus.
• Duo Folds+ (achat unique) : tous les widgets, alertes de limite, tout l'historique et les records, couleurs des widgets, export CSV. Dans TestFlight l'achat est gratuit (mode test d'Apple). Réglages > Version de test > « Simuler Duo Folds+ » montre les deux modes.
• Sans Duo Folds+, les grands widgets sont floutés : touche-les pour voir l'offre.

À tester : chaque pli compte-t-il une seule fois ? Les widgets affichent-ils les mêmes chiffres que l'app ? L'achat débloque-t-il les widgets tout de suite ?""",
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
                  {"data": [{"type": "betaTesters", "id": tid} for tid in missing]}), tolerate=("already",))
    if not g["attributes"].get("hasAccessToAllBuilds"):
        step(f"build ajouté au groupe « {g['attributes']['name']} »",
             call("POST", f"/v1/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": bid}]}),
             tolerate=("already",))
    count = len(call("GET", f"/v1/betaGroups/{g['id']}/betaTesters?limit=200").get("data", []))
    print(f"groupe « {g['attributes']['name']} » (interne) : {count} testeur(s)")

detail = call("GET", f"/v1/builds/{bid}/buildBetaDetail").get("data", {})
print("état pour les testeurs internes :", detail.get("attributes", {}).get("internalBuildState"))
print("\nBUILD DISTRIBUÉ" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
