"""Testeur interne TestFlight : invite une personne dans App Store Connect (rôle le plus restreint qui permet de
tester en interne, une seule app visible), puis, une fois l'invitation acceptée, l'ajoute au groupe interne de l'app.

Le dépôt est public : l'e-mail n'apparaît jamais. On donne son empreinte SHA-256 (EMAIL_SHA256), et le script
retrouve l'adresse parmi les testeurs TestFlight déjà connus de l'app, les utilisateurs et les invitations.
Le journal n'affiche que les deux premières lettres et le domaine."""
import hashlib, json, os, time, urllib.parse, urllib.request, urllib.error
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
        return {"error": e.code, "detail": e.read().decode()[:500]}


def pages(path):
    while path:
        r = call("GET", path)
        if "error" in r:
            print("  lecture impossible", path.split("?")[0], r["error"], r["detail"][:200])
            return
        yield from r.get("data", [])
        nxt = r.get("links", {}).get("next")
        path = nxt[len(API):] if nxt else None


WANT = os.environ["EMAIL_SHA256"].strip().lower()
APP = os.environ["APP_ID"].strip()
ROLE = os.environ.get("ROLE", "MARKETING").strip()
FIRST = os.environ.get("FIRST", "").strip() or "Tester"
LAST = os.environ.get("LAST", "").strip() or "Foldboard"


def h(e):
    return hashlib.sha256((e or "").strip().lower().encode()).hexdigest()


def masked(e):
    return e[:2] + "…@" + e.split("@")[-1]


email = None
user = None
invite = None
for u in pages("/v1/users?limit=200"):
    if h(u["attributes"].get("username")) == WANT or h(u["attributes"].get("email")) == WANT:
        user, email = u, u["attributes"].get("username") or u["attributes"].get("email")
for i in pages("/v1/userInvitations?limit=200"):
    if h(i["attributes"].get("email")) == WANT:
        invite, email = i, i["attributes"]["email"]
tester = None
for t in pages(f"/v1/betaTesters?filter[apps]={APP}&limit=200"):
    if h(t["attributes"].get("email")) == WANT:
        tester = t
        email = email or t["attributes"]["email"]
        FIRST = t["attributes"].get("firstName") or FIRST
        LAST = t["attributes"].get("lastName") or LAST

if not email:
    print("INTROUVABLE : cette adresse n'est ni testeur TestFlight de l'app, ni utilisateur, ni invitée.")
    raise SystemExit(2)
print("personne :", masked(email), "| utilisateur :", bool(user), "| invitée :", bool(invite), "| testeur :", bool(tester))

# 1. L'invitation App Store Connect (rôle restreint, seulement cette app).
if not user and not invite:
    body = {"data": {"type": "userInvitations",
                     "attributes": {"email": email, "firstName": FIRST, "lastName": LAST, "roles": [ROLE],
                                    "allAppsVisible": False, "provisioningAllowed": False},
                     "relationships": {"visibleApps": {"data": [{"type": "apps", "id": APP}]}}}}
    r = call("POST", "/v1/userInvitations", body)
    if "error" in r:
        print("ÉCHEC invitation", r["error"], r["detail"].replace(email, masked(email)))
        raise SystemExit(1)
    print(f"INVITÉE : rôle {ROLE}, app {APP} seulement (e-mail d'Apple envoyé à {masked(email)})")
elif invite:
    print("invitation déjà envoyée, en attente d'acceptation (expire le", invite["attributes"].get("expirationDate"), ")")

# 2. Le groupe interne de l'app (créé s'il n'existe pas), qui reçoit tous les builds.
group = None
for g in pages(f"/v1/apps/{APP}/betaGroups?limit=50"):
    if g["attributes"].get("isInternalGroup"):
        group = g
        break
if not group:
    r = call("POST", "/v1/betaGroups", {"data": {"type": "betaGroups",
                                                   "attributes": {"name": "Équipe", "isInternalGroup": True,
                                                                  "hasAccessToAllBuilds": True},
                                                   "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
    if "error" in r:
        print("ÉCHEC groupe interne", r["error"], r["detail"][:300])
        raise SystemExit(1)
    group = r["data"]
    print("groupe interne créé :", group["attributes"]["name"])
print("groupe interne :", group["attributes"]["name"], "| tous les builds :", group["attributes"].get("hasAccessToAllBuilds"))

# 3. Une fois l'invitation acceptée : testeur du groupe interne.
if not user:
    print("EN ATTENTE : il doit d'abord accepter l'e-mail d'Apple ; relancer ensuite pour l'ajouter au groupe interne.")
    raise SystemExit(0)
r = call("POST", "/v1/betaTesters", {"data": {"type": "betaTesters",
                                             "attributes": {"email": email, "firstName": FIRST, "lastName": LAST},
                                             "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}}}})
if "error" in r and r["error"] != 409:
    print("ÉCHEC ajout au groupe interne", r["error"], r["detail"].replace(email, masked(email))[:300])
    raise SystemExit(1)
print("TESTEUR INTERNE : ajouté au groupe", group["attributes"]["name"])
