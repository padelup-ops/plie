"""FOLDLY : liste les utilisateurs App Store Connect et retire ceux demandés (APPLY=1). Jamais le titulaire du compte."""
import json, os, sys, time, urllib.request, urllib.error
import jwt
API = "https://api.appstoreconnect.apple.com"
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 600,
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

WANT = [x.strip().lower() for x in os.environ.get("REMOVE", "").split(",") if x.strip()]
APPLY = os.environ.get("APPLY") == "1"

def match(a):
    keys = {(a.get("username") or "").lower(), (a.get("email") or "").lower(), (a.get("firstName") or "").lower()}
    return any(w in keys for w in WANT)

for kind in ("users", "userInvitations"):
    for u in call("GET", f"/v1/{kind}?limit=100").get("data", []):
        a = u["attributes"]
        roles = a.get("roles") or []
        tag = ""
        if WANT and match(a):
            if "ACCOUNT_HOLDER" in roles:
                tag = "  -> GARDÉ (titulaire du compte)"
            elif APPLY:
                r = call("DELETE", f"/v1/{kind}/{u['id']}")
                tag = "  -> RETIRÉ" if "error" not in r else f"  -> ÉCHEC {r['error']} {r['detail'][:200]}"
            else:
                tag = "  -> à retirer (APPLY=1)"
        print(f"{kind:16} {a.get('firstName','')} {a.get('lastName','')} | {a.get('username') or a.get('email')} | {','.join(roles)}{tag}")
