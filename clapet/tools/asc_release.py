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
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from listing import SHOT_LANG, WHATS_NEW_103  # noqa: E402
LOCALES = SHOT_LANG
REVIEW_NOTES = (
    "Foldly counts how many times a foldable iPhone (iPhone Duo) is closed and opened, so people can keep that habit under control.\n\n"
    "On an iPhone Duo: keep Foldly on screen and fold the device. The app reads the hinge (SwiftUI onHingeChange) and "
    "the count goes up; the ring turns orange near the daily limit and red above it.\n"
    "On a device without a hinge (like an iPad): tap the hinge drawing on the main screen to add a fold.\n\n"
    "Optional automatic counting: the app's Shortcuts action \"Count a fold\" can be added to the personal automation "
    "\"When iPhone is Closed\" (Shortcuts > Automation). The app shows these steps under \"Count even when the app is closed\".\n\n"
    "Following Guideline 5.2.5, the app was renamed from DUO FOLDS to Foldly: the Apple product name is no longer used "
    "in the app name, the name shown on the device or the metadata.\n\n"
    "Free app with one optional in-app purchase, Foldly+ (non-consumable, com.padelup.clapet.plus). Open it from the \"Plus\" "
    "button at the top of the main screen, or tap a locked widget or the full history. It unlocks the medium, large and Lock Screen "
    "widgets, limit alerts, the full history and records, widget colors and CSV export. Restore Purchases is on the same screen "
    "and in Settings. Foldly+ also adds \"Why you open it\": right after the Duo is unfolded, a card asks why in one tap (it can be dismissed and goes away by itself), and the answers are summed up at the top of History. People who bought the paid version 1.0 keep everything without paying again. No account, no ads, no data collection. "
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
        point = next((p for p in page.get("data", []) if float(p["attributes"].get("customerPrice") or -1) == float(PRICE_EUR)), None)
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
APP_NOTES = {
    "com.padelup.foldboard": {
        "1.0.4": {
            "en-US": "The biggest update yet!\n• Trackpad: hold the space bar, the letters fade and you move the cursor anywhere, up and down too, like on Apple's keyboard.\n• Keyboard in the middle: a new button puts the keyboard in the middle for two hands, and Foldboard learns when you like it there.\n• Duo open in portrait: a bigger full keyboard, with large keys like Apple's.\n• New Swedish layout (å, ö, ä).\n• Shows what it learns: \"Noted\" when you correct it, milestones of learned habits, and a \"Your keyboard is learning\" card in the app.\n• Reminders before your free trial ends.\n• Glass theme: see-through keys.\n• New icon, and better key detection near the edges.",
            "fr-FR": "La plus grosse mise à jour !\n• Pavé tactile : garde le doigt sur la barre d'espace, les lettres s'effacent et tu déplaces le curseur partout, en haut et en bas aussi, comme sur le clavier d'Apple.\n• Clavier au milieu : un nouveau bouton le met au milieu pour écrire à deux mains, et Foldboard apprend quand tu le préfères là.\n• Duo ouvert en portrait : un clavier entier plus grand, avec de grandes touches comme celui d'Apple.\n• Nouvelle disposition suédoise (å, ö, ä).\n• Il montre ce qu'il apprend : « Noté » quand tu le corriges, des paliers d'habitudes apprises et une carte « Ton clavier apprend » dans l'app.\n• Des rappels avant la fin de l'essai gratuit.\n• Thème Verre : des touches translucides.\n• Nouvelle icône, et touches mieux reconnues près des bords.",
        },
        "1.0.5": {
            "en-US": "The biggest update yet!\n• New guide: every keyboard button explained, and how to teach it where you want it.\n• Trackpad: hold the space bar, the letters fade and you move the cursor anywhere, up and down too, like on Apple's keyboard.\n• Keyboard in the middle: a new button puts the keyboard in the middle for two hands, and Foldboard learns when you like it there.\n• Duo open in portrait: a bigger full keyboard, with large keys like Apple's.\n• New Swedish layout (å, ö, ä).\n• Shows what it learns: \"Noted\" when you correct it, milestones of learned habits, and a \"Your keyboard is learning\" card in the app.\n• Reminders before your free trial ends.\n• Glass theme: see-through keys.\n• New icon, and better key detection near the edges.",
            "fr-FR": "La plus grosse mise à jour !\n• Nouveau guide : chaque bouton du clavier expliqué, et comment lui apprendre où tu le veux.\n• Pavé tactile : garde le doigt sur la barre d'espace, les lettres s'effacent et tu déplaces le curseur partout, en haut et en bas aussi, comme sur le clavier d'Apple.\n• Clavier au milieu : un nouveau bouton le met au milieu pour écrire à deux mains, et Foldboard apprend quand tu le préfères là.\n• Duo ouvert en portrait : un clavier entier plus grand, avec de grandes touches comme celui d'Apple.\n• Nouvelle disposition suédoise (å, ö, ä).\n• Il montre ce qu'il apprend : « Noté » quand tu le corriges, des paliers d'habitudes apprises et une carte « Ton clavier apprend » dans l'app.\n• Des rappels avant la fin de l'essai gratuit.\n• Thème Verre : des touches translucides.\n• Nouvelle icône, et touches mieux reconnues près des bords.",
        },
        "1.0.12": {
            "en-US": "• New: clipboard. What you copy in any app is kept on your iPhone (never sent anywhere): open it with the clipboard button at the top of the keyboard, pin what you want to keep, and paste with one tap. Something you just copied also shows up in the suggestion bar.\n• Space-bar trackpad: much more precise. Move slowly to go letter by letter, faster to jump further, and lines only change when you really move up or down.\n• Double space only adds a period when you tap space twice quickly.\n• Teach your thumbs in 30 seconds: type a sentence with each thumb and the keyboard follows your hand right away. Available anytime from the app.\n• Better hand detection: the size of each touch is now one more clue.\n• Your iPhone text replacements always work, even short ones, and your contacts' names are suggested and capitalized.\n• Accents in the order of your language (ä ö ü ß, á é í ó ú ñ, å ä ö), plus ž ł ğ ř and ° on 0.\n• French keyboard: type e then ’ for é, a then ’ for à (and ’ then e still works).\n• The space before a period or comma is removed automatically.\n• One-handed: the globe, emoji, settings and hide buttons next to the keyboard no longer move it to the other side. The period now sits on your thumb's side of the space bar.\n• Smarter autocorrect for every word: swapped letters (mainteannt → maintenant), a key next to the right one (courznt → courant), an extra or a missing letter (pourqoi → pourquoi), and short words (fe → de). its becomes it’s when it should (its great → it’s great, on its own stays).\n• More accurate slide to type: the keyboard now checks every turn of your path and its length, so long words like bonjour are no longer mistaken for shorter ones.",
            "fr-FR": "• Nouveau : presse-papier. Ce que tu copies dans n'importe quelle app est gardé sur ton iPhone (jamais envoyé) : ouvre-le avec le bouton presse-papier en haut du clavier, épingle ce que tu veux garder et colle d'un appui. Ce que tu viens de copier apparaît aussi dans la barre de suggestions.\n• Pavé tactile de la barre d'espace bien plus précis : lentement, lettre par lettre ; plus vite, ça va plus loin. On ne change de ligne qu'en montant ou descendant franchement.\n• Le double espace n'ajoute un point que si tu tapes deux espaces coup sur coup.\n• Apprends-lui tes pouces en 30 secondes : tape une phrase avec chaque pouce et le clavier suit ta main tout de suite. Disponible à tout moment dans l'app.\n• Meilleure détection de la main : la taille de chaque appui devient un indice de plus.\n• Tes remplacements de texte de l'iPhone marchent toujours, même courts, et les prénoms de tes contacts sont proposés avec leur majuscule.\n• Les accents dans l'ordre de ta langue (ä ö ü ß, á é í ó ú ñ, å ä ö), plus ž ł ğ ř et ° sur le 0.\n• Clavier français : e puis ’ donne é, a puis ’ donne à (et ’ puis e marche toujours).\n• L'espace avant un point ou une virgule disparaît toute seule.\n• À une main : les boutons globe, emoji, réglages et masquer à côté du clavier ne le font plus changer de côté. Le point passe du côté de ton pouce, à côté de l'espace.\n• Une correction automatique plus intelligente, sur tous les mots : lettres inversées (mainteannt → maintenant), touche voisine (courznt → courant), lettre en trop ou oubliée (pourqoi → pourquoi), et mots courts (fe → de). En anglais, its devient it’s quand il le faut.\n• Écrire en glissant plus précis : le clavier vérifie chaque virage de ton tracé et sa longueur, un mot long comme bonjour n'est plus pris pour un mot plus court."
        },
        "1.0.11": {
            "en-US": "• Teach your thumbs in 30 seconds: type a sentence with each thumb and the keyboard follows your hand right away. Available anytime from the app.\n• Better hand detection: the size of each touch is now one more clue.\n• Your iPhone text replacements always work, even short ones, and your contacts' names are suggested and capitalized.\n• Accents in the order of your language (ä ö ü ß, á é í ó ú ñ, å ä ö), plus ž ł ğ ř and ° on 0.\n• French keyboard: type e then ’ for é, a then ’ for à (and ’ then e still works).\n• The space before a period or comma is removed automatically.\n• One-handed: the globe, emoji, settings and hide buttons next to the keyboard no longer move it to the other side. The period now sits on your thumb's side of the space bar.\n• Smarter autocorrect for every word: swapped letters (mainteannt → maintenant), a key next to the right one (courznt → courant), an extra or a missing letter (pourqoi → pourquoi), and short words (fe → de). its becomes it’s when it should (its great → it’s great, on its own stays).\n• More accurate slide to type: the keyboard now checks every turn of your path and its length, so long words like bonjour are no longer mistaken for shorter ones.",
            "fr-FR": "• Apprends-lui tes pouces en 30 secondes : tape une phrase avec chaque pouce et le clavier suit ta main tout de suite. Disponible à tout moment dans l'app.\n• Meilleure détection de la main : la taille de chaque appui devient un indice de plus.\n• Tes remplacements de texte de l'iPhone marchent toujours, même courts, et les prénoms de tes contacts sont proposés avec leur majuscule.\n• Les accents dans l'ordre de ta langue (ä ö ü ß, á é í ó ú ñ, å ä ö), plus ž ł ğ ř et ° sur le 0.\n• Clavier français : e puis ’ donne é, a puis ’ donne à (et ’ puis e marche toujours).\n• L'espace avant un point ou une virgule disparaît toute seule.\n• À une main : les boutons globe, emoji, réglages et masquer à côté du clavier ne le font plus changer de côté. Le point passe du côté de ton pouce, à côté de l'espace.\n• Une correction automatique plus intelligente, sur tous les mots : lettres inversées (mainteannt → maintenant), touche voisine (courznt → courant), lettre en trop ou oubliée (pourqoi → pourquoi), et mots courts (fe → de). En anglais, its devient it’s quand il le faut.\n• Écrire en glissant plus précis : le clavier vérifie chaque virage de ton tracé et sa longueur, un mot long comme bonjour n'est plus pris pour un mot plus court."
        },
        "1.0.10": {
            "en-US": "The biggest update yet:\n• Smarter hand detection: the keyboard now combines how you hold the phone, where your thumb lands and how the phone moves when you tap, and shows how often it picks the right side.\n• Slide to type: glide your finger from letter to letter, like Apple's keyboard, with precise word matching.\n• Space-bar trackpad: the cursor now follows your finger in every direction, like on Apple's keyboard.\n• One-handed on the open Duo: the suggestion bar stays above the keyboard, within reach of your thumb.\n• Long-press the period for the apostrophe and the comma.\n• New language model: corrections and suggestions that follow your sentence, and the next word after a space.\n• Corrections use where your finger landed, and only fix real typos. It learns your words.\n• Forgotten apostrophes and accents (dont → don't), missing spaces, English and French mixed.\n• Follow-your-hand starts again on its own after you use the arrows.\n• Option to follow your hand on the open Duo in landscape. Split keyboard: V on both halves.",
            "fr-FR": "La plus grosse mise à jour :\n• Détection de la main plus intelligente : le clavier combine la façon dont tu tiens le téléphone, où ton pouce tombe sur les touches et comment le téléphone bouge quand tu tapes, et t'affiche à quel point il choisit le bon côté.\n• Écrire en glissant : fais glisser ton doigt de lettre en lettre, comme sur le clavier d'Apple, avec une reconnaissance précise des mots.\n• Pavé tactile de la barre d'espace : le curseur suit ton doigt dans tous les sens, comme sur le clavier d'Apple.\n• Duo ouvert à une main : la barre de suggestions reste au-dessus du clavier, à portée du pouce.\n• Appui long sur le point pour l'apostrophe et la virgule.\n• Nouveau modèle de langue : des corrections et suggestions qui suivent ta phrase, et le mot suivant après une espace.\n• La correction tient compte de l'endroit où ton doigt s'est posé et apprend tes mots.\n• Accents et apostrophes oubliés (ca → ça, jai → j'ai), espaces oubliées, français et anglais mélangés, touche ’ pour les accents.\n• Suivre ta main reprend tout seul après les flèches.\n• Option pour suivre ta main sur le Duo ouvert en paysage. Clavier coupé : le V des deux côtés."
        },
        "1.0.9": {
            "en-US": "The biggest update yet:\n• Slide to type: glide your finger from letter to letter, like Apple's keyboard, with precise word matching.\n• Space-bar trackpad: the cursor now follows your finger in every direction, like on Apple's keyboard.\n• One-handed on the open Duo: the suggestion bar stays above the keyboard, within reach of your thumb.\n• Long-press the period for the apostrophe and the comma.\n• New language model: corrections and suggestions that follow your sentence, and the next word after a space.\n• Corrections use where your finger landed, and only fix real typos. It learns your words.\n• Forgotten apostrophes and accents (dont → don't), missing spaces, English and French mixed.\n• Follow-your-hand starts again on its own after you use the arrows.\n• Option to follow your hand on the open Duo in landscape. Split keyboard: V on both halves.",
            "fr-FR": "La plus grosse mise à jour :\n• Écrire en glissant : fais glisser ton doigt de lettre en lettre, comme sur le clavier d'Apple, avec une reconnaissance précise des mots.\n• Pavé tactile de la barre d'espace : le curseur suit ton doigt dans tous les sens, comme sur le clavier d'Apple.\n• Duo ouvert à une main : la barre de suggestions reste au-dessus du clavier, à portée du pouce.\n• Appui long sur le point pour l'apostrophe et la virgule.\n• Nouveau modèle de langue : des corrections et suggestions qui suivent ta phrase, et le mot suivant après une espace.\n• La correction tient compte de l'endroit où ton doigt s'est posé et apprend tes mots.\n• Accents et apostrophes oubliés (ca → ça, jai → j'ai), espaces oubliées, français et anglais mélangés, touche ’ pour les accents.\n• Suivre ta main reprend tout seul après les flèches.\n• Option pour suivre ta main sur le Duo ouvert en paysage. Clavier coupé : le V des deux côtés."
        },
        "1.0.8": {
            "en-US": "The biggest update yet:\n• Slide to type: glide your finger from letter to letter, like Apple's keyboard.\n• One-handed on the open Duo: the suggestion bar stays above the keyboard, within reach of your thumb.\n• Long-press the period for the apostrophe and the comma.\n• New language model: corrections and suggestions that follow your sentence, and the next word after a space.\n• Corrections use where your finger landed, and only fix real typos. It learns your words.\n• Forgotten apostrophes and accents (dont → don't), missing spaces, English and French mixed.\n• Follow-your-hand starts again on its own after you use the arrows.\n• Option to follow your hand on the open Duo in landscape. Split keyboard: V on both halves.",
            "fr-FR": "La plus grosse mise à jour :\n• Écrire en glissant : fais glisser ton doigt de lettre en lettre, comme sur le clavier d'Apple.\n• Duo ouvert à une main : la barre de suggestions reste au-dessus du clavier, à portée du pouce.\n• Appui long sur le point pour l'apostrophe et la virgule.\n• Nouveau modèle de langue : des corrections et suggestions qui suivent ta phrase, et le mot suivant après une espace.\n• La correction tient compte de l'endroit où ton doigt s'est posé et apprend tes mots.\n• Accents et apostrophes oubliés (ca → ça, jai → j'ai), espaces oubliées, français et anglais mélangés, touche ’ pour les accents.\n• Suivre ta main reprend tout seul après les flèches.\n• Option pour suivre ta main sur le Duo ouvert en paysage. Clavier coupé : le V des deux côtés."
        },
        "1.0.7": {
            "en-US": "Smarter typing, like Apple's keyboard:\n• New language model: much better corrections and suggestions that follow your sentence, and the next word in the bar after a space.\n• Corrections use where your finger actually landed, and only fix real typos.\n• Learns your own words and the way you write.\n• Forgotten apostrophes and accents: dont → don't, im → I'm, ca → ça.\n• Missing space: \"helloworld\" → \"hello world\".\n• French and English mixed: English words are no longer \"corrected\" on a French keyboard.\n• Double space adds a period after quotes and emojis too.\n• Follow-your-hand: after you move it with the arrows, it starts following your hand again on its own.\n• Option to follow your hand on the open Duo in landscape.\n• Split keyboard: the V key on both halves, like Apple's.",
            "fr-FR": "Une frappe bien plus intelligente, comme le clavier d'Apple :\n• Nouveau modèle de langue : des corrections et des suggestions qui suivent ta phrase, et le mot suivant dans la barre après une espace.\n• La correction tient compte de l'endroit où ton doigt s'est posé, et ne corrige que les vraies fautes de frappe.\n• Il apprend tes mots et ta façon d'écrire.\n• Accents et apostrophes oubliés : ca → ça, apres → après, jai → j'ai, et « je vais a » → « je vais à ».\n• La touche ’ à droite du N sert d'accent : ’ puis e → é.\n• Espace oubliée : « bonjourtoi » → « bonjour toi ».\n• Français et anglais mélangés : les mots anglais ne sont plus « corrigés » en français.\n• Le double espace met un point aussi après un guillemet ou un emoji.\n• Suivre ta main : après un déplacement avec les flèches, le clavier se remet à suivre ta main tout seul.\n• Option pour suivre ta main sur le Duo ouvert en paysage.\n• Clavier coupé en deux : le V des deux côtés, comme chez Apple."
        },
        "1.0.6": {
            "en-US": "The biggest update yet!\n• New guide: every keyboard button explained, and how to teach it where you want it.\n• Trackpad: hold the space bar, the letters fade and you move the cursor anywhere, up and down too, like on Apple's keyboard.\n• Keyboard in the middle: a new button puts the keyboard in the middle for two hands, and Foldboard learns when you like it there.\n• Duo open in portrait: a bigger full keyboard, with large keys like Apple's.\n• Left-hand keyboard: the period moves to the other side of the space bar, so typing is mirrored.\n• New Swedish layout (å, ö, ä).\n• Shows what it learns: \"Noted\" when you correct it, milestones of learned habits, and a \"Your keyboard is learning\" card in the app.\n• Reminders before your free trial ends.\n• Glass theme: see-through keys.\n• New icon, and better key detection near the edges.",
            "fr-FR": "La plus grosse mise à jour !\n• Nouveau guide : chaque bouton du clavier expliqué, et comment lui apprendre où tu le veux.\n• Pavé tactile : garde le doigt sur la barre d'espace, les lettres s'effacent et tu déplaces le curseur partout, en haut et en bas aussi, comme sur le clavier d'Apple.\n• Clavier au milieu : un nouveau bouton le met au milieu pour écrire à deux mains, et Foldboard apprend quand tu le préfères là.\n• Duo ouvert en portrait : un clavier entier plus grand, avec de grandes touches comme celui d'Apple.\n• Clavier à gauche : le point passe de l'autre côté de l'espace, la frappe est en miroir.\n• Nouvelle disposition suédoise (å, ö, ä).\n• Il montre ce qu'il apprend : « Noté » quand tu le corriges, des paliers d'habitudes apprises et une carte « Ton clavier apprend » dans l'app.\n• Des rappels avant la fin de l'essai gratuit.\n• Thème Verre : des touches translucides.\n• Nouvelle icône, et touches mieux reconnues près des bords.",
        },
    },
}

RELEASE_NOTES = {
    "1.0.3": WHATS_NEW_103,
    "1.0.4": {
        "en-US": "• Foldly+ is now available: every widget, limit alerts, your full history, widget colors and CSV export, in one purchase.\n• Fixes and improvements.",
        "fr-FR": "• Foldly+ est maintenant disponible : tous les widgets, les alertes de limite, tout l'historique, les couleurs des widgets et l'export CSV, en un seul achat.\n• Corrections et améliorations.",
        "de-DE": "• Foldly+ ist jetzt verfügbar: alle Widgets, Limit-Hinweise, dein ganzer Verlauf, Widget-Farben und CSV-Export, mit einem einzigen Kauf.\n• Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• Foldly+ ya está disponible: todos los widgets, avisos de límite, todo tu historial, colores de widgets y exportación CSV, en una sola compra.\n• Correcciones y mejoras.",
        "ja": "• Foldly+が利用可能になりました：すべてのウィジェット、上限の通知、全履歴、ウィジェットの色、CSV書き出しを一度の購入で。\n• 不具合の修正と改善。",
        "ko": "• 이제 Foldly+를 이용할 수 있습니다: 모든 위젯, 한도 알림, 전체 기록, 위젯 색상, CSV 내보내기를 한 번의 구입으로.\n• 버그 수정 및 개선.",
        "zh-Hans": "• Foldly+ 现已推出：所有小组件、限额提醒、完整历史、小组件颜色和 CSV 导出，一次购买即可。\n• 问题修复和改进。",
    },
    "1.0.5": {
        "en-US": "• New with Foldly+: Why you open it. When you unfold your Duo, answer in one tap (a notification, boredom, work or someone) and see the real reasons behind your opens in your history.\n• Fixed: a single fold could sometimes be counted twice when you closed your phone with Foldly on screen. Thanks to everyone who reported it!",
        "fr-FR": "• Nouveau avec Foldly+ : Pourquoi tu l'ouvres. Quand tu déplies ton Duo, réponds en un toucher (une notif, l'ennui, le boulot ou quelqu'un) et découvre dans l'historique la vraie raison de tes ouvertures.\n• Corrigé : un même pli pouvait parfois être compté deux fois quand tu fermais ton téléphone avec Foldly à l'écran. Merci à ceux qui l'ont signalé !",
        "de-DE": "• Neu mit Foldly+: Warum du es öffnest. Beim Aufklappen deines Duo antwortest du mit einem Tippen (Mitteilung, Langeweile, Arbeit oder jemand) und siehst im Verlauf die wahren Gründe für deine Öffnungen.\n• Behoben: Ein einzelnes Falten wurde manchmal doppelt gezählt, wenn du dein Telefon mit Foldly auf dem Bildschirm geschlossen hast. Danke für eure Hinweise!",
        "es-ES": "• Nuevo con Foldly+: Por qué lo abres. Al desplegar tu Duo, responde con un toque (una notificación, aburrimiento, trabajo o alguien) y descubre en el historial las verdaderas razones de tus aperturas.\n• Corregido: un mismo pliegue a veces se contaba dos veces al cerrar el teléfono con Foldly en pantalla. ¡Gracias a quienes lo avisasteis!",
        "ja": "• Foldly+の新機能「開く理由」：Duoを開いたら1タップで答える（通知、退屈、仕事、誰か）と、開く本当の理由が履歴でわかります。\n• 修正：Foldlyを表示したまま閉じたとき、1回の折りたたみが2回数えられることがある問題を修正しました。ご報告ありがとうございました！",
        "ko": "• Foldly+ 새 기능 '여는 이유': Duo를 펼칠 때 한 번 탭으로 답하면(알림, 심심해서, 일, 누군가) 기록에서 여는 진짜 이유를 볼 수 있어요.\n• 수정: Foldly를 화면에 띄운 채 휴대폰을 닫으면 한 번 접은 것이 가끔 두 번 세어지던 문제를 고쳤어요. 알려 주셔서 감사합니다!",
        "zh-Hans": "• Foldly+ 新功能“打开的原因”：展开 Duo 时轻点一下回答（通知、无聊、工作或某个人），在历史中看清你打开手机的真正原因。\n• 已修复：在 Foldly 显示时合上手机，一次折叠有时会被计为两次。感谢所有反馈的朋友！",
    },
    "1.0.6": {
        "en-US": "• Fixed: on the outer screen with the Modern look, the fold count could be cut to “…” (especially with a larger display setting). The hinge gauge now moves under the number when space is tight. Thanks Matthew for reporting it!",
        "fr-FR": "• Corrigé : sur l'écran extérieur avec le look Moderne, le nombre de plis pouvait être coupé en « … » (surtout avec un affichage agrandi). La jauge de la charnière passe maintenant sous le nombre quand la place manque. Merci à Matthew pour le signalement !",
        "de-DE": "• Behoben: Auf dem Außendisplay im Look Modern konnte die Anzahl der Faltungen zu „…“ abgeschnitten werden (vor allem mit vergrößerter Anzeige). Die Scharnieranzeige rückt jetzt unter die Zahl, wenn der Platz knapp ist. Danke für den Hinweis!",
        "es-ES": "• Corregido: en la pantalla exterior con el aspecto Moderno, el número de pliegues podía cortarse en «…» (sobre todo con la pantalla ampliada). Ahora el indicador de la bisagra se coloca debajo del número cuando falta espacio. ¡Gracias por avisar!",
        "ja": "• 修正：外側の画面でモダンの見た目のとき、折りたたみ回数が「…」と切れて表示されることがある問題（特に画面表示を拡大している場合）。スペースが足りないときは、ヒンジのゲージが数字の下に移動します。ご報告ありがとうございました！",
        "ko": "• 수정: 바깥 화면에서 모던 모양을 쓸 때 접은 횟수가 “…”로 잘려 보일 수 있던 문제(특히 화면 확대 설정 시). 이제 공간이 부족하면 힌지 게이지가 숫자 아래로 이동해요. 알려 주셔서 감사합니다!",
        "zh-Hans": "• 已修复：在外屏使用“现代”外观时，折叠次数可能被截断为“…”（尤其是放大显示时）。现在空间不足时，铰链仪表会移到数字下方。感谢反馈！",
    },
    "1.0.7": {
        "en-US": "• Bring your past stats: in Adjust the count, import a file from Scriptable, a shortcut or another app (CSV, text or JSON), or add past days by hand. Your history keeps each day.\n• Foldly+ is at its launch price until November 13: pay once, keep it for life.\n• After 3 days, Foldly sums up your first folds and your peak hour.\n• You can now buy Foldly+ straight from the App Store page.\n• Small fixes and improvements.",
        "fr-FR": "• Reprends tes anciennes stats : dans Corriger le compteur, importe un fichier de Scriptable, d'un raccourci ou d'une autre app (CSV, texte ou JSON), ou ajoute des jours à la main. L'historique garde chaque jour.\n• Foldly+ est à son prix de lancement jusqu'au 13 novembre : un seul achat, à vie.\n• Après 3 jours, Foldly résume tes premiers plis et ton heure de pointe.\n• Tu peux maintenant acheter Foldly+ directement depuis la fiche App Store.\n• Petites corrections et améliorations.",
        "de-DE": "• Übernimm deine alten Daten: Füge unter „Zähler anpassen“ die Tage vor Foldly hinzu (Faltungen und Aufklappen) sowie deine Gesamtzahl an Aufklappvorgängen.\n• Foldly+ gibt es bis 13. November zum Einführungspreis: einmal kaufen, für immer behalten.\n• Nach 3 Tagen fasst Foldly deine ersten Faltungen und deine Spitzenzeit zusammen.\n• Du kannst Foldly+ jetzt direkt auf der App Store-Seite kaufen.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• Trae tus estadísticas anteriores: en Ajustar el contador, añade los días que registraste antes de Foldly (pliegues y aperturas) y tu total de aperturas.\n• Foldly+ tiene precio de lanzamiento hasta el 13 de noviembre: un solo pago, para siempre.\n• Tras 3 días, Foldly resume tus primeros pliegues y tu hora pico.\n• Ahora puedes comprar Foldly+ directamente desde la página del App Store.\n• Pequeñas correcciones y mejoras.",
        "ja": "• 以前の記録を取り込めます：「回数を修正」で、Foldly以前に記録した日（折りたたみ・開いた回数）と、開いた回数の合計を追加できます。\n• Foldly+は11月13日までリリース記念価格：一度の購入でずっと使えます。\n• 3日後、最初の折りたたみ回数とピークの時間をまとめてお見せします。\n• App StoreのページからFoldly+を直接購入できるようになりました。\n• 細かな修正と改善。",
        "ko": "• 예전 기록 가져오기: '횟수 조정'에서 Foldly 이전에 기록한 날(접힘·펼침)과 전체 펼친 횟수를 추가할 수 있어요.\n• Foldly+를 11월 13일까지 출시 기념 가격으로: 한 번 구입으로 평생 사용.\n• 3일이 지나면 처음 접은 횟수와 가장 많이 접는 시간을 정리해 드려요.\n• 이제 App Store 페이지에서 바로 Foldly+를 구입할 수 있어요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• 导入以前的数据：在“调整计数”中添加使用 Foldly 之前记录的日子（折叠和展开），以及展开总次数。\n• Foldly+ 首发价至 11 月 13 日：一次购买，永久使用。\n• 使用 3 天后，Foldly 会总结你最初的折叠次数和高峰时段。\n• 现在可以直接在 App Store 页面购买 Foldly+。\n• 小问题修复和改进。",
    },
    "1.0.8": {
        "en-US": "• New in Foldly+: Your sessions. See how long your Duo stays open each time: your average session, short vs long sessions, your longest one, weekdays vs weekends, and how much of your waking day you spend unfolded. Thanks BraXzy for the idea!\n• Small fixes and improvements.",
        "fr-FR": "• Nouveau dans Foldly+ : Tes sessions. Combien de temps ton Duo reste ouvert à chaque fois : ta session moyenne, les courtes et les longues, la plus longue, la semaine contre le week-end, et la part de ta journée passée déplié. Merci BraXzy pour l'idée !\n• Petites corrections et améliorations.",
        "de-DE": "• Neu in Foldly+: Deine Sitzungen. Wie lange dein Duo jedes Mal offen bleibt: deine durchschnittliche Sitzung, kurze und lange Sitzungen, die längste, Wochentage gegen Wochenende und wie viel deines wachen Tages du aufgeklappt verbringst.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• Nuevo en Foldly+: Tus sesiones. Cuánto tiempo sigue abierto tu Duo cada vez: tu sesión media, sesiones cortas y largas, la más larga, entre semana frente a fin de semana, y cuánto de tu día pasas con él desplegado.\n• Pequeñas correcciones y mejoras.",
        "ja": "• Foldly+の新機能「セッション」：Duoを開くたびに開いている時間を表示。平均時間、短い／長いセッション、最長記録、平日と週末の比較、起きている時間のうち開いていた割合が分かります。\n• 細かな修正と改善。",
        "ko": "• Foldly+ 새 기능 ‘내 세션’: Duo를 펼칠 때마다 열려 있는 시간을 보여 줘요. 평균 세션, 짧은/긴 세션, 가장 긴 세션, 평일과 주말 비교, 깨어 있는 시간 중 펼친 비율까지.\n• 작은 수정 및 개선.",
        "zh-Hans": "• Foldly+ 新功能“你的使用时段”：查看 Duo 每次展开多久——平均时长、短时段与长时段、最长一次、工作日与周末对比，以及清醒时间中展开的比例。\n• 小问题修复和改进。",
    },
    "1.0.9": {
        "en-US": "• New in Foldly+: Your sessions. See how long your Duo stays open each time: your average session, short vs long sessions, your longest one, weekdays vs weekends, and how much of your waking day you spend unfolded. Thanks BraXzy for the idea!\n• A calmer, cleaner look: simpler titles, line icons instead of emoji, and shorter durations in Your sessions so everything fits.\n• Small fixes and improvements.",
        "fr-FR": "• Nouveau dans Foldly+ : Tes sessions. Combien de temps ton Duo reste ouvert à chaque fois : ta session moyenne, les courtes et les longues, la plus longue, la semaine contre le week-end, et la part de ta journée passée déplié. Merci BraXzy pour l'idée !\n• Un design plus calme et plus net : des titres plus simples, des icônes à la place des emojis, et des durées plus courtes dans Tes sessions pour que tout tienne.\n• Petites corrections et améliorations.",
        "de-DE": "• Neu in Foldly+: Deine Sitzungen. Wie lange dein Duo jedes Mal offen bleibt: deine durchschnittliche Sitzung, kurze und lange Sitzungen, die längste, Wochentage gegen Wochenende und wie viel deines wachen Tages du aufgeklappt verbringst.\n• Ein ruhigeres, klareres Design: einfachere Titel, Symbole statt Emojis und kürzere Zeitangaben in Deine Sitzungen, damit alles passt.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• Nuevo en Foldly+: Tus sesiones. Cuánto tiempo sigue abierto tu Duo cada vez: tu sesión media, sesiones cortas y largas, la más larga, entre semana frente a fin de semana, y cuánto de tu día pasas con él desplegado.\n• Un diseño más tranquilo y limpio: títulos más sencillos, iconos en lugar de emojis y duraciones más cortas en Tus sesiones para que todo quepa.\n• Pequeñas correcciones y mejoras.",
        "ja": "• Foldly+の新機能「セッション」：Duoを開くたびに開いている時間を表示。平均時間、短い／長いセッション、最長記録、平日と週末の比較、起きている時間のうち開いていた割合が分かります。\n• より落ち着いたすっきりデザインに：シンプルな見出し、絵文字の代わりにアイコン、セッションの時間表示を短くしました。\n• 細かな修正と改善。",
        "ko": "• Foldly+ 새 기능 ‘내 세션’: Duo를 펼칠 때마다 열려 있는 시간을 보여 줘요. 평균 세션, 짧은/긴 세션, 가장 긴 세션, 평일과 주말 비교, 깨어 있는 시간 중 펼친 비율까지.\n• 더 차분하고 깔끔한 디자인: 단순해진 제목, 이모지 대신 아이콘, ‘내 세션’의 더 짧은 시간 표시.\n• 작은 수정 및 개선.",
        "zh-Hans": "• Foldly+ 新功能“你的使用时段”：查看 Duo 每次展开多久——平均时长、短时段与长时段、最长一次、工作日与周末对比，以及清醒时间中展开的比例。\n• 更安静、更清爽的设计：更简洁的标题、用图标代替表情符号，“你的使用时段”中的时长更简短。\n• 小问题修复和改进。",
    },
    "1.0.20": {
        "en-US": "• Thank you for 2,000 downloads: two new themes, Bento and Atelier! Move your cards wherever you want, hide the ones you don't need and pick your color. Included in Foldly+, or free for 3 days.\n• Ideas box: suggest what Foldly should do next and vote for the best ideas.\n• Better layout on the open Duo.",
        "fr-FR": "• Merci pour les 2 000 téléchargements : deux nouveaux thèmes, Bento et Atelier ! Déplace tes cartes où tu veux, cache celles qui ne te servent pas et choisis ta couleur. Inclus dans Foldly+, ou gratuits pendant 3 jours.\n• Boîte à idées : propose ce que Foldly devrait faire ensuite et vote pour les meilleures idées.\n• Meilleure disposition sur le Duo ouvert.",
        "de-DE": "• Danke für 2.000 Downloads: zwei neue Themen, Bento und Atelier! Verschiebe deine Karten, blende aus, was du nicht brauchst, und wähle deine Farbe. In Foldly+ enthalten oder 3 Tage gratis.\n• Ideenbox: Schlag vor, was Foldly als Nächstes können soll, und stimme für die besten Ideen.\n• Besseres Layout auf dem geöffneten Duo.",
        "es-ES": "• Gracias por las 2000 descargas: ¡dos temas nuevos, Bento y Atelier! Mueve tus tarjetas, oculta las que no uses y elige tu color. Incluidos en Foldly+, o gratis 3 días.\n• Buzón de ideas: propón lo próximo que debería hacer Foldly y vota las mejores ideas.\n• Mejor disposición con el Duo abierto.",
        "ja": "• 2,000ダウンロードの感謝を込めて、新テーマ「Bento」と「Atelier」！カードを自由に動かし、不要なものは隠して、色も選べます。Foldly+に含まれ、3日間無料でお試しできます。\n• アイデアボックス：Foldlyの次の機能を提案して、いいアイデアに投票しよう。\n• 開いたDuoでのレイアウトを改善。",
        "ko": "• 2,000 다운로드 감사 선물: 새 테마 Bento와 Atelier! 카드를 원하는 곳으로 옮기고, 필요 없는 카드는 숨기고, 색상을 고르세요. Foldly+에 포함, 또는 3일 무료 체험.\n• 아이디어 상자: Foldly가 다음에 할 일을 제안하고 최고의 아이디어에 투표하세요.\n• 펼친 Duo에서 더 나은 배치.",
        "zh-Hans": "• 感谢 2000 次下载：两款新主题 Bento 和 Atelier！卡片可随意移动、隐藏用不到的，还能挑选颜色。包含在 Foldly+ 中，或免费试用 3 天。\n• 想法箱：告诉我们 Foldly 接下来该做什么，并为最好的想法投票。\n• 展开 Duo 时布局更好。",
        "it": "• Grazie per i 2.000 download: due nuovi temi, Bento e Atelier! Sposta le schede dove vuoi, nascondi quelle che non ti servono e scegli il tuo colore. Inclusi in Foldly+, o gratis per 3 giorni.\n• Box delle idee: suggerisci cosa dovrebbe fare Foldly e vota le idee migliori.\n• Disposizione migliore con il Duo aperto.",
        "pt-BR": "• Obrigado pelos 2.000 downloads: dois temas novos, Bento e Atelier! Mova seus cartões, esconda os que não usa e escolha sua cor. Incluídos no Foldly+, ou grátis por 3 dias.\n• Caixa de ideias: sugira o que o Foldly deve fazer a seguir e vote nas melhores ideias.\n• Layout melhor com o Duo aberto.",
        "nl-NL": "• Bedankt voor 2.000 downloads: twee nieuwe thema’s, Bento en Atelier! Zet je kaarten waar je wilt, verberg wat je niet nodig hebt en kies je kleur. Inbegrepen in Foldly+, of 3 dagen gratis.\n• Ideeënbus: stel voor wat Foldly hierna moet doen en stem op de beste ideeën.\n• Betere indeling op de geopende Duo.",
        "ru": "• Спасибо за 2 000 загрузок: две новые темы, Bento и Atelier! Двигайте карточки куда угодно, скрывайте лишние и выбирайте цвет. Входят в Foldly+ или бесплатно 3 дня.\n• Ящик идей: предложите, что Foldly стоит сделать дальше, и голосуйте за лучшие идеи.\n• Улучшенная раскладка на открытом Duo."
    },
    "1.0.19": {
        "en-US": "• Founders: thank you for 2,000 downloads! Everyone who opens Foldly before December 1 gets the Founder badge and Gold 2K, an exclusive widget color.\n• Light widgets: widgets now follow your iPhone (light by day), or pick light or dark in Settings.\n• Medium and large widgets now show your all-time total, your last 7 days and when you'll reach your next milestone.\n• A simpler, nicer Settings screen.\n• Duo Pack: with Foldly+, get Foldboard Pro for €1.99 until November 30.\n• Automatic counting: a clear checklist when it doesn't count yet.",
        "fr-FR": "• Fondateurs : merci pour les 2 000 téléchargements ! Tous ceux qui ouvrent Foldly avant le 1er décembre reçoivent le badge Fondateur et l'Or 2K, une couleur de widget exclusive.\n• Widgets clairs : ils suivent ton iPhone (clairs en journée), ou choisis clair ou sombre dans les Réglages.\n• Les widgets moyen et grand affichent ton total, tes 7 derniers jours et quand tu atteindras ton prochain palier.\n• Des Réglages plus simples et plus beaux.\n• Pack Duo : avec Foldly+, Foldboard Pro à 1,99 € jusqu'au 30 novembre.\n• Comptage automatique : une liste claire à vérifier quand ça ne compte pas encore.",
        "de-DE": "• Gründer: Danke für 2.000 Downloads! Wer Foldly vor dem 1. Dezember öffnet, bekommt das Gründer-Abzeichen und Gold 2K, eine exklusive Widget-Farbe.\n• Helle Widgets: Sie folgen deinem iPhone (tagsüber hell), oder wähle hell oder dunkel in den Einstellungen.\n• Mittlere und große Widgets zeigen jetzt deine Gesamtzahl, die letzten 7 Tage und wann du den nächsten Meilenstein erreichst.\n• Einfachere, schönere Einstellungen.\n• Duo-Paket: Mit Foldly+ gibt es Foldboard Pro bis 30. November für 1,99 €.\n• Automatisches Zählen: eine klare Checkliste, wenn noch nichts gezählt wird.",
        "es-ES": "• Fundadores: ¡gracias por las 2000 descargas! Quien abra Foldly antes del 1 de diciembre recibe la insignia de Fundador y Oro 2K, un color de widget exclusivo.\n• Widgets claros: siguen a tu iPhone (claros de día), o elige claro u oscuro en Ajustes.\n• Los widgets mediano y grande muestran tu total, tus últimos 7 días y cuándo alcanzarás tu próxima meta.\n• Ajustes más simples y bonitos.\n• Pack Duo: con Foldly+, Foldboard Pro por 1,99 € hasta el 30 de noviembre.\n• Conteo automático: una lista clara para revisar si aún no cuenta.",
        "ja": "• ファウンダー：2,000ダウンロードありがとう！12月1日までにFoldlyを開いた方に、ファウンダーバッジと専用ウィジェットカラー「ゴールド2K」を。\n• ライトなウィジェット：iPhoneに合わせて昼は明るく。設定でライト／ダークも選べます。\n• 中・大サイズのウィジェットに、累計・直近7日間・次のマイルストーンまでの目安を表示。\n• よりシンプルで見やすい設定画面。\n• Duoパック：Foldly+をお持ちなら、11月30日までFoldboard Proが1.99ユーロ。\n• 自動カウント：まだカウントされないときの確認リストを追加。",
        "ko": "• 파운더: 다운로드 2,000회 감사합니다! 12월 1일 전에 Foldly를 연 모든 분께 파운더 배지와 전용 위젯 색상 골드 2K를 드려요.\n• 밝은 위젯: iPhone을 따라 낮에는 밝게, 설정에서 라이트/다크 선택도 가능해요.\n• 중간·큰 위젯에 누적, 최근 7일, 다음 목표까지 예상 기간을 표시해요.\n• 더 간단하고 보기 좋은 설정.\n• Duo 팩: Foldly+ 사용자는 11월 30일까지 Foldboard Pro를 1.99유로에.\n• 자동 카운트: 아직 세어지지 않을 때 확인할 목록을 추가했어요.",
        "zh-Hans": "• 创始用户：感谢 2000 次下载！12 月 1 日前打开 Foldly 的用户将获得创始用户徽章和专属小组件颜色「金色 2K」。\n• 浅色小组件：跟随 iPhone（白天浅色），也可在设置中选择浅色或深色。\n• 中号和大号小组件显示累计次数、最近 7 天以及达到下一个里程碑的预计时间。\n• 更简洁美观的设置页面。\n• Duo 套装：拥有 Foldly+，11 月 30 日前 Foldboard Pro 仅需 1.99 欧元。\n• 自动计数：尚未计数时提供清晰的检查清单。",
        "it": "• Fondatori: grazie per i 2.000 download! Chi apre Foldly prima del 1° dicembre riceve il badge Fondatore e Oro 2K, un colore dei widget esclusivo.\n• Widget chiari: seguono il tuo iPhone (chiari di giorno), oppure scegli chiaro o scuro nelle Impostazioni.\n• I widget medio e grande mostrano il totale, gli ultimi 7 giorni e quando raggiungerai il prossimo traguardo.\n• Impostazioni più semplici e belle.\n• Pack Duo: con Foldly+, Foldboard Pro a 1,99 € fino al 30 novembre.\n• Conteggio automatico: una lista chiara da controllare se non conta ancora.",
        "pt-BR": "• Fundadores: obrigado pelos 2.000 downloads! Quem abrir o Foldly antes de 1º de dezembro ganha o selo de Fundador e o Ouro 2K, uma cor de widget exclusiva.\n• Widgets claros: seguem o seu iPhone (claros de dia), ou escolha claro ou escuro nos Ajustes.\n• Os widgets médio e grande mostram seu total, os últimos 7 dias e quando você chegará ao próximo marco.\n• Ajustes mais simples e bonitos.\n• Pacote Duo: com o Foldly+, Foldboard Pro por 1,99 € até 30 de novembro.\n• Contagem automática: uma lista clara para conferir quando ainda não conta.",
        "nl-NL": "• Oprichters: bedankt voor 2.000 downloads! Wie Foldly vóór 1 december opent, krijgt de Oprichter-badge en Goud 2K, een exclusieve widgetkleur.\n• Lichte widgets: ze volgen je iPhone (overdag licht), of kies licht of donker in Instellingen.\n• De middelgrote en grote widgets tonen je totaal, je laatste 7 dagen en wanneer je je volgende mijlpaal haalt.\n• Eenvoudigere, mooiere instellingen.\n• Duo-pakket: met Foldly+ Foldboard Pro voor € 1,99 tot 30 november.\n• Automatisch tellen: een duidelijke checklist als er nog niets geteld wordt.",
        "ru": "• Основатели: спасибо за 2 000 загрузок! Все, кто откроет Foldly до 1 декабря, получат значок Основателя и Золото 2K — эксклюзивный цвет виджетов.\n• Светлые виджеты: они следуют за iPhone (днём светлые), или выберите светлые или тёмные в Настройках.\n• Средний и большой виджеты показывают общий итог, последние 7 дней и когда вы достигнете следующей отметки.\n• Более простые и красивые Настройки.\n• Пакет Duo: с Foldly+ — Foldboard Pro за 1,99 € до 30 ноября.\n• Автоматический подсчёт: понятный список проверок, если он ещё не работает."
    },
    "1.0.18": {
        "en-US": "• Founders: thank you for 2,000 downloads! Everyone who opens Foldly before December 1 gets the Founder badge and Gold 2K, an exclusive widget color.\n• Light widgets: widgets now follow your iPhone (light by day), or pick light or dark in Settings.\n• Medium and large widgets now show your all-time total, your last 7 days and when you'll reach your next milestone.\n• A simpler, nicer Settings screen.\n• Duo Pack: with Foldly+, get Foldboard Pro for €1.99 until November 30.",
        "fr-FR": "• Fondateurs : merci pour les 2 000 téléchargements ! Tous ceux qui ouvrent Foldly avant le 1er décembre reçoivent le badge Fondateur et l'Or 2K, une couleur de widget exclusive.\n• Widgets clairs : ils suivent ton iPhone (clairs en journée), ou choisis clair ou sombre dans les Réglages.\n• Les widgets moyen et grand affichent ton total, tes 7 derniers jours et quand tu atteindras ton prochain palier.\n• Des Réglages plus simples et plus beaux.\n• Pack Duo : avec Foldly+, Foldboard Pro à 1,99 € jusqu'au 30 novembre.",
        "de-DE": "• Gründer: Danke für 2.000 Downloads! Wer Foldly vor dem 1. Dezember öffnet, bekommt das Gründer-Abzeichen und Gold 2K, eine exklusive Widget-Farbe.\n• Helle Widgets: Sie folgen deinem iPhone (tagsüber hell), oder wähle hell oder dunkel in den Einstellungen.\n• Mittlere und große Widgets zeigen jetzt deine Gesamtzahl, die letzten 7 Tage und wann du den nächsten Meilenstein erreichst.\n• Einfachere, schönere Einstellungen.\n• Duo-Paket: Mit Foldly+ gibt es Foldboard Pro bis 30. November für 1,99 €.",
        "es-ES": "• Fundadores: ¡gracias por las 2000 descargas! Quien abra Foldly antes del 1 de diciembre recibe la insignia de Fundador y Oro 2K, un color de widget exclusivo.\n• Widgets claros: siguen a tu iPhone (claros de día), o elige claro u oscuro en Ajustes.\n• Los widgets mediano y grande muestran tu total, tus últimos 7 días y cuándo alcanzarás tu próxima meta.\n• Ajustes más simples y bonitos.\n• Pack Duo: con Foldly+, Foldboard Pro por 1,99 € hasta el 30 de noviembre.",
        "ja": "• ファウンダー：2,000ダウンロードありがとう！12月1日までにFoldlyを開いた方に、ファウンダーバッジと専用ウィジェットカラー「ゴールド2K」を。\n• ライトなウィジェット：iPhoneに合わせて昼は明るく。設定でライト／ダークも選べます。\n• 中・大サイズのウィジェットに、累計・直近7日間・次のマイルストーンまでの目安を表示。\n• よりシンプルで見やすい設定画面。\n• Duoパック：Foldly+をお持ちなら、11月30日までFoldboard Proが1.99ユーロ。",
        "ko": "• 파운더: 다운로드 2,000회 감사합니다! 12월 1일 전에 Foldly를 연 모든 분께 파운더 배지와 전용 위젯 색상 골드 2K를 드려요.\n• 밝은 위젯: iPhone을 따라 낮에는 밝게, 설정에서 라이트/다크 선택도 가능해요.\n• 중간·큰 위젯에 누적, 최근 7일, 다음 목표까지 예상 기간을 표시해요.\n• 더 간단하고 보기 좋은 설정.\n• Duo 팩: Foldly+ 사용자는 11월 30일까지 Foldboard Pro를 1.99유로에.",
        "zh-Hans": "• 创始用户：感谢 2000 次下载！12 月 1 日前打开 Foldly 的用户将获得创始用户徽章和专属小组件颜色「金色 2K」。\n• 浅色小组件：跟随 iPhone（白天浅色），也可在设置中选择浅色或深色。\n• 中号和大号小组件显示累计次数、最近 7 天以及达到下一个里程碑的预计时间。\n• 更简洁美观的设置页面。\n• Duo 套装：拥有 Foldly+，11 月 30 日前 Foldboard Pro 仅需 1.99 欧元。",
        "it": "• Fondatori: grazie per i 2.000 download! Chi apre Foldly prima del 1° dicembre riceve il badge Fondatore e Oro 2K, un colore dei widget esclusivo.\n• Widget chiari: seguono il tuo iPhone (chiari di giorno), oppure scegli chiaro o scuro nelle Impostazioni.\n• I widget medio e grande mostrano il totale, gli ultimi 7 giorni e quando raggiungerai il prossimo traguardo.\n• Impostazioni più semplici e belle.\n• Pack Duo: con Foldly+, Foldboard Pro a 1,99 € fino al 30 novembre.",
        "pt-BR": "• Fundadores: obrigado pelos 2.000 downloads! Quem abrir o Foldly antes de 1º de dezembro ganha o selo de Fundador e o Ouro 2K, uma cor de widget exclusiva.\n• Widgets claros: seguem o seu iPhone (claros de dia), ou escolha claro ou escuro nos Ajustes.\n• Os widgets médio e grande mostram seu total, os últimos 7 dias e quando você chegará ao próximo marco.\n• Ajustes mais simples e bonitos.\n• Pacote Duo: com o Foldly+, Foldboard Pro por 1,99 € até 30 de novembro.",
        "nl-NL": "• Oprichters: bedankt voor 2.000 downloads! Wie Foldly vóór 1 december opent, krijgt de Oprichter-badge en Goud 2K, een exclusieve widgetkleur.\n• Lichte widgets: ze volgen je iPhone (overdag licht), of kies licht of donker in Instellingen.\n• De middelgrote en grote widgets tonen je totaal, je laatste 7 dagen en wanneer je je volgende mijlpaal haalt.\n• Eenvoudigere, mooiere instellingen.\n• Duo-pakket: met Foldly+ Foldboard Pro voor € 1,99 tot 30 november.",
        "ru": "• Основатели: спасибо за 2 000 загрузок! Все, кто откроет Foldly до 1 декабря, получат значок Основателя и Золото 2K — эксклюзивный цвет виджетов.\n• Светлые виджеты: они следуют за iPhone (днём светлые), или выберите светлые или тёмные в Настройках.\n• Средний и большой виджеты показывают общий итог, последние 7 дней и когда вы достигнете следующей отметки.\n• Более простые и красивые Настройки.\n• Пакет Duo: с Foldly+ — Foldboard Pro за 1,99 € до 30 ноября."
    },
    "1.0.17": {
        "en-US": "• Open vs closed while you're awake: the Time closed card now also shows your open and closed time during your waking hours only, so nights no longer weigh on it. Thanks for the idea!\n• Only use the “Opened” automation? Foldly now also counts the fold before each opening.\n• New from us: Foldboard, the keyboard for your Duo.",
        "fr-FR": "• Ouvert et fermé quand tu es éveillé : la carte Temps fermé montre aussi ton temps ouvert et fermé pendant tes heures d'éveil seulement, la nuit ne pèse plus. Merci pour l'idée !\n• Tu n'utilises que l'automatisation « Ouvert » ? Foldly compte maintenant aussi le pli avant chaque ouverture.\n• Nouveau chez nous : Foldboard, le clavier pour ton Duo.",
        "de-DE": "• Offen und zu, während du wach bist: Die Karte „Zeit zugeklappt“ zeigt jetzt auch nur deine Wachstunden, die Nacht zählt nicht mehr mit.\n• Nur die Automation „Geöffnet“? Foldly zählt jetzt auch das Zuklappen vor jedem Öffnen.\n• Neu von uns: Foldboard, die Tastatur für dein Duo.",
        "es-ES": "• Abierto y cerrado mientras estás despierto: la tarjeta Tiempo cerrado muestra ahora solo tus horas de vigilia, la noche ya no pesa.\n• ¿Solo usas la automatización «Abierto»? Foldly cuenta también el cierre anterior a cada apertura.\n• Nuevo: Foldboard, el teclado para tu Duo.",
        "ja": "• 起きている時間の開閉：「閉じた時間」カードに起きている時間だけの開閉時間を表示。夜の時間が影響しなくなりました。\n• 「開いたとき」のオートメーションだけでも、開く前の折りたたみを数えます。\n• 新登場：Duo のためのキーボード Foldboard。",
        "ko": "• 깨어 있는 동안의 열림/닫힘: ‘닫힌 시간’ 카드에 깨어 있는 시간만의 열림·닫힘 시간이 표시돼요. 밤 시간은 더 이상 반영되지 않아요.\n• ‘열렸을 때’ 자동화만 써도 열기 전의 접기를 셉니다.\n• 새로운 앱: Duo를 위한 키보드 Foldboard.",
        "zh-Hans": "• 清醒时段的展开与合上：“合上时间”卡片现在也显示仅在清醒时段的展开和合上时间，夜晚不再影响统计。\n• 只用“打开时”自动化？Foldly 也会统计每次打开前的合上。\n• 新品：Foldboard，为你的 Duo 打造的键盘。",
        "it": "• Aperto e chiuso mentre sei sveglio: la scheda Tempo chiuso mostra ora anche solo le ore di veglia, la notte non pesa più.\n• Usi solo l'automazione “Aperto”? Foldly conta anche la chiusura prima di ogni apertura. Grazie Marco!\n• Novità: Foldboard, la tastiera per il tuo Duo.",
        "pt-BR": "• Aberto e fechado enquanto você está acordado: o cartão Tempo fechado agora mostra só as suas horas acordado, a noite não pesa mais.\n• Usa só a automação “Aberto”? O Foldly também conta o fechamento antes de cada abertura.\n• Novo: Foldboard, o teclado para o seu Duo.",
        "nl-NL": "• Open en dicht terwijl je wakker bent: de kaart Tijd dicht toont nu ook alleen je wakkere uren, de nacht telt niet meer mee.\n• Alleen de automatisering “Geopend”? Foldly telt nu ook het dichtklappen vóór elke keer openen.\n• Nieuw: Foldboard, het toetsenbord voor je Duo.",
        "ru": "• Открыт и закрыт, пока вы не спите: карточка «Время в закрытом виде» теперь показывает и только часы бодрствования — ночь больше не искажает данные.\n• Только автоматизация «Открыт»? Foldly считает и закрытие перед каждым открытием.\n• Новинка: Foldboard — клавиатура для вашего Duo.",
    },
    "1.0.16": {
        "en-US": "• Only use the “Opened” automation? Foldly now also counts the fold that came before each opening.\n• Small fixes and improvements.",
        "fr-FR": "• Tu n'utilises que l'automatisation « Ouvert » ? Foldly compte maintenant aussi le pli qui précède chaque ouverture.\n• Petites corrections et améliorations.",
        "de-DE": "• Du nutzt nur die Automation „Geöffnet“? Foldly zählt jetzt auch das Zuklappen vor jedem Öffnen.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• ¿Solo usas la automatización «Abierto»? Foldly ahora también cuenta el cierre anterior a cada apertura.\n• Pequeñas correcciones y mejoras.",
        "ja": "• 「開いたとき」のオートメーションだけでも、開く前の折りたたみを数えるようになりました。\n• 細かな修正と改善。",
        "ko": "• ‘열렸을 때’ 자동화만 사용해도 이제 열기 전의 접기를 함께 셉니다.\n• 작은 수정 및 개선.",
        "zh-Hans": "• 只用“打开时”自动化？Foldly 现在也会统计每次打开前的那次合上。\n• 小问题修复和改进。",
        "it": "• Usi solo l'automazione “Aperto”? Ora Foldly conta anche la chiusura prima di ogni apertura. Grazie Marco!\n• Piccole correzioni e miglioramenti.",
        "pt-BR": "• Usa só a automação “Aberto”? Agora o Foldly também conta o fechamento antes de cada abertura.\n• Pequenas correções e melhorias.",
        "nl-NL": "• Gebruik je alleen de automatisering “Geopend”? Foldly telt nu ook het dichtklappen vóór elke keer openen.\n• Kleine verbeteringen.",
        "ru": "• Используете только автоматизацию «Открыт»? Теперь Foldly считает и закрытие перед каждым открытием.\n• Небольшие исправления и улучшения.",
    },
    "1.0.15": {
        "en-US": "• Foldly now speaks Italian, Portuguese, Dutch and Russian. Grazie Marco for the idea!\n• Small fixes and improvements.",
        "fr-FR": "• Foldly parle maintenant italien, portugais, néerlandais et russe. Grazie Marco pour l'idée !\n• Petites corrections et améliorations.",
        "de-DE": "• Foldly spricht jetzt Italienisch, Portugiesisch, Niederländisch und Russisch.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• Foldly ya habla italiano, portugués, neerlandés y ruso.\n• Pequeñas correcciones y mejoras.",
        "ja": "• Foldly がイタリア語、ポルトガル語、オランダ語、ロシア語に対応しました。\n• 細かな修正と改善。",
        "ko": "• Foldly가 이제 이탈리아어, 포르투갈어, 네덜란드어, 러시아어를 지원해요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• Foldly 现已支持意大利语、葡萄牙语、荷兰语和俄语。\n• 小问题修复和改进。",
        "it": "• Foldly ora parla italiano! Grazie Marco per l'idea.\n• Piccole correzioni e miglioramenti.",
        "pt-BR": "• O Foldly agora fala português!\n• Pequenas correções e melhorias.",
        "nl-NL": "• Foldly spreekt nu Nederlands!\n• Kleine verbeteringen.",
        "ru": "• Foldly теперь говорит по-русски!\n• Небольшие исправления и улучшения.",
    },
    "1.0.14": {
        "en-US": "• Open all night? The whole night now counts as rest, even if you go to bed before your rest hours or get up after them (up to 3 hours before and after). Thanks for the idea!\n• Small fixes and improvements.",
        "fr-FR": "• Ouvert toute la nuit ? Toute la nuit compte maintenant comme du repos, même si tu te couches avant tes heures de repos ou te lèves après (jusqu'à 3 h avant et après). Merci pour l'idée !\n• Petites corrections et améliorations.",
        "de-DE": "• Die ganze Nacht offen? Jetzt zählt die ganze Nacht als Ruhe, auch wenn du vor deinen Ruhezeiten schlafen gehst oder danach aufstehst (bis zu 3 Stunden davor und danach). Danke für die Idee!\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• ¿Abierto toda la noche? Ahora toda la noche cuenta como reposo, aunque te acuestes antes de tus horas de reposo o te levantes después (hasta 3 horas antes y después). ¡Gracias por la idea!\n• Pequeñas correcciones y mejoras.",
        "ja": "• 一晩中開いていた場合、休止時間の前に寝ても後に起きても、夜全体が休止として数えられるようになりました（前後3時間まで）。アイデアをありがとう！\n• 細かな修正と改善。",
        "ko": "• 밤새 열려 있었나요? 휴식 시간대보다 일찍 자거나 늦게 일어나도 이제 밤 전체가 휴식으로 계산돼요(앞뒤 최대 3시간). 아이디어 고마워요!\n• 작은 수정 및 개선.",
        "zh-Hans": "• 整晚都展开？现在即使你在静置时段之前睡觉或之后起床，整晚也都算作静置（前后最多各 3 小时）。感谢你的建议！\n• 小问题修复和改进。",
    },
    "1.6.2": {
        "en-US": "• MINI GOLF: the ball no longer gets stuck against a wall on the slope.\n• FIREFLY: no more fireflies in hidden areas.\n• SCHOOL: chalk digits are recognized much more reliably.\n• Small fixes and improvements.",
        "fr-FR": "• MINIGOLF : la balle ne reste plus bloquée contre un mur sur la pente.\n• LUCIOLE : plus de lucioles dans les zones cachées.\n• ÉCOLE : les chiffres écrits à la craie sont bien mieux reconnus.\n• Petites corrections et améliorations.",
        "de-DE": "• MINIGOLF: Der Ball bleibt am Hang nicht mehr an einer Wand hängen.\n• GLÜHWÜRMCHEN: keine Glühwürmchen mehr in verdeckten Bereichen.\n• SCHULE: Kreidezahlen werden viel zuverlässiger erkannt.\n• Kleine Korrekturen und Verbesserungen.",
        "es-ES": "• MINIGOLF: la bola ya no se queda atascada contra una pared en la pendiente.\n• LUCIÉRNAGA: ya no hay luciérnagas en zonas ocultas.\n• ESCUELA: las cifras escritas con tiza se reconocen mucho mejor.\n• Pequeñas correcciones y mejoras.",
        "ja": "• ミニゴルフ：坂の壁にボールが引っかからなくなりました。\n• ホタル：隠れた場所にホタルが出なくなりました。\n• 学校：チョークで書いた数字の認識が大きく向上しました。\n• 細かな修正と改善。",
        "ko": "• 미니 골프: 경사면에서 공이 벽에 끼지 않아요.\n• 반딧불이: 가려진 곳에 반딧불이가 나오지 않아요.\n• 학교: 분필로 쓴 숫자를 훨씬 정확하게 알아봐요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• 迷你高尔夫：球不会再卡在斜坡的墙边。\n• 萤火虫：隐藏区域不再出现萤火虫。\n• 学校：粉笔写的数字识别更加准确。\n• 小问题修复和改进。",
    },
    "1.0.13": {
        "en-US": "• Open but not in use: set your Rest hours in Settings (23:00 to 7:00 by default). Time your Duo stays open then counts as rest, and is left out of your open time. Shortcuts for the Sleep focus are optional.\n• The App Store page now speaks more than 30 languages.\n• Small fixes and improvements.",
        "fr-FR": "• Ouvert mais pas utilisé : règle tes heures de repos dans les réglages (de 23 h à 7 h par défaut). Le temps où ton Duo reste ouvert à ces heures compte comme du repos, et Foldly montre la part de ton temps ouvert passée au repos. Des raccourcis pour le mode Repos sont facultatifs.\n• La fiche App Store parle maintenant plus de 30 langues.\n• Petites corrections et améliorations.",
        "de-DE": "• Offen, aber nicht benutzt: Lege deine Ruhezeiten in den Einstellungen fest (standardmäßig 23:00 bis 7:00 Uhr). Die Zeit, in der dein Duo dann offen bleibt, zählt als Ruhe, und Foldly zeigt, wie viel deiner offenen Zeit im Ruhemodus war. Kurzbefehle für den Schlaf-Fokus sind optional.\n• Die App-Store-Seite spricht jetzt über 30 Sprachen.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• Abierto pero sin usar: define tus horas de reposo en Ajustes (de 23:00 a 7:00 por defecto). El tiempo que tu Duo permanece abierto en ese horario cuenta como reposo, y Foldly muestra cuánto de tu tiempo abierto fue en reposo. Los atajos para el modo Sueño son opcionales.\n• La ficha de la App Store ya habla más de 30 idiomas.\n• Pequeñas correcciones y mejoras.",
        "ja": "• 開いているだけで使っていない時間：設定で休止時間を決められます（初期設定は23:00〜7:00）。その時間帯にDuoが開いている時間は休止として数え、開いている時間のうち休止中の時間が表示されます。睡眠モード用のショートカットは任意です。\n• App Storeのページが30以上の言語に対応しました。\n• 細かな修正と改善。",
        "ko": "• 열려 있지만 사용하지 않는 시간: 설정에서 휴식 시간대를 정할 수 있어요(기본 23:00~7:00). 이 시간대에 Duo가 열려 있는 시간은 휴식으로 계산하고, 열려 있던 시간 중 휴식 시간을 보여 줘요. 수면 집중 모드용 단축어는 선택 사항이에요.\n• App Store 페이지가 30개 이상의 언어를 지원해요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• 展开但未使用：可在设置中设定静置时段（默认 23:00 至 7:00）。Duo 在该时段内保持展开的时间会算作静置，Foldly 会显示展开时间中有多少处于静置状态。睡眠专注模式的快捷指令为可选项。\n• App Store 页面现已支持 30 多种语言。\n• 小问题修复和改进。",
    },
    "1.0.12": {
        "en-US": "• Leaderboards are now free for everyone, with new ones: who folds the most today, this week and since day one. Share your rank!\n• Contest of the month: the winners get Foldly+ for free and pick a new feature.\n• Today, hour by hour, right on the home screen.\n• Your weekly and monthly recaps are always one tap away, and the notification opens them.",
        "fr-FR": "• Les classements sont gratuits pour tous, avec des nouveaux : qui plie le plus aujourd'hui, cette semaine et depuis le début. Partage ton rang !\n• Le concours du mois : les gagnants reçoivent Foldly+ gratuit et choisissent une nouvelle fonctionnalité.\n• Aujourd'hui, heure par heure, directement sur l'écran principal.\n• Tes bilans de la semaine et du mois sont toujours à portée de main, et la notification les ouvre.",
        "de-DE": "• Ranglisten sind jetzt für alle kostenlos, mit neuen: Wer faltet heute, diese Woche und seit Tag eins am meisten? Teile deinen Rang!\n• Wettbewerb des Monats: Die Gewinner bekommen Foldly+ gratis und wählen eine neue Funktion.\n• Heute, Stunde für Stunde, direkt auf dem Startbildschirm.\n• Deine Wochen- und Monatsrückblicke sind immer einen Tipp entfernt, und die Mitteilung öffnet sie.",
        "es-ES": "• Las clasificaciones son gratis para todos, con nuevas: quién pliega más hoy, esta semana y desde el primer día. ¡Comparte tu puesto!\n• Concurso del mes: los ganadores reciben Foldly+ gratis y eligen una nueva función.\n• Hoy, hora a hora, en la pantalla principal.\n• Tus resúmenes semanales y mensuales siempre a un toque, y la notificación los abre.",
        "ja": "• ランキングが誰でも無料に。新ランキング：今日・今週・これまででいちばん折った人。順位をシェアしよう！\n• 今月のコンテスト：優勝者は Foldly+ が無料になり、新機能を選べます。\n• 今日の1時間ごとの回数をホーム画面に表示。\n• 週間・月間まとめにいつでもすぐアクセス。通知からも開けます。",
        "ko": "• 순위가 모두에게 무료예요. 새 순위: 오늘, 이번 주, 처음부터 가장 많이 접은 사람. 내 순위를 공유하세요!\n• 이달의 대회: 우승자는 Foldly+를 무료로 받고 새 기능을 골라요.\n• 오늘 시간대별 기록을 홈 화면에서 바로.\n• 주간·월간 요약을 언제든 한 번에 열 수 있고, 알림을 누르면 바로 열려요.",
        "zh-Hans": "• 排行榜现在对所有人免费，并新增：今天、本周和至今谁折得最多。分享你的排名！\n• 本月比赛：冠军免费获得 Foldly+ 并挑选一个新功能。\n• 今天按小时的数据，直接显示在主屏幕上。\n• 每周和每月总结随时一键打开，通知也能直接打开。",
    },
    "1.0.11": {
        "en-US": "• 1,000 downloads in 3 days, thank you! To celebrate, Foldly+ is at its lowest price ever with a gift code, until November 16.\n• New setting: count each movement. Opening and closing then count as 2 instead of 1. Your history, widgets and watch follow too.\n• Importing your history works with Scriptable files as they are, no need to convert them first.\n• When a day was counted both by Foldly and by your old tool, Foldly now keeps the higher count, today included, so no fold gets lost.\n• Small fixes and improvements.",
        "fr-FR": "• 1 000 téléchargements en 3 jours, merci ! Pour fêter ça, Foldly+ est à son prix le plus bas avec un code cadeau, jusqu'au 16 novembre.\n• Nouveau réglage : compter chaque mouvement. Ouvrir puis fermer compte alors pour 2 au lieu de 1. L'historique, les widgets et la montre suivent aussi.\n• L'import de ton historique lit directement les fichiers Scriptable, plus besoin de les convertir.\n• Quand un jour a été compté à la fois par Foldly et par ton ancien outil, Foldly garde le plus grand des deux nombres, aujourd'hui compris : aucun pli n'est perdu.\n• Petites corrections et améliorations.",
        "de-DE": "• 1.000 Downloads in 3 Tagen, danke! Zur Feier gibt es Foldly+ mit einem Geschenkcode so günstig wie nie, bis zum 16. November.\n• Neue Einstellung: jede Bewegung zählen. Öffnen und Schließen zählen dann als 2 statt 1. Verlauf, Widgets und Uhr passen sich an.\n• Der Import deines Verlaufs liest Scriptable-Dateien direkt, ohne Umwandeln.\n• Wenn ein Tag sowohl von Foldly als auch von deinem alten Tool gezählt wurde, behält Foldly die höhere Zahl, auch für heute: Kein Zuklappen geht verloren.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• ¡1000 descargas en 3 días, gracias! Para celebrarlo, Foldly+ está a su precio más bajo con un código de regalo, hasta el 16 de noviembre.\n• Nuevo ajuste: contar cada movimiento. Abrir y cerrar cuentan entonces como 2 en lugar de 1. El historial, los widgets y el reloj también.\n• La importación de tu historial lee directamente los archivos de Scriptable, sin convertirlos antes.\n• Si un día lo contaron tanto Foldly como tu herramienta anterior, Foldly conserva la cifra más alta, también la de hoy: no se pierde ningún pliegue.\n• Pequeñas correcciones y mejoras.",
        "ja": "• 3日間で1,000ダウンロード、ありがとう！お祝いに、ギフトコードで Foldly+ が過去最安値に（11月16日まで）。\n• 新しい設定：動きごとに数える。開いて閉じると1回ではなく2回に。履歴、ウィジェット、Apple Watchも同じ数え方に。\n• 履歴の読み込みがScriptableのファイルにそのまま対応。変換は不要です。\n• Foldlyと以前のツールの両方で記録された日は、多い方の数を残します（今日も含む）。折りたたみの記録が失われません。\n• 細かな修正と改善。",
        "ko": "• 3일 만에 1,000 다운로드, 고마워요! 기념으로 11월 16일까지 선물 코드로 Foldly+를 역대 최저가에 드려요.\n• 새 설정: 동작마다 세기. 열고 닫으면 1회가 아니라 2회로 셉니다. 기록, 위젯, 워치도 함께 바뀌어요.\n• 기록 가져오기가 Scriptable 파일을 그대로 읽어요. 따로 변환할 필요가 없어요.\n• Foldly와 이전 도구가 모두 센 날은 두 숫자 중 큰 쪽을 남겨요(오늘 포함). 접은 횟수가 사라지지 않아요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• 3 天 1,000 次下载，谢谢你！为了庆祝，使用礼物代码即可以史上最低价获得 Foldly+，至 11 月 16 日。\n• 新设置：每个动作都计数。打开再合上将算作 2 次而不是 1 次。历史、小组件和手表也会同步。\n• 导入历史记录可直接读取 Scriptable 文件，无需先转换。\n• 如果某一天 Foldly 和你之前的工具都有记录，Foldly 会保留较大的数字（包括今天），不会漏掉任何一次折叠。\n• 小问题修复和改进。",
    },
    "1.0.10": {
        "en-US": "• Importing your history works with Scriptable files as they are, no need to convert them first.\n• When a day was counted both by Foldly and by your old tool, Foldly now keeps the higher count, today included, so no fold gets lost.\n• Small fixes and improvements.",
        "fr-FR": "• L'import de ton historique lit directement les fichiers Scriptable, plus besoin de les convertir.\n• Quand un jour a été compté à la fois par Foldly et par ton ancien outil, Foldly garde le plus grand des deux nombres, aujourd'hui compris : aucun pli n'est perdu.\n• Petites corrections et améliorations.",
        "de-DE": "• Der Import deines Verlaufs liest Scriptable-Dateien direkt, ohne Umwandeln.\n• Wenn ein Tag sowohl von Foldly als auch von deinem alten Tool gezählt wurde, behält Foldly die höhere Zahl, auch für heute: Kein Zuklappen geht verloren.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• La importación de tu historial lee directamente los archivos de Scriptable, sin convertirlos antes.\n• Si un día lo contaron tanto Foldly como tu herramienta anterior, Foldly conserva la cifra más alta, también la de hoy: no se pierde ningún pliegue.\n• Pequeñas correcciones y mejoras.",
        "ja": "• 履歴の読み込みがScriptableのファイルにそのまま対応。変換は不要です。\n• Foldlyと以前のツールの両方で記録された日は、多い方の数を残します（今日も含む）。折りたたみの記録が失われません。\n• 細かな修正と改善。",
        "ko": "• 기록 가져오기가 Scriptable 파일을 그대로 읽어요. 따로 변환할 필요가 없어요.\n• Foldly와 이전 도구가 모두 센 날은 두 숫자 중 큰 쪽을 남겨요(오늘 포함). 접은 횟수가 사라지지 않아요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• 导入历史记录可直接读取 Scriptable 文件，无需先转换。\n• 如果某一天 Foldly 和你之前的工具都有记录，Foldly 会保留较大的数字（包括今天），不会漏掉任何一次折叠。\n• 小问题修复和改进。",
    },
    "1.3": {
        "en-US": "• New game: CASCADE! A pixel-art coin pusher made for the Duo folded into an L: coins rain down the standing half, bounce off the pins and land on the flat board, where the pusher shoves them off the edge. Upgrade your machine, aim for the pink target, find the diamond, and fold-unfold the Duo to shake the board.\n• Small fixes and improvements.",
        "fr-FR": "• Nouveau jeu : CASCADE ! Une machine à pièces en pixel art, faite pour le Duo plié en L : les pièces pleuvent sur la moitié debout, rebondissent sur les clous et tombent sur le plateau à plat, où le poussoir les fait tomber du bord. Améliore ta machine, vise la cible rose, trouve le diamant, et plie-déplie le Duo pour secouer le plateau.\n• Petites corrections et améliorations.",
        "de-DE": "• Neues Spiel: CASCADE! Ein Münzschieber in Pixel-Art für den Duo im L-Modus: Münzen regnen über die stehende Hälfte, prallen an den Stiften ab und landen auf dem flachen Brett, wo der Schieber sie über die Kante schiebt. Verbessere deinen Automaten, triff das pinke Ziel, finde den Diamanten und klappe den Duo zu und auf, um das Brett zu rütteln.\n• Kleine Fehlerbehebungen und Verbesserungen.",
        "es-ES": "• ¡Nuevo juego: CASCADA! Una máquina de monedas en pixel art pensada para el Duo plegado en L: las monedas caen por la mitad de pie, rebotan en los clavos y aterrizan en el tablero plano, donde el empujador las tira por el borde. Mejora tu máquina, apunta a la diana rosa, encuentra el diamante y pliega y despliega el Duo para sacudir el tablero.\n• Pequeñas correcciones y mejoras.",
        "ja": "• 新ゲーム「カスケード」！L字に折ったDuoのためのピクセルアートのコインプッシャー。立てた側をコインが落ち、ピンで跳ねて平らな台へ。プッシャーで端から押し出そう。マシンを強化し、ピンクのターゲットを狙い、ダイヤを見つけ、Duoを折って戻すと台が揺れます。\n• 細かな修正と改善。",
        "ko": "• 새 게임: 캐스케이드! L자로 접은 Duo를 위한 픽셀 아트 코인 푸셔. 코인이 세운 쪽으로 쏟아져 핀에 튕기고, 평평한 판에 떨어지면 푸셔가 가장자리로 밀어내요. 머신을 업그레이드하고, 분홍 타깃을 노리고, 다이아몬드를 찾고, Duo를 접었다 펴서 판을 흔드세요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• 新游戏：瀑布！专为折成 L 形的 Duo 打造的像素风推币机：硬币从竖起的一半落下，在钉子上弹跳，落到平放的平台上，推板把它们推下边缘。升级你的机器，瞄准粉色目标，找到钻石，快速折叠再展开 Duo 来摇晃平台。\n• 小问题修复和改进。",
    },
    "1.6.1": {
        "en-US": "• The App Store page now speaks more than 30 languages.\n• Small fixes and improvements.",
        "fr-FR": "• La fiche App Store parle maintenant plus de 30 langues.\n• Petites corrections et améliorations.",
        "de-DE": "• Die App-Store-Seite gibt es jetzt in über 30 Sprachen.\n• Kleine Korrekturen und Verbesserungen.",
        "es-ES": "• La ficha del App Store ya está en más de 30 idiomas.\n• Pequeñas correcciones y mejoras.",
        "ja": "• App Storeのページが30以上の言語に対応しました。\n• 細かな修正と改善。",
        "ko": "• App Store 페이지가 이제 30개 이상의 언어로 제공돼요.\n• 작은 수정 및 개선.",
        "zh-Hans": "• App Store 页面现已支持 30 多种语言。\n• 小问题修复和改进。",
    },
    "1.6": {
        "en-US": "• FISHING: fold the Duo into an L, the hinge is the waterline. Cast with a flick of the hinge, strike when it bites, then reel by folding gently. 15 catches to find.\n• MINI GOLF: 9 holes, solo or with two. Fold the Duo and the top half becomes a slope: the ball rolls toward the hinge.\n• COMET: a pixel shoot 'em up across both screens. Fold halfway to drop a bomb.\n• Translation fixes in German, Spanish, Japanese, Korean and Chinese.\n• Try any locked game for free once, and a new free game of the day, every day.\n• Dark mode for the home screen and menus (Settings: Auto, Light or Dark).\n• Leaderboards with Game Center: COMET, MINI GOLF, MINESWEEPER, FISHING and more.\n• CASCADE: fixed a bug that gave endless coins.",
        "fr-FR": "• PÊCHE : Duo plié en L, la charnière est la ligne de l'eau. Lance d'un coup de charnière, ferre quand ça mord, puis mouline en pliant doucement. 15 prises à trouver.\n• MINIGOLF : 9 trous, seul ou à deux. Plie le Duo : la moitié du haut devient une pente et la balle roule vers la charnière.\n• COMÈTE : un shoot'em up pixel sur les deux écrans. Plie à moitié pour lâcher une bombe.\n• Corrections de traduction en allemand, espagnol, japonais, coréen et chinois.\n• Essaie gratuitement chaque jeu fermé une fois, et un nouveau jeu du jour gratuit, tous les jours.\n• Mode sombre pour l'accueil et les menus (Réglages : Auto, Clair ou Sombre).\n• Classements Game Center : COMÈTE, MINIGOLF, DÉMINEUR, PÊCHE et d'autres.\n• CASCADE : correction d'un bug qui donnait des pièces à l'infini.",
        "de-DE": "• ANGELN: Klapp den Duo zum L, das Scharnier ist die Wasserlinie. Wirf mit einem Scharnier-Schwung, schlag an, wenn es beißt, und kurble durch sanftes Klappen. 15 Fänge zu entdecken.\n• MINIGOLF: 9 Löcher, allein oder zu zweit. Klapp den Duo und die obere Hälfte wird zum Hang: Der Ball rollt zum Scharnier.\n• KOMET: ein Pixel-Shoot-'em-up über beide Bildschirme. Halb zuklappen für eine Bombe.\n• Übersetzungen korrigiert.\n• Teste jedes gesperrte Spiel einmal gratis, und jeden Tag ein neues Gratis-Spiel des Tages.\n• Dunkelmodus für Startseite und Menüs (Einstellungen: Auto, Hell oder Dunkel).\n• Bestenlisten mit Game Center: KOMET, MINIGOLF, MINENSUCHE, ANGELN und mehr.\n• CASCADE: Fehler mit endlosen Münzen behoben.",
        "es-ES": "• PESCA: pliega el Duo en L, la bisagra es la línea del agua. Lanza con un golpe de bisagra, tira cuando piquen y recoge plegando suave. 15 capturas por descubrir.\n• MINIGOLF: 9 hoyos, solo o a dos. Pliega el Duo y la mitad de arriba se vuelve una cuesta: la bola rueda hacia la bisagra.\n• COMETA: un matamarcianos pixel en las dos pantallas. Pliega a medias para soltar una bomba.\n• Correcciones de traducción.\n• Prueba gratis una vez cada juego bloqueado, y un nuevo juego del día gratis, cada día.\n• Modo oscuro para el inicio y los menús (Ajustes: Auto, Claro u Oscuro).\n• Clasificaciones con Game Center: COMETA, MINIGOLF, BUSCAMINAS, PESCA y más.\n• CASCADE: corregido un fallo que daba monedas infinitas.",
        "ja": "• つり：DuoをL字に折ると、ヒンジが水面に。ヒンジをクイッと動かして投げ、アタリでアワセて、ゆっくり開閉して巻こう。全15種。\n• ミニゴルフ：9ホール、1人でも2人でも。Duoを折ると上半分が坂になり、ボールがヒンジへ転がる。\n• コメット：2画面を使ったドット絵シューティング。半分折ってボム。\n• 翻訳を修正しました。\n• ロック中のゲームを1回無料でお試し。毎日「今日のゲーム」が無料に。\n• ホームとメニューにダークモード（設定：自動・ライト・ダーク）。\n• Game Centerのランキング：コメット、ミニゴルフ、マインスイーパー、つりなど。\n• CASCADE：コインが無限に出る不具合を修正。",
        "ko": "• 낚시: Duo를 L자로 접으면 힌지가 수면이에요. 힌지를 휙 움직여 던지고, 입질이 오면 챔질, 천천히 접었다 펴서 감아요. 15종을 찾아요.\n• 미니 골프: 9홀, 혼자 또는 둘이서. Duo를 접으면 위쪽 절반이 경사가 되어 공이 힌지 쪽으로 굴러요.\n• 혜성: 두 화면을 쓰는 픽셀 슈팅 게임. 반쯤 접으면 폭탄!\n• 번역을 고쳤어요.\n• 잠긴 게임을 한 번씩 무료로 체험하고, 매일 새로운 오늘의 게임을 무료로.\n• 홈과 메뉴에 다크 모드 (설정: 자동, 라이트, 다크).\n• Game Center 순위표: 혜성, 미니 골프, 지뢰찾기, 낚시 등.\n• CASCADE: 코인이 끝없이 나오던 버그 수정.",
        "zh-Hans": "• 钓鱼：把 Duo 折成 L 形，铰链就是水面。动一下铰链抛竿，咬钩时提竿，再轻轻开合收线。共 15 种待发现。\n• 迷你高尔夫：9 个洞，单人或双人。折起 Duo，上半部分变成斜坡，球会滚向铰链。\n• 彗星：横跨两块屏幕的像素射击游戏。折到一半投下炸弹。\n• 修正了翻译。\n• 每个未解锁的游戏都能免费试玩一次，每天还有一个免费的今日游戏。\n• 首页和菜单支持深色模式（设置：自动、浅色或深色）。\n• Game Center 排行榜：彗星、迷你高尔夫、扫雷、钓鱼等。\n• CASCADE：修复了金币无限产生的问题。",
    },
    "1.5": {
        "en-US": "• FISHING: fold the Duo into an L, the hinge is the waterline. Cast with a flick of the hinge, strike when it bites, then reel by folding gently. 15 catches to find.\n• MINI GOLF: 9 holes, solo or with two. Fold the Duo and the top half becomes a slope: the ball rolls toward the hinge.\n• COMET: a pixel shoot 'em up across both screens. Fold halfway to drop a bomb.\n• Translation fixes in German, Spanish, Japanese, Korean and Chinese.\n• Try any locked game for free once, and a new free game of the day, every day.",
        "fr-FR": "• PÊCHE : Duo plié en L, la charnière est la ligne de l'eau. Lance d'un coup de charnière, ferre quand ça mord, puis mouline en pliant doucement. 15 prises à trouver.\n• MINIGOLF : 9 trous, seul ou à deux. Plie le Duo : la moitié du haut devient une pente et la balle roule vers la charnière.\n• COMÈTE : un shoot'em up pixel sur les deux écrans. Plie à moitié pour lâcher une bombe.\n• Corrections de traduction en allemand, espagnol, japonais, coréen et chinois.\n• Essaie gratuitement chaque jeu fermé une fois, et un nouveau jeu du jour gratuit, tous les jours.",
        "de-DE": "• ANGELN: Klapp den Duo zum L, das Scharnier ist die Wasserlinie. Wirf mit einem Scharnier-Schwung, schlag an, wenn es beißt, und kurble durch sanftes Klappen. 15 Fänge zu entdecken.\n• MINIGOLF: 9 Löcher, allein oder zu zweit. Klapp den Duo und die obere Hälfte wird zum Hang: Der Ball rollt zum Scharnier.\n• KOMET: ein Pixel-Shoot-'em-up über beide Bildschirme. Halb zuklappen für eine Bombe.\n• Übersetzungen korrigiert.\n• Teste jedes gesperrte Spiel einmal gratis, und jeden Tag ein neues Gratis-Spiel des Tages.",
        "es-ES": "• PESCA: pliega el Duo en L, la bisagra es la línea del agua. Lanza con un golpe de bisagra, tira cuando piquen y recoge plegando suave. 15 capturas por descubrir.\n• MINIGOLF: 9 hoyos, solo o a dos. Pliega el Duo y la mitad de arriba se vuelve una cuesta: la bola rueda hacia la bisagra.\n• COMETA: un matamarcianos pixel en las dos pantallas. Pliega a medias para soltar una bomba.\n• Correcciones de traducción.\n• Prueba gratis una vez cada juego bloqueado, y un nuevo juego del día gratis, cada día.",
        "ja": "• つり：DuoをL字に折ると、ヒンジが水面に。ヒンジをクイッと動かして投げ、アタリでアワセて、ゆっくり開閉して巻こう。全15種。\n• ミニゴルフ：9ホール、1人でも2人でも。Duoを折ると上半分が坂になり、ボールがヒンジへ転がる。\n• コメット：2画面を使ったドット絵シューティング。半分折ってボム。\n• 翻訳を修正しました。\n• ロック中のゲームを1回無料でお試し。毎日「今日のゲーム」が無料に。",
        "ko": "• 낚시: Duo를 L자로 접으면 힌지가 수면이에요. 힌지를 휙 움직여 던지고, 입질이 오면 챔질, 천천히 접었다 펴서 감아요. 15종을 찾아요.\n• 미니 골프: 9홀, 혼자 또는 둘이서. Duo를 접으면 위쪽 절반이 경사가 되어 공이 힌지 쪽으로 굴러요.\n• 혜성: 두 화면을 쓰는 픽셀 슈팅 게임. 반쯤 접으면 폭탄!\n• 번역을 고쳤어요.\n• 잠긴 게임을 한 번씩 무료로 체험하고, 매일 새로운 오늘의 게임을 무료로.",
        "zh-Hans": "• 钓鱼：把 Duo 折成 L 形，铰链就是水面。动一下铰链抛竿，咬钩时提竿，再轻轻开合收线。共 15 种待发现。\n• 迷你高尔夫：9 个洞，单人或双人。折起 Duo，上半部分变成斜坡，球会滚向铰链。\n• 彗星：横跨两块屏幕的像素射击游戏。折到一半投下炸弹。\n• 修正了翻译。\n• 每个未解锁的游戏都能免费试玩一次，每天还有一个免费的今日游戏。",
    },
    "1.4": {
        "en-US": "• 4 new games!\n• CASCADE: a pixel-art coin pusher made for the Duo folded into an L. Coins rain down, the pusher shoves them off the edge. Upgrade your machine and fold-unfold the Duo to shake the board.\n• SEA BATTLE: sink the other fleet. Two players: close the Duo and pass it, the fold hides your grid. Or play the computer.\n• DOTS & BOXES: face to face with the Duo open flat. Close a box, it takes your color and initial.\n• MINES: the classic, with three grid sizes. Fold the Duo a little to place flags.",
        "fr-FR": "• 4 nouveaux jeux !\n• CASCADE : une machine à pièces en pixel art, faite pour le Duo plié en L. Les pièces pleuvent, le poussoir les fait tomber. Améliore ta machine et plie-déplie le Duo pour secouer le plateau.\n• BATAILLE NAVALE : coule la flotte d'en face. À deux : ferme le Duo et passe-le, le pli cache ta grille. Ou contre l'ordinateur.\n• CARRÉS : face à face, Duo ouvert à plat. Ferme un carré, il prend ta couleur et ton initiale.\n• DÉMINEUR : le classique, en trois tailles. Plie un peu le Duo pour poser des drapeaux.",
        "de-DE": "• 4 neue Spiele!\n• CASCADE: ein Münzschieber in Pixel-Art für den Duo im L-Modus. Münzen regnen, der Schieber schiebt sie über die Kante. Verbessere deinen Automaten und klappe den Duo zu und auf, um das Brett zu rütteln.\n• SCHIFFE VERSENKEN: Versenke die gegnerische Flotte. Zu zweit: Duo zuklappen und weitergeben, der Knick versteckt dein Feld. Oder gegen den Computer.\n• KÄSTCHEN: Gesicht an Gesicht, Duo flach. Schließ ein Kästchen, es bekommt deine Farbe und deinen Buchstaben.\n• MINENSUCHE: der Klassiker in drei Größen. Klappe den Duo etwas zu, um Flaggen zu setzen.",
        "es-ES": "• ¡4 juegos nuevos!\n• CASCADA: una máquina de monedas en pixel art para el Duo plegado en L. Llueven monedas y el empujador las tira por el borde. Mejora tu máquina y pliega y despliega el Duo para sacudir el tablero.\n• HUNDIR LA FLOTA: hunde la flota rival. A dos: cierra el Duo y pásalo, el pliegue esconde tu tablero. O contra el ordenador.\n• CUADRADOS: cara a cara con el Duo abierto en plano. Cierra un cuadrado y se lleva tu color y tu inicial.\n• BUSCAMINAS: el clásico en tres tamaños. Pliega un poco el Duo para poner banderas.",
        "ja": "• 新しいゲームが4つ！\n• カスケード：L字に折ったDuoのためのピクセルアートのコインプッシャー。マシンを強化し、Duoを折って戻すと台が揺れます。\n• 海戦：相手の艦隊を沈めよう。2人ならDuoを閉じて渡すと、折り目がグリッドを隠します。コンピュータとも対戦できます。\n• ドット＆ボックス：Duoを平らに開いて向かい合って。箱を閉じると色とイニシャルが入ります。\n• マインスイーパ：定番を3サイズで。Duoを少し折ると旗を置けます。",
        "ko": "• 새 게임 4개!\n• 캐스케이드: L자로 접은 Duo를 위한 픽셀 아트 코인 푸셔. 머신을 업그레이드하고 Duo를 접었다 펴서 판을 흔드세요.\n• 해전: 상대 함대를 침몰시키세요. 2인: Duo를 닫아 건네면 접힘이 판을 숨겨요. 컴퓨터와도 대결.\n• 점과 상자: Duo를 평평하게 펼치고 마주 보고. 상자를 닫으면 내 색과 이니셜이 들어가요.\n• 지뢰 찾기: 클래식을 세 가지 크기로. Duo를 살짝 접으면 깃발을 꽂아요.",
        "zh-Hans": "• 4 款新游戏！\n• 瀑布：专为折成 L 形的 Duo 打造的像素风推币机。升级机器，折叠再展开 Duo 摇晃平台。\n• 海战：击沉对方舰队。双人：合上 Duo 递给对方，折叠藏住你的棋盘。也可以和电脑对战。\n• 点格棋：Duo 平放面对面。围成格子就填上你的颜色和首字母。\n• 扫雷：经典玩法，三种尺寸。把 Duo 稍微折起就能插旗。",
    },
}
NEW_VERSION = os.environ.get("NEW_VERSION", "").strip()
if NEW_VERSION:
    existing = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&filter[versionString]={NEW_VERSION}").get("data", [])
    if existing:
        print(f"ok     version {NEW_VERSION} déjà créée ({existing[0]['attributes'].get('appStoreState')})")
        new_vid = existing[0]["id"]
    else:
        # Une app jamais publiée garde sa première version modifiable : on la renomme plutôt que d'en créer une autre.
        all_v = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10").get("data", [])
        never_live = not any(x["attributes"].get("appStoreState") in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION") for x in all_v)
        editable_v = [x for x in all_v if x["attributes"].get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
        # 1.0.6 retirée puis remplacée par 1.0.7 : on renomme aussi la version modifiable plutôt que d'en créer une autre.
        if editable_v:
            ev = editable_v[0]
            r = step(f"version {ev['attributes']['versionString']} renommée en {NEW_VERSION}", call("PATCH", f"/v1/appStoreVersions/{ev['id']}",
                     {"data": {"type": "appStoreVersions", "id": ev["id"], "attributes": {"versionString": NEW_VERSION}}}))
            new_vid = ev["id"]
        else:
            r = step(f"version {NEW_VERSION} créée", call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions",
                     "attributes": {"platform": "IOS", "versionString": NEW_VERSION, "releaseType": "MANUAL" if BUNDLE == "com.padelup.clapet" and NEW_VERSION not in ("1.0.4", "1.0.5", "1.0.6", "1.0.7", "1.0.8", "1.0.9", "1.0.10", "1.0.11", "1.0.12", "1.0.13", "1.0.14", "1.0.15", "1.0.16", "1.0.17", "1.6", "1.6.1", "1.6.2") else "AFTER_APPROVAL"},
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}))
            new_vid = r.get("data", {}).get("id")
    # Les numéros de version se recoupent entre les apps : chaque app a ses propres notes quand il le faut.
    notes = (APP_NOTES.get(BUNDLE, {}).get(NEW_VERSION) if BUNDLE in APP_NOTES else RELEASE_NOTES.get(NEW_VERSION)) or {}
    if new_vid and notes:
        for l in call("GET", f"/v1/appStoreVersions/{new_vid}/appStoreVersionLocalizations").get("data", []):
            loc = l["attributes"]["locale"]
            # Apple exige « Nouveautés » dans chaque langue d'une mise à jour : langue proche, sinon l'anglais.
            text = (notes.get(loc) or notes.get({"fr": "fr-FR", "es": "es-ES", "de": "de-DE", "pt": "en-US",
                    "zh": "zh-Hans"}.get(loc.split("-")[0], "")) or notes.get("en-US"))
            if text:
                step(f"nouveautés {l['attributes']['locale']}", call("PATCH", f"/v1/appStoreVersionLocalizations/{l['id']}", {"data": {
                     "type": "appStoreVersionLocalizations", "id": l["id"], "attributes": {"whatsNew": text}}}),
                     tolerate=("cannot be edited at this time",))  # première version d'une app : pas de « Nouveautés »

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
    "type": "appStoreVersions", "id": vid, "attributes": {"copyright": f"2026 {owner}", "releaseType": "MANUAL" if NEW_VERSION and BUNDLE == "com.padelup.clapet" and NEW_VERSION not in ("1.0.4", "1.0.5", "1.0.6", "1.0.7", "1.0.8", "1.0.9", "1.0.10", "1.0.11", "1.0.12", "1.0.13", "1.0.14", "1.0.15", "1.0.16", "1.0.17", "1.6", "1.6.1", "1.6.2") else "AFTER_APPROVAL"}}}))

# Coordonnées pour la vérification : celles déjà données pour la bêta
contact = call("GET", f"/v1/apps/{app_id}/betaAppReviewDetail").get("data", {}).get("attributes", {})
if not contact.get("contactFirstName"):
    # Nouvelle app sans bêta publique : on reprend les coordonnées de Foldly.
    other = call("GET", "/v1/apps?filter[bundleId]=com.padelup.clapet").get("data", [])
    if other:
        contact = call("GET", f"/v1/apps/{other[0]['id']}/betaAppReviewDetail").get("data", {}).get("attributes", {})
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
    _site_ok = {}

    def site_lang(locale):
        """La langue du site pour cette langue de fiche (l'anglais si le site n'a pas cette langue)."""
        lang = LOCALES.get(locale, "en")
        if lang not in _site_ok:
            try:
                _site_ok[lang] = urllib.request.urlopen(f"{SITE}/{lang}/privacy.html", timeout=20).getcode() == 200
            except Exception:
                _site_ok[lang] = False
        return lang if _site_ok[lang] else "en"

    for l in call("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations").get("data", []):
        lang = site_lang(l["attributes"]["locale"])
        step(f"confidentialité {l['attributes']['locale']}", call("PATCH", f"/v1/appInfoLocalizations/{l['id']}", {"data": {
            "type": "appInfoLocalizations", "id": l["id"], "attributes": {"privacyPolicyUrl": f"{SITE}/{lang}/privacy.html"}}}))
    for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", []):
        lang = site_lang(l["attributes"]["locale"])
        step(f"assistance {l['attributes']['locale']}", call("PATCH", f"/v1/appStoreVersionLocalizations/{l['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": l["id"], "attributes": {"supportUrl": f"{SITE}/{lang}/", "marketingUrl": f"{SITE}/{lang}/"}}}))
else:
    print("       pas encore de site (SITE_URL) : assistance et confidentialité à faire")

# Captures d'écran : iPhone 6,7" et iPhone Duo (le badge « conçu pour l'iPhone Duo » demande ces dernières)
SHOT_SETS = [(SHOT_TYPE, ""), ("APP_IPHONE_DUO", "duo-"), ("APP_WATCH_ULTRA", "watch-")]
for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations").get("data", []):
    loc = l["attributes"]["locale"]
    lang = LOCALES.get(loc)
    # Les autres variantes d'une langue (en-GB, fr-CA…) reprennent les captures de cette langue.
    if not lang and os.path.exists(os.path.join(SHOTS_DIR, f"{loc[:2]}-1.png")):
        lang = loc[:2]
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
if SUBMIT:
    # Sur une mise à jour d'une app déjà en ligne, la fiche (catégories, âge, confidentialité) est figée et déjà remplie.
    if NEW_VERSION:
        problems = [x for x in problems if not x.startswith(("catégories", "classification", "confidentialité", "nom "))]
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
    r_ = step("version ajoutée à la demande", call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
         "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                           "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}}), tolerate=("already",))
    if "error" in r_ and "already" not in r_.get("detail", ""):
        # Jamais d'envoi sans la version (sinon les vidéos partent seules).
        print(r_.get("detail", "")[:4000])
        print("\nPAS ENVOYÉ : la version n'a pas pu être ajoutée")
        sys.exit(1)
    # Les vidéos d'en-tête et de recherche (iOS 27) placées sur cette version partent avec elle.
    # ASSETS_DIR=none : pas de vidéos cette fois (on retire celles déjà mises dans la demande).
    if os.environ.get("ASSETS_DIR") == "none":
        for it in call("GET", f"/v1/reviewSubmissions/{sub_id}/items?include=appAssetLibraryVideo,appStoreVersion&limit=50").get("data", []):
            rels = it.get("relationships", {})
            vid_rel = (rels.get("appAssetLibraryVideo") or {}).get("data")
            if vid_rel is None and "appAssetLibraryVideo" not in rels:
                # Relation non renvoyée : on la demande directement.
                rr = call("GET", f"/v1/reviewSubmissionItems/{it['id']}/relationships/appAssetLibraryVideo")
                vid_rel = rr.get("data") if isinstance(rr, dict) and "error" not in rr else None
            if vid_rel:
                step("ancienne vidéo d'en-tête retirée de la demande", call("DELETE", f"/v1/reviewSubmissionItems/{it['id']}"))
    for v_ in ([] if os.environ.get("ASSETS_DIR") == "none" else call("GET", f"/v1/appAssetLibraries/{app_id}/videos?limit=50").get("data", [])):
        st = str(v_["attributes"].get("state") or "")
        if "APPROVED" in st or "REVIEW" in st or "REJECTED" in st:
            continue
        step(f"vidéo d'en-tête {v_['attributes'].get('referenceName')} ajoutée à la demande", call("POST", "/v1/reviewSubmissionItems", {"data": {
             "type": "reviewSubmissionItems", "relationships": {
                 "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                 "appAssetLibraryVideo": {"data": {"type": "appAssetLibraryVideos", "id": v_["id"]}}}}}),
             tolerate=("already", "ENTITY_ERROR", "STATE_ERROR"))
    # Le premier achat intégré (Foldly+) part avec cette version.
    late_iaps = []
    for x in call("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50").get("data", []):
        st = x["attributes"].get("state")
        print("       achat", x["attributes"].get("productId"), st)
        if st in ("READY_TO_SUBMIT", "DEVELOPER_ACTION_NEEDED", "REJECTED"):
            r_iap = step(f"achat {x['attributes'].get('productId')} envoyé avec la version", call("POST", "/v1/inAppPurchaseSubmissions", {"data": {
                 "type": "inAppPurchaseSubmissions", "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": x["id"]}}}}}),
                 tolerate=("already",))
            if isinstance(r_iap, dict) and "error" in r_iap and "no pending version" in r_iap.get("detail", ""):
                # Déjà ajouté à la version dans App Store Connect : il part avec la demande.
                problems.remove(f"achat {x['attributes'].get('productId')} envoyé avec la version")
                print(f"ok     achat {x['attributes'].get('productId')} déjà joint à la version")
                continue
            if isinstance(r_iap, dict) and "error" in r_iap and "FIRST_NON_CONSUMABLE" in r_iap.get("detail", ""):
                # Nouvelle app : le premier achat doit être dans la même demande que la version.
                r2 = step(f"achat {x['attributes'].get('productId')} ajouté à la demande", call("POST", "/v1/reviewSubmissionItems", {"data": {
                     "type": "reviewSubmissionItems", "relationships": {
                         "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                         "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": x["id"]}}}}}), tolerate=("already",))
                if isinstance(r2, dict) and "error" in r2:
                    print(r2.get("detail", "")[:1500])
                    late_iaps.append(x)
                continue
            if isinstance(r_iap, dict) and "error" in r_iap and "already" not in r_iap.get("detail", ""):
                print(r_iap.get("detail", "")[:3000])
                print("\nPAS ENVOYÉ : l'achat intégré n'a pas pu partir avec la version")
                sys.exit(1)
    r = step("ENVOI À LA VÉRIFICATION D'APPLE", call("PATCH", f"/v1/reviewSubmissions/{sub_id}", {"data": {
         "type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}}))
    # Dernier essai : les achats envoyés juste après la version (même moment pour Apple).
    for x in late_iaps:
        step(f"achat {x['attributes'].get('productId')} envoyé juste après la version", call("POST", "/v1/inAppPurchaseSubmissions", {"data": {
             "type": "inAppPurchaseSubmissions", "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": x["id"]}}}}}),
             tolerate=("already",))
    v = call("GET", f"/v1/appStoreVersions/{vid}").get("data", {}).get("attributes", {})
    print("état de la version :", v.get("appStoreState"))

print("\nPRÊT" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
