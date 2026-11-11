"""Ouvre une app dans tous les pays de l'App Store (et ses achats intégrés).
Entrées : BUNDLE (identifiant de l'app), MODE (probe | open)."""
import json, os, sys, time, urllib.request, urllib.error
import jwt
API = "https://api.appstoreconnect.apple.com"
BUNDLE = os.environ["BUNDLE"]; MODE = os.environ.get("MODE", "probe")
tok = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1100, "aud": "appstoreconnect-v1"},
                 os.environ["ASC_PRIVATE_KEY"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
def call(m, p, b=None):
    r = urllib.request.Request(API + p if p.startswith("/") else p, method=m, data=json.dumps(b).encode() if b else None,
                               headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r) as x: return json.loads(x.read() or b"{}")
    except urllib.error.HTTPError as e: return {"error": e.code, "detail": e.read().decode()[:600]}
def all_pages(p):
    out = []
    while p:
        r = call("GET", p); out += r.get("data", []); p = r.get("links", {}).get("next")
    return out
app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]
av = call("GET", f"/v1/apps/{app['id']}/appAvailabilityV2").get("data")
print("disponibilité", av and av["attributes"])
tas = all_pages(f"/v2/appAvailabilities/{av['id']}/territoryAvailabilities?limit=200&include=territory")
off = [t for t in tas if not t["attributes"].get("available")]
print(f"PAYS : {len(tas) - len(off)} ouverts sur {len(tas)}")
print("FERMÉS :", sorted(t["relationships"]["territory"]["data"]["id"] for t in off))
print("états :", sorted({(t["attributes"].get("contentStatuses") or ["?"])[0] for t in off}))
if MODE == "open":
    ok = 0
    for t in off:
        r = call("PATCH", f"/v1/territoryAvailabilities/{t['id']}", {"data": {"type": "territoryAvailabilities", "id": t["id"], "attributes": {"available": True}}})
        if r.get("error"): print("ÉCHEC", t["relationships"]["territory"]["data"]["id"], r["detail"][:200])
        else: ok += 1
    print("ouverts maintenant :", ok)
    if not av["attributes"].get("availableInNewTerritories"):
        print("(les nouveaux pays ne sont pas ouverts automatiquement)")
