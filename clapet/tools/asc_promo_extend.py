"""Foldly : lit la promo en cours et, si EXTEND=1, repousse seulement sa date de fin.

La date Apple est le jour où le prix suivant commence (comme PLUS_LATER_DATE dans asc_plus.py).
« Vendredi 20 novembre 2026, fin de journée, Europe/Paris » = le prix réduit court encore
tout le vendredi, et le prix suivant commence le samedi 21 novembre 2026.

Ne change ni le prix, ni les pays, ni une autre app. Ne soumet rien à la vérification.
"""
import json
import os
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.padelup.clapet"
# Frontière actuelle qui veut dire « l'offre s'arrête le jeudi 19 » ou « le vendredi 20 au matin ».
OLD_ENDS = {"2026-11-19", "2026-11-20"}
# Le prix suivant commence le samedi : le vendredi 20 est encore au prix réduit, jusqu'à minuit à Paris.
NEW_END = "2026-11-21"
EXTEND = os.environ.get("EXTEND") == "1"

token = jwt.encode(
    {"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
    os.environ["ASC_PRIVATE_KEY"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path if path.startswith("/") else path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        try:
            detail = "; ".join(f"{x.get('code')}: {x.get('detail')}" for x in json.loads(text).get("errors", [])) or text[:800]
        except Exception:
            detail = text[:800]
        return {"error": e.code, "detail": detail}


def get_all(path):
    out, url = [], path
    while url:
        page = call("GET", url)
        if isinstance(page, dict) and "error" in page:
            print("LECTURE", page["error"], url[:140], page["detail"][:300])
            return out
        if "data" in page:
            if isinstance(page["data"], list):
                out += page["data"]
            else:
                return page
        for inc in page.get("included", []):
            out.append(inc)
        nxt = (page.get("links") or {}).get("next")
        url = nxt.replace(API, "") if nxt else None
    return out


def money(point):
    a = (point or {}).get("attributes") or {}
    return a.get("customerPrice"), a.get("proceeds"), (point or {}).get("id")


apps = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")
if not apps.get("data"):
    print("app introuvable", apps)
    raise SystemExit(1)
app = apps["data"][0]
app_id = app["id"]
print("APP", app_id, app["attributes"].get("name"), app["attributes"].get("bundleId"))

# --- prix de l'app elle-même ---
print("\n== PRIX DE L'APP ==")
sched = call("GET", f"/v1/apps/{app_id}/appPriceSchedule?include=manualPrices,automaticPrices,baseTerritory")
if "error" in sched:
    print("schedule", sched)
else:
    base = ((sched.get("data") or {}).get("relationships") or {}).get("baseTerritory", {}).get("data")
    print("base", base)
    for inc in sched.get("included", []):
        a = inc.get("attributes") or {}
        if inc["type"] == "appPrices":
            print(" appPrice", inc["id"], "start", a.get("startDate"), "end", a.get("endDate"), "manual", a.get("manual"))

# --- achats intégrés ---
print("\n== ACHATS ==")
iaps = []
for path in (f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50", f"/v2/inAppPurchases?filter[app]={app_id}&limit=50"):
    got = call("GET", path)
    if got.get("data"):
        iaps = got["data"]
        break
    print(" iap list", path.split("?")[0], got.get("error"), (got.get("detail") or "")[:180])

changes = []
for iap in iaps:
    ia = iap["attributes"]
    iid = iap["id"]
    print(f"\nIAP {ia.get('productId')} | {ia.get('name')} | {ia.get('inAppPurchaseType')} | {ia.get('state')} | {iid}")
    sch = call("GET", f"/v2/inAppPurchases/{iid}/iapPriceSchedule?include=baseTerritory,manualPrices,automaticPrices")
    if "error" in sch:
        sch = call("GET", f"/v1/inAppPurchases/{iid}/priceSchedule?include=baseTerritory,manualPrices")
    if "error" in sch:
        print(" schedule", sch["error"], sch["detail"][:240])
        continue
    data = sch.get("data") or {}
    sid = data.get("id")
    base = ((data.get("relationships") or {}).get("baseTerritory") or {}).get("data")
    print(" schedule", sid, "base", (base or {}).get("id"))
    included = {x["id"]: x for x in sch.get("included", [])}
    def is_manual(p):
        return (p.get("attributes") or {}).get("manual") is not False
    manuals = [x for x in sch.get("included", []) if x["type"] == "inAppPurchasePrices" and is_manual(x)]
    if not manuals and sid:
        extra = call("GET", f"/v1/inAppPurchasePriceSchedules/{sid}/manualPrices?include=inAppPurchasePricePoint,territory&limit=200")
        if "error" in extra:
            print(" manualPrices", extra["error"], extra["detail"][:240])
        else:
            manuals = [x for x in extra.get("data", []) if x["type"] == "inAppPurchasePrices"]
            for x in extra.get("included", []):
                included[x["id"]] = x
            while extra.get("links", {}).get("next"):
                extra = call("GET", extra["links"]["next"].replace(API, ""))
                manuals += [x for x in extra.get("data", []) if x["type"] == "inAppPurchasePrices"]
                for x in extra.get("included", []):
                    included[x["id"]] = x
    autos = [x for x in sch.get("included", []) if x["type"] == "inAppPurchasePrices" and not (x.get("attributes") or {}).get("manual", True)]
    print(f" prix manuels {len(manuals)} | automatiques inclus {len(autos)}")
    # Résumé par (début, fin, prix) pour ne pas noyer 175 pays.
    groups = {}
    rows = []
    for p in manuals:
        full = call("GET", f"/v1/inAppPurchasePrices/{p['id']}?include=inAppPurchasePricePoint,territory")
        src = full.get("data") or p
        for inc in full.get("included", []):
            included[inc["id"]] = inc
        a = src.get("attributes") or {}
        rel = src.get("relationships") or {}
        point_id = ((rel.get("inAppPurchasePricePoint") or {}).get("data") or {}).get("id")
        terr = ((rel.get("territory") or {}).get("data") or {}).get("id")
        point = included.get(point_id) or {}
        price, proceeds, _ = money(point)
        if price is None and point_id:
            got = call("GET", f"/v1/inAppPurchasePricePoints/{point_id}?include=territory")
            if "data" in got:
                price, proceeds, _ = money(got["data"])
                included[point_id] = got["data"]
                terr = terr or ((got["data"].get("relationships") or {}).get("territory", {}).get("data") or {}).get("id")
        key = (a.get("startDate"), a.get("endDate"), str(price))
        groups.setdefault(key, []).append(terr or "?")
        rows.append({"id": p["id"], "start": a.get("startDate"), "end": a.get("endDate"), "price": price,
                     "proceeds": proceeds, "territory": terr, "point": point_id, "manual": a.get("manual")})
    for (start, end, price), terrs in sorted(groups.items(), key=lambda kv: (kv[0][0] or "", kv[0][1] or "")):
        sample = ", ".join(sorted(t for t in terrs if t)[:8])
        print(f"  {price} €  {start or 'maintenant'} → {end or 'sans fin'}  ({len(terrs)} pays) {sample}")
    ends = {r["end"] for r in rows if r["end"] in OLD_ENDS}
    starts = {r["start"] for r in rows if r["start"] in OLD_ENDS}
    boundary = ends | starts
    if len(boundary) == 1 and rows and all(r["point"] for r in rows):
        old = boundary.pop()
        print(f" FRONTIÈRE À REPOUSSER {old} → {NEW_END}")
        changes.append((iid, ia.get("productId"), sid, base, rows, old))
    elif boundary:
        missing = sum(1 for r in rows if not r["point"])
        print(" RIEN N'EST MODIFIÉ :", sorted(boundary), f"({missing} prix sans palier)" if missing else "plusieurs frontières")

# --- codes offre ---
print("\n== CODES OFFRE ==")
for iap in iaps:
    iid = iap["id"]
    for path in (f"/v1/inAppPurchaseOfferCodes?filter[inAppPurchase]={iid}&limit=50",
                 f"/v2/inAppPurchases/{iid}/offerCodes?limit=50"):
        got = call("GET", path)
        if got.get("data"):
            for c in got["data"]:
                a = c.get("attributes") or {}
                print(" code", iap["attributes"].get("productId"), c["id"],
                      {k: a.get(k) for k in ("name", "customerEligibilities", "offerEligibility", "active",
                                             "expirationDate", "productionCodeCount", "numberOfCodes") if k in a or True})
            break
        if got.get("error") and got["error"] != 404:
            print(" codes", iap["attributes"].get("productId"), got["error"], (got.get("detail") or "")[:160])

if not EXTEND:
    print("\nLECTURE SEULE (EXTEND n'est pas 1)")
    raise SystemExit(0)

if not changes:
    print("\nRIEN À REPOUSSER : aucune frontière au 19 ou au 20 novembre")
    raise SystemExit(0)

for iid, product, sid, base, rows, old in changes:
    base_id = (base or {}).get("id") or "FRA"
    included = []
    links = []
    for i, r in enumerate(rows):
        local = f"${{p{i}}}"
        start = NEW_END if r["start"] == old else r["start"]
        end = NEW_END if r["end"] == old else r["end"]
        included.append({"type": "inAppPurchasePrices", "id": local,
                         "attributes": {"startDate": start, "endDate": end},
                         "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": r["point"]}}}})
        links.append({"type": "inAppPurchasePrices", "id": local})
        if r["price"] is not None and (r["start"] == old or r["end"] == old):
            print(f"  {product} {r['territory']} {r['price']}  {r['start']}→{start}  {r['end']}→{end}")
    result = call("POST", "/v1/inAppPurchasePriceSchedules", {"data": {"type": "inAppPurchasePriceSchedules", "relationships": {
        "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
        "baseTerritory": {"data": {"type": "territories", "id": base_id}},
        "manualPrices": {"data": links}}}, "included": included})
    if "error" in result:
        print("ÉCHEC prix", product, result["error"], result["detail"][:500])
    else:
        print("ok prix", product, "frontière", old, "→", NEW_END, "base", base_id, "lignes", len(rows))

print("\n== RELECTURE ==")
time.sleep(3)
for iid, product, sid, base, rows, old in changes:
    extra = call("GET", f"/v2/inAppPurchases/{iid}/iapPriceSchedule?include=manualPrices,inAppPurchasePricePoint&limit=200")
    if "error" in extra:
        print(product, extra)
        continue
    seen = {}
    for p in extra.get("included", []):
        if p["type"] != "inAppPurchasePrices":
            continue
        a = p.get("attributes") or {}
        point_id = ((p.get("relationships") or {}).get("inAppPurchasePricePoint") or {}).get("data", {}).get("id")
        point = next((x for x in extra.get("included", []) if x["id"] == point_id), {})
        price = (point.get("attributes") or {}).get("customerPrice")
        seen.setdefault((a.get("startDate"), a.get("endDate"), str(price)), 0)
        seen[(a.get("startDate"), a.get("endDate"), str(price))] += 1
    print(product)
    for k, n in sorted(seen.items()):
        print(f"  {k[2]}  {k[0] or 'maintenant'} → {k[1] or 'sans fin'}  ({n})")
