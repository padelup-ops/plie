"""Construit le fichier des clubs de padel de la zone PadelUp (OpenStreetMap), embarqué dans l'app PadelUp Neo.

Zone : France, Belgique, Suisse, pays frontaliers de la France (Luxembourg, Allemagne, Italie, Monaco, Andorre,
Espagne), Maroc, Algérie, Tunisie. Chaque pays est demandé à Overpass par sa frontière officielle, puis les
terrains sont regroupés en clubs (voir app/opendata.py).

    python3 padelup/tools/zone_clubs.py sortie.json

Données © contributeurs OpenStreetMap, licence ODbL : l'attribution est affichée dans l'app.
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'backend', 'app'))
import opendata  # noqa: E402

BUDGET_S = int(os.environ.get('ZONE_CLUBS_BUDGET', 80 * 60))


def write(out, by_country, failures):
    clubs = []
    for code, elements in by_country.items():
        for c in opendata.group_clubs(elements):
            c['country'] = c.get('country') or code
            clubs.append(c)
    clubs.sort(key=lambda c: (c['country'], c['lat'], c['lon']))
    data = opendata.to_compact(clubs)
    data['generated'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    data['source'] = '© OpenStreetMap contributors (ODbL)'
    data['countries'] = sorted(by_country)
    data['partial'] = bool(failures)
    tmp = out + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
    os.replace(tmp, out)
    return clubs


def main(out):
    started_all = time.time()
    by_country, failures = {}, []
    for code, name in opendata.ZONE_COUNTRIES.items():
        if time.time() - started_all > BUDGET_S:
            failures.append(f'{code}: budget de temps dépassé')
            continue
        started = time.time()
        try:
            elements = opendata.run_query(opendata.country_query(code), timeout=280, retries=2, pause=10)
        except RuntimeError as exc:
            failures.append(f'{code}: {exc}')
            print(f'ÉCHEC {name} ({code}) : {exc}', flush=True)
            continue
        # Second passage, plus léger : les clubs nommés « padel » sans étiquette sport (un seul essai, échec toléré).
        try:
            named = opendata.run_query(opendata.country_name_query(code), timeout=200, retries=0, pause=5)
            known = {(e.get('type'), e.get('id')) for e in elements}
            elements += [e for e in named if (e.get('type'), e.get('id')) not in known]
        except RuntimeError as exc:
            print(f'  ({name} : recherche par nom indisponible : {exc})', flush=True)
        by_country[code] = elements
        clubs = write(out, by_country, failures)
        here = sum(1 for c in clubs if c['country'] == code)
        print(f'{name:<11} {len(elements):>6} éléments OSM → {here:>5} clubs ({time.time() - started:.0f} s)', flush=True)
        time.sleep(3)
    clubs = write(out, by_country, failures)
    per = {}
    for c in clubs:
        per[c['country']] = per.get(c['country'], 0) + 1
    print(f'Total : {len(clubs)} clubs, {sum(c["courts"] for c in clubs)} terrains, '
          f'{os.path.getsize(out) / 1e6:.1f} Mo, {(time.time() - started_all) / 60:.0f} min')
    print('Par pays :', ', '.join(f'{k} {v}' for k, v in sorted(per.items(), key=lambda kv: -kv[1])))
    if failures:
        print('Pays en échec :', *failures, sep='\n  ')
    return 0 if clubs else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else 'clubs-zone.json'))
