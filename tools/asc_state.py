"""Sonde : où en est une app sur l'App Store (versions, builds, demandes, EULA, liens de la fiche, achats).
Lecture seule. BUNDLE choisit l'app. N'écrit ni adresse, ni clé, ni chiffre."""
import json, os, time, urllib.request, urllib.error
import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = os.environ.get("BUNDLE", "").strip() or "com.padelup.vicefold"
EULA_URL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 900,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(p):
    req = urllib.request.Request(API + p, headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode(errors="replace")[:300]}


def attrs(x):
    return (x or {}).get("attributes") or {}


apps = call(f"/v1/apps?filter[bundleId]={BUNDLE}&limit=5").get("data", [])
app = next((a for a in apps if attrs(a).get("bundleId") == BUNDLE), None)
if not app:
    print("app introuvable")
    raise SystemExit(1)
aid = app["id"]
print("APP", aid, attrs(app).get("name"))

for v in call(f"/v1/apps/{aid}/appStoreVersions?filter[platform]=IOS&limit=6").get("data", []):
    a = attrs(v)
    b = attrs(call(f"/v1/appStoreVersions/{v['id']}/build").get("data"))
    print("VERSION", a.get("versionString"), a.get("appStoreState"), "sortie", a.get("releaseType"),
          "build", b.get("version"), "créée", (a.get("createdDate") or "")[:16])
    if a.get("appStoreState") not in ("READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION", "REMOVED_FROM_SALE"):
        for l in call(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations?limit=50").get("data", []):
            la = attrs(l)
            d = la.get("description") or ""
            print("   FICHE", la.get("locale"), "description", len(d), "lien EULA", "oui" if EULA_URL in d else "NON",
                  "nouveautés", len(la.get("whatsNew") or ""))

for b in call(f"/v1/builds?filter[app]={aid}&sort=-uploadedDate&limit=6").get("data", []):
    a = attrs(b)
    print("BUILD", a.get("version"), a.get("processingState"), "expiré" if a.get("expired") else "valide",
          (a.get("uploadedDate") or "")[:16])

for s in call(f"/v1/reviewSubmissions?filter[app]={aid}&limit=8").get("data", []):
    a = attrs(s)
    print("DEMANDE", s["id"][:8], a.get("state"), (a.get("submittedDate") or "")[:16])
    for it in call(f"/v1/reviewSubmissions/{s['id']}/items?limit=20").get("data", []):
        kinds = [k for k, x in (it.get("relationships") or {}).items()
                 if k != "reviewSubmission" and isinstance(x, dict) and x.get("data")]
        print("   élément", attrs(it).get("state"), ",".join(kinds))

e = call(f"/v1/apps/{aid}/endUserLicenseAgreement")
text = attrs(e.get("data") if isinstance(e.get("data"), dict) else None).get("agreementText") or ""
if text:
    print("EULA propre à l'app : oui,", len(text), "caractères, lien Apple", "oui" if EULA_URL in text else "non")
    print("   ", text[:200].replace("\n", " "))
else:
    print("EULA propre à l'app : non", e.get("error") or "")

for info in call(f"/v1/apps/{aid}/appInfos?limit=5").get("data", []):
    print("INFOS", attrs(info).get("appStoreState") or attrs(info).get("state"))
    for l in call(f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=50").get("data", []):
        la = attrs(l)
        print("   ", la.get("locale"), "|", la.get("name"), "| confidentialité", la.get("privacyPolicyUrl") or "ABSENTE")

for x in call(f"/v1/apps/{aid}/inAppPurchasesV2?limit=20").get("data", []):
    a = attrs(x)
    print("ACHAT", a.get("productId"), a.get("state"), a.get("inAppPurchaseType"))
for g in call(f"/v1/apps/{aid}/subscriptionGroups?limit=10").get("data", []):
    print("GROUPE", attrs(g).get("referenceName"))
    for s in call(f"/v1/subscriptionGroups/{g['id']}/subscriptions?limit=20").get("data", []):
        a = attrs(s)
        print("   ABONNEMENT", a.get("productId"), a.get("state"), a.get("subscriptionPeriod"))
