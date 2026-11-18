"""FOLD WIDGETS : prépare les identifiants (app, widget, groupe d'app) et regarde la fiche.

Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY.
N'utilise pas BUNDLE_ID : ce secret reste celui d'Origamo. L'équipe n'est pas lue ici
(la signature passe par APPLE_TEAM_ID dans le workflow).

La fiche App Store Connect ne peut pas être créée par l'API : s'il n'y en a pas,
le script l'écrit et s'arrête. Le workflow n'envoie alors rien sur TestFlight.
"""
import json
import os
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
