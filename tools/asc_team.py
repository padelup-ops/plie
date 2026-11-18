"""Équipe TestFlight interne, sans jamais écrire d'adresse dans le dépôt ni dans les journaux (publics).

MODE=find  NAME=Matthew : cherche la personne parmi les utilisateurs App Store Connect, les invitations et les testeurs
           (toutes apps). Affiche le prénom, le nom, l'adresse masquée, son empreinte SHA-256 et ses accès.
MODE=add   EMAIL_SHA256=… APP_ID=… : donne à cet utilisateur l'accès à l'app (s'il ne voit pas toutes les apps),
           puis l'ajoute au groupe interne de l'app."""
import hashlib, json, os, time, urllib.request, urllib.error
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
        return {"error": e.code, "detail": e.read().decode()[:3000]}


def pages(path):
    while path:
        r = call("GET", path)
        if "error" in r:
            print("  lecture impossible", path.split("?")[0], r["error"])
            return
        yield from r.get("data", [])
        nxt = r.get("links", {}).get("next")
        path = nxt[len(API):] if nxt else None


def h(e):
    return hashlib.sha256((e or "").strip().lower().encode()).hexdigest()


def masked(e):
    e = e or ""
    return e[:2] + "…@" + e.split("@")[-1] if "@" in e else "?"


def why(r):
    try:
        errs = json.loads(r["detail"]).get("errors", [])
        out = []
        for x in errs:
            out.append(f"{x.get('code')}: {x.get('detail')}")
            for k, v in (x.get("meta") or {}).get("associatedErrors", {}).items():
                for y in v:
                    out.append(f"   {y.get('code')}: {y.get('detail')}")
        return " | ".join(out)
    except Exception:
        return r.get("detail", "")[:400]


MODE = os.environ.get("MODE", "find")
if MODE == "find":
    name = os.environ.get("NAME", "").strip().lower()
    apps = {a["id"]: a["attributes"]["name"] for a in pages("/v1/apps?limit=200")}
    seen = set()
    for u in pages("/v1/users?limit=200&include=visibleApps"):
        a = u["attributes"]
        full = f"{a.get('firstName', '')} {a.get('lastName', '')}"
        if name in full.lower():
            e = a.get("username") or a.get("email")
            vis = "toutes" if a.get("allAppsVisible") else ", ".join(apps.get(x["id"], x["id"]) for x in u.get("relationships", {}).get("visibleApps", {}).get("data", []) or [])
            print(f"UTILISATEUR {full} | {masked(e)} | sha256 {h(e)} | rôles {a.get('roles')} | apps : {vis}")
            seen.add(h(e))
    for i in pages("/v1/userInvitations?limit=200"):
        a = i["attributes"]
        full = f"{a.get('firstName', '')} {a.get('lastName', '')}"
        if name in full.lower():
            print(f"INVITATION {full} | {masked(a.get('email'))} | sha256 {h(a.get('email'))} | expire {a.get('expirationDate')}")
    for app_id, app_name in apps.items():
        for t in pages(f"/v1/betaTesters?filter[apps]={app_id}&limit=200"):
            a = t["attributes"]
            full = f"{a.get('firstName', '')} {a.get('lastName', '')}"
            if name in full.lower():
                print(f"TESTEUR {app_name} | {full} | {masked(a.get('email'))} | sha256 {h(a.get('email'))} | type {a.get('inviteType')} | état {a.get('state')}")
else:
    want, app = os.environ["EMAIL_SHA256"].strip().lower(), os.environ["APP_ID"].strip()
    user = next((u for u in pages("/v1/users?limit=200") if h(u["attributes"].get("username") or u["attributes"].get("email")) == want), None)
    tester = None
    for a in [x["id"] for x in pages("/v1/apps?limit=200")]:
        tester = tester or next((t for t in pages(f"/v1/betaTesters?filter[apps]={a}&limit=200") if h(t["attributes"].get("email")) == want), None)
    if not user:
        print("PAS UTILISATEUR App Store Connect : il faut d'abord l'inviter (clapet-invite.yml).")
        raise SystemExit(1)
    a = user["attributes"]
    email = a.get("username") or a.get("email")
    print("personne :", a.get("firstName"), masked(email), "| rôles", a.get("roles"), "| toutes les apps :", a.get("allAppsVisible"))
    if not a.get("allAppsVisible"):
        r = call("POST", f"/v1/users/{user['id']}/relationships/visibleApps", {"data": [{"type": "apps", "id": app}]})
        print("accès à l'app :", "ok" if "error" not in r else "ÉCHEC " + why(r))
    group = next((g for g in pages(f"/v1/apps/{app}/betaGroups?limit=50") if g["attributes"].get("isInternalGroup")), None)
    if not group:
        print("ÉCHEC : pas de groupe interne")
        raise SystemExit(1)
    in_group = {h(t["attributes"].get("email")) for t in pages(f"/v1/betaGroups/{group['id']}/betaTesters?limit=200")}
    if want in in_group:
        print("TESTEUR INTERNE : déjà dans", group["attributes"]["name"])
        raise SystemExit(0)
    r = call("POST", "/v1/betaTesters", {"data": {"type": "betaTesters",
             "attributes": {"email": email, "firstName": a.get("firstName"), "lastName": a.get("lastName")},
             "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}}}})
    if "error" in r and tester:
        r = call("POST", f"/v1/betaGroups/{group['id']}/relationships/betaTesters", {"data": [{"type": "betaTesters", "id": tester["id"]}]})
    print("TESTEUR INTERNE : ajouté à " + group["attributes"]["name"] if "error" not in r else "ÉCHEC groupe : " + why(r).replace(email, masked(email)))
