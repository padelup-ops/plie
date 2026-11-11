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
print("CAMPAGNES", [(c["id"], c["name"], c["status"], c.get("servingStatus"), c.get("countriesOrRegions"), (c.get("dailyBudgetAmount") or {}).get("amount")) for c in camps])

if MODE == "probe":
    for name in ("Foldly", "Foldboard"):
        r = call("GET", "/search/apps?query=" + urllib.parse.quote(name) + "&returnOwnedApps=true")
        print("APP", name, [(a.get("adamId"), a.get("appName"), a.get("developerName")) for a in r.get("data", [])][:5] or r)

elif MODE == "create":
    plan = json.loads(os.environ.get("PLAN") or open("tools/apple_ads_plan.json").read())
    for c in plan["campaigns"]:
        if c["name"] in by_name:
            print("déjà là :", c["name"]); continue
        r = call("POST", "/campaigns", {"name": c["name"], "adamId": c["adamId"], "countriesOrRegions": c["countries"],
                 "dailyBudgetAmount": {"amount": str(c["daily"]), "currency": CUR}, "adChannelType": "SEARCH",
                 "supplySources": ["APPSTORE_SEARCH_RESULTS"], "billingEvent": "TAPS", "status": "ENABLED"})
        if "error" in r: print("ÉCHEC campagne", c["name"], r); continue
        cid = r["data"]["id"]; print("ok campagne", c["name"], cid)
        start = (datetime.datetime.utcnow() + datetime.timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%S.000")
        for g in c["groups"]:
            gr = call("POST", f"/campaigns/{cid}/adgroups", {"name": g["name"], "pricingModel": "CPC", "startTime": start,
                      "defaultBidAmount": {"amount": str(g["bid"]), "currency": CUR}, "automatedKeywordsOptIn": bool(g.get("searchMatch")),
                      "status": "ENABLED"})
            if "error" in gr: print("ÉCHEC groupe", g["name"], gr); continue
            gid = gr["data"]["id"]; print("  ok groupe", g["name"], gid)
            kws = [{"text": k, "matchType": g.get("match", "EXACT"), "bidAmount": {"amount": str(g["bid"]), "currency": CUR}} for k in g.get("keywords", [])]
            if kws:
                kr = call("POST", f"/campaigns/{cid}/adgroups/{gid}/targetingkeywords/bulk", kws)
                print("    mots-clés", len(kws), "ÉCHEC " + str(kr)[:400] if "error" in kr else "ok")
            neg = [{"text": k, "matchType": "EXACT"} for k in g.get("negatives", [])]
            if neg: print("    négatifs", "ok" if "error" not in call("POST", f"/campaigns/{cid}/adgroups/{gid}/negativekeywords/bulk", neg) else "ÉCHEC")

elif MODE in ("pause", "resume"):
    for c in camps:
        r = call("PUT", f"/campaigns/{c['id']}", {"campaign": {"status": "PAUSED" if MODE == "pause" else "ENABLED"}})
        print(c["name"], "ÉCHEC" if "error" in r else MODE)

if MODE in ("report", "create", "probe") and camps:
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
    if "error" in r: print("rapport :", r)
