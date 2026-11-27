"""App Switch personnelle : ce qu'il faut côté compte développeur Apple pour l'installer sans ordinateur.

    python3 switch_sign.py appareils     liste les iPhone déjà enregistrés sur le compte (lecture seule)

Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY. Rien n'est envoyé à la vérification d'Apple : une app signée
« développement » ne s'installe que sur les appareils enregistrés, et garde le droit au débogage dont le JIT a besoin.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
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


def appareils():
    r = call("GET", "/v1/devices?limit=200")
    if "error" in r:
        print("ÉCHEC", r)
        return 1
    rows = r.get("data", [])
    print(f"APPAREILS {len(rows)}")
    for d in rows:
        a = d["attributes"]
        # L'identifiant complet reste hors du journal : sa fin suffit pour le reconnaître.
        print("APPAREIL", a.get("status"), "|", a.get("platform"), "|", a.get("deviceClass"), "|", a.get("model"), "|",
              a.get("name"), "| ajouté", (a.get("addedDate") or "")[:10], "| …" + (a.get("udid") or "")[-4:])
    certs = call("GET", "/v1/certificates?limit=200").get("data", [])
    for c in certs:
        a = c["attributes"]
        print("CERTIFICAT", a.get("certificateType"), "|", a.get("displayName"), "| expire", (a.get("expirationDate") or "")[:10])
    return 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "appareils":
        sys.exit(appareils())
    print(__doc__)
    sys.exit(2)
