"""Candidatures « mise en vedette » (Featuring nominations) dans App Store Connect.

MODE=probe  : liste les candidatures existantes (brouillons et envoyées).
MODE=create : crée et envoie une candidature par app : Foldly 1.0.12 et Origamo 1.6 (sauf si une du même nom existe).
"""
import json, os, sys, time, urllib.request, urllib.error
import jwt
API = "https://api.appstoreconnect.apple.com"
MODE = os.environ.get("MODE", "probe")
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
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
        return {"error": e.code, "detail": e.read().decode()[:1500]}

def app_id(bundle):
    return call("GET", f"/v1/apps?filter[bundleId]={bundle}")["data"][0]["id"]

FOLDLY = app_id("com.padelup.clapet")
ORIGAMO = app_id(os.environ["ORIGAMO_BUNDLE"])

existing = []
for state in ("DRAFT", "SUBMITTED", "ARCHIVED"):
    r = call("GET", f"/v1/nominations?filter[state]={state}&limit=50&include=relatedApps")
    if "error" in r:
        print("liste", state, "->", r["error"], r["detail"][:400])
        continue
    for n in r.get("data", []):
        a = n["attributes"]
        apps = [x["id"] for x in n.get("relationships", {}).get("relatedApps", {}).get("data", [])]
        existing.append(a.get("name"))
        print(f"{state:9} | {a.get('name')} | {a.get('type')} | sortie {a.get('publishStartDate')} | apps {apps}")

NOMS = [
    (FOLDLY, "Foldly 1.0.12: public leaderboards and a monthly contest", "APP_ENHANCEMENTS",
     "Foldly is one of the first apps built around the iPhone Duo's hinge. It counts how many times you fold and unfold your Duo each day, "
     "like a step counter for your phone habit, so you notice when you unfold it out of boredom and pick it up a little less. "
     "1,000 people downloaded Foldly in its first 3 days, and 1 in 5 of them bought Foldly+. "
     "Version 1.0.12 adds free leaderboards for everyone (who folds the most today, this week and since day one), a monthly contest whose "
     "winners get Foldly+ and pick a new feature, and a today-by-hour view on the home screen, requested by our users. "
     "Foldly uses the hinge API, Live Activities, home and lock screen widgets, an Apple Watch app and Game Center. It works on the inner and "
     "the outer screen, has no ads and no account, keeps all data on the device, and is available in 7 languages."),
    (ORIGAMO, "Origamo 1.6: folding mini games for iPhone Duo", "APP_ENHANCEMENTS",
     "Origamo is a collection of mini games where the iPhone Duo's hinge is the controller. You flick the hinge to cast your line in Fishing, "
     "fold to fire in Comet, tilt to aim in Mini Golf, and play face to face with a friend with the phone open flat. "
     "Version 1.6 adds three new games (Fishing, Mini Golf, Comet), a free trial of every game and a free game of the day, dark mode, and "
     "Game Center leaderboards. Origamo uses the inner and the outer screen, has no ads, and is available in 7 languages."),
]

if MODE != "create":
    sys.exit(0)

start = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() + 3 * 86400))
for app, name, kind, desc in NOMS:
    if name in existing:
        print("déjà là :", name)
        continue
    body = {"data": {"type": "nominations",
            "attributes": {"name": name, "type": kind, "description": desc[:1000], "submitted": True,
                           "publishStartDate": start, "deviceFamilies": ["IPHONE"], "hasInAppEvents": False,
                           "launchInSelectedMarketsFirst": False, "preOrderEnabled": False,
                           "notes": "Built for iPhone Duo (inner and outer screens, hinge API)."},
            "relationships": {"relatedApps": {"data": [{"type": "apps", "id": app}]}}}}
    r = call("POST", "/v1/nominations", body)
    if "error" in r:
        print("ÉCHEC", name, "->", r["error"], r["detail"][:900])
    else:
        print("ENVOYÉE", name, r["data"]["attributes"].get("state"))
