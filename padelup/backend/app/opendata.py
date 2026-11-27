"""Clubs de padel du monde entier depuis OpenStreetMap (API Overpass, données ODbL, sans clé).

Module autonome (sans Django) : utilisé par le serveur (import, adoption d'un club par son identifiant OSM)
et par l'outil qui construit le fichier mondial embarqué dans l'app (padelup/tools/world_clubs.py).

OpenStreetMap décrit le padel de deux façons, souvent mélangées :
  - le lieu (club, complexe sportif : leisure=sports_centre, club=sport...) avec un nom ;
  - chaque terrain (leisure=pitch + sport=padel), en général sans nom.
On regroupe donc les terrains autour du lieu le plus proche, ou entre eux quand aucun lieu n'est cartographié.
"""
import json
import math
import time
import urllib.parse
import urllib.request

OVERPASS_MIRRORS = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
]
PADEL_FILTER = '["sport"~"(^|;)padel(;|$)"]'
USER_AGENT = 'PadelUp/2.0 (+https://github.com/padelup-ops/plie)'
VENUE_RADIUS_M = 300
CLUSTER_RADIUS_M = 200


# Zone couverte par PadelUp : la France, la Belgique, la Suisse, les pays frontaliers de la France, et le Maghreb.
ZONE_COUNTRIES = {
    'FR': 'France', 'BE': 'Belgique', 'CH': 'Suisse', 'LU': 'Luxembourg', 'DE': 'Allemagne', 'IT': 'Italie',
    'MC': 'Monaco', 'AD': 'Andorre', 'ES': 'Espagne', 'MA': 'Maroc', 'DZ': 'Algérie', 'TN': 'Tunisie',
}


def country_query(code, timeout=240):
    """Tous les éléments padel d'un pays (frontière OSM du pays : ISO 3166-1)."""
    return (f'[out:json][timeout:{timeout}];area["ISO3166-1"="{code}"][admin_level=2]->.a;'
            f'nwr{PADEL_FILTER}(area.a);out center tags;')


def bbox_query(south, west, north, east, timeout=180):
    return f'[out:json][timeout:{timeout}];nwr{PADEL_FILTER}({south},{west},{north},{east});out center tags;'


def element_query(osm_type, osm_id):
    return f'[out:json][timeout:25];{osm_type}({int(osm_id)});out center tags;'


def run_query(query, mirrors=None, retries=2, timeout=200, pause=5.0):
    """Exécute une requête Overpass en essayant plusieurs serveurs. Renvoie la liste des éléments."""
    last = None
    for attempt in range(retries + 1):
        for url in (mirrors or OVERPASS_MIRRORS):
            try:
                data = urllib.parse.urlencode({'data': query}).encode()
                req = urllib.request.Request(url, data=data, headers={'User-Agent': USER_AGENT})
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    return json.loads(resp.read().decode('utf-8')).get('elements', [])
            except Exception as exc:  # serveur saturé, délai dépassé...
                last = exc
        time.sleep(pause * (attempt + 1))
    raise RuntimeError(f'Overpass indisponible : {last}')


def point(el):
    if 'lat' in el and 'lon' in el:
        return el['lat'], el['lon']
    c = el.get('center') or {}
    if 'lat' in c:
        return c['lat'], c['lon']
    return None


def distance_m(a, b):
    lat1, lon1 = map(math.radians, a)
    lat2, lon2 = map(math.radians, b)
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(h))


def is_pitch(tags):
    return tags.get('leisure') == 'pitch'


def is_indoor(tags):
    if tags.get('indoor') in ('yes', 'room') or tags.get('covered') == 'yes' or tags.get('leisure') == 'sports_hall':
        return True
    if tags.get('indoor') == 'no' or tags.get('covered') == 'no':
        return False
    return None


def _clean_url(value):
    value = (value or '').strip().split(';')[0].strip()
    if value and not value.startswith(('http://', 'https://')):
        value = 'https://' + value
    return value[:300]


def _venue(el, pt, tags):
    return {
        'id': f"{el['type']}/{el['id']}",
        'name': (tags.get('name') or tags.get('operator') or tags.get('brand') or '').strip()[:200],
        'lat': round(pt[0], 6), 'lon': round(pt[1], 6),
        'courts': 0,
        'indoor': 0, 'outdoor': 0,
        'city': (tags.get('addr:city') or tags.get('addr:town') or tags.get('addr:village') or '').strip()[:100],
        'postcode': (tags.get('addr:postcode') or '').strip()[:20],
        'street': ' '.join(x for x in [tags.get('addr:housenumber', ''), tags.get('addr:street', '')] if x).strip()[:200],
        'country': (tags.get('addr:country') or '').strip().upper()[:2],
        'website': _clean_url(tags.get('website') or tags.get('contact:website') or tags.get('url')),
        'phone': (tags.get('phone') or tags.get('contact:phone') or '').split(';')[0].strip()[:40],
        'email': (tags.get('email') or tags.get('contact:email') or '').split(';')[0].strip()[:200],
        'opening_hours': (tags.get('opening_hours') or '').strip()[:250],
        'fee': tags.get('fee', ''),
        'access': tags.get('access', ''),
    }


def _cells(pt):
    return int(math.floor(pt[0] * 200)), int(math.floor(pt[1] * 200))  # mailles d'environ 500 m


def group_clubs(elements):
    """Regroupe les éléments OSM (lieux et terrains) en clubs. Renvoie une liste de dictionnaires."""
    venues, pitches = [], []
    for el in elements:
        tags = el.get('tags') or {}
        pt = point(el)
        if not pt:
            continue
        if is_pitch(tags):
            pitches.append((el, pt, tags))
        elif tags.get('access') not in ('private', 'no'):
            venues.append(_venue(el, pt, tags))

    grid = {}

    def add_to_grid(v):
        grid.setdefault(_cells((v['lat'], v['lon'])), []).append(v)

    def nearest(pt, radius):
        cx, cy = _cells(pt)
        best, best_d = None, radius
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for v in grid.get((cx + dx, cy + dy), []):
                    d = distance_m(pt, (v['lat'], v['lon']))
                    if d <= best_d:
                        best, best_d = v, d
        return best

    for v in venues:
        add_to_grid(v)
    clusters = []
    for el, pt, tags in pitches:
        if tags.get('access') in ('private', 'no'):
            continue
        host = nearest(pt, VENUE_RADIUS_M)
        if host is None:
            host = _venue(el, pt, tags)
            host['_cluster'] = True
            clusters.append(host)
            add_to_grid(host)
        else:
            # Un lieu anonyme prend le nom ou l'adresse du premier terrain qui en a un.
            for key in ('name', 'city', 'postcode', 'street', 'website', 'phone', 'country'):
                if not host.get(key):
                    host[key] = _venue(el, pt, tags)[key]
        host['courts'] += max(1, int(tags['courts']) if str(tags.get('courts', '')).isdigit() else 1)
        flag = is_indoor(tags)
        if flag is True:
            host['indoor'] += 1
        elif flag is False:
            host['outdoor'] += 1

    clubs = []
    for v in venues + clusters:
        v.pop('_cluster', None)
        if v['courts'] == 0 and not v['name']:
            continue
        clubs.append(v)
    return clubs


COMPACT_FIELDS = ['id', 'name', 'lat', 'lon', 'courts', 'indoor', 'outdoor', 'city', 'postcode', 'street',
                  'country', 'website', 'phone', 'email', 'opening_hours']


def to_compact(clubs):
    """Format compact embarqué dans l'app : une ligne par club, champs dans l'ordre de COMPACT_FIELDS."""
    return {'v': 1, 'fields': COMPACT_FIELDS, 'clubs': [[c.get(k, '') for k in COMPACT_FIELDS] for c in clubs]}


def from_compact(data):
    fields = data.get('fields') or COMPACT_FIELDS
    return [dict(zip(fields, row)) for row in data.get('clubs', [])]
