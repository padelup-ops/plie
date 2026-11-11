"""Apple Ads (Search Ads) : lecture et gestion des campagnes.

Entrées : APPLE_ADS_CLIENT_SECRET (secret GitHub, JWT valable 180 jours), MODE (probe | report | create | pause | resume),
          PLAN (JSON des campagnes à créer, voir tools/apple_ads_plan.json), DAYS (période du rapport).
"""
import datetime, json, os, sys, urllib.error, urllib.parse, urllib.request

CID = "SEARCHADS.58f3bbdc-a4ae-4647-bc54-8674d809ee6b"
API = "https://api.searchads.apple.com/api/v5"
MODE = os.environ.get("MODE", "probe")
secret = os.environ["APPLE_ADS_CLIENT_SECRET"].strip()

q = urllib.parse.urlencode({"grant_type": "client_credentials", "client_id": CID, "client_secret": secret, "scope": "searchadsorg"})
tok = json.loads(urllib.request.urlopen(urllib.request.Request("https://appleid.apple.com/auth/oauth2/token?" + q, method="POST",
      headers={"Content-Type": "application/x-www-form-urlencoded"})).read())["access_token"]
ORG = None


def call(method, path, body=None):
    h = {"Authorization": "Bearer " + tok, "Content-Type": "application/json"}
    if ORG: h["X-AP-Context"] = f"orgId={ORG}"
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body is not None else None, headers=h)
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:1500]}


acl = call("GET", "/acls")
print("COMPTES", [(a.get("orgId"), a.get("orgName"), a.get("currency"), a.get("roleNames")) for a in acl.get("data", [])] or acl)
if not acl.get("data"): sys.exit(1)
ORG = acl["data"][0]["orgId"]; CUR = acl["data"][0].get("currency", "EUR")
camps = call("GET", "/campaigns?limit=100").get("data", [])
by_name = {c["name"]: c for c in camps}
print("CAMPAGNES", [(c["id"], c["name"], c["status"], c.get("servingStatus"), c.get("servingStateReasons"), c.get("countriesOrRegions"), (c.get("dailyBudgetAmount") or {}).get("amount")) for c in camps])

if MODE == "probe":
    for name in ("Foldly", "Foldboard"):
        r = call("GET", "/search/apps?query=" + urllib.parse.quote(name) + "&returnOwnedApps=true")
        print("APP", name, [(a.get("adamId"), a.get("appName"), a.get("developerName")) for a in r.get("data", [])][:5] or r)

elif MODE == "create":
    plan = json.loads(os.environ.get("PLAN") or open("tools/apple_ads_plan.json").read())
    for c in plan["campaigns"]:
        if c["name"] in by_name:
            cid = by_name[c["name"]]["id"]
            if call("GET", f"/campaigns/{cid}/adgroups").get("data"):
                print("déjà là :", c["name"]); continue
            print("campagne sans groupe, on complète :", c["name"])
        else:
          r = call("POST", "/campaigns", {"name": c["name"], "adamId": c["adamId"], "countriesOrRegions": c["countries"],
                   "dailyBudgetAmount": {"amount": str(c["daily"]), "currency": CUR}, "adChannelType": "SEARCH",
                 "supplySources": ["APPSTORE_SEARCH_RESULTS"], "billingEvent": "TAPS", "status": "ENABLED"})
          if r.get("error"): print("ÉCHEC campagne", c["name"], r); continue
          cid = r["data"]["id"]; print("ok campagne", c["name"], cid)
        start = (datetime.datetime.utcnow() + datetime.timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%S.000")
        for g in c["groups"]:
            gr = call("POST", f"/campaigns/{cid}/adgroups", {"name": g["name"], "pricingModel": "CPC", "startTime": start,
                      "defaultBidAmount": {"amount": str(g["bid"]), "currency": CUR}, "automatedKeywordsOptIn": bool(g.get("searchMatch")),
                      "status": "ENABLED"})
            if gr.get("error"): print("ÉCHEC groupe", g["name"], gr); continue
            gid = gr["data"]["id"]; print("  ok groupe", g["name"], gid)
            kws = [{"text": k, "matchType": g.get("match", "EXACT"), "bidAmount": {"amount": str(g["bid"]), "currency": CUR}} for k in g.get("keywords", [])]
            if kws:
                kr = call("POST", f"/campaigns/{cid}/adgroups/{gid}/targetingkeywords/bulk", kws)
                print("    mots-clés", len(kws), "ÉCHEC " + str(kr)[:400] if isinstance(kr, dict) and kr.get("error") else "ok")
            neg = [{"text": k, "matchType": "EXACT"} for k in g.get("negatives", [])]
            if neg: print("    négatifs", (lambda x: "ÉCHEC " + str(x)[:300] if isinstance(x, dict) and x.get("error") else "ok")(call("POST", f"/campaigns/{cid}/adgroups/{gid}/negativekeywords/bulk", neg)))

elif MODE == "budget":
    # BUDGETS="Foldly – Marque=3;Foldly – Découverte=1" : nouveau budget par jour de chaque campagne.
    for part in os.environ.get("BUDGETS", "").split(";"):
        if "=" not in part:
            continue
        name, amount = part.rsplit("=", 1)
        c = by_name.get(name.strip())
        if not c:
            print("ÉCHEC campagne introuvable", name)
            continue
        r = call("PUT", f"/campaigns/{c['id']}", {"campaign": {"dailyBudgetAmount": {"amount": amount.strip(), "currency": CUR}}})
        print("budget", name.strip(), "→", amount.strip(), "€/jour", "ÉCHEC " + str(r)[:300] if r.get("error") else "ok")

elif MODE == "tune":
    # 11 nov. : Découverte ne gagnait aucune enchère, et les mots-clés Duo sont peu cherchés.
    disc = by_name.get("Foldly – Découverte")
    if disc:
        for g in call("GET", f"/campaigns/{disc['id']}/adgroups").get("data", []):
            r = call("PUT", f"/campaigns/{disc['id']}/adgroups/{g['id']}", {"defaultBidAmount": {"amount": "1", "currency": CUR}})
            print("enchère Découverte → 1 €", g["name"], "ÉCHEC " + str(r)[:300] if r.get("error") else "ok")
    duo = by_name.get("Foldly – iPhone Duo")
    if duo:
        groups = call("GET", f"/campaigns/{duo['id']}/adgroups").get("data", [])
        gid = next((g["id"] for g in groups if g["name"] == "Large (temps d'écran)"), None)
        if not gid:
            start = (datetime.datetime.utcnow() + datetime.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%S.000")
            gr = call("POST", f"/campaigns/{duo['id']}/adgroups", {"name": "Large (temps d'écran)", "pricingModel": "CPC", "startTime": start,
                      "defaultBidAmount": {"amount": "0.8", "currency": CUR}, "automatedKeywordsOptIn": False, "status": "ENABLED"})
            if gr.get("error"): print("ÉCHEC groupe large", gr)
            else: gid = gr["data"]["id"]; print("ok groupe large", gid)
        if gid:
            words = ["screen time", "screen time tracker", "phone addiction", "digital detox", "phone habits", "flip phone", "foldable",
                     "temps d'écran", "bildschirmzeit", "tiempo de pantalla", "tempo di utilizzo", "schermtijd", "スクリーンタイム"]
            kws = [{"text": k, "matchType": "BROAD", "bidAmount": {"amount": "0.8", "currency": CUR}} for k in words]
            kr = call("POST", f"/campaigns/{duo['id']}/adgroups/{gid}/targetingkeywords/bulk", kws)
            print("mots-clés larges", len(kws), "ÉCHEC " + str(kr)[:500] if isinstance(kr, dict) and kr.get("error") else "ok")

elif MODE in ("pause", "resume"):
    for c in camps:
        r = call("PUT", f"/campaigns/{c['id']}", {"campaign": {"status": "PAUSED" if MODE == "pause" else "ENABLED"}})
        print(c["name"], "ÉCHEC" if r.get("error") else MODE)

if MODE in ("report", "create", "probe", "tune", "budget") and camps:
    days = int(os.environ.get("DAYS", "7"))
    end = datetime.date.today(); start = end - datetime.timedelta(days=days - 1)
    r = call("POST", "/reports/campaigns", {"startTime": str(start), "endTime": str(end), "granularity": None,
             "selector": {"orderBy": [{"field": "localSpend", "sortOrder": "DESCENDING"}], "pagination": {"offset": 0, "limit": 100}},
             "returnRowTotals": True, "returnRecordsWithNoMetrics": True})
    rows = r.get("data", {}).get("reportingDataResponse", {}).get("row", [])
    print(f"RAPPORT {start} → {end}")
    for row in rows:
        m, t = row.get("metadata", {}), row.get("total", {})
        print(f"  {m.get('campaignName')}: dépensé {t.get('localSpend', {}).get('amount')} · impressions {t.get('impressions')} · appuis {t.get('taps')} · installations {t.get('totalInstalls', t.get('installs'))} · coût/install {t.get('totalAvgCPI', t.get('avgCPA', {})).get('amount') if isinstance(t.get('totalAvgCPI', t.get('avgCPA')), dict) else ''}")
    if r.get("error"): print("rapport :", r)
