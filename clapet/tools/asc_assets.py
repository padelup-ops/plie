"""Les « creative assets » d'App Store Connect (iOS 27) : la vidéo d'en-tête de la fiche et celle des résultats de recherche.

MODE=discover   lit la bibliothèque d'assets de l'app et les données de référence (placements, spécifications)
MODE=upload     envoie les vidéos de ASSETS_DIR/<locale>/(header|search).mp4 dans la bibliothèque (sans rien soumettre)
MODE=place      les place sur la version modifiable (en-tête et recherche, par langue) : elles partent en vérification avec elle
"""
import hashlib, json, os, sys, time, urllib.request, urllib.error
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


# ---------------------------------------------------------------- envoi dans la bibliothèque (sans rien soumettre)
LIB = (lib.get("data") or {}).get("id")
ASSETS_DIR = os.environ.get("ASSETS_DIR", "clapet/tools/store/creative")
KINDS = {"header": "PRODUCT_PAGE_HEADER_ASSET", "search": "APP_STORE_SEARCH_RESULTS_ASSET"}
problems = []


def library_videos():
    out, url = [], f"/v1/appAssetLibraries/{LIB}/videos?limit=200"
    while url:
        r = call("GET", url)
        if "error" in r:
            print("liste des vidéos :", short(r, 600))
            return out
        out += r.get("data", [])
        url = (r.get("links") or {}).get("next")
    return out


def reserve(name, size, ref):
    """Réserve la vidéo dans la bibliothèque (le nom de la relation n'est pas encore documenté partout : on essaie)."""
    last = None
    for rel in ("appAssetLibrary", "library", "assetLibrary"):
        for attrs in ({"fileName": name, "fileSize": size, "category": "CREATIVE_ASSETS", "referenceName": ref},
                      {"fileName": name, "fileSize": size, "category": "CREATIVE_ASSETS"}):
            body = {"data": {"type": "appAssetLibraryVideos", "attributes": attrs,
                             "relationships": {rel: {"data": {"type": "appAssetLibraries", "id": LIB}}}}}
            r = call("POST", "/v1/appAssetLibraryVideos", body)
            if "error" not in r:
                print(f"       réservée (relation « {rel} », attributs {sorted(attrs)})")
                return r
            last = r
            if "referenceName" not in r["detail"] and "relationship" not in r["detail"].lower():
                break
    print("ÉCHEC  réservation :", short(last, 900))
    return None


def upload_file(path, ref):
    data = open(path, "rb").read()
    r = reserve(os.path.basename(path), len(data), ref)
    if not r:
        problems.append(os.path.basename(path))
        return None
    vid = r["data"]["id"]
    ops = r["data"]["attributes"].get("uploadOperations") or []
    for op in ops:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op.get("method", "PUT"),
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
        urllib.request.urlopen(req).read()
    print(f"       {len(ops)} morceau(x) envoyé(s)")
    c = call("PATCH", f"/v1/appAssetLibraryVideos/{vid}", {"data": {"type": "appAssetLibraryVideos", "id": vid,
             "attributes": {"uploaded": True}}})
    if "error" in c:
        print("ÉCHEC  validation de l'envoi :", short(c, 600))
        problems.append(os.path.basename(path))
        return vid
    for attempt in range(60):
        a = call("GET", f"/v1/appAssetLibraryVideos/{vid}").get("data", {}).get("attributes", {})
        state = a.get("state") or (a.get("assetDeliveryState") or {}).get("state")
        if state not in ("UPLOAD_COMPLETE", "AWAITING_UPLOAD", "PROCESSING", None) or attempt == 59:
            print(f"       état {state} · spécification {a.get('specId')} · {short({k: v for k, v in a.items() if k not in ('uploadOperations',)}, 900)}")
            break
        time.sleep(15)
    return vid


if MODE == "upload":
    have = {v["attributes"].get("referenceName"): v for v in library_videos()}
    print(len(have), "vidéo(s) déjà dans la bibliothèque")
    report = {}
    for locale in sorted(os.listdir(ASSETS_DIR)):
        folder = os.path.join(ASSETS_DIR, locale)
        if not os.path.isdir(folder):
            continue
        for kind in KINDS:
            path = os.path.join(folder, kind + ".mp4")
            if not os.path.exists(path):
                continue
            digest = hashlib.md5(open(path, "rb").read()).hexdigest()[:12]
            ref = f"{kind}-{locale}-{digest}"
            if ref in have:
                print(f"ok     {kind} {locale} déjà envoyée ({have[ref]['id']})")
                report[f"{locale}/{kind}"] = have[ref]["id"]
                continue
            print(f"envoi  {kind} {locale} ({os.path.getsize(path) // 1024} Ko)")
            vid = upload_file(path, ref)
            if vid:
                report[f"{locale}/{kind}"] = vid
    json.dump(report, open("out/assets.json", "w"), indent=1)
    print("\nENVOYÉ DANS LA BIBLIOTHÈQUE" if not problems else "\nÀ REVOIR : " + ", ".join(problems))


# ---------------------------------------------------------------- placement sur la version suivante (MODE=place)
def placements_of(loc_id):
    r = call("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/placements?limit=50")
    return r.get("data", []) if "error" not in r else []


def create_placement(kind, vid, loc_id):
    last = None
    for vrel in ("video", "asset", "appAssetLibraryVideo"):
        for lrel in ("appStoreVersionLocalization", "localization"):
            body = {"data": {"type": "appAssetLibraryPlacements",
                             "attributes": {"placementType": KINDS[kind], "placementGroup": "DEFAULT_PROFILE"},
                             "relationships": {vrel: {"data": {"type": "appAssetLibraryVideos", "id": vid}},
                                               lrel: {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}}
            r = call("POST", "/v1/appAssetLibraryPlacements", body)
            if "error" not in r:
                return r
            last = r
            if "relationship" not in r["detail"].lower():
                return r
    return last


if MODE == "place":
    versions = call("GET", f"/v1/apps/{app['id']}/appStoreVersions?filter[platform]=IOS&limit=10").get("data", [])
    version = next((v for v in versions if v["attributes"].get("appStoreState") in
                    ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")), None)
    if not version:
        print("aucune version modifiable : les vidéos seront placées sur la prochaine version",
              [(v["attributes"].get("versionString"), v["attributes"].get("appStoreState")) for v in versions])
        sys.exit(0)
    print("VERSION", version["attributes"].get("versionString"), version["attributes"].get("appStoreState"))
    have = {v["attributes"].get("referenceName") or "": v for v in library_videos()}
    for loc in call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations").get("data", []):
        locale = loc["attributes"]["locale"]
        current = placements_of(loc["id"])
        for kind in KINDS:
            path = os.path.join(ASSETS_DIR, locale, kind + ".mp4")
            if not os.path.exists(path):
                continue
            digest = hashlib.md5(open(path, "rb").read()).hexdigest()[:12]
            asset = have.get(f"{kind}-{locale}-{digest}")
            if not asset:
                print(f"ÉCHEC  {kind} {locale} : pas encore dans la bibliothèque (lancer MODE=upload)")
                problems.append(f"{kind} {locale}")
                continue
            # Une seule vidéo par emplacement : on retire l'ancienne.
            for p in current:
                if (p["attributes"].get("placementType") == KINDS[kind]):
                    call("DELETE", f"/v1/appAssetLibraryPlacements/{p['id']}")
            r = create_placement(kind, asset["id"], loc["id"])
            if "error" in r:
                print(f"ÉCHEC  {kind} {locale} :", short(r, 900))
                problems.append(f"{kind} {locale}")
            else:
                print(f"ok     {kind} {locale} placée sur la version")
    print("\nPLACÉES" if not problems else "\nÀ REVOIR : " + ", ".join(problems))
