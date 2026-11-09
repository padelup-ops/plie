"""FOLDLY : Game Center (détail, classements ouverts à tous et concours du mois, textes FR/EN) et lien avec une version (VERSION=1.0.2)."""
import json, os, sys, time, urllib.request, urllib.error
import jwt
API = "https://api.appstoreconnect.apple.com"
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 600,
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
        return {"error": e.code, "detail": e.read().decode()[:600]}

def ok(label, r):
    print(("ÉCHEC  " + label + f" -> {r['error']} {r['detail'][:400]}") if "error" in r else ("ok     " + label))
    return r

app = call("GET", "/v1/apps?filter[bundleId]=com.padelup.clapet")["data"][0]
app_id = app["id"]
gcd = call("GET", f"/v1/apps/{app_id}/gameCenterDetail").get("data")
if not gcd:
    gcd = ok("Game Center activé", call("POST", "/v1/gameCenterDetails", {"data": {"type": "gameCenterDetails",
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})).get("data")
if not gcd:
    sys.exit(1)
print("Game Center", gcd["id"])

# rec : None (classique), ou (début, durée, règle) pour un classement qui se renouvelle.
DAILY = ("2026-11-08T23:00:00Z", ["PT24H"], "FREQ=DAILY;INTERVAL=1")
WEEKLY = ("2026-11-08T23:00:00Z", ["PT168H"], "FREQ=WEEKLY;INTERVAL=1")
MONTHLY = ("2026-11-09T23:00:00Z", ["P1M", "PT720H", "PT672H"], "FREQ=MONTHLY;INTERVAL=1")
MONTHLY_FALLBACK = ("2026-11-09T23:00:00Z", ["PT720H"], "FREQ=DAILY;INTERVAL=30")
BOARDS = [
    {"vendorIdentifier": "foldly.streak", "referenceName": "Longest streak under limit", "rec": "old30" and None,
     "en-US": ("Longest streak under limit", "days", "day"), "fr-FR": ("Plus longue série sous limite", "jours", "jour")},
    {"vendorIdentifier": "foldly.month", "referenceName": "Days under limit, 30 days", "rec": ("2026-11-03T23:00:00Z", ["PT720H"], "FREQ=DAILY;INTERVAL=30"),
     "en-US": ("Days under limit (30 days)", "days", "day"), "fr-FR": ("Jours sous limite (30 jours)", "jours", "jour")},
    {"vendorIdentifier": "foldly.folds.day", "referenceName": "Folds today", "rec": DAILY,
     "en-US": ("Most folds today", "folds", "fold"), "fr-FR": ("Le plus de plis aujourd'hui", "plis", "pli")},
    {"vendorIdentifier": "foldly.folds.week", "referenceName": "Folds this week", "rec": WEEKLY,
     "en-US": ("Most folds this week", "folds", "fold"), "fr-FR": ("Le plus de plis cette semaine", "plis", "pli")},
    {"vendorIdentifier": "foldly.folds.total", "referenceName": "Folds since day one", "rec": None,
     "en-US": ("Most folds since day one", "folds", "fold"), "fr-FR": ("Le plus de plis depuis le début", "plis", "pli")},
    {"vendorIdentifier": "foldly.contest.folds", "referenceName": "Contest: most folds", "rec": MONTHLY,
     "en-US": ("Contest: most folds", "folds", "fold"), "fr-FR": ("Concours : le plus de plis", "plis", "pli")},
    {"vendorIdentifier": "foldly.contest.open", "referenceName": "Contest: most time unfolded", "rec": MONTHLY,
     "en-US": ("Contest: most time unfolded", "min", "min"), "fr-FR": ("Concours : le plus de temps déplié", "min", "min")},
    {"vendorIdentifier": "foldly.contest.calm", "referenceName": "Contest: the calmest", "rec": MONTHLY, "sort": "ASC", "fmt": "DECIMAL_POINT_1_PLACE",
     "en-US": ("Contest: the calmest", "folds/day", "fold/day"), "fr-FR": ("Concours : le plus zen", "plis/jour", "pli/jour")},
]
have = {b["attributes"]["vendorIdentifier"]: b for b in call("GET", f"/v1/gameCenterDetails/{gcd['id']}/gameCenterLeaderboards?limit=50").get("data", [])}
for b in BOARDS:
    lb = have.get(b["vendorIdentifier"])
    if not lb:
        attrs = {"referenceName": b["referenceName"], "vendorIdentifier": b["vendorIdentifier"], "defaultFormatter": b.get("fmt", "INTEGER"),
                 "submissionType": "BEST_SCORE", "scoreSortType": b.get("sort", "DESC"), "scoreRangeStart": "0", "scoreRangeEnd": "10000000"}
        tries = [{}]
        if b["rec"]:
            recs = [b["rec"]] + ([MONTHLY_FALLBACK] if b["rec"] is MONTHLY else [])
            tries = [{"recurrenceStartDate": start, "recurrenceDuration": d, "recurrenceRule": rule} for start, durs, rule in recs for d in durs]
        for extra in tries:
            r = call("POST", "/v1/gameCenterLeaderboards", {"data": {"type": "gameCenterLeaderboards",
                "attributes": {**attrs, **extra}, "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": gcd["id"]}}}}})
            lb = ok("classement " + b["vendorIdentifier"] + (" " + extra.get("recurrenceDuration", "") + " " + extra.get("recurrenceRule", "") if extra else ""), r).get("data")
            if lb:
                break
    else:
        print("ok     classement " + b["vendorIdentifier"] + " (déjà créé)")
    if not lb:
        continue
    locs = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/gameCenterLeaderboards/{lb['id']}/localizations").get("data", [])}
    for locale in ("en-US", "fr-FR"):
        name, plural, singular = b[locale]
        attrs = {"name": name[:32], "formatterSuffix": " " + plural, "formatterSuffixSingular": " " + singular}
        if locale in locs:
            ok(f"  texte {locale}", call("PATCH", f"/v1/gameCenterLeaderboardLocalizations/{locs[locale]['id']}", {"data": {
                "type": "gameCenterLeaderboardLocalizations", "id": locs[locale]["id"], "attributes": attrs}}))
        else:
            ok(f"  texte {locale}", call("POST", "/v1/gameCenterLeaderboardLocalizations", {"data": {"type": "gameCenterLeaderboardLocalizations",
                "attributes": {"locale": locale, **attrs},
                "relationships": {"gameCenterLeaderboard": {"data": {"type": "gameCenterLeaderboards", "id": lb["id"]}}}}}))

VERSION = os.environ.get("VERSION", "").strip()
if VERSION:
    v = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&filter[versionString]={VERSION}").get("data", [])
    if not v:
        print("version", VERSION, "pas encore créée")
    else:
        ok(f"Game Center lié à la version {VERSION}", call("POST", "/v1/gameCenterAppVersions", {"data": {"type": "gameCenterAppVersions",
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v[0]["id"]}}}}}))
print("FIN")
