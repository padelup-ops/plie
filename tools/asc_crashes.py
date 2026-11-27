"""Les derniers plantages envoyés par les testeurs TestFlight (retour « plantage » de l'app TestFlight) pour une app.

Le dépôt est public : on n'affiche ni l'adresse ni le commentaire du testeur, seulement la date, l'appareil, iOS, le
build, le type d'exception et les fonctions du fil qui a planté.
  BUNDLE  (com.padelup.foldboard par défaut)   LIMIT  (5 par défaut)
"""
import json, os, re, time, urllib.request, urllib.error
import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = os.environ.get("BUNDLE", "").strip() or "com.padelup.foldboard"
LIMIT = int(os.environ.get("LIMIT", "") or 5)
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 900,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(p):
    req = urllib.request.Request(API + p if p.startswith("/") else p, headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:400]}


def clean(s):
    return re.sub(r"[\w.+-]+@[\w-]+\.[\w.-]+", "…@…", s or "")


app = call(f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]
print("APP", app["id"], app["attributes"].get("name"))
subs = call(f"/v1/apps/{app['id']}/betaFeedbackCrashSubmissions?limit={LIMIT}&sort=-createdDate")
if "error" in subs:
    print("ÉCHEC liste", subs["error"], clean(subs["detail"]))
    raise SystemExit(0)
rows = subs.get("data", [])
print("plantages envoyés :", len(rows))
for s in rows:
    a = s["attributes"]
    print("=" * 70)
    print("PLANTAGE", a.get("createdDate"), "|", a.get("deviceModel"), "| iOS", a.get("osVersion"), "| bundle", a.get("buildBundleId"),
          "| plateforme", a.get("appPlatform"), "| batterie", a.get("batteryPercentage"), "| orientation", a.get("screenOrientation") or a.get("orientation"))
    log = call(f"/v1/betaFeedbackCrashSubmissions/{s['id']}/crashLog")
    if "error" in log:
        print("   journal : ÉCHEC", log["error"], clean(log["detail"])[:200])
        continue
    text = (log.get("data", {}).get("attributes", {}) or {}).get("logText") or ""
    lines = text.splitlines()
    print("   journal :", len(lines), "lignes")
    keep = []
    for i, l in enumerate(lines):
        if re.search(r"^(Process|Identifier|Version|Hardware Model|OS Version|Exception|Termination|Triggered|Crashed Thread|Application Specific|Last Exception|Code Type|Role|Date/Time)", l) \
                or "EXC_" in l or "abort" in l.lower() and i < 80 or "Fatal error" in l or "jetsam" in l.lower() or "memory" in l.lower() and i < 80:
            keep.append(l)
    for l in keep[:40]:
        print("   ", clean(l)[:220])
    # Le fil qui a planté : ses 30 premières fonctions.
    start = next((i for i, l in enumerate(lines) if re.match(r"Thread \d+.*Crashed", l)), None)
    if start is None:
        start = next((i for i, l in enumerate(lines) if l.startswith("Last Exception Backtrace")), None)
    if start is not None:
        for l in lines[start:start + 32]:
            print("   |", clean(l)[:220])
    else:
        # Journal au format JSON (.ips) : on montre les lignes qui parlent de Foldboard.
        for l in [x for x in lines if "Foldboard" in x or "Keyboard" in x][:40]:
            print("   |", clean(l)[:220])
