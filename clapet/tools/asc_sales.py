"""Ventes des derniers jours (rapport SALES / SUMMARY quotidien). VENDOR = numéro de fournisseur (Paiements et rapports financiers)."""
import gzip, io, json, os, time, urllib.request, urllib.error, datetime
import jwt
API = "https://api.appstoreconnect.apple.com"
token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 600,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
vendor = os.environ.get("VENDOR", "")
days = int(os.environ.get("DAYS", "10"))
total = {}
for k in range(1, days + 1):
    d = (datetime.date.today() - datetime.timedelta(days=k)).isoformat()
    q = f"filter[frequency]=DAILY&filter[reportType]=SALES&filter[reportSubType]=SUMMARY&filter[version]=1_1&filter[reportDate]={d}"
    if vendor:
        q += f"&filter[vendorNumber]={vendor}"
    req = urllib.request.Request(f"{API}/v1/salesReports?{q}", headers={"Authorization": "Bearer " + token, "Accept": "application/a-gzip"})
    try:
        raw = urllib.request.urlopen(req).read()
    except urllib.error.HTTPError as e:
        print(d, "->", e.code, e.read().decode()[:400]); continue
    rows = gzip.GzipFile(fileobj=io.BytesIO(raw)).read().decode().splitlines()
    head = rows[0].split("\t")
    for line in rows[1:]:
        r = dict(zip(head, line.split("\t")))
        key = (r.get("Title"), r.get("Product Type Identifier"))
        units = int(float(r.get("Units") or 0))
        total[key] = total.get(key, 0) + units
        print(d, r.get("Title"), r.get("SKU"), "type", r.get("Product Type Identifier"), "unités", units,
              "pays", r.get("Country Code"), "prix client", r.get("Customer Price"), r.get("Customer Currency"),
              "revenu", r.get("Developer Proceeds"), r.get("Currency of Proceeds"))
print("\nTOTAL", json.dumps({f"{a} ({b})": n for (a, b), n in total.items()}, ensure_ascii=False))
print("Types : 1/1F = achat de l'app, 7/7F = mise à jour (gratuite), IA1 = achat intégré, 3F = réédition")
