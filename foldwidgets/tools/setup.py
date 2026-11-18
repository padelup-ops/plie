"""FOLD WIDGETS : prépare les identifiants (app, widget, groupe d'app) et regarde la fiche.

Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY.
N'utilise pas BUNDLE_ID : ce secret reste celui d'Origamo. L'équipe n'est pas lue ici
(la signature passe par APPLE_TEAM_ID dans le workflow).

La fiche App Store Connect ne peut pas être créée par l'API : s'il n'y en a pas,
le script l'écrit et s'arrête. Le workflow n'envoie alors rien sur TestFlight.
"""
import base64
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
APP = "com.padelup.foldwidgets"
WIDGET = APP + ".widget"
GROUP = "group.com.padelup.foldwidgets"

token = jwt.encode(
    {
        "iss": os.environ["ASC_ISSUER_ID"],
        "iat": int(time.time()),
        "exp": int(time.time()) + 1200,
        "aud": "appstoreconnect-v1",
    },
    os.environ["ASC_PRIVATE_KEY"],
    algorithm="ES256",
    headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
)


def call(method, path, body=None):
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(
        API + path,
        method=method,
        data=data,
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        return {"error": error.code, "detail": error.read().decode()[:800]}


def bundle_ids():
    found = {}
    path = "/v1/bundleIds?limit=200&filter[platform]=IOS"
    page = call("GET", path)
    for item in page.get("data", []):
        found[item["attributes"]["identifier"]] = item["id"]
    return found


existing = bundle_ids()
ids = {}
for ident, name in ((APP, "Fold Widgets"), (WIDGET, "Fold Widgets Widget")):
    if ident in existing:
        ids[ident] = existing[ident]
        print("ok     identifiant déjà là :", ident)
        continue
    created = call(
        "POST",
        "/v1/bundleIds",
        {"data": {"type": "bundleIds", "attributes": {"identifier": ident, "name": name, "platform": "IOS"}}},
    )
    if "data" in created:
        ids[ident] = created["data"]["id"]
        print("ok     identifiant créé :", ident)
    else:
        print("ÉCHEC  identifiant :", ident, created)


def enable_group(bundle_resource_id):
    """Turns the App Groups capability on. Apple's API accepts no group id here:
    creating group.com.padelup.foldwidgets and assigning it is done in the developer portal.
    """
    caps = call("GET", f"/v1/bundleIds/{bundle_resource_id}/bundleIdCapabilities").get("data", [])
    if any(item["attributes"].get("capabilityType") == "APP_GROUPS" for item in caps):
        print("ok     App Groups déjà actif :", bundle_resource_id)
        return
    result = call(
        "POST",
        "/v1/bundleIdCapabilities",
        {
            "data": {
                "type": "bundleIdCapabilities",
                "attributes": {"capabilityType": "APP_GROUPS"},
                "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}}},
            }
        },
    )
    if "data" in result:
        print("ok     capacité App Groups activée :", bundle_resource_id)
        print("GROUPE à assigner à la main :", GROUP)
    else:
        print("GROUPE à activer à la main :", GROUP)
        print(result)


for ident, resource in ids.items():
    print("==", ident)
    enable_group(resource)
    caps = call("GET", f"/v1/bundleIds/{resource}/bundleIdCapabilities").get("data", [])
    for cap in caps:
        if cap["attributes"].get("capabilityType") == "APP_GROUPS":
            print("CAP", json.dumps(cap.get("attributes"), ensure_ascii=False)[:700])


def distribution_certs():
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    found = []
    for cert in call("GET", "/v1/certificates?limit=200").get("data", []):
        kind = cert["attributes"].get("certificateType") or ""
        exp = cert["attributes"].get("expirationDate") or ""
        if kind in ("DISTRIBUTION", "IOS_DISTRIBUTION") and exp > now:
            found.append(cert)
            print("CERT", kind, "|", cert["attributes"].get("displayName") or cert["attributes"].get("name"), "|", exp[:10], "|", cert["id"])
    found.sort(key=lambda cert: cert["attributes"].get("expirationDate") or "")
    return found


def profiles_by_bundle():
    raw = call("GET", "/v1/profiles?limit=200&filter[profileType]=IOS_APP_STORE&include=bundleId")
    if "error" in raw:
        print("ÉCHEC  lecture des profils", raw)
        return {}
    grouped = {}
    for profile in raw.get("data", []):
        bundle = (profile.get("relationships") or {}).get("bundleId", {}).get("data") or {}
        grouped.setdefault(bundle.get("id"), []).append(profile)
    return grouped


def install_profile(profile):
    content = profile["attributes"].get("profileContent")
    uuid = profile["attributes"].get("uuid")
    if not content or not uuid:
        return False
    blob = base64.b64decode(content)
    folder = pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{uuid}.mobileprovision").write_bytes(blob)
    has_group = GROUP.encode() in blob
    print("ok     profil installé", profile["attributes"].get("name"), "|", uuid, "| groupe", "oui" if has_group else "NON")
    return has_group


def ensure_profile(ident, bundle_resource_id, certs, existing):
    """Recreate the App Store profile so it picks up the App Group assigned on the App ID."""
    if not certs:
        print("ÉCHEC  pas de certificat de distribution : le profil ne peut pas être créé")
        return
    current = existing.get(bundle_resource_id, [])
    for profile in current:
        state = profile["attributes"].get("profileState")
        print("PROFIL", ident, profile["attributes"].get("name"), state, profile["id"])
        deleted = call("DELETE", f"/v1/profiles/{profile['id']}")
        if deleted.get("error"):
            print("ÉCHEC  suppression profil", profile["id"], deleted)
        else:
            print("ok     ancien profil retiré", profile["id"], state)
    name = "FW " + ident
    created = call(
        "POST",
        "/v1/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
                    "certificates": {"data": [{"type": "certificates", "id": cert["id"]} for cert in certs]},
                },
            }
        },
    )
    if "data" not in created and len(certs) > 1:
        created = call(
            "POST",
            "/v1/profiles",
            {
                "data": {
                    "type": "profiles",
                    "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
                    "relationships": {
                        "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}},
                        "certificates": {"data": [{"type": "certificates", "id": certs[-1]["id"]}]},
                    },
                }
            },
        )
    if "data" not in created:
        print("ÉCHEC  profil", ident, created)
        return
    install_profile(created["data"])


certs = distribution_certs()
existing_profiles = profiles_by_bundle()
for ident, resource in ids.items():
    ensure_profile(ident, resource, certs, existing_profiles)

apps = call("GET", "/v1/apps?limit=200").get("data", [])
mine = [item for item in apps if item["attributes"]["bundleId"] == APP]
if not mine:
    print("FICHE  à créer sur App Store Connect (nom Fold Widgets, identifiant " + APP + ", SKU foldwidgets-001, langue principale Français)")
    sys.exit(0)
cid = mine[0]["id"]
print("FICHE  ok", cid)

groups = call("GET", f"/v1/apps/{cid}/betaGroups?limit=50").get("data", [])
for group in groups:
    print("GROUPE", group["attributes"]["name"], "| interne" if group["attributes"].get("isInternalGroup") else "| externe")
if not any(group["attributes"].get("isInternalGroup") for group in groups):
    created = call(
        "POST",
        "/v1/betaGroups",
        {
            "data": {
                "type": "betaGroups",
                "attributes": {"name": "Fold Widgets interne", "isInternalGroup": True, "hasAccessToAllBuilds": True},
                "relationships": {"app": {"data": {"type": "apps", "id": cid}}},
            }
        },
    )
    print("ok     groupe interne créé" if "data" in created else "ÉCHEC  groupe interne " + json.dumps(created)[:400])
