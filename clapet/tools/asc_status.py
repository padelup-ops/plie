"""DUO FOLDS : état des derniers builds sur App Store Connect (traitement, TestFlight, version 1.0)."""
import json, os, time, urllib.request, urllib.error
import jwt
API = "https://api.appstoreconnect.apple.com"
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 600,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
def call(path):
    req = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + token})
    try:
        return json.load(urllib.request.urlopen(req))
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:500]}
app = call("/v1/apps?filter[bundleId]=" + os.environ.get("APP_BUNDLE", "com.padelup.clapet"))["data"][0]
print("APP", app["id"], app["attributes"]["name"])
for b in call(f"/v1/builds?filter[app]={app['id']}&sort=-uploadedDate&limit=8&include=buildBetaDetail").get("data", []):
    a = b["attributes"]
    d = call(f"/v1/builds/{b['id']}/buildBetaDetail").get("data", {}).get("attributes", {})
    print(f"build {a.get('version')} | traitement {a.get('processingState')} | expiré {a.get('expired')} | "
          f"interne {d.get('internalBuildState')} | externe {d.get('externalBuildState')} | envoyé {a.get('uploadedDate', '')[:16]}")
for s in call(f"/v1/apps/{app['id']}/betaAppReviewSubmissions?limit=5").get("data", []) if False else []:
    pass
subs = call(f"/v1/betaAppReviewSubmissions?filter[build]=" + ",".join(b["id"] for b in call(f"/v1/builds?filter[app]={app['id']}&limit=8").get("data", [])))
for s in subs.get("data", []):
    print("vérification bêta", s["id"], s["attributes"].get("betaReviewState"), s["attributes"].get("submittedDate"))

# Les envois de builds (avec les erreurs d'Apple si un envoi a échoué)
ups = call(f"/v1/apps/{app['id']}/buildUploads?limit=6&sort=-uploadedDate")
if "error" in ups:
    ups = call(f"/v1/buildUploads?filter[app]={app['id']}&limit=6")
if "error" in ups:
    print("envois :", ups)
for u in ups.get("data", []):
    a = u["attributes"]
    print("envoi", a.get("cfBundleVersion"), a.get("cfBundleShortVersionString"), "|", (a.get("state") or {}) if not isinstance(a.get("state"), dict) else a["state"].get("state"),
          "|", json.dumps(a.get("state"))[:900] if isinstance(a.get("state"), dict) else json.dumps({k: v for k, v in a.items() if k not in ("cfBundleVersion",)})[:900])

# La version App Store
for v in call(f"/v1/apps/{app['id']}/appStoreVersions?limit=5").get("data", []):
    print("version App Store", v["attributes"].get("versionString"), "|", v["attributes"].get("appStoreState"))

# Captures et prix de la version en préparation
for v in call(f"/v1/apps/{app['id']}/appStoreVersions?limit=3").get("data", []):
    for l in call(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations").get("data", []):
        sets = call(f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets").get("data", [])
        desc = []
        for st in sets:
            n = len(call(f"/v1/appScreenshotSets/{st['id']}/appScreenshots").get("data", []))
            desc.append(f"{st['attributes'].get('screenshotDisplayType')}:{n}")
        print("captures", v["attributes"].get("versionString"), l["attributes"].get("locale"), desc)
    b = call(f"/v1/appStoreVersions/{v['id']}/build").get("data")
    print("build choisi", v["attributes"].get("versionString"), b["attributes"].get("version") if b else None)
sched = call(f"/v1/apps/{app['id']}/appPriceSchedule?include=manualPrices")
print("prix :", [x.get("relationships", {}).get("appPricePoint", {}).get("data", {}).get("id", "")[:40] for x in sched.get("included", [])] or sched.get("error"))
print("disponibilité :", "oui" if call(f"/v1/apps/{app['id']}/appAvailabilityV2").get("data") else "non")
iaps = call(f"/v1/apps/{app['id']}/inAppPurchasesV2?limit=10").get("data", [])
print("achats intégrés :", [(i["attributes"].get("productId"), i["attributes"].get("state")) for i in iaps])

# Sonde : quel type de captures pour l'iPhone Duo ? (l'erreur d'Apple liste les valeurs acceptées)
if os.environ.get("PROBE") == "1":
    def post(path, body):
        req = urllib.request.Request(API + path, method="POST", data=json.dumps(body).encode(),
                                     headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
        try:
            return json.load(urllib.request.urlopen(req))
        except urllib.error.HTTPError as e:
            return {"error": e.code, "detail": e.read().decode()[:3000]}
    v = next((v for v in call(f"/v1/apps/{app['id']}/appStoreVersions?limit=3").get("data", [])), None)
    loc = call(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations").get("data", [])[0]
    r = post("/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_IPHONE_DUO_PROBE"},
             "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})
    print("SONDE", json.dumps(r)[:3000])
