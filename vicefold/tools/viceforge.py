"""VICEFOLD : lit l'API de données GTA6 de ViceForge (https://viceforge.app/developers) pour préparer son
intégration au guide. Il faut une clé (offre gratuite : 100 requêtes par jour), dans le secret VICEFORGE_API_KEY.

Pour l'instant, le script ne fait qu'afficher la forme des données (champs, nombre d'entrées, un exemple) : rien
n'est republié tant que l'usage de leurs données dans une app n'est pas réglé avec eux.
"""
import json
import os
import sys
import urllib.error
import urllib.request

KEY = os.environ.get("VICEFORGE_API_KEY", "").strip()
BASE = "https://api.viceforge.app/api/v1/public"
ENDPOINTS = ["/locations", "/predictions", "/guides", "/economy/properties", "/economy/vehicles"]

if not KEY:
    print("::notice::Pas de clé VICEFORGE_API_KEY : rien à lire.")
    sys.exit(0)


def shape(v, depth=0):
    if isinstance(v, dict):
        return {k: shape(x, depth + 1) for k, x in list(v.items())[:25]} if depth < 3 else "{…}"
    if isinstance(v, list):
        return [shape(v[0], depth + 1), f"… {len(v)} éléments"] if v else []
    return type(v).__name__


for ep in ENDPOINTS:
    req = urllib.request.Request(BASE + ep, headers={"X-API-Key": KEY, "Accept": "application/json", "User-Agent": "Vicefold"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read())
        print(f"== {ep}")
        print(json.dumps(shape(data), ensure_ascii=False, indent=1)[:3000])
    except urllib.error.HTTPError as e:
        print(f"== {ep} : HTTP {e.code} (offre insuffisante ou clé refusée)")
    except Exception as e:  # noqa: BLE001
        print(f"== {ep} : {e}")
