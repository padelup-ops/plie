"""App Switch personnelle : ce qu'il faut côté compte développeur Apple pour l'installer sans ordinateur.

    python3 switch_sign.py appareils                      liste les iPhone déjà enregistrés (lecture seule)
    python3 switch_sign.py preparer UDID DOSSIER          enregistre l'iPhone s'il ne l'est pas, crée un certificat de
                                                          développement et un profil par app, écrits dans DOSSIER
    python3 switch_sign.py liens DOSSIER                  écrit les liens d'installation (valables quelques minutes)

Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY, BUNDLE_ID (celui d'Origamo, pour le préfixe des identifiants) ;
pour « liens » : GITHUB_TOKEN, GITHUB_REPOSITORY.
Rien n'est envoyé à la vérification d'Apple : une app signée « développement » ne s'installe que sur les appareils
enregistrés, et garde le droit au débogage dont le JIT a besoin. Les deux apps : l'émulateur Switch (MeloNX) et
StikDebug, qui active le JIT.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
APPS = {"switch": ("retrofold.switch", "RetroFold Switch"), "stikdebug": ("retrofold.stikdebug", "RetroFold StikDebug")}
_token = None


def token():
    global _token
    if _token is None:
        import jwt
        _token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                             "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                            headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
    return _token


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:600]}


def bundle_ids():
    base = os.environ["BUNDLE_ID"].rsplit(".", 1)[0]
    return {key: base + "." + suffix for key, (suffix, _) in APPS.items()}


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
    for c in call("GET", "/v1/certificates?limit=200").get("data", []):
        a = c["attributes"]
        print("CERTIFICAT", a.get("certificateType"), "|", a.get("displayName"), "| expire", (a.get("expirationDate") or "")[:10])
    return 0


def preparer(udid, out):
    os.makedirs(out, exist_ok=True)
    udid = udid.strip()

    # 1. L'iPhone : déjà enregistré, ou ajouté (une place sur les 100 du compte, jusqu'au renouvellement annuel).
    found = [d for d in call("GET", "/v1/devices?limit=200").get("data", []) if d["attributes"].get("udid", "").lower() == udid.lower()]
    if found:
        device = found[0]
        print("ok     iPhone déjà enregistré :", device["attributes"].get("name"), "|", device["attributes"].get("model"))
    else:
        r = call("POST", "/v1/devices", {"data": {"type": "devices", "attributes": {"name": "iPhone Duo (Switch)", "platform": "IOS", "udid": udid}}})
        if "data" not in r:
            print("ÉCHEC  enregistrement de l'iPhone :", r)
            return 1
        device = r["data"]
        print("ok     iPhone enregistré :", device["attributes"].get("model"), "| état", device["attributes"].get("status"))

    # 2. Les identifiants des deux apps, et pour l'émulateur les droits à plus de mémoire.
    existing = {b["attributes"]["identifier"]: b["id"] for b in call("GET", "/v1/bundleIds?limit=200&filter[platform]=IOS").get("data", [])}
    ids = bundle_ids()
    resource = {}
    for key, ident in ids.items():
        if ident in existing:
            resource[key] = existing[ident]
            print("ok     identifiant déjà là :", ident)
            continue
        r = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": ident, "name": APPS[key][1], "platform": "IOS"}}})
        if "data" not in r:
            print("ÉCHEC  identifiant :", ident, r)
            return 1
        resource[key] = r["data"]["id"]
        print("ok     identifiant créé :", ident)
    for cap in ("INCREASED_MEMORY_LIMIT", "EXTENDED_VIRTUAL_ADDRESSING"):
        r = call("POST", "/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": cap},
                 "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": resource["switch"]}}}}})
        print("ok     droit" if "data" in r else "note   droit non ajouté", cap, "" if "data" in r else str(r)[:200])

    # 3. Un certificat de développement à nous (la clé privée ne sort pas de cette machine de compilation).
    key, csr, pem, p12 = (os.path.join(out, n) for n in ("cle.pem", "demande.csr", "certificat.pem", "signature.p12"))
    cert_id_file = os.path.join(out, "certificat.id")
    cert = None
    if os.path.exists(cert_id_file) and os.path.exists(p12):
        # Celui d'une signature précédente, gardé avec sa clé : les apps déjà installées restent valables.
        r = call("GET", "/v1/certificates/" + open(cert_id_file).read().strip())
        if "data" in r:
            cert = r["data"]
            print("ok     certificat de développement repris, expire", (cert["attributes"].get("expirationDate") or "")[:10])
    if cert is None:
        cert = nouveau_certificat(out, key, csr, pem, p12, cert_id_file)
        if cert is None:
            return 1
    return profils(out, ids, resource, cert, device)


def nouveau_certificat(out, key, csr, pem, p12, cert_id_file):
    subprocess.run(["/usr/bin/openssl", "genrsa", "-out", key, "2048"], check=True, capture_output=True)
    subprocess.run(["/usr/bin/openssl", "req", "-new", "-key", key, "-out", csr, "-subj", "/CN=RetroFold Switch/C=FR"], check=True, capture_output=True)
    body = {"data": {"type": "certificates", "attributes": {"certificateType": "DEVELOPMENT", "csrContent": open(csr).read()}}}
    r = call("POST", "/v1/certificates", body)
    if "data" not in r and "already have a current Development certificate" in str(r):
        # La clé d'accès n'a droit qu'à un certificat de développement. Si celui qui existe est le nôtre (créé par cet
        # outil, clé privée perdue), on le remplace ; jamais un certificat que nous n'avons pas créé.
        if not revoquer_le_notre():
            print("ÉCHEC  certificat : un certificat de développement existe déjà et n'est pas celui de cet outil")
            return None
        r = call("POST", "/v1/certificates", body)
    if "data" not in r:
        print("ÉCHEC  certificat :", r)
        return None
    cert = r["data"]
    der = base64.b64decode(cert["attributes"]["certificateContent"])
    open(os.path.join(out, "certificat.cer"), "wb").write(der)
    subprocess.run(["/usr/bin/openssl", "x509", "-inform", "DER", "-in", os.path.join(out, "certificat.cer"), "-out", pem], check=True, capture_output=True)
    subprocess.run(["/usr/bin/openssl", "pkcs12", "-export", "-inkey", key, "-in", pem, "-out", p12, "-passout", "pass:retrofold"], check=True, capture_output=True)
    open(cert_id_file, "w").write(cert["id"])
    print("ok     certificat de développement créé, expire", (cert["attributes"].get("expirationDate") or "")[:10])
    return cert


def revoquer_le_notre():
    """Révoque le certificat de développement attaché aux profils créés par cet outil (reconnus à leur nom), et
    supprime ces profils. Ne touche à rien d'autre. Vrai si un certificat, et un seul, a été révoqué."""
    names = tuple(title + " " for _, title in APPS.values())
    ours = [p for p in call("GET", "/v1/profiles?limit=200").get("data", []) if p["attributes"].get("name", "").startswith(names)]
    cert_ids = set()
    for p in ours:
        for c in call("GET", f"/v1/profiles/{p['id']}/certificates").get("data", []):
            a = c["attributes"]
            if a.get("certificateType") == "DEVELOPMENT" and a.get("displayName") == "Created via API":
                cert_ids.add(c["id"])
    if len(cert_ids) != 1:
        print("note   certificats de cet outil trouvés :", len(cert_ids))
        return False
    cert_id = cert_ids.pop()
    r = call("DELETE", "/v1/certificates/" + cert_id)
    if "error" in r:
        print("ÉCHEC  révocation :", r)
        return False
    print("ok     ancien certificat de cet outil révoqué (sa clé privée était perdue)")
    for p in ours:
        call("DELETE", "/v1/profiles/" + p["id"])
    print("ok     anciens profils supprimés :", len(ours))
    return True


def profils(out, ids, resource, cert, device):
    # 4. Un profil par app : ce certificat, cet iPhone.
    for key_, ident in ids.items():
        r = call("POST", "/v1/profiles", {"data": {"type": "profiles", "attributes": {"name": f"{APPS[key_][1]} {time.strftime('%Y%m%d-%H%M%S')}", "profileType": "IOS_APP_DEVELOPMENT"},
                 "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": resource[key_]}},
                                   "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]},
                                   "devices": {"data": [{"type": "devices", "id": device["id"]}]}}}})
        if "data" not in r:
            print("ÉCHEC  profil :", ident, r)
            return 1
        open(os.path.join(out, key_ + ".mobileprovision"), "wb").write(base64.b64decode(r["data"]["attributes"]["profileContent"]))
        open(os.path.join(out, key_ + ".bundleid"), "w").write(ident)
        print("ok     profil créé :", ident, "| expire", (r["data"]["attributes"].get("expirationDate") or "")[:10])
    return 0


def github(path, follow=True):
    req = urllib.request.Request("https://api.github.com" + path, headers={"Authorization": "Bearer " + os.environ["GITHUB_TOKEN"], "Accept": "application/vnd.github+json"})

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k):
            return None

    opener = urllib.request.build_opener() if follow else urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(req) as r:
            return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


def liens(out):
    """Pour chaque app signée jointe à une exécution : un manifeste d'installation qui pointe sur une adresse de
    téléchargement temporaire de GitHub (elle expire au bout de quelques minutes, d'où des liens à refaire à la demande)."""
    os.makedirs(out, exist_ok=True)
    repo = os.environ["GITHUB_REPOSITORY"]
    for key, (_, title) in APPS.items():
        name = f"{title.replace(' ', '')}-signee.ipa"
        status, _, raw = github(f"/repos/{repo}/actions/artifacts?name={urllib.parse.quote(name)}&per_page=5")
        rows = [a for a in json.loads(raw).get("artifacts", []) if not a.get("expired")] if status == 200 else []
        if not rows:
            print("ÉCHEC  aucune app signée jointe sous le nom", name, status)
            return 1
        # La plus récente : une signature plus ancienne peut porter un certificat remplacé depuis.
        art = max(rows, key=lambda a: a.get("created_at") or "")
        status, headers, _ = github(f"/repos/{repo}/actions/artifacts/{art['id']}/zip", follow=False)
        url = headers.get("Location") or headers.get("location")
        if not url:
            print("ÉCHEC  adresse de téléchargement :", name, status)
            return 1
        ident = bundle_ids()[key]
        esc = url.replace("&", "&amp;")
        manifest = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
<key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>{esc}</string></dict></array>
<key>metadata</key><dict><key>bundle-identifier</key><string>{ident}</string><key>bundle-version</key><string>1.0</string>
<key>kind</key><string>software</string><key>title</key><string>{title}</string></dict>
</dict></array></dict></plist>
"""
        open(os.path.join(out, f"{key}-manifest.plist"), "w").write(manifest)
        print("ok     manifeste écrit pour", title, "| app jointe le", art.get("created_at"))
    return 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "appareils":
        sys.exit(appareils())
    if mode == "preparer" and len(sys.argv) == 4:
        sys.exit(preparer(sys.argv[2], sys.argv[3]))
    if mode == "liens" and len(sys.argv) == 3:
        sys.exit(liens(sys.argv[2]))
    print(__doc__)
    sys.exit(2)
