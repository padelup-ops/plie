"""Demande de mise en avant (Featuring nomination) de Foldly sur App Store Connect.

Variables : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY, SUBMIT (1 = envoyer à Apple, sinon brouillon).
Crée la nomination (ou reprend celle qui existe déjà sous le même nom), puis l'envoie si demandé.
"""
import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "com.padelup.clapet"
NAME = "Foldly launch - Made for iPhone Duo"

DESCRIPTION = (
    "Foldly is a fold counter made for iPhone Duo. It reads the hinge live and counts every fold and unfold, "
    "like a step counter for the device's signature gesture. People set a daily limit (alerts at 80% and 100%), "
    "see how long their Duo stays open each day, and follow it all in Health-style widgets on the Home Screen "
    "and Lock Screen. With the Shortcuts triggers \"When iPhone is Closed\" and \"Opened\", it keeps counting all "
    "day; both automations install in one tap from the app. The history shows 30 days, 12 months, streaks under "
    "the limit, records and a weekday-by-hour map of when you fold. Two themes (Classic and Modern), English and "
    "French, no account, no ads and no data collected. One purchase, everything included."
)
NOTES = (
    "Independent developer based in France. Built specifically for the iPhone Duo hinge (SwiftUI onHingeChange, "
    "iOS 27.1 SDK) with dedicated iPhone Duo screenshots. A digital wellbeing angle: it helps people notice how "
    "often they reach for their phone, and keep it under a limit they choose. Public TestFlight testers shaped "
    "several features (manual count adjustment, one-tap automations, a larger hinge gauge). Press kit with "
    "screenshots, icon and a 30-second video: https://foldly.netlify.app/press/"
)
MATERIALS = ["https://foldly.netlify.app/press/", "https://testflight.apple.com/join/F3SbgAp2"]

token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_PRIVATE_KEY"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {"error": e.code, "detail": e.read().decode()[:3000]}


app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]
app_id = app["id"]
print("APP", app_id, app["attributes"]["name"])

nom = None
for state in ("SUBMITTED", "DRAFT"):
    found = call("GET", f"/v1/nominations?filter[relatedApps]={app_id}&filter[state]={state}&limit=50")
    if "error" in found:
        print("liste", state, found["detail"][:300])
        continue
    for n in found.get("data", []):
        print("nomination", n["id"], n["attributes"].get("state"), n["attributes"].get("name"))
        if nom is None and n["attributes"].get("name") == NAME:
            nom = n

start = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=22)).strftime("%Y-%m-%dT00:00:00Z")
attrs = {
    "name": NAME,
    "type": "APP_LAUNCH",
    "description": DESCRIPTION[:1000],
    "notes": NOTES[:1000],
    "publishStartDate": start,
    "deviceFamilies": ["IPHONE"],
    "locales": ["en-US", "fr-FR"],
    "supplementalMaterialsUris": MATERIALS,
    "hasInAppEvents": False,
    "launchInSelectMarketsFirst": False,
    "preOrderEnabled": False,
}
if nom is None:
    body = {"data": {"type": "nominations", "attributes": dict(attrs, submitted=False),
                     "relationships": {"relatedApps": {"data": [{"type": "apps", "id": app_id}]}}}}
    r = call("POST", "/v1/nominations", body)
    print("CRÉATION", json.dumps(r)[:3000])
    if "error" in r:
        sys.exit(1)
    nom = r["data"]
else:
    print("nomination déjà créée", nom["id"], nom["attributes"].get("state"))

if os.environ.get("SUBMIT") == "1" and nom["attributes"].get("state") != "SUBMITTED":
    r = call("PATCH", f"/v1/nominations/{nom['id']}",
             {"data": {"type": "nominations", "id": nom["id"], "attributes": {"submitted": True}}})
    print("ENVOI", json.dumps(r)[:3000])
    if "error" in r:
        sys.exit(1)
    print("ok     demande de mise en avant envoyée à Apple, état :", r["data"]["attributes"].get("state"))
else:
    print("état :", nom["attributes"].get("state"))
