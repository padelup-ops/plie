"""Fin de la bêta TestFlight (Foldly par défaut, BUNDLE_ID pour une autre app).

MODE=probe : montre les builds, leurs groupes et ceux liés à une version App Store.
MODE=apply : coupe le lien public des groupes externes, retire les builds des groupes externes,
             et expire les builds qui ne servent pas à l'App Store (ceux d'une version en ligne ou en revue sont gardés).
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
        return {"error": e.code, "detail": e.read().decode()[:600]}

app = call("GET", "/v1/apps?filter[bundleId]=" + os.environ.get("BUNDLE_ID", "com.padelup.clapet"))["data"][0]
print("app", app["attributes"]["name"])
aid = app["id"]

# Les builds liés à une version App Store (en ligne, en revue…) : on ne les expire pas.
# On garde seulement la version en ligne la plus récente et celles en cours (revue, en attente).
keep = {}
live_seen = False
for v in call("GET", f"/v1/apps/{aid}/appStoreVersions?limit=10&include=build").get("data", []):
    st = v["attributes"].get("appStoreState") or v["attributes"].get("appVersionState")
    b = (v.get("relationships", {}).get("build", {}) or {}).get("data")
    print("version", v["attributes"]["versionString"], st, "build id", b and b["id"])
    if not b:
        continue
    if st == "READY_FOR_SALE":
        if live_seen:
            continue
        live_seen = True
    elif st in ("REPLACED_WITH_NEW_VERSION", "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE"):
        continue
    keep[b["id"]] = f'{v["attributes"]["versionString"]} {st}'

groups = [g for g in call("GET", f"/v1/apps/{aid}/betaGroups?limit=50").get("data", [])]
external = [g for g in groups if not g["attributes"].get("isInternalGroup")]
for g in groups:
    a = g["attributes"]
    ids = [x["id"] for x in call("GET", f"/v1/betaGroups/{g['id']}/builds?limit=50").get("data", [])]
    g["_builds"] = ids
    print(f'groupe {a["name"]} | interne {a.get("isInternalGroup")} | lien public {a.get("publicLinkEnabled")} | {len(ids)} builds')

builds = []
url = f"/v1/builds?filter[app]={aid}&limit=200&fields[builds]=version,expired,uploadedDate,processingState"
while url:
    page = call("GET", url)
    builds += page.get("data", [])
    nxt = page.get("links", {}).get("next")
    url = nxt.replace(API, "") if nxt else None
builds.sort(key=lambda b: int(b["attributes"]["version"]))
live = [b for b in builds if not b["attributes"].get("expired")]
print(f"\n{len(builds)} builds, {len(live)} pas encore expirés")
for b in live:
    tag = "GARDÉ (" + keep[b["id"]] + ")" if b["id"] in keep else "à expirer"
    inext = [g["attributes"]["name"] for g in external if b["id"] in g["_builds"]]
    print(f'  build {b["attributes"]["version"]:>4} | {tag} | groupes externes {inext}')

if MODE != "apply":
    sys.exit(0)

print("\n--- fin de la bêta")
for g in external:
    if g["attributes"].get("publicLinkEnabled"):
        r = call("PATCH", f"/v1/betaGroups/{g['id']}", {"data": {"type": "betaGroups", "id": g["id"],
                 "attributes": {"publicLinkEnabled": False}}})
        print("lien public coupé :", g["attributes"]["name"], "ok" if "error" not in r else f"ÉCHEC {r}")
    if g["_builds"]:
        r = call("DELETE", f"/v1/betaGroups/{g['id']}/relationships/builds",
                 {"data": [{"type": "builds", "id": i} for i in g["_builds"]]})
        print("builds retirés du groupe", g["attributes"]["name"], "ok" if "error" not in r else f"ÉCHEC {r}")
for b in live:
    if b["id"] in keep:
        continue
    r = call("PATCH", f"/v1/builds/{b['id']}", {"data": {"type": "builds", "id": b["id"], "attributes": {"expired": True}}})
    print("build", b["attributes"]["version"], "expiré" if "error" not in r else f"ÉCHEC {r['error']} {r['detail'][:200]}")
print("\nBÊTA ARRÊTÉE")
