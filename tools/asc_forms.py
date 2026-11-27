"""Sonde : ce qu'Apple réclame avant une première soumission (formulaires de conformité, confidentialité, captures).
Lecture seule, sauf FIX_EMPTY_SETS=1 qui supprime les jeux de captures vides (un jeu vide compte comme « requis mais
absent »). BUNDLE choisit l'app. N'écrit ni clé ni adresse."""
import json, os, time, urllib.request, urllib.error
import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = os.environ.get("BUNDLE", "").strip() or "com.padelup.allonoel"
FIX = os.environ.get("FIX_EMPTY_SETS") == "1"
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 900,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(p, method="GET"):
    req = urllib.request.Request(API + p, method=method, headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode(errors="replace")[:400]}


def attrs(x):
    return (x or {}).get("attributes") or {}


def show(label, r, n=900):
    print(label, json.dumps(r, ensure_ascii=False)[:n])


apps = call(f"/v1/apps?filter[bundleId]={BUNDLE}&limit=5").get("data", [])
app = next((a for a in apps if attrs(a).get("bundleId") == BUNDLE), None)
if not app:
    print("app introuvable")
    raise SystemExit(1)
aid = app["id"]
print("APP", aid, attrs(app).get("name"))
full = call(f"/v1/apps/{aid}").get("data") or {}
rels = sorted((full.get("relationships") or {}).keys())
print("relations de l'app :", rels)
for k in rels:
    if any(w in k.lower() for w in ("compliance", "form", "usage", "privacy", "declaration", "ppm", "aigener", "security")):
        show(f"  {k} ->", call(f"/v1/apps/{aid}/{k}?limit=20"))
for info in call(f"/v1/apps/{aid}/appInfos?limit=5").get("data", []):
    d = call(f"/v1/appInfos/{info['id']}").get("data") or {}
    irels = sorted((d.get("relationships") or {}).keys())
    print("INFOS", info["id"], attrs(d).get("state") or attrs(d).get("appStoreState"), "relations :", irels)
    show("  attributs ->", attrs(d), 700)
    for k in irels:
        if any(w in k.lower() for w in ("compliance", "form", "usage", "privacy", "declaration", "ppm", "age")):
            show(f"  {k} ->", call(f"/v1/appInfos/{info['id']}/{k}"), 700)
for guess in ("complianceForms", "appComplianceForms", "ppmForms", "complianceRequirements", "appDataUsagesPublishState",
              "dataUsagePublishState", "appDataUsages"):
    r = call(f"/v1/apps/{aid}/{guess}?limit=20")
    show(f"essai apps/{guess} ->", r, 500)

for v in call(f"/v1/apps/{aid}/appStoreVersions?filter[platform]=IOS&limit=3").get("data", []):
    print("VERSION", attrs(v).get("versionString"), attrs(v).get("appStoreState"))
    if attrs(v).get("appStoreState") in ("READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION"):
        continue
    for loc in call(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations?limit=50").get("data", []):
        sets = call(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets?limit=50").get("data", [])
        line = []
        for s in sets:
            n = len(call(f"/v1/appScreenshotSets/{s['id']}/appScreenshots?limit=20").get("data", []))
            line.append(f"{attrs(s).get('screenshotDisplayType')}={n}")
            if n == 0 and FIX:
                r = call(f"/v1/appScreenshotSets/{s['id']}", method="DELETE")
                print("   jeu vide supprimé" if "error" not in r else f"   suppression refusée {r}")
        print("  ", attrs(loc).get("locale"), loc["id"][:8], " ".join(line) or "aucun jeu")
