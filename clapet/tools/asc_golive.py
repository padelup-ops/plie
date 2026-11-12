"""FOLDLY : publie la version validée par Apple (sortie manuelle) et passe l'app en gratuit au même moment.
VERSION=1.0.3. Ne fait rien si la version n'est pas encore validée."""
import json, os, sys, time, urllib.request, urllib.error
import jwt
API = "https://api.appstoreconnect.apple.com"
VERSION = os.environ.get("VERSION", "1.0.3")
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read(); return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:1500]}
app = call("GET", "/v1/apps?filter[bundleId]=com.padelup.clapet")["data"][0]
app_id = app["id"]
v = call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[versionString]={VERSION}")["data"][0]
state = v["attributes"].get("appStoreState")
print("version", VERSION, state)
if state != "PENDING_DEVELOPER_RELEASE":
    print("PAS ENCORE VALIDÉE : rien à faire")
    sys.exit(0)
# 1. L'app passe en gratuit (base France, 0 €) — sauf KEEP_PRICE=1 (l'app est déjà gratuite)
if os.environ.get("KEEP_PRICE") == "1":
    r = call("POST", "/v1/appStoreVersionReleaseRequests", {"data": {"type": "appStoreVersionReleaseRequests",
             "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    print("publication :", "ok" if "error" not in r else r)
    time.sleep(5)
    print("état :", call("GET", f"/v1/appStoreVersions/{v['id']}")["data"]["attributes"].get("appStoreState"))
    print("PUBLIÉE")
    sys.exit(0)
point, url = None, f"/v1/apps/{app_id}/appPricePoints?filter[territory]=FRA&limit=200"
while url and not point:
    page = call("GET", url)
    point = next((p for p in page.get("data", []) if float(p["attributes"].get("customerPrice") or 0) == 0), None)
    nxt = page.get("links", {}).get("next"); url = nxt.replace(API, "") if nxt else None
if not point:
    sys.exit("palier gratuit introuvable")
r = call("POST", "/v1/appPriceSchedules", {"data": {"type": "appPriceSchedules", "relationships": {
    "app": {"data": {"type": "apps", "id": app_id}},
    "baseTerritory": {"data": {"type": "territories", "id": "FRA"}},
    "manualPrices": {"data": [{"type": "appPrices", "id": "${p}"}]}}},
    "included": [{"type": "appPrices", "id": "${p}", "attributes": {"startDate": None},
                  "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": point["id"]}}}}]})
print("app gratuite :", "ok" if "error" not in r else r)
# 2. Publication de la version
r = call("POST", "/v1/appStoreVersionReleaseRequests", {"data": {"type": "appStoreVersionReleaseRequests",
         "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
print("publication :", "ok" if "error" not in r else r)
time.sleep(5)
print("état :", call("GET", f"/v1/appStoreVersions/{v['id']}")["data"]["attributes"].get("appStoreState"))
print("PUBLIÉE")
