"""Les « creative assets » d'App Store Connect (iOS 27) : la vidéo d'en-tête de la fiche et celle des résultats de recherche.

MODE=discover   lit la bibliothèque d'assets de l'app et les données de référence (placements, spécifications)
MODE=upload     envoie les vidéos de ASSETS_DIR/<locale>/(header|search).mp4 dans la bibliothèque (sans rien soumettre)
MODE=place      les place sur la version modifiable (en-tête et recherche, par langue) : elles partent en vérification avec elle
"""
import json, os, sys, time, urllib.request, urllib.error
import jwt

API = "https://api.appstoreconnect.apple.com"
MODE = os.environ.get("MODE", "discover")
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None, raw=False):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(path if path.startswith("http") else API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            txt = r.read()
            return json.loads(txt) if txt else {}
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:1500]}


def short(obj, n=2500):
    s = json.dumps(obj, ensure_ascii=False)
    return s if len(s) <= n else s[:n] + " …"


app = call("GET", "/v1/apps?filter[bundleId]=" + os.environ.get("APP_BUNDLE", "com.padelup.clapet"))["data"][0]
print("APP", app["id"], app["attributes"]["name"])
lib = call("GET", f"/v1/apps/{app['id']}/assetLibrary")
print("bibliothèque :", short(lib, 1200))

if MODE == "discover":
    ref = call("GET", "/v1/appAssetLibraryRefData")
    os.makedirs("out", exist_ok=True)
    json.dump(ref, open("out/refdata.json", "w"), ensure_ascii=False, indent=1)
    print("données de référence :", len(json.dumps(ref)), "caractères (out/refdata.json)")
    # Ce qui concerne les en-têtes et la recherche
    txt = json.dumps(ref, ensure_ascii=False)
    for word in ("PRODUCT_PAGE_HEADER_ASSET", "APP_STORE_SEARCH_RESULTS_ASSET", "CREATIVE_ASSETS", "DEFAULT_PROFILE"):
        print(word, "présent" if word in txt else "absent")
    if "data" in ref:
        d = ref["data"]
        a = d.get("attributes", d) if isinstance(d, dict) else {}
        print("clés :", list(a.keys())[:40] if isinstance(a, dict) else type(a))
    lib_id = (lib.get("data") or {}).get("id")
    if lib_id:
        for kind in ("appAssetLibraryImages", "appAssetLibraryVideos"):
            r = call("GET", f"/v1/appAssetLibraries/{lib_id}/{kind[0].lower() + kind[1:]}?limit=20")
            if "error" in r:
                r = call("GET", f"/v1/{kind}?filter[appAssetLibrary]={lib_id}&limit=20")
            print(kind, ":", short(r, 1500))
    for v in call("GET", f"/v1/apps/{app['id']}/appStoreVersions?limit=3").get("data", []):
        print("version", v["id"], v["attributes"].get("versionString"), v["attributes"].get("appStoreState"))
