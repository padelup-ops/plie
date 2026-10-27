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
app = call("/v1/apps?filter[bundleId]=com.padelup.clapet")["data"][0]
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
