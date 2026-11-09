"""Fiches App Store dans toutes les langues (nom, sous-titre, mots-clés, description, texte promo).

MODE=probe : montre, pour chaque app, les versions, les langues présentes et les textes en-US / fr-FR.
MODE=apply : pour l'app APP (foldly | origamo | waffle), ajoute ou met à jour chaque langue de tools/meta/<app>.json
             sur la version modifiable (et sur la fiche de l'app : nom, sous-titre).
"""
import json, os, sys, time, urllib.request, urllib.error
import jwt
API = "https://api.appstoreconnect.apple.com"
MODE = os.environ.get("MODE", "probe")
APP = os.environ.get("APP", "")
BUNDLES = {"foldly": "com.padelup.clapet", "origamo": os.environ.get("ORIGAMO_BUNDLE", ""), "waffle": "com.padelup.waffle"}
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
        return {"error": e.code, "detail": e.read().decode()[:700]}

EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW"}

def app_of(key):
    return call("GET", f"/v1/apps?filter[bundleId]={BUNDLES[key]}")["data"][0]

def versions(app_id):
    return call("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10").get("data", [])

def infos(app_id):
    return call("GET", f"/v1/apps/{app_id}/appInfos").get("data", [])

if MODE == "probe":
    for key in ("foldly", "origamo", "waffle"):
        if not BUNDLES[key]:
            continue
        app = app_of(key)
        print(f"\n===== {key} {app['id']} {app['attributes']['name']}")
        vs = versions(app["id"])
        for v in vs[:4]:
            print("version", v["attributes"]["versionString"], v["attributes"].get("appStoreState"))
        for inf in infos(app["id"]):
            st = inf["attributes"].get("appStoreState") or inf["attributes"].get("state")
            locs = call("GET", f"/v1/appInfos/{inf['id']}/appInfoLocalizations?limit=50").get("data", [])
            print("appInfo", st, "langues:", sorted(l["attributes"]["locale"] for l in locs))
            for l in locs:
                a = l["attributes"]
                if a["locale"] in ("en-US", "fr-FR"):
                    print("  ", a["locale"], "|", a.get("name"), "|", a.get("subtitle"))
        if vs:
            v = vs[0]
            locs = call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations?limit=50").get("data", [])
            print("version", v["attributes"]["versionString"], "langues:", sorted(l["attributes"]["locale"] for l in locs))
            for l in locs:
                a = l["attributes"]
                if a["locale"] in ("en-US", "fr-FR"):
                    print(f"--- {a['locale']} keywords: {a.get('keywords')}")
                    print(f"--- {a['locale']} promo: {a.get('promotionalText')}")
                    print(f"--- {a['locale']} description:\n{a.get('description')}\n")
    sys.exit(0)

# ---------------- apply
data = json.load(open(f"tools/meta/{APP}.json"))
app = app_of(APP)
vs = versions(app["id"])
v = next((x for x in vs if x["attributes"].get("appStoreState") in EDITABLE - {"WAITING_FOR_REVIEW"}), None)
if not v:
    sys.exit("ÉCHEC : aucune version modifiable pour " + APP + " (états : " + ", ".join(x["attributes"].get("appStoreState") for x in vs[:3]) + ")")
print("version modifiable :", v["attributes"]["versionString"], v["attributes"]["appStoreState"])
info = next((i for i in infos(app["id"]) if (i["attributes"].get("appStoreState") or i["attributes"].get("state")) not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION")), None) or infos(app["id"])[0]
have_v = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations?limit=50").get("data", [])}
have_i = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=50").get("data", [])}
ok_n = 0
for loc, m in data["locales"].items():
    if loc in data.get("skip", []):
        continue
    attrs_i = {"name": m["name"][:30], "subtitle": m["subtitle"][:30]}
    if loc in have_i:
        r = call("PATCH", f"/v1/appInfoLocalizations/{have_i[loc]['id']}", {"data": {"type": "appInfoLocalizations", "id": have_i[loc]["id"], "attributes": attrs_i}})
    else:
        r = call("POST", "/v1/appInfoLocalizations", {"data": {"type": "appInfoLocalizations", "attributes": {"locale": loc, **attrs_i},
                 "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}})
    if "error" in r:
        print(f"ÉCHEC nom {loc}: {r['error']} {r['detail'][:300]}")
    attrs_v = {"description": m["description"][:4000], "keywords": m["keywords"][:100], "promotionalText": m["promo"][:170]}
    if data.get("support"):
        attrs_v["supportUrl"] = data["support"]
    if v["attributes"]["versionString"] != "1.0" or data.get("update"):
        attrs_v["whatsNew"] = m.get("whatsNew") or data["locales"]["en-US"].get("whatsNew", "Improvements and fixes.")
    if loc in have_v:
        if loc in data.get("keep_existing", []):
            attrs_v = {k: attrs_v[k] for k in ("keywords", "promotionalText") if k in attrs_v}
        r = call("PATCH", f"/v1/appStoreVersionLocalizations/{have_v[loc]['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": have_v[loc]["id"], "attributes": attrs_v}})
    else:
        r = call("POST", "/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations", "attributes": {"locale": loc, **attrs_v},
                 "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    if "error" in r:
        print(f"ÉCHEC fiche {loc}: {r['error']} {r['detail'][:300]}")
    else:
        ok_n += 1
print(f"\nLANGUES OK : {ok_n} / {len(data['locales'])}")
