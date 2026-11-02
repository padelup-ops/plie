"""FOLDLY : Game Center (détail, deux classements, textes FR/EN) et lien avec une version (VERSION=1.0.2)."""
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

app_id = app["id"]
gcd = call("GET", f"/v1/apps/{app_id}/gameCenterDetail").get("data")
if not gcd:
    gcd = ok("Game Center activé", call("POST", "/v1/gameCenterDetails", {"data": {"type": "gameCenterDetails",
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})).get("data")
if not gcd:
    sys.exit(1)
print("Game Center", gcd["id"])

BOARDS = [
    {"vendorIdentifier": "foldly.streak", "referenceName": "Longest streak under limit", "monthly": False,
     "en-US": ("Longest streak under your limit", "days", "day"), "fr-FR": ("Plus longue série sous ta limite", "jours", "jour")},
    {"vendorIdentifier": "foldly.month", "referenceName": "Days under limit this month", "monthly": True,
     "en-US": ("Days under your limit this month", "days", "day"), "fr-FR": ("Jours sous ta limite ce mois-ci", "jours", "jour")},
]
have = {b["attributes"]["vendorIdentifier"]: b for b in call("GET", f"/v1/gameCenterDetails/{gcd['id']}/gameCenterLeaderboards?limit=50").get("data", [])}
for b in BOARDS:
    lb = have.get(b["vendorIdentifier"])
    if not lb:
        attrs = {"referenceName": b["referenceName"], "vendorIdentifier": b["vendorIdentifier"], "defaultFormatter": "INTEGER",
                 "submissionType": "BEST_SCORE", "scoreSortType": "DESC", "scoreRangeStart": "0", "scoreRangeEnd": "100000"}
        if b["monthly"]:
            attrs.update({"recurrenceStartDate": "2026-11-01T00:00:00Z", "recurrenceDuration": "P1M", "recurrenceRule": "FREQ=MONTHLY;INTERVAL=1"})
        lb = ok("classement " + b["vendorIdentifier"], call("POST", "/v1/gameCenterLeaderboards", {"data": {"type": "gameCenterLeaderboards",
            "attributes": attrs, "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": gcd["id"]}}}}})).get("data")
    else:
        print("ok     classement " + b["vendorIdentifier"] + " (déjà créé)")
    if not lb:
        continue
    locs = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/gameCenterLeaderboards/{lb['id']}/localizations").get("data", [])}
    for locale in ("en-US", "fr-FR"):
        name, plural, singular = b[locale]
        attrs = {"name": name, "formatterSuffix": " " + plural, "formatterSuffixSingular": " " + singular}
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
